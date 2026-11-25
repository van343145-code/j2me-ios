package java.util;

public class Base64 {
    private Base64() {}

    public static Encoder getEncoder() {
        return Encoder.RFC4648;
    }

    public static Encoder getUrlEncoder() {
        return Encoder.RFC4648_URLSAFE;
    }

    public static Encoder getMimeEncoder() {
        return Encoder.RFC2045;
    }

    public static Encoder getMimeEncoder(int lineLength, byte[] lineSeparator) {
        if (lineSeparator == null) {
            throw new NullPointerException();
        }
        int[] base64 = Decoder.fromBase64;
        for (int i = 0; i < lineSeparator.length; i++) {
            int b = lineSeparator[i] & 0xFF;
            if (b < base64.length && base64[b] != -1) {
                throw new IllegalArgumentException("Illegal base64 line separator character 0x" + Integer.toString(b, 16));
            }
        }
        lineLength &= ~0b11;
        if (lineLength <= 0) {
            return Encoder.RFC4648;
        }
        return new Encoder(false, lineSeparator, lineLength, true);
    }

    public static Decoder getDecoder() {
        return Decoder.RFC4648;
    }

    public static Decoder getUrlDecoder() {
        return Decoder.RFC4648_URLSAFE;
    }

    public static Decoder getMimeDecoder() {
        return Decoder.RFC2045;
    }

    public static class Encoder {
        private final byte[] newline;
        private final int linemax;
        private final boolean isURL;
        private final boolean doPadding;

        private Encoder(boolean isURL, byte[] newline, int linemax, boolean doPadding) {
            this.isURL = isURL;
            this.newline = newline;
            this.linemax = linemax;
            this.doPadding = doPadding;
        }

        private static final char[] toBase64 = {
            'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
            'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
            'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/'
        };

        private static final char[] toBase64URL = {
            'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
            'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
            'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-', '_'
        };

        private static final int MIMELINEMAX = 76;
        private static final byte[] CRLF = new byte[] {'\r', '\n'};

        static final Encoder RFC4648 = new Encoder(false, null, -1, true);
        static final Encoder RFC4648_URLSAFE = new Encoder(true, null, -1, true);
        static final Encoder RFC2045 = new Encoder(false, CRLF, MIMELINEMAX, true);

        private int outLength(int srclen) {
            int len;
            if (doPadding) {
                len = 4 * ((srclen + 2) / 3);
            } else {
                int n = srclen % 3;
                len = 4 * (srclen / 3) + (n == 0 ? 0 : n + 1);
            }
            if (linemax > 0) {
                len += (len - 1) / linemax * newline.length;
            }
            return len;
        }

        public byte[] encode(byte[] src) {
            int len = outLength(src.length);
            byte[] dst = new byte[len];
            int ret = encode0(src, 0, src.length, dst);
            if (ret != dst.length) {
                return Arrays.copyOf(dst, ret);
            }
            return dst;
        }

        public int encode(byte[] src, byte[] dst) {
            int len = outLength(src.length);
            if (dst.length < len) {
                throw new IllegalArgumentException("Output byte array is too small for encoding all input bytes");
            }
            return encode0(src, 0, src.length, dst);
        }

        public String encodeToString(byte[] src) {
            byte[] encoded = encode(src);
            char[] chars = new char[encoded.length];
            for (int i = 0; i < encoded.length; i++) {
                chars[i] = (char) (encoded[i] & 0xFF);
            }
            return new String(chars);
        }

        public Encoder withoutPadding() {
            if (!doPadding) {
                return this;
            }
            return new Encoder(isURL, newline, linemax, false);
        }

        private int encode0(byte[] src, int off, int end, byte[] dst) {
            char[] base64 = isURL ? toBase64URL : toBase64;
            int sp = off;
            int slen = (end - off) / 3 * 3;
            int sl = off + slen;
            if (linemax > 0 && slen > linemax / 4 * 3) {
                slen = linemax / 4 * 3;
            }
            int dp = 0;
            while (sp < sl) {
                int sl0 = Math.min(sp + slen, sl);
                for (int sp0 = sp, dp0 = dp; sp0 < sl0; ) {
                    int bits = (src[sp0++] & 0xff) << 16 |
                               (src[sp0++] & 0xff) << 8 |
                               (src[sp0++] & 0xff);
                    dst[dp0++] = (byte) base64[(bits >>> 18) & 0x3f];
                    dst[dp0++] = (byte) base64[(bits >>> 12) & 0x3f];
                    dst[dp0++] = (byte) base64[(bits >>> 6) & 0x3f];
                    dst[dp0++] = (byte) base64[bits & 0x3f];
                }
                int dlen = (sl0 - sp) / 3 * 4;
                dp += dlen;
                sp = sl0;
                if (dlen == linemax && sp < end) {
                    for (int i = 0; i < newline.length; i++) {
                        dst[dp++] = newline[i];
                    }
                }
            }
            if (sp < end) {
                int b0 = src[sp++] & 0xff;
                dst[dp++] = (byte) base64[b0 >> 2];
                if (sp == end) {
                    dst[dp++] = (byte) base64[(b0 << 4) & 0x3f];
                    if (doPadding) {
                        dst[dp++] = '=';
                        dst[dp++] = '=';
                    }
                } else {
                    int b1 = src[sp++] & 0xff;
                    dst[dp++] = (byte) base64[(b0 << 4) & 0x3f | (b1 >> 4)];
                    dst[dp++] = (byte) base64[(b1 << 2) & 0x3f];
                    if (doPadding) {
                        dst[dp++] = '=';
                    }
                }
            }
            return dp;
        }
    }

