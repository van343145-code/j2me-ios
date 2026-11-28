#include "miniz.h"
#include "miniz_wrapper.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#if defined(__APPLE__) || defined(__MACH__) || defined(__unix__)
#include <pthread.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

#define ZIP_CACHE_MAX_ARCHIVES 16

typedef struct CachedZipArchive {
    char path[1024];
    time_t mtime_sec;
    off_t file_size;
    void *mapped;
    size_t mapped_len;
    mz_zip_archive archive;
    pthread_mutex_t lock;
    int active_refs;
    int pending_free;
    int is_ephemeral;
    unsigned long long last_used;
} CachedZipArchive;

static CachedZipArchive *g_zip_cache[ZIP_CACHE_MAX_ARCHIVES] = {0};
static pthread_mutex_t g_zip_cache_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned long long g_zip_lru_tick = 0;

static void zip_cache_free_entry(CachedZipArchive *entry) {
    if (!entry) return;
    mz_zip_reader_end(&entry->archive);
    if (entry->mapped && entry->mapped != MAP_FAILED && entry->mapped_len > 0) {
        munmap(entry->mapped, entry->mapped_len);
    }
    pthread_mutex_destroy(&entry->lock);
    free(entry);
}

static void zip_cache_invalidate(char const *jarpath) {
    if (!jarpath) return;
    CachedZipArchive *to_free = NULL;
    pthread_mutex_lock(&g_zip_cache_lock);
    for (int i = 0; i < ZIP_CACHE_MAX_ARCHIVES; i++) {
        CachedZipArchive *e = g_zip_cache[i];
        if (e && strcmp(e->path, jarpath) == 0) {
            e->pending_free = 1;
            if (e->active_refs == 0) {
                g_zip_cache[i] = NULL;
                to_free = e;
            }
            break;
        }
    }
    pthread_mutex_unlock(&g_zip_cache_lock);
    if (to_free) zip_cache_free_entry(to_free);
}

