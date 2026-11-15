//! Desktop entry point.
//!
//! All the game lives in the library so the same code can be built as a
//! `cdylib` for Android, where the entry point is `android_main` rather than
//! `main`.

fn main() {
    deepdelve_app::main();
}