    public static class Decoder {
        private final boolean isURL;
        private final boolean isMIME;

        private Decoder(boolean isURL, boolean isMIME) {
            this.isURL = isURL;
            this.isMIME = isMIME;
        }

        private static final int[] fromBase64 = new int[256];
        private static final int[] fromBase64URL = new int[256];

        static {
            Arrays.fill(fromBase64, -1);
            for (int i = 0; i < Encoder.toBase64.length; i++) {
                fromBase64[Encoder.toBase64[i]] = i;
            }
            fromBase64['='] = -2;

            Arrays.fill(fromBase64URL, -1);
            for (int i = 0; i < Encoder.toBase64URL.length; i++) {
                fromBase64URL[Encoder.toBase64URL[i]] = i;
            }
            fromBase64URL['='] = -2;
        }

        static final Decoder RFC4648 = new Decoder(false, false);
        static final Decoder RFC4648_URLSAFE = new Decoder(true, false);
        static final Decoder RFC2045 = new Decoder(false, true);

        public byte[] decode(byte[] src) {
            byte[] dst = new byte[outLength(src, 0, src.length)];
            int ret = decode0(src, 0, src.length, dst);
            if (ret != dst.length) {
                dst = Arrays.copyOf(dst, ret);
            }
            return dst;
        }

        public byte[] decode(String src) {
            byte[] bytes = new byte[src.length()];
            for (int i = 0; i < src.length(); i++) {
                char c = src.charAt(i);
                if (c > 0xFF) {
                    throw new IllegalArgumentException("Illegal base64 character " + Integer.toString(c, 16));
                }
                bytes[i] = (byte) c;
            }
            return decode(bytes);
        }

        public int decode(byte[] src, byte[] dst) {
            int len = outLength(src, 0, src.length);
            if (dst.length < len) {
                throw new IllegalArgumentException("Output byte array is too small for decoding all input bytes");
            }
            return decode0(src, 0, src.length, dst);
        }

        private int outLength(byte[] src, int sp, int sl) {
            int[] base64 = isURL ? fromBase64URL : fromBase64;
            int paddings = 0;
            int len = sl - sp;
            if (len == 0) {
                return 0;
            }
            if (len < 2) {
                if (isMIME && base64[0] == -1) {
                    return 0;
                }
                throw new IllegalArgumentException("Input byte[] should at least have 2 bytes for base64 bytes");
            }
            if (isMIME) {
                int n = 0;
                while (sp < sl) {
                    int b = src[sp++] & 0xff;
                    if (b == '=') {
                        len -= (sl - sp + 1);
                        break;
                    }
                    if (base64[b] == -1) {
                        n++;
                    }
                }
                len -= n;
            } else if (src[sl - 1] == '=') {
                paddings++;
                if (src[sl - 2] == '=') {
                    paddings++;
                }
            }
            if (paddings == 0 && (len & 0x3) != 0) {
                paddings = 4 - (len & 0x3);
            }
            return 3 * ((len + 3) / 4) - paddings;
        }

        private int decode0(byte[] src, int sp, int sl, byte[] dst) {
            int[] base64 = isURL ? fromBase64URL : fromBase64;
            int dp = 0;
            int bits = 0;
            int shiftto = 18;
            while (sp < sl) {
                if (shiftto == 18 && sp + 4 < sl) {
                    int sl0 = sp + ((sl - sp) & ~3);
                    while (sp < sl0) {
                        int b1 = base64[src[sp++] & 0xff];
                        int b2 = base64[src[sp++] & 0xff];
                        int b3 = base64[src[sp++] & 0xff];
                        int b4 = base64[src[sp++] & 0xff];
                        if ((b1 | b2 | b3 | b4) < 0) {
                            sp -= 4;
                            break;
                        }
                        int bits0 = b1 << 18 | b2 << 12 | b3 << 6 | b4;
                        dst[dp++] = (byte) (bits0 >> 16);
                        dst[dp++] = (byte) (bits0 >> 8);
                        dst[dp++] = (byte) bits0;
                    }
                    if (sp >= sl) {
                        break;
                    }
                }
                int b = src[sp++] & 0xff;
                if ((b = base64[b]) < 0) {
                    if (b == -2) {
                        if ((shiftto == 6 && (sp == sl || src[sp++] != '=')) || shiftto == 18) {
                            throw new IllegalArgumentException("Input byte array has wrong 4-byte ending unit");
                        }
                        break;
                    }
                    if (isMIME) {
                        continue;
                    }
                    throw new IllegalArgumentException("Illegal base64 character " + Integer.toString(src[sp - 1], 16));
                }
                bits |= (b << shiftto);
                shiftto -= 6;
                if (shiftto < 0) {
                    dst[dp++] = (byte) (bits >> 16);
                    dst[dp++] = (byte) (bits >> 8);
                    dst[dp++] = (byte) bits;
                    shiftto = 18;
                    bits = 0;
                }
            }
            if (shiftto == 6) {
                dst[dp++] = (byte) (bits >> 16);
            } else if (shiftto == 0) {
                dst[dp++] = (byte) (bits >> 16);
                dst[dp++] = (byte) (bits >> 8);
            } else if (shiftto == 12) {
                throw new IllegalArgumentException("Last unit does not have enough valid bits");
            }
            while (sp < sl) {
                if (isMIME && base64[src[sp++] & 0xff] < 0) {
                    continue;
                }
                throw new IllegalArgumentException("Input byte array has incorrect ending byte at " + sp);
            }
            return dp;
        }
    }
}