static CachedZipArchive *zip_cache_acquire(char const *jarpath) {
    if (!jarpath || strlen(jarpath) >= 1024) return NULL;
    struct stat st;
    if (stat(jarpath, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size <= 0) {
        return NULL;
    }

    CachedZipArchive *retired = NULL;
    pthread_mutex_lock(&g_zip_cache_lock);
    for (int i = 0; i < ZIP_CACHE_MAX_ARCHIVES; i++) {
        CachedZipArchive *e = g_zip_cache[i];
        if (e && !e->pending_free && strcmp(e->path, jarpath) == 0) {
            if (e->file_size == st.st_size && e->mtime_sec == st.st_mtime) {
                e->active_refs++;
                e->last_used = ++g_zip_lru_tick;
                pthread_mutex_unlock(&g_zip_cache_lock);
                return e;
            } else {
                e->pending_free = 1;
                if (e->active_refs == 0) {
                    g_zip_cache[i] = NULL;
                    retired = e;
                }
                break;
            }
        }
    }
    pthread_mutex_unlock(&g_zip_cache_lock);
    if (retired) zip_cache_free_entry(retired);

    // Cache miss: mmap read-only once so 24 JVMs share kernel file-backed pages with 0 dirty RAM.
    int fd = open(jarpath, O_RDONLY);
    if (fd < 0) return NULL;
    size_t len = (size_t)st.st_size;
    void *mapped = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (mapped == MAP_FAILED) return NULL;

    CachedZipArchive *created = (CachedZipArchive *)calloc(1, sizeof(CachedZipArchive));
    if (!created) {
        munmap(mapped, len);
        return NULL;
    }
    snprintf(created->path, sizeof(created->path), "%s", jarpath);
    created->mtime_sec = st.st_mtime;
    created->file_size = st.st_size;
    created->mapped = mapped;
    created->mapped_len = len;
    if (mz_zip_reader_init_mem(&created->archive, mapped, len, 0) == MZ_FALSE) {
        munmap(mapped, len);
        free(created);
        return NULL;
    }
    pthread_mutex_init(&created->lock, NULL);

    CachedZipArchive *evicted = NULL;
    pthread_mutex_lock(&g_zip_cache_lock);
    // Double-check if another thread cached the exact same JAR concurrently
    for (int i = 0; i < ZIP_CACHE_MAX_ARCHIVES; i++) {
        CachedZipArchive *e = g_zip_cache[i];
        if (e && !e->pending_free && strcmp(e->path, jarpath) == 0 &&
            e->file_size == st.st_size && e->mtime_sec == st.st_mtime) {
            e->active_refs++;
            e->last_used = ++g_zip_lru_tick;
            pthread_mutex_unlock(&g_zip_cache_lock);
            zip_cache_free_entry(created);
            return e;
        }
    }

    int target_slot = -1;
    unsigned long long oldest_tick = (unsigned long long)-1;
    for (int i = 0; i < ZIP_CACHE_MAX_ARCHIVES; i++) {
        if (!g_zip_cache[i]) {
            target_slot = i;
            break;
        }
        if (g_zip_cache[i]->active_refs == 0 && g_zip_cache[i]->last_used < oldest_tick) {
            oldest_tick = g_zip_cache[i]->last_used;
            target_slot = i;
        }
    }
    if (target_slot < 0) {
        // All cache slots busy: return ephemeral non-table reader freed right after call.
        created->is_ephemeral = 1;
        pthread_mutex_unlock(&g_zip_cache_lock);
        return created;
    }
    if (g_zip_cache[target_slot]) {
        evicted = g_zip_cache[target_slot];
    }
    created->active_refs = 1;
    created->last_used = ++g_zip_lru_tick;
    g_zip_cache[target_slot] = created;
    pthread_mutex_unlock(&g_zip_cache_lock);

    if (evicted) zip_cache_free_entry(evicted);
    return created;
}

static void zip_cache_release(CachedZipArchive *entry) {
    if (!entry) return;
    CachedZipArchive *to_free = NULL;
    pthread_mutex_lock(&g_zip_cache_lock);
    if (entry->active_refs > 0) entry->active_refs--;
    if (entry->pending_free && entry->active_refs == 0) {
        for (int i = 0; i < ZIP_CACHE_MAX_ARCHIVES; i++) {
            if (g_zip_cache[i] == entry) {
                g_zip_cache[i] = NULL;
                break;
            }
        }
        to_free = entry;
    }
    pthread_mutex_unlock(&g_zip_cache_lock);
    if (to_free) zip_cache_free_entry(to_free);
}
#endif


s32 zip_loadfile(char const *jarpath, char const *filename, ByteBuf *buf) {
    int file_index = 0;
    mz_zip_archive_file_stat file_stat = {0};

    //skit the first '/'
    if (filename && filename[0] == '/') {
        filename += 1;
    }

#if defined(__APPLE__) || defined(__MACH__) || defined(__unix__)
    CachedZipArchive *cached = zip_cache_acquire(jarpath);
    if (cached) {
        if (cached->is_ephemeral) {
            // Uncached temporary mmap (all 16 slots busy)
            int ret = 0;
            file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
            if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
                ret = -1;
            } else {
                size_t uncompressed_size = (size_t) file_stat.m_uncomp_size;
                bytebuf_expand(buf, uncompressed_size);
                if (mz_zip_reader_extract_file_to_mem(&cached->archive, file_stat.m_filename, buf->buf, uncompressed_size, 0) == MZ_FALSE) {
                    ret = -1;
                } else {
                    buf->wp = uncompressed_size;
                }
            }
            zip_cache_free_entry(cached);
            return ret;
        }
        int ret = 0;
        pthread_mutex_lock(&cached->lock);
        file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
        if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
            ret = -1;
        } else {
            size_t uncompressed_size = (size_t) file_stat.m_uncomp_size;
            bytebuf_expand(buf, uncompressed_size);
            if (mz_zip_reader_extract_file_to_mem(&cached->archive, file_stat.m_filename, buf->buf, uncompressed_size, 0) == MZ_FALSE) {
                ret = -1;
            } else {
                buf->wp = uncompressed_size;
            }
        }
        pthread_mutex_unlock(&cached->lock);
        zip_cache_release(cached);
        return ret;
    }
