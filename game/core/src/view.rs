//! Visual scale constants, shared by the renderer and the camera.
//!
//! The guiding decision: tiles are deliberately **large**. Terraria draws
//! 16px tiles and fits 45-60 of them across the screen, which on a phone
//! reduces the world to specks. Deepdelve draws chunky, detailed tiles and
//! fits roughly 24 across, so the art is legible at arm's length.

/// Edge length of a source tile texture, in texels.
///
/// 48 gives room for real detail (bevelled edges, mineral flecks, grass
/// fringe) instead of the handful of pixels a 16px tile allows.
pub const TILE_SOURCE_PX: u32 = 48;

/// Integer upscale applied when drawing. Integer scaling keeps pixel art
/// crisp; fractional scaling muddies it.
pub const RENDER_SCALE: u32 = 2;

/// On-screen size of one tile, in physical pixels.
pub const TILE_SCREEN_PX: u32 = TILE_SOURCE_PX * RENDER_SCALE;

/// Roughly how many tiles span the long edge of a landscape phone screen.
/// Used to derive camera zoom; the exact count follows the real viewport.
pub const TARGET_TILES_ACROSS: f32 = 24.0;

/// Player height in tiles. Two tiles tall at 96 screen px per tile makes the
/// character about 18% of a 1080px-tall landscape screen.
pub const PLAYER_HEIGHT_TILES: f32 = 1.8;

/// Player width in tiles. Under 1.0 so the player fits through a single-tile
/// gap, which keeps mined tunnels one tile wide.
pub const PLAYER_WIDTH_TILES: f32 = 0.8;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiles_render_far_larger_than_terrarias_sixteen_pixels() {
        assert!(
            TILE_SCREEN_PX >= 64,
            "tiles must be chunky on screen, got {TILE_SCREEN_PX}px"
        );
    }

    #[test]
    fn upscaling_is_integral_so_pixel_art_stays_crisp() {
        assert_eq!(TILE_SCREEN_PX % TILE_SOURCE_PX, 0);
    }

    #[test]
    fn player_fits_through_a_single_tile_gap() {
        assert!(
            PLAYER_WIDTH_TILES < 1.0,
            "player must squeeze through one-tile tunnels"
        );
    }
}
