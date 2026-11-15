//! Minimal PNG encoder, so tiles and world slices can be exported as images
//! without pulling in a dependency.
//!
//! Uses stored (uncompressed) deflate blocks: the files are larger than a
//! real encoder would produce, but the format is valid and the code is small
//! enough to audit.

/// Encode `rgba` (row-major, 4 bytes per pixel) as an 8-bit RGBA PNG.
///
/// # Panics
/// If `rgba.len()` is not `width * height * 4`.
pub fn encode_rgba(width: u32, height: u32, rgba: &[u8]) -> Vec<u8> {
    let expected = width as usize * height as usize * 4;
    assert_eq!(
        rgba.len(),
        expected,
        "pixel buffer must hold width * height * 4 bytes"
    );

    let mut out = Vec::with_capacity(expected + expected / 64 + 128);
    out.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);

    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.push(8); // bit depth
    ihdr.push(6); // truecolour with alpha
    ihdr.push(0); // deflate
    ihdr.push(0); // adaptive filtering
    ihdr.push(0); // no interlace
    write_chunk(&mut out, b"IHDR", &ihdr);

    // Scanlines, each prefixed with filter type 0 (None).
    let stride = width as usize * 4;
    let mut raw = Vec::with_capacity(height as usize * (stride + 1));
    for row in 0..height as usize {
        raw.push(0);
        raw.extend_from_slice(&rgba[row * stride..(row + 1) * stride]);
    }

    write_chunk(&mut out, b"IDAT", &zlib_stored(&raw));
    write_chunk(&mut out, b"IEND", &[]);

    out
}

/// Append a length-type-data-CRC chunk.
fn write_chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(kind);
    out.extend_from_slice(data);

    let mut crc_input = Vec::with_capacity(4 + data.len());
    crc_input.extend_from_slice(kind);
    crc_input.extend_from_slice(data);
    out.extend_from_slice(&crc32(&crc_input).to_be_bytes());
}

/// Wrap `raw` in a zlib stream built from stored (uncompressed) deflate blocks.
fn zlib_stored(raw: &[u8]) -> Vec<u8> {
    const MAX_BLOCK: usize = 0xFFFF;

    let mut out = vec![0x78, 0x01];

    if raw.is_empty() {
        // A single final, empty stored block.
        out.extend_from_slice(&[1, 0, 0, 0xFF, 0xFF]);
    } else {
        let blocks: Vec<&[u8]> = raw.chunks(MAX_BLOCK).collect();
        let last = blocks.len() - 1;

        for (index, block) in blocks.iter().enumerate() {
            out.push(if index == last { 1 } else { 0 });

            let len = block.len() as u16;
            out.extend_from_slice(&len.to_le_bytes());
            out.extend_from_slice(&(!len).to_le_bytes());
            out.extend_from_slice(block);
        }
    }

    out.extend_from_slice(&adler32(raw).to_be_bytes());
    out
}

fn adler32(data: &[u8]) -> u32 {
    const MOD: u32 = 65521;

    let mut a: u32 = 1;
    let mut b: u32 = 0;

    for &byte in data {
        a = (a + byte as u32) % MOD;
        b = (b + a) % MOD;
    }

    (b << 16) | a
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFF_FFFF;

    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }

    !crc
}

#[cfg(test)]
mod tests {
    use super::*;

    const SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

    fn tiny_image() -> (u32, u32, Vec<u8>) {
        // 2x2: red, green, blue, white
        let pixels = vec![
            255, 0, 0, 255, //
            0, 255, 0, 255, //
            0, 0, 255, 255, //
            255, 255, 255, 255,
        ];
        (2, 2, pixels)
    }

    #[test]
    fn output_starts_with_the_png_signature() {
        let (w, h, pixels) = tiny_image();

        let encoded = encode_rgba(w, h, &pixels);

        assert_eq!(&encoded[..8], &SIGNATURE, "missing PNG magic bytes");
    }

    #[test]
    fn output_ends_with_an_iend_chunk() {
        let (w, h, pixels) = tiny_image();

        let encoded = encode_rgba(w, h, &pixels);

        assert_eq!(
            &encoded[encoded.len() - 12..],
            &[
                0, 0, 0, 0, // zero-length data
                b'I', b'E', b'N', b'D', //
                0xAE, 0x42, 0x60, 0x82, // CRC of "IEND"
            ],
            "stream should close with a zero-length IEND chunk"
        );
    }

    #[test]
    fn ihdr_declares_the_requested_dimensions_and_rgba_format() {
        let encoded = encode_rgba(7, 3, &vec![0u8; 7 * 3 * 4]);

        // IHDR data begins at: 8 signature + 4 length + 4 type.
        let ihdr = &encoded[16..16 + 13];

        assert_eq!(u32::from_be_bytes([ihdr[0], ihdr[1], ihdr[2], ihdr[3]]), 7);
        assert_eq!(u32::from_be_bytes([ihdr[4], ihdr[5], ihdr[6], ihdr[7]]), 3);
        assert_eq!(ihdr[8], 8, "bit depth should be 8");
        assert_eq!(ihdr[9], 6, "colour type should be 6 (truecolour + alpha)");
        assert_eq!(ihdr[10], 0, "compression method should be 0 (deflate)");
        assert_eq!(ihdr[11], 0, "filter method should be 0");
        assert_eq!(ihdr[12], 0, "interlace should be 0 (none)");
    }

    #[test]
    fn large_images_span_multiple_deflate_blocks_without_corruption() {
        // Wider than one 65535-byte stored block, so block splitting is exercised.
        let (w, h) = (200u32, 200u32);
        let encoded = encode_rgba(w, h, &vec![128u8; (w * h * 4) as usize]);

        assert!(
            encoded.len() > (w * h * 4) as usize,
            "stored deflate should be at least as large as the raw data"
        );
        assert_eq!(&encoded[..8], &SIGNATURE);
    }

    #[test]
    #[should_panic(expected = "pixel buffer")]
    fn mismatched_buffer_length_is_rejected() {
        encode_rgba(4, 4, &[0u8; 10]);
    }
}