#endif

    mz_zip_archive zipArchive = {0};
    int ret = 0;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        ret = -1;
    } else {

        file_index = mz_zip_reader_locate_file(&zipArchive, filename, NULL, 0);//
        if (!mz_zip_reader_file_stat(&zipArchive, file_index, &file_stat)) {
            ret = -1;
        } else {
            size_t uncompressed_size = (size_t) file_stat.m_uncomp_size;
            bytebuf_expand(buf, uncompressed_size);
            mz_bool p = mz_zip_reader_extract_file_to_mem(&zipArchive, file_stat.m_filename, buf->buf, uncompressed_size, 0);
            if (p == MZ_FALSE) {
                ret = -1;
            } else {
                buf->wp = uncompressed_size;
            }
        }
        mz_zip_reader_end(&zipArchive);
    }
    return ret;
}


s32 zip_loadfile_to_mem(char const *jarpath, char const *filename, c8 *buf, s64 bufsize) {
    int file_index = 0;
    mz_zip_archive_file_stat file_stat = {0};

    //skit the first '/'
    if (filename && filename[0] == '/') {
        filename += 1;
    }

#if defined(__APPLE__) || defined(__MACH__) || defined(__unix__)
    CachedZipArchive *cached = zip_cache_acquire(jarpath);
    if (cached) {
        if (cached->is_ephemeral) {
            int ret = 0;
            file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
            if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
                ret = -1;
            } else if (!mz_zip_reader_extract_file_to_mem(&cached->archive, file_stat.m_filename, buf, bufsize, MZ_ZIP_FLAG_CASE_SENSITIVE)) {
                ret = -1;
            }
            zip_cache_free_entry(cached);
            return ret;
        }
        int ret = 0;
        pthread_mutex_lock(&cached->lock);
        file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
        if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
            ret = -1;
        } else if (!mz_zip_reader_extract_file_to_mem(&cached->archive, file_stat.m_filename, buf, bufsize, MZ_ZIP_FLAG_CASE_SENSITIVE)) {
            ret = -1;
        }
        pthread_mutex_unlock(&cached->lock);
        zip_cache_release(cached);
        return ret;
    }
#endif

    mz_zip_archive zipArchive = {0};
    int ret = 0;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        ret = -1;
    } else {

        file_index = mz_zip_reader_locate_file(&zipArchive, filename, NULL, 0);//
        if (!mz_zip_reader_file_stat(&zipArchive, file_index, &file_stat)) {
            ret = -1;
        } else {
            size_t uncompressed_size = (size_t) file_stat.m_uncomp_size;
            mz_bool op = mz_zip_reader_extract_file_to_mem(&zipArchive, file_stat.m_filename, buf, bufsize, MZ_ZIP_FLAG_CASE_SENSITIVE);
            if (!op) {
                ret = -1;
            }
        }
        mz_zip_reader_end(&zipArchive);
    }
    return ret;
}

s64 zip_get_file_unzip_size(char const *jarpath, char const *filename) {
    int file_index = 0;
    mz_zip_archive_file_stat file_stat = {0};

    //skit the first '/'
    if (filename && filename[0] == '/') {
        filename += 1;
    }

#if defined(__APPLE__) || defined(__MACH__) || defined(__unix__)
    CachedZipArchive *cached = zip_cache_acquire(jarpath);
    if (cached) {
        if (cached->is_ephemeral) {
            s64 ret = 0;
            file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
            if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
                ret = -1;
            } else {
                ret = (s64) file_stat.m_uncomp_size;
            }
            zip_cache_free_entry(cached);
            return ret;
        }
        s64 ret = 0;
        pthread_mutex_lock(&cached->lock);
        file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
        if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
            ret = -1;
        } else {
            ret = (s64) file_stat.m_uncomp_size;
        }
        pthread_mutex_unlock(&cached->lock);
        zip_cache_release(cached);
        return ret;
    }
#endif

    mz_zip_archive zipArchive = {0};
    s64 ret = 0;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        ret = -1;
    } else {

        file_index = mz_zip_reader_locate_file(&zipArchive, filename, NULL, 0);//
        if (!mz_zip_reader_file_stat(&zipArchive, file_index, &file_stat)) {
            ret = -1;
        } else {
            size_t uncompressed_size = (size_t) file_stat.m_uncomp_size;
            ret = uncompressed_size;
        }
        mz_zip_reader_end(&zipArchive);
    }
    return ret;
}

