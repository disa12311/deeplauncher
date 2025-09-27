// src/lib.rs
// Optional shim — not required when Cargo.toml uses path = "game_engine.rs"
// We keep a minimal re-export so both layouts work.
pub use crate::game_engine::*;
