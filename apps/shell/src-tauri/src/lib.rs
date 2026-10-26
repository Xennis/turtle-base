#[cfg(target_os = "android")]
mod android;
mod flutter;
mod loopback;
mod secrets;
mod sql;

use std::fs;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();
    #[cfg(target_os = "android")]
    let builder = builder.plugin(android::init());
    builder
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .manage(flutter::FlutterData::default())
        .setup(|app| {
            secrets::use_platform_store();
            let data = app.path().app_data_dir()?;
            fs::create_dir_all(data.join("files").join("tmp"))?;
            app.manage(sql::Database::open(&data.join("turtle-base.sqlite"))?);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            sql::sql_execute,
            loopback::loopback_listen,
            flutter::flutter_find,
            flutter::flutter_query,
            flutter::flutter_list_files,
            flutter::flutter_read_file,
            secrets::secrets_get,
            secrets::secrets_set,
            secrets::secrets_remove,
            #[cfg(target_os = "android")]
            android::android_platform,
        ])
        .run(tauri::generate_context!())
        .expect("turtle-base failed to start");
}
