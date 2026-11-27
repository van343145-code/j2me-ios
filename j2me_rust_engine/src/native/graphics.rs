use image::GenericImageView;

pub fn decode_image(data: &[u8]) -> Option<(i32, i32, Vec<i32>)> {
    let img = image::load_from_memory(data).ok()?;
    let (w, h) = img.dimensions();
    let rgba = img.to_rgba8();
    let mut pixels = Vec::with_capacity((w * h) as usize);
    for p in rgba.pixels() {
        let r = p[0] as u32;
        let g = p[1] as u32;
        let b = p[2] as u32;
        let a = p[3] as u32;
        let argb = (a << 24) | (r << 16) | (g << 8) | b;
        pixels.push(argb as i32);
    }
    Some((w as i32, h as i32, pixels))
}

#[inline(always)]
fn blend_pixel(dst: i32, src: i32) -> i32 {
    let sa = ((src as u32) >> 24) & 0xFF;
    if sa == 255 {
        return src;
    }
    if sa == 0 {
        return dst;
    }
    let da = ((dst as u32) >> 24) & 0xFF;
    let inv_sa = 255 - sa;

    let sr = ((src as u32) >> 16) & 0xFF;
    let sg = ((src as u32) >> 8) & 0xFF;
    let sb = (src as u32) & 0xFF;

    let dr = ((dst as u32) >> 16) & 0xFF;
    let dg = ((dst as u32) >> 8) & 0xFF;
    let db = (dst as u32) & 0xFF;

    let out_a = sa + (da * inv_sa) / 255;
    let out_r = (sr * sa + dr * inv_sa) / 255;
    let out_g = (sg * sa + dg * inv_sa) / 255;
    let out_b = (sb * sa + db * inv_sa) / 255;

    ((out_a << 24) | (out_r << 16) | (out_g << 8) | out_b) as i32
}

pub fn fill_rect(
    pixels: &mut [i32],
    stride: i32,
    cx: i32,
    cy: i32,
    cw: i32,
    ch: i32,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    color: i32,
) {
    if stride <= 0 || w <= 0 || h <= 0 {
        return;
    }
    let total_h = (pixels.len() as i32) / stride;

    // Intersection with clip
    let clip_x2 = (cx + cw).min(stride);
    let clip_y2 = (cy + ch).min(total_h);
    let clip_x1 = cx.max(0);
    let clip_y1 = cy.max(0);

    let draw_x1 = x.max(clip_x1);
    let draw_y1 = y.max(clip_y1);
    let draw_x2 = (x + w).min(clip_x2);
    let draw_y2 = (y + h).min(clip_y2);

    if draw_x1 >= draw_x2 || draw_y1 >= draw_y2 {
        return;
    }

    let has_alpha = ((color as u32) >> 24) < 255;

    for row in draw_y1..draw_y2 {
        let row_start = (row * stride + draw_x1) as usize;
        let row_end = (row * stride + draw_x2) as usize;
        if has_alpha {
            for px in &mut pixels[row_start..row_end] {
                *px = blend_pixel(*px, color);
            }
        } else {
            pixels[row_start..row_end].fill(color);
        }
    }
}

pub fn draw_line(
    pixels: &mut [i32],
    stride: i32,
    cx: i32,
    cy: i32,
    cw: i32,
    ch: i32,
    mut x1: i32,
    mut y1: i32,
    x2: i32,
    y2: i32,
    color: i32,
) {
    if stride <= 0 {
        return;
    }
    let total_h = (pixels.len() as i32) / stride;
    let clip_x1 = cx.max(0);
    let clip_y1 = cy.max(0);
    let clip_x2 = (cx + cw).min(stride);
    let clip_y2 = (cy + ch).min(total_h);

    let dx = (x2 - x1).abs();
    let sx = if x1 < x2 { 1 } else { -1 };
    let dy = -(y2 - y1).abs();
    let sy = if y1 < y2 { 1 } else { -1 };
    let mut err = dx + dy;

    loop {
        if x1 >= clip_x1 && x1 < clip_x2 && y1 >= clip_y1 && y1 < clip_y2 {
            let idx = (y1 * stride + x1) as usize;
            if idx < pixels.len() {
                pixels[idx] = blend_pixel(pixels[idx], color);
            }
        }
        if x1 == x2 && y1 == y2 {
            break;
        }
        let e2 = 2 * err;
        if e2 >= dy {
            err += dy;
            x1 += sx;
        }
        if e2 <= dx {
            err += dx;
            y1 += sy;
        }
    }
}

pub fn draw_rgb(
    dst: &mut [i32],
    dst_stride: i32,
    cx: i32,
    cy: i32,
    cw: i32,
    ch: i32,
    src: &[i32],
    offset: i32,
    scanlen: i32,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    process_alpha: bool,
) {
    if dst_stride <= 0 || w <= 0 || h <= 0 || scanlen <= 0 {
        return;
    }
    let total_h = (dst.len() as i32) / dst_stride;
    let clip_x1 = cx.max(0);
    let clip_y1 = cy.max(0);
    let clip_x2 = (cx + cw).min(dst_stride);
    let clip_y2 = (cy + ch).min(total_h);

    for row in 0..h {
        let dest_y = y + row;
        if dest_y < clip_y1 || dest_y >= clip_y2 {
            continue;
        }
        let src_row_start = (offset + row * scanlen) as usize;

        for col in 0..w {
            let dest_x = x + col;
            if dest_x < clip_x1 || dest_x >= clip_x2 {
                continue;
            }
            let src_idx = src_row_start + col as usize;
            if src_idx >= src.len() {
                break;
            }
            let sp = src[src_idx];
            let dp_idx = (dest_y * dst_stride + dest_x) as usize;
            if dp_idx < dst.len() {
                if process_alpha {
                    dst[dp_idx] = blend_pixel(dst[dp_idx], sp);
                } else {
                    dst[dp_idx] = (sp as u32 | 0xFF00_0000) as i32;
                }
            }
        }
    }
}
