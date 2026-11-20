//! Engine-agnostic game logic for Deepdelve.
//!
//! This crate deliberately has no rendering, windowing, or engine dependency so
//! that every rule of the game can be tested headlessly. The Bevy layer on top
//! only draws what lives here and feeds input into it.

pub mod anim;
pub mod art;
pub mod audio;
pub mod biome;
pub mod boss;
pub mod craft;
pub mod daynight;
pub mod decor;
pub mod enemy;
pub mod gear;
pub mod icon;
pub mod interact;
pub mod item;
pub mod light;
pub mod noise;
pub mod paint;
pub mod physics;
pub mod png;
pub mod quest;
pub mod save;
pub mod sky;
pub mod spawn;
pub mod sprite;
pub mod tilemap;
pub mod touch;
pub mod vfx;
pub mod view;
pub mod world;