s32 zip_get_file_index(char const *jarpath, char const *filename) {
    int file_index = 0;
    mz_zip_archive_file_stat file_stat = {0};

    //skit the first '/'
    if (filename && filename[0] == '/') {
        filename += 1;
    }

#if defined(__APPLE__) || defined(__MACH__) || defined(__unix__)
    CachedZipArchive *cached = zip_cache_acquire(jarpath);
    if (cached) {
        if (cached->is_ephemeral) {
            int ret = 0;
            file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
            if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
                ret = -1;
            } else {
                ret = file_index;
            }
            zip_cache_free_entry(cached);
            return ret;
        }
        int ret = 0;
        pthread_mutex_lock(&cached->lock);
        file_index = mz_zip_reader_locate_file(&cached->archive, filename, NULL, 0);
        if (!mz_zip_reader_file_stat(&cached->archive, file_index, &file_stat)) {
            ret = -1;
        } else {
            ret = file_index;
        }
        pthread_mutex_unlock(&cached->lock);
        zip_cache_release(cached);
        return ret;
    }
#endif

    mz_zip_archive zipArchive = {0};
    int ret = 0;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        ret = -1;
    } else {

        file_index = mz_zip_reader_locate_file(&zipArchive, filename, NULL, 0);//
        if (!mz_zip_reader_file_stat(&zipArchive, file_index, &file_stat)) {
            ret = -1;
        } else {
            ret = file_index;
        }
        mz_zip_reader_end(&zipArchive);
    }
    return ret;
}


s32 zip_savefile_mem(char const *jarpath, char const *filename, char const *buf, int size) {
#if defined(__APPLE__) || defined(__MACH__) || defined(__unix__)
    zip_cache_invalidate(jarpath);
#endif
    int file_index = 0;
    mz_zip_archive zipArchive = {0};
    mz_zip_archive_file_stat file_stat = {0};

    //skit the first '/'
    if (filename && filename[0] == '/') {
        filename += 1;
    }

    int ret = 0;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        if (mz_zip_writer_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
            ret = -1;
        }
    } else {
        if (mz_zip_writer_init_from_reader(&zipArchive, jarpath) == MZ_FALSE) {//
            ret = -1;
        }
    }
    if (ret == 0) {
        if (mz_zip_writer_add_mem(&zipArchive, filename, buf, size, MZ_DEFAULT_COMPRESSION) == MZ_FALSE) {//
            ret = -1;
        }
        if (mz_zip_writer_finalize_archive(&zipArchive) == MZ_FALSE) {//
            ret = -1;
        }
        mz_zip_writer_end(&zipArchive);
    }
    return ret;
}


s32 zip_savefile(char const *jarpath, char const *filename, ByteBuf *buf) {
    return zip_savefile_mem(jarpath, filename, buf->buf, buf->wp);
}

s32 zip_filecount(char *jarpath) {
    int file_index = 0;
    mz_zip_archive zipArchive = {0};
    mz_zip_archive_file_stat file_stat = {0};

    int ret = 0;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        ret = -1;
    } else {
        ret = mz_zip_reader_get_num_files(&zipArchive);
        mz_zip_reader_end(&zipArchive);
    }
    return ret;
}

ArrayList *zip_get_filenames(char *jarpath) {
    mz_zip_archive zipArchive = {0};

    ArrayList *list = arraylist_create(0);
    int ret = 0;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        ret = -1;
    } else {
        int count = mz_zip_reader_get_num_files(&zipArchive);
        int i;
        for (i = 0; i < count; i++) {
            char buf[1024];
            mz_uint requiremore = mz_zip_reader_get_filename(&zipArchive, i, buf, 1024);
            if (strlen(buf)) {
                Utf8String *ustr = utf8_create_c(buf);
                arraylist_push_back_unsafe(list, ustr);
            }
        }

        mz_zip_reader_end(&zipArchive);
    }
    return list;
}

void zip_destroy_filenames_list(ArrayList *list) {
    s32 i;
    for (i = 0; i < list->length; i++) {
        Utf8String *ustr = arraylist_get_value_unsafe(list, i);
        if (ustr) {
            utf8_destroy(ustr);
        }
    }
    arraylist_destroy(list);
}

