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

// Launcher functions that HTML expects
#[wasm_bindgen]
pub fn wasm_ready() -> String {
    "WASM module loaded successfully".to_string()
}

#[wasm_bindgen]
pub fn get_launch_url(version: &str) -> String {
    match version {
        "1.8" => "minecraft_1.8.html".to_string(),
        "1.12" => "minecraft_1.12.html".to_string(),
        _ => "index.html".to_string(),
    }
}

#[wasm_bindgen]
pub fn list_versions() -> String {
    "1.8,1.12".to_string()
}

#[wasm_bindgen]
pub fn version_info(version: &str) -> String {
    match version {
        "1.8" => "Minecraft 1.8 - Classic PvP version".to_string(),
        "1.12" => "Minecraft 1.12 - Modding friendly".to_string(),
        _ => "Unknown version".to_string(),
    }
}

// Thread-safe launcher callback storage
use std::sync::Mutex;
use std::sync::OnceLock;

static LAUNCHER_CALLBACK: OnceLock<Mutex<Option<js_sys::Function>>> = OnceLock::new();

#[wasm_bindgen]
pub fn set_launcher_callback(callback: js_sys::Function) {
    let callback_store = LAUNCHER_CALLBACK.get_or_init(|| Mutex::new(None));
    if let Ok(mut cb) = callback_store.lock() {
        *cb = Some(callback);
    }
}

#[wasm_bindgen]
pub fn start_engine(version: &str) -> JsValue {
    let url = get_launch_url(version);
    
    // Try to call the JavaScript callback if set
    let callback_store = LAUNCHER_CALLBACK.get_or_init(|| Mutex::new(None));
    if let Ok(callback_guard) = callback_store.lock() {
        if let Some(ref callback) = *callback_guard {
            let this = JsValue::null();
            let version_val = JsValue::from_str(version);
            let url_val = JsValue::from_str(&url);
            
            if let Err(e) = callback.call2(&this, &version_val, &url_val) {
                web_sys::console::log_1(&format!("Callback error: {:?}", e).into());
            }
        }
    }
    
    // Return result object
    let result = js_sys::Object::new();
    js_sys::Reflect::set(&result, &"status".into(), &"success".into()).unwrap();
    js_sys::Reflect::set(&result, &"url".into(), &url.into()).unwrap();
    js_sys::Reflect::set(&result, &"version".into(), &version.into()).unwrap();
    
    result.into()
}

// Game Engine class for canvas rendering (unchanged)
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