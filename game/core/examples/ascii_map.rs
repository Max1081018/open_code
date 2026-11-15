//! Print a generated world as ASCII, so terrain can be eyeballed without a GPU.
//!
//! Usage: `cargo run --example ascii_map -- [seed] [width] [height]`

use deepdelve_core::world::{Tile, World};

fn main() {
    let mut args = std::env::args().skip(1);
    let arg = |args: &mut dyn Iterator<Item = String>, default: usize| {
        args.next().and_then(|a| a.parse().ok()).unwrap_or(default)
    };

    let seed = arg(&mut args, 7) as u64;
    let width = arg(&mut args, 118);
    let height = arg(&mut args, 36);

    let world = World::generate(seed, width, height);

    println!("seed {seed}  {width}x{height}");
    for y in 0..world.height() {
        let row: String = (0..world.width())
            .map(|x| match world.tile(x, y) {
                Tile::Air => ' ',
                Tile::Grass => '"',
                Tile::Dirt => '.',
                Tile::Stone => '#',
                Tile::CoalOre => 'c',
                Tile::CopperOre => 'u',
                Tile::IronOre => 'i',
                Tile::GoldOre => 'G',
            })
            .collect();
        println!("|{row}|");
    }
}