s32 zip_is_directory(char *jarpath, int index) {
    mz_zip_archive zipArchive = {0};

    int ret = -1;
    if (mz_zip_reader_init_file(&zipArchive, jarpath, 0) == MZ_FALSE) {//
        ret = -1;
    } else {

        ret = mz_zip_reader_is_file_a_directory(&zipArchive, index);
        mz_zip_reader_end(&zipArchive);
    }
    return ret;
}

s32 zip_extract(char *zip_data, int size, ByteBuf *data) {
    mz_zip_archive zipArchive = {0};
    mz_zip_archive_file_stat file_stat = {0};
    int ret = 0;
    if (mz_zip_reader_init_mem(&zipArchive, zip_data, size, 0) == MZ_FALSE) {//
        ret = -1;
    } else {
        if (!mz_zip_reader_file_stat(&zipArchive, 0, &file_stat)) {
            ret = -1;
        } else {
            size_t uncompressed_size = (size_t) file_stat.m_uncomp_size;
            bytebuf_expand(data, (s32) uncompressed_size);
            mz_bool p = mz_zip_reader_extract_to_mem(&zipArchive, 0, data->buf, uncompressed_size, 0);
            if (p == MZ_FALSE) {
                ret = -1;
            } else {
                data->wp = uncompressed_size;
            }
        }
        mz_zip_reader_end(&zipArchive);
    }
    return ret;
}

s32 zip_compress(char *data, int size, ByteBuf *zip_data) {
    mz_zip_archive zipArchive = {0};
    int ret = 0;
    if (mz_zip_writer_init_heap(&zipArchive, 0, 0) == MZ_FALSE) {//
        ret = -1;
    } else {
        if (mz_zip_writer_add_mem(&zipArchive, "", data, size, MZ_DEFAULT_COMPRESSION) == MZ_FALSE) {//
            ret = -1;
        } else {
            void *buf = NULL;
            size_t outSize = 0;
            if (mz_zip_writer_finalize_heap_archive(&zipArchive, &buf, &outSize) == MZ_FALSE) {//
                ret = -1;
            } else {
                bytebuf_write_batch(zip_data, buf, (s32) outSize);
            }
        }
        mz_zip_writer_end(&zipArchive);
    }
    return ret;
}

// 修改gzip_compress函数，生成完整的GZIP格式
s32 gzip_compress(char *data, int size, ByteBuf *gzip_data) {
    mz_stream stream = {0};
    int status;
    mz_ulong crc = mz_crc32(MZ_CRC32_INIT, (const unsigned char *) data, size);

    // 分配压缩缓冲区 - 预留头部(10字节)和尾部(8字节)的空间
    mz_ulong compressed_size = mz_compressBound(size) + 18;
    unsigned char *compressed_data = (unsigned char *) MZ_MALLOC(compressed_size);
    if (!compressed_data) {
        return -1;
    }

    // 写入GZIP头部
    compressed_data[0] = 0x1F;  // ID1
    compressed_data[1] = 0x8B;  // ID2
    compressed_data[2] = 0x08;  // CM = DEFLATE
    compressed_data[3] = 0x00;  // FLG
    compressed_data[4] = 0x00;  // MTIME (4 bytes)
    compressed_data[5] = 0x00;
    compressed_data[6] = 0x00;
    compressed_data[7] = 0x00;
    compressed_data[8] = 0x00;  // XFL
    compressed_data[9] = 0xFF;  // OS = unknown

    // 设置压缩流
    stream.next_in = (const unsigned char *) data;
    stream.avail_in = size;
    stream.next_out = compressed_data + 10;  // 跳过GZIP头
    stream.avail_out = compressed_size - 18;  // 减去头和尾的大小

    // 初始化deflate
    status = mz_deflateInit2(&stream, MZ_DEFAULT_LEVEL, MZ_DEFLATED, -MZ_DEFAULT_WINDOW_BITS, 8, MZ_DEFAULT_STRATEGY);
    if (status != MZ_OK) {
        MZ_FREE(compressed_data);
        return -1;
    }

    // 执行压缩
    status = mz_deflate(&stream, MZ_FINISH);
    if (status != MZ_STREAM_END) {
        mz_deflateEnd(&stream);
        MZ_FREE(compressed_data);
        return -1;
    }

    // 获取压缩后的大小
    mz_ulong compressed_len = stream.total_out;
    mz_deflateEnd(&stream);

    // 写入CRC32和原始大小(8字节尾部)
    unsigned char *footer = compressed_data + 10 + compressed_len;
    *(mz_uint32 *) footer = crc;
    *(mz_uint32 *) (footer + 4) = size;

    // 写入到输出缓冲区
    bytebuf_write_batch(gzip_data, (char *) compressed_data, compressed_len + 18);
    MZ_FREE(compressed_data);

    return 0;
}

