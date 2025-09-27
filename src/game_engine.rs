use wasm_bindgen::prelude::*;
use web_sys::{CanvasRenderingContext2d, HtmlCanvasElement};

// Đảm bảo khi có panic sẽ log ra console
#[wasm_bindgen(start)]
pub fn main_js() -> Result<(), JsValue> {
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
    #[wasm_bindgen(constructor)]
    pub fn new(canvas_id: &str) -> Result<GameEngine, JsValue> {
        // Lấy canvas từ DOM
        let window = web_sys::window().unwrap();
        let document = window.document().unwrap();
        let canvas = document
            .get_element_by_id(canvas_id)
            .unwrap()
            .dyn_into::<HtmlCanvasElement>()?;

        let ctx = canvas
            .get_context("2d")?
            .unwrap()
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

    pub fn render(&self) {
        self.ctx.set_fill_style(&JsValue::from_str("black"));
        self.ctx
            .fill_rect(0.0, 0.0, self.width as f64, self.height as f64);

        self.ctx.set_fill_style(&JsValue::from_str("red"));
        self.ctx.fill_rect(self.x - 10.0, self.y - 10.0, 20.0, 20.0);
    }
}
