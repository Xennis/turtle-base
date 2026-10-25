use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rusqlite::{Connection, OpenFlags};
use serde_json::{Map, Value};
use tauri::ipc::Response;

use crate::sql::json_of;

const DATABASE_NAME: &str = "turtle_base.sqlite";

/// The Flutter app's data on this machine, read-only - for the app's one-time
/// import (see FlutterAppData in packages/platform). Looked up again on each
/// find, so a folder that appeared meanwhile (or a test's) is seen.
#[derive(Default)]
pub struct FlutterData(Mutex<Option<PathBuf>>);

impl FlutterData {
    fn location(&self) -> Result<PathBuf, String> {
        self.0
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
            .ok_or("No Flutter app data found".into())
    }
}

/// Where the Flutter app keeps its data (path_provider's application support
/// directory): the XDG data folder on Linux; on macOS its sandbox container,
/// or Application Support where it ran unsandboxed. `TURTLE_FLUTTER_DATA_DIR`
/// points elsewhere, e.g. for tests. Phones get the data through sync.
fn candidates() -> Vec<PathBuf> {
    if let Some(folder) = env::var_os("TURTLE_FLUTTER_DATA_DIR") {
        return vec![folder.into()];
    }
    let Some(home) = env::var_os("HOME").map(PathBuf::from) else {
        return vec![];
    };
    if cfg!(target_os = "macos") {
        let support = Path::new("Library/Application Support/org.xennis.apps.turtleBase");
        vec![
            home.join("Library/Containers/org.xennis.apps.turtleBase/Data")
                .join(support),
            home.join(support),
        ]
    } else if cfg!(target_os = "linux") {
        let data = env::var_os("XDG_DATA_HOME").map_or_else(|| home.join(".local/share"), PathBuf::from);
        vec![data.join("org.xennis.apps.turtle_base")]
    } else {
        vec![]
    }
}

/// Only names of the Flutter app's file store - nothing else of the disk is handed out.
fn is_store_name(name: &str) -> bool {
    let hash = name
        .strip_prefix("sha256-")
        .map(|rest| rest.strip_suffix(".thumb.jpg").unwrap_or(rest));
    hash.is_some_and(|hash| hash.len() == 64 && hash.bytes().all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f')))
}

#[tauri::command]
pub fn flutter_find(data: tauri::State<'_, FlutterData>) -> Option<String> {
    let found = candidates()
        .into_iter()
        .find(|folder| folder.join(DATABASE_NAME).is_file());
    let location = found.as_ref().map(|folder| folder.to_string_lossy().into_owned());
    *data.0.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = found;
    location
}

#[tauri::command]
pub async fn flutter_query(
    data: tauri::State<'_, FlutterData>,
    sql: String,
) -> Result<Vec<Map<String, Value>>, String> {
    query(&data.location()?.join(DATABASE_NAME), &sql).map_err(|error| error.to_string())
}

fn query(database: &Path, sql: &str) -> rusqlite::Result<Vec<Map<String, Value>>> {
    if !sql.trim_start().to_ascii_lowercase().starts_with("select") {
        return Err(rusqlite::Error::InvalidQuery);
    }
    let connection = Connection::open_with_flags(database, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let mut statement = connection.prepare(sql)?;
    let names: Vec<String> = statement.column_names().map(String::from).collect();
    let mut rows = statement.query([])?;
    let mut result = vec![];
    while let Some(row) = rows.next()? {
        let mut object = Map::new();
        for (index, name) in names.iter().enumerate() {
            object.insert(name.clone(), json_of(row.get_ref(index)?));
        }
        result.push(object);
    }
    Ok(result)
}

#[tauri::command]
pub fn flutter_list_files(data: tauri::State<'_, FlutterData>) -> Result<Vec<String>, String> {
    let Ok(entries) = fs::read_dir(data.location()?.join("files")) else {
        return Ok(vec![]);
    };
    Ok(entries
        .flatten()
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_file()))
        .filter_map(|entry| entry.file_name().into_string().ok())
        .filter(|name| is_store_name(name))
        .collect())
}

/// The bytes as they are - not a JSON array.
#[tauri::command]
pub async fn flutter_read_file(data: tauri::State<'_, FlutterData>, name: String) -> Result<Response, String> {
    if !is_store_name(&name) {
        return Err(format!("Not a file of the Flutter app: {name}"));
    }
    let bytes = fs::read(data.location()?.join("files").join(name)).map_err(|error| error.to_string())?;
    Ok(Response::new(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_names_of_the_file_store() {
        let hash = "0123456789abcdef".repeat(4);

        assert!(is_store_name(&format!("sha256-{hash}")));
        assert!(is_store_name(&format!("sha256-{hash}.thumb.jpg")));
        assert!(!is_store_name(&format!("sha256-{hash}.png")));
        assert!(!is_store_name("sha256-../../etc/passwd"));
        assert!(!is_store_name(DATABASE_NAME));
    }

    #[test]
    fn runs_only_selects_and_never_writes() {
        let folder = env::temp_dir().join(format!("turtle-flutter-{}", std::process::id()));
        fs::create_dir_all(&folder).unwrap();
        let database = folder.join(DATABASE_NAME);
        Connection::open(&database)
            .unwrap()
            .execute_batch("CREATE TABLE spaces (id TEXT); INSERT INTO spaces VALUES ('garden')")
            .unwrap();

        let rows = query(&database, "SELECT id FROM spaces").unwrap();
        let write = query(&database, "DELETE FROM spaces");
        let sneaky = query(&database, "SELECT 1; DELETE FROM spaces");

        assert_eq!(Value::from(rows), serde_json::json!([{ "id": "garden" }]));
        assert!(write.is_err());
        assert!(sneaky.is_err());
        fs::remove_dir_all(folder).unwrap();
    }
}
