// src/lib.rs
// Improved game_engine for WASM (wasm-bindgen)
// Features:
//  - version registry (add/remove/list)
//  - async start_engine_async -> returns a Promise (JsValue result object)
//  - launcher callback & pack_loader callback (both may return Promise and will be awaited)
//  - event listeners (emit events from Rust to JS)
// Build: wasm-pack build --target web --out-dir ./wasm/pkg

use wasm_bindgen::prelude::*;
use wasm_bindgen::JsCast;
use wasm_bindgen_futures::future_to_promise;
use js_sys::{Array, Function, Object, Reflect, Promise};
use std::cell::RefCell;
use std::collections::HashMap;
use web_sys::window;

// Thread-local storages for callbacks and registry
thread_local! {
    static LAUNCH_CALLBACK: RefCell<Option<Function>> = RefCell::new(None);
    static PACK_LOADER: RefCell<Option<Function>> = RefCell::new(None);
    static EVENT_LISTENERS: RefCell<HashMap<String, Function>> = RefCell::new(HashMap::new());
    static VERSIONS: RefCell<HashMap<String, String>> = {
        // default versions
        let mut m = HashMap::new();
        m.insert("1.8".to_string(), "minecraft_1.8.html".to_string());
        m.insert("1.12".to_string(), "minecraft_1.12.html".to_string());
        RefCell::new(m)
    };
    static VERSION_INFOS: RefCell<HashMap<String, String>> = {
        let mut m = HashMap::new();
        m.insert("1.8".to_string(), "Minecraft 1.8 engine (stub)".to_string());
        m.insert("1.12".to_string(), "Minecraft 1.12 engine (stub)".to_string());
        RefCell::new(m)
    };
}

/// Quick check that wasm module is up.
#[wasm_bindgen]
pub fn wasm_ready() -> String {
    "game_engine (improved) wasm ready".into()
}

/// List registered versions as JS Array of strings.
#[wasm_bindgen]
pub fn list_versions() -> Array {
    VERSIONS.with(|v| {
        let arr = Array::new();
        for k in v.borrow().keys() {
            arr.push(&JsValue::from_str(k));
        }
        arr
    })
}

/// Add or update a version mapping: version -> url
#[wasm_bindgen]
pub fn add_version(version: &str, url: &str, info: Option<String>) -> bool {
    VERSIONS.with(|v| {
        v.borrow_mut().insert(version.to_string(), url.to_string());
    });
    if let Some(i) = info {
        VERSION_INFOS.with(|vi| {
            vi.borrow_mut().insert(version.to_string(), i);
        });
    }
    true
}

/// Remove a registered version. Returns true if removed.
#[wasm_bindgen]
pub fn remove_version(version: &str) -> bool {
    let mut removed = false;
    VERSIONS.with(|v| {
        removed = v.borrow_mut().remove(version).is_some();
    });
    VERSION_INFOS.with(|vi| {
        vi.borrow_mut().remove(version);
    });
    removed
}

/// Get info string for a version
#[wasm_bindgen]
pub fn version_info(version: &str) -> String {
    VERSION_INFOS.with(|vi| {
        vi.borrow().get(version).cloned().unwrap_or_else(|| "unknown version".to_string())
    })
}

/// Get launch URL for a version (from registry)
#[wasm_bindgen]
pub fn get_launch_url(version: &str) -> String {
    VERSIONS.with(|v| {
        v.borrow().get(version).cloned().unwrap_or_else(|| "index.html".to_string())
    })
}

/// Attempt to navigate via web_sys (WASM-side navigation)
#[wasm_bindgen]
pub fn navigate_version(version: &str) -> Result<(), JsValue> {
    let url = get_launch_url(version);
    if let Some(win) = window() {
        win.location().set_href(&url)
    } else {
        Err(JsValue::from_str("no window available"))
    }
}

/// Register a JS function as launcher callback.
/// Rust will call this with (version, url) when it wants JS to perform navigation/animation.
/// The provided JS function may return a Promise — Rust will await it when calling via async APIs.
#[wasm_bindgen]
pub fn set_launcher_callback(cb: &JsValue) -> Result<(), JsValue> {
    if cb.is_function() {
        let f: Function = cb.clone().unchecked_into();
        LAUNCH_CALLBACK.with(|c| {
            *c.borrow_mut() = Some(f);
        });
        Ok(())
    } else {
        Err(JsValue::from_str("callback must be a function"))
    }
}

/// Register a JS function as pack loader.
/// When Rust wants to ensure a version pack is loaded, it will call this with (version, url).
/// The loader function should return a Promise that resolves when loading is complete.
#[wasm_bindgen]
pub fn set_pack_loader(cb: &JsValue) -> Result<(), JsValue> {
    if cb.is_function() {
        let f: Function = cb.clone().unchecked_into();
        PACK_LOADER.with(|p| {
            *p.borrow_mut() = Some(f);
        });
        Ok(())
    } else {
        Err(JsValue::from_str("pack_loader must be a function"))
    }
}

/// Clear launcher callback.
#[wasm_bindgen]
pub fn clear_launcher_callback() {
    LAUNCH_CALLBACK.with(|c| *c.borrow_mut() = None);
}

/// Clear pack loader.
#[wasm_bindgen]
pub fn clear_pack_loader() {
    PACK_LOADER.with(|p| *p.borrow_mut() = None);
}

/// Set an event listener for a custom event name.
/// The callback will be stored under the event name and can be emitted from Rust.
#[wasm_bindgen]
pub fn set_event_listener(event: &str, cb: &JsValue) -> Result<(), JsValue> {
    if !cb.is_function() {
        return Err(JsValue::from_str("listener must be a function"));
    }
    let f: Function = cb.clone().unchecked_into();
    EVENT_LISTENERS.with(|m| {
        m.borrow_mut().insert(event.to_string(), f);
    });
    Ok(())
}

/// Clear event listener.
#[wasm_bindgen]
pub fn clear_event_listener(event: &str) {
    EVENT_LISTENERS.with(|m| {
        m.borrow_mut().remove(event);
    });
}

/// Emit an event from Rust to any registered JS listener.
/// The listener receives (eventName, payload).
fn emit_event(event: &str, payload: &JsValue) {
    EVENT_LISTENERS.with(|m| {
        if let Some(cb) = m.borrow().get(event) {
            let _ = cb.call2(&JsValue::NULL, &JsValue::from_str(event), payload);
        }
    });
}

/// Internal stubbed engine start logic — replace with real engine initialization.
/// Returns (status, message)
fn internal_start_engine_stub(version: &str) -> (String, String) {
    match version {
        "1.8" => ("ok".to_string(), "mc18 engine started (stub)".to_string()),
        "1.12" => ("ok".to_string(), "mc1.12 engine started (stub)".to_string()),
        _ => ("error".to_string(), format!("unknown version: {}", version)),
    }
}

/// Async start engine: returns a Promise resolving to an object { status, message, url, version }
/// Steps:
///  - ensure version exists
///  - if pack_loader is set, call it and await (allow JS to fetch/instantiate pack)
///  - run internal engine init (stub)
///  - call launcher_callback if present (await if returns Promise)
///  - emit events and return final object
#[wasm_bindgen]
pub fn start_engine_async(version: &str) -> Promise {
    let ver = version.to_string();

    // Wrap async logic in a future and convert to Promise
    future_to_promise(async move {
        // Check version exists and get url
        let url = VERSIONS.with(|v| {
            v.borrow().get(&ver).cloned().unwrap_or_else(|| "index.html".to_string())
        });

        // 1) If pack_loader is registered, call it: pack_loader(version, url)
        let pack_ok = PACK_LOADER.with(|p| p.borrow().clone()).map(|f| {
            // call and get result (may be Promise)
            let this = JsValue::NULL;
            match f.call2(&this, &JsValue::from_str(&ver), &JsValue::from_str(&url)) {
                Ok(rv) => Ok(rv),
                Err(e) => Err(e),
            }
        });

        if let Some(Ok(loader_ret)) = pack_ok {
            // If loader returned a Promise, await it
            if loader_ret.is_instance_of::<Promise>() {
                let js_future = wasm_bindgen_futures::JsFuture::from(Promise::from(loader_ret));
                if let Err(e) = js_future.await {
                    let err_obj = Object::new();
                    Reflect::set(&err_obj, &JsValue::from_str("status"), &JsValue::from_str("error"))?;
                    Reflect::set(&err_obj, &JsValue::from_str("message"), &e)?;
                    Reflect::set(&err_obj, &JsValue::from_str("url"), &JsValue::from_str(&url))?;
                    Reflect::set(&err_obj, &JsValue::from_str("version"), &JsValue::from_str(&ver))?;
                    // emit event
                    emit_event("pack_load_failed", &e);
                    return Ok(JsValue::from(err_obj));
                }
            }
            // otherwise assume loader returned synchronously OK — continue
        } else if let Some(Err(e)) = pack_ok {
            // loader call failed synchronously
            let err_obj = Object::new();
            Reflect::set(&err_obj, &JsValue::from_str("status"), &JsValue::from_str("error"))?;
            Reflect::set(&err_obj, &JsValue::from_str("message"), &e)?;
            Reflect::set(&err_obj, &JsValue::from_str("url"), &JsValue::from_str(&url))?;
            Reflect::set(&err_obj, &JsValue::from_str("version"), &JsValue::from_str(&ver))?;
            emit_event("pack_load_failed", &e);
            return Ok(JsValue::from(err_obj));
        }

        // 2) Do internal engine startup (stubbed)
        let (status, message) = internal_start_engine_stub(&ver);

        // Build result object
        let result = Object::new();
        Reflect::set(&result, &JsValue::from_str("status"), &JsValue::from_str(&status))?;
        Reflect::set(&result, &JsValue::from_str("message"), &JsValue::from_str(&message))?;
        Reflect::set(&result, &JsValue::from_str("url"), &JsValue::from_str(&url))?;
        Reflect::set(&result, &JsValue::from_str("version"), &JsValue::from_str(&ver))?;

        // Emit event: engine_started
        emit_event("engine_started", &JsValue::from(result.clone()));

        // 3) If launcher callback is set, call it with (version, url) and await its promise if present.
        let launcher_ret = LAUNCH_CALLBACK.with(|c| c.borrow().clone());
        if let Some(cb) = launcher_ret {
            let this = JsValue::NULL;
            match cb.call2(&this, &JsValue::from_str(&ver), &JsValue::from_str(&url)) {
                Ok(rv) => {
                    if rv.is_instance_of::<Promise>() {
                        // await JS Promise
                        let js_future = wasm_bindgen_futures::JsFuture::from(Promise::from(rv));
                        if let Err(e) = js_future.await {
                            // launcher callback failed
                            let err_obj = Object::new();
                            Reflect::set(&err_obj, &JsValue::from_str("status"), &JsValue::from_str("error"))?;
                            Reflect::set(&err_obj, &JsValue::from_str("message"), &e)?;
                            Reflect::set(&err_obj, &JsValue::from_str("url"), &JsValue::from_str(&url))?;
                            Reflect::set(&err_obj, &JsValue::from_str("version"), &JsValue::from_str(&ver))?;
                            emit_event("launcher_failed", &e);
                            return Ok(JsValue::from(err_obj));
                        }
                    }
                    // else synchronous return -> ignore content
                }
                Err(e) => {
                    // synchronous error calling callback
                    let err_obj = Object::new();
                    Reflect::set(&err_obj, &JsValue::from_str("status"), &JsValue::from_str("error"))?;
                    Reflect::set(&err_obj, &JsValue::from_str("message"), &e)?;
                    Reflect::set(&err_obj, &JsValue::from_str("url"), &JsValue::from_str(&url))?;
                    Reflect::set(&err_obj, &JsValue::from_str("version"), &JsValue::from_str(&ver))?;
                    emit_event("launcher_failed", &e);
                    return Ok(JsValue::from(err_obj));
                }
            }
        }

        // Return result object
        Ok(JsValue::from(result))
    })
}

/// Synchronous start_engine wrapper (calls start_engine_async and returns Promise as JsValue)
#[wasm_bindgen]
pub fn start_engine(version: &str) -> Promise {
    start_engine_async(version)
}
