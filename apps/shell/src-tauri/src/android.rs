use serde_json::Value;
use tauri::plugin::{Builder, PluginHandle, TauriPlugin};
use tauri::{Manager, Wry};

/// AndroidPlatformPlugin.kt in the Android project - what Tauri's own plugins don't cover on Android.
pub struct AndroidPlatform(PluginHandle<Wry>);

pub fn init() -> TauriPlugin<Wry> {
    Builder::new("android-platform")
        .setup(|app, api| {
            app.manage(AndroidPlatform(api.register_android_plugin(
                "org.xennis.apps.turtlebase",
                "AndroidPlatformPlugin",
            )?));
            Ok(())
        })
        .build()
}

/// Runs `command` of AndroidPlatformPlugin.kt with `args`.
#[tauri::command]
pub async fn android_platform(
    platform: tauri::State<'_, AndroidPlatform>,
    command: String,
    args: Value,
) -> Result<Value, String> {
    platform
        .0
        .run_mobile_plugin_async(command, args)
        .await
        .map_err(|error| error.to_string())
}
