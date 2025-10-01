use wasm_bindgen::prelude::*;

#[wasm_bindgen(start)]
pub fn wasm_start() -> Result<(), JsValue> {
    console_error_panic_hook::set_once();
    Ok(())
}

#[wasm_bindgen]
pub fn wasm_ready() -> String {
    "WASM module loaded".to_string()
}

#[wasm_bindgen]
pub fn get_launch_url(version: &str) -> String {
    match version {
        "1.8" => "/minecraft_1.8.html".to_string(),
        "1.12" => "/minecraft_1.12.html".to_string(),
        _ => "/index.html".to_string(),
    }
}

#[wasm_bindgen]
pub fn list_versions() -> String {
    "1.8,1.12".to_string()
}

#[wasm_bindgen]
pub fn version_info(version: &str) -> String {
    match version {
        "1.8" => "Minecraft 1.8 - Classic PvP".to_string(),
        "1.12" => "Minecraft 1.12 - Modding friendly".to_string(),
        _ => "Unknown".to_string(),
    }
}

#[wasm_bindgen]
pub fn start_engine(version: &str) -> JsValue {
    let url = get_launch_url(version);
    let obj = js_sys::Object::new();
    js_sys::Reflect::set(&obj, &"status".into(), &"success".into()).ok();
    js_sys::Reflect::set(&obj, &"url".into(), &url.into()).ok();
    js_sys::Reflect::set(&obj, &"version".into(), &version.into()).ok();
    obj.into()
}