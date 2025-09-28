// src/game_engine.rs
use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use web_sys::{window, HtmlCanvasElement, CanvasRenderingContext2d};

/// Install better panic messages on the JS console
#[wasm_bindgen(start)]
pub fn wasm_start() -> Result<(), JsValue> {
    console_error_panic_hook::set_once();
    Ok(())
}

#[wasm_bindgen]
pub struct GameEngine {
    width: u32,
    height: u32,
    ctx: CanvasRenderingContext2d,
    x: f64,
    y: f64,
    dx: f64,
    dy: f64,
}

#[wasm_bindgen]
impl GameEngine {
    /// Create engine from an existing canvas id (string)
    #[wasm_bindgen(constructor)]
    pub fn new(canvas_id: &str) -> Result<GameEngine, JsValue> {
        let window = window().ok_or_else(|| JsValue::from_str("no window"))?;
        let document = window.document().ok_or_else(|| JsValue::from_str("no document"))?;
        let el = document
            .get_element_by_id(canvas_id)
            .ok_or_else(|| JsValue::from_str("canvas not found"))?;
        let canvas: HtmlCanvasElement = el.dyn_into::<HtmlCanvasElement>()?;
        let ctx = canvas
            .get_context("2d")?
            .ok_or_else(|| JsValue::from_str("failed to get 2d context"))?
            .dyn_into::<CanvasRenderingContext2d>()?;

        let width = canvas.width();
        let height = canvas.height();

        Ok(GameEngine {
            width,
            height,
            ctx,
            x: (width / 2) as f64,
            y: (height / 2) as f64,
            dx: 2.0,
            dy: 1.5,
        })
    }

    /// Advance simple physics
    pub fn update(&mut self) {
        self.x += self.dx;
        self.y += self.dy;

        if self.x < 0.0 || self.x > self.width as f64 {
            self.dx = -self.dx;
        }
        if self.y < 0.0 || self.y > self.height as f64 {
            self.dy = -self.dy;
        }
    }

    /// Render a simple frame (background + red square)
    pub fn render(&self) {
        // clear canvas with black background
        self.ctx.set_fill_style(&JsValue::from_str("#000"));
        self.ctx.fill_rect(0.0, 0.0, self.width as f64, self.height as f64);

        // draw red square
        self.ctx.set_fill_style(&JsValue::from_str("#e74c3c"));
        self.ctx.fill_rect(self.x - 10.0, self.y - 10.0, 20.0, 20.0);
    }

    /// Resize canvas information if you change canvas size from JS
    pub fn resize(&mut self, w: u32, h: u32) {
        self.width = w;
        self.height = h;
    }
}