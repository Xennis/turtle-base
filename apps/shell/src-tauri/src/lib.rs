mod secrets;
mod sql;

use std::fs;

use tauri::Manager;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .setup(|app| {
            secrets::use_platform_store();
            let data = app.path().app_data_dir()?;
            fs::create_dir_all(data.join("files").join("tmp"))?;
            app.manage(sql::Database::open(&data.join("turtle-base.sqlite"))?);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            sql::sql_execute,
            secrets::secrets_get,
            secrets::secrets_set,
            secrets::secrets_remove,
        ])
        .run(tauri::generate_context!())
        .expect("turtle-base failed to start");
}
