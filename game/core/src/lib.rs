//! Engine-agnostic game logic for Deepdelve.
//!
//! This crate deliberately has no rendering, windowing, or engine dependency so
//! that every rule of the game can be tested headlessly. The Bevy layer on top
//! only draws what lives here and feeds input into it.

pub mod art;
pub mod craft;
pub mod enemy;
pub mod interact;
pub mod item;
pub mod noise;
pub mod physics;
pub mod png;
pub mod tilemap;
pub mod view;
pub mod world;
