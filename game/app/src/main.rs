//! Bevy frontend for Deepdelve.
//!
//! Deliberately thin: this layer draws what `deepdelve-core` decides and
//! feeds input into it. No game rules live here.

use bevy::prelude::*;

fn main() {
    App::new().add_plugins(DefaultPlugins).run();
}
