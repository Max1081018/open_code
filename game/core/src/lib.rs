//! Engine-agnostic game logic for Deepdelve.
//!
//! This crate deliberately has no rendering, windowing, or engine dependency so
//! that every rule of the game can be tested headlessly. The Bevy layer on top
//! only draws what lives here and feeds input into it.

pub mod noise;
pub mod world;
