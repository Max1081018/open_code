//! Write every synthesised sound to disk, for listening and validation.
//! Usage: `cargo run --example dump_audio -- out_dir`
use deepdelve_core::audio::{ambient_wav, sfx_wav, ALL_SFX};

fn main() {
    let dir = std::env::args().nth(1).unwrap_or_else(|| ".".to_string());
    std::fs::create_dir_all(&dir).expect("create output directory");

    for kind in ALL_SFX {
        let path = format!("{dir}/sfx_{kind:?}.wav").to_lowercase();
        let bytes = sfx_wav(kind);
        std::fs::write(&path, &bytes).expect("write wav");
        println!("{path}: {} bytes", bytes.len());
    }

    for (name, warmth) in [("surface", 0.85f32), ("cave", 0.1)] {
        let path = format!("{dir}/ambient_{name}.wav");
        let bytes = ambient_wav(7, 12.0, warmth);
        std::fs::write(&path, &bytes).expect("write wav");
        println!("{path}: {} bytes", bytes.len());
    }
}