// 修改gzip_extract函数，解析标准GZIP格式
s32 gzip_extract(char *gzip_data, int size, ByteBuf *data) {
    if (size < 18 ||
        (unsigned char) gzip_data[0] != 0x1F ||
        (unsigned char) gzip_data[1] != 0x8B ||
        (unsigned char) gzip_data[2] != 0x08) {
        return -1;  // 无效的GZIP格式
    }

    mz_stream stream = {0};
    int status;

    // 读取原始大小(从尾部)
    mz_uint32 original_size = *(mz_uint32 *) (gzip_data + size - 4);
    mz_uint32 expected_crc = *(mz_uint32 *) (gzip_data + size - 8);

    // 分配解压缓冲区
    unsigned char *uncompressed_data = (unsigned char *) MZ_MALLOC(original_size);
    if (!uncompressed_data) {
        return -1;
    }

    // 设置解压流
    stream.next_in = (unsigned char *) gzip_data + 10;  // 跳过GZIP头
    stream.avail_in = size - 18;  // 减去头和尾的大小
    stream.next_out = uncompressed_data;
    stream.avail_out = original_size;

    // 初始化inflate
    status = mz_inflateInit2(&stream, -MZ_DEFAULT_WINDOW_BITS);
    if (status != MZ_OK) {
        MZ_FREE(uncompressed_data);
        return -1;
    }

    // 执行解压
    status = mz_inflate(&stream, MZ_FINISH);
    mz_inflateEnd(&stream);

    if (status != MZ_STREAM_END || stream.total_out != original_size) {
        MZ_FREE(uncompressed_data);
        return -1;
    }

    // 验证CRC32
    mz_uint32 computed_crc = mz_crc32(MZ_CRC32_INIT, uncompressed_data, original_size);
    if (computed_crc != expected_crc) {
        MZ_FREE(uncompressed_data);
        return -1;
    }

    // 写入到输出缓冲区
    bytebuf_write_batch(data, (char *) uncompressed_data, original_size);
    MZ_FREE(uncompressed_data);

    return 0;
}

//
//
//void test_gzip_compression() {
//    // 测试数据
//    const char *original_data = "这是一个测试字符串，用于验证gzip压缩和解压功能是否正常工作。";
//    int original_size = strlen(original_data) + 1; // 包含null终止符
//
//    // 初始化缓冲区
//    ByteBuf *compressed_buf = bytebuf_create(1024);
//    ByteBuf *decompressed_buf = bytebuf_create(1024);
//
//    // 压缩数据
//    printf("开始压缩...\n");
//    int compress_result = gzip_compress((char *) original_data, original_size, compressed_buf);
//    if (compress_result != 0) {
//        printf("压缩失败!\n");
//        return;
//    }
//    printf("压缩成功，压缩后大小: %d 字节\n", compressed_buf->wp);
//
//    // 解压数据
//    printf("开始解压...\n");
//    int decompress_result = gzip_extract(compressed_buf->buf, compressed_buf->wp, decompressed_buf);
//    if (decompress_result != 0) {
//        printf("解压失败!\n");
//        return;
//    }
//    printf("解压成功，解压后大小: %d 字节\n", decompressed_buf->wp);
//
//    // 比较数据
//    if (original_size != decompressed_buf->wp) {
//        printf("数据大小不一致! 原始: %d, 解压后: %d\n", original_size, decompressed_buf->wp);
//    } else if (memcmp(original_data, decompressed_buf->buf, original_size) != 0) {
//        printf("数据内容不一致!\n");
//    } else {
//        printf("测试通过! 原始数据和解压数据完全一致。\n");
//    }
//
//    // 清理
//    bytebuf_destroy(compressed_buf);
//    bytebuf_destroy(decompressed_buf);
//}
//
//void test_gzip_file_compression() {
//    const char *input_file = "./f"; // 输入文件路径
//    const char *compressed_file = "./test_compressed.gz"; // 压缩后文件路径
//    const char *decompressed_file = "./test_decompressed.dat"; // 解压后文件路径
//
//    // 1. 读取原始文件内容
//    ByteBuf *original_buf = bytebuf_create(0);
//    FILE *fp = fopen(input_file, "rb");
//    if (!fp) {
//        printf("无法打开输入文件: %s\n", input_file);
//        return;
//    }
//
//    fseek(fp, 0, SEEK_END);
//    long file_size = ftell(fp);
//    fseek(fp, 0, SEEK_SET);
//
//    bytebuf_expand(original_buf, file_size);
//    fread(original_buf->buf, 1, file_size, fp);
//    original_buf->wp = file_size;
//    fclose(fp);
//
//    // 2. 压缩数据
//    ByteBuf *compressed_buf = bytebuf_create(0);
//    printf("开始压缩文件...\n");
//    if (gzip_compress(original_buf->buf, original_buf->wp, compressed_buf) != 0) {
//        printf("文件压缩失败\n");
//        goto cleanup;
//    }
//    printf("压缩成功，压缩后大小: %d 字节\n", compressed_buf->wp);
//
//
//    // 保存压缩文件
//    fp = fopen(compressed_file, "wb");
//    if (!fp) {
//        printf("无法创建压缩文件\n");
//        goto cleanup;
//    }
//    fwrite(compressed_buf->buf, 1, compressed_buf->wp, fp);
//    fclose(fp);
//
//
//
//    compressed_file = "./f_c.gz";
//    FILE *fp1 = fopen(compressed_file, "rb");
//    if (!fp1) {
//        printf("无法打开输入文件: %s\n", compressed_file);
//        return;
//    }
//
//    fseek(fp1, 0, SEEK_END);
//    long file_size1 = ftell(fp1);
//    fseek(fp1, 0, SEEK_SET);
//
//    bytebuf_expand(compressed_buf, file_size1);
//    fread(compressed_buf->buf, 1, file_size, fp1);
//    compressed_buf->wp = file_size1;
//    fclose(fp1);
//    // 3. 解压数据
//    ByteBuf *decompressed_buf = bytebuf_create(0);
//    printf("开始解压文件...\n");
//    if (gzip_extract(compressed_buf->buf, compressed_buf->wp, decompressed_buf) != 0) {
//        printf("文件解压失败\n");
//        goto cleanup;
//    }
//    printf("解压成功，解压后大小: %d 字节\n", decompressed_buf->wp);
//
//    // 保存解压文件
//    fp = fopen(decompressed_file, "wb");
//    if (!fp) {
//        printf("无法创建解压文件\n");
//        goto cleanup;
//    }
//    fwrite(decompressed_buf->buf, 1, decompressed_buf->wp, fp);
//    fclose(fp);
//
//    // 4. 验证数据一致性
//    if (original_buf->wp != decompressed_buf->wp) {
//        printf("警告: 文件大小不一致 (原始: %d, 解压后: %d)\n", original_buf->wp, decompressed_buf->wp);
//    } else if (memcmp(original_buf->buf, decompressed_buf->buf, original_buf->wp) != 0) {
//        printf("警告: 文件内容不一致\n");
//    } else {
//        printf("测试成功! 原始文件和解压文件完全一致\n");
//    }
//
//    cleanup:
//    // 释放资源
//    if (original_buf) bytebuf_destroy(original_buf);
//    if (compressed_buf) bytebuf_destroy(compressed_buf);
//    if (decompressed_buf) bytebuf_destroy(decompressed_buf);
//}
//
//
//int main() {
//    test_gzip_compression();
//    test_gzip_file_compression();
//    return 0;
//}
