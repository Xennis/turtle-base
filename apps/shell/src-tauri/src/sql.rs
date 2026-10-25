use std::path::Path;
use std::sync::Mutex;

use rusqlite::types::{ToSqlOutput, ValueRef};
use rusqlite::{Connection, ToSql, params_from_iter};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// The app's one SQLite connection (see SqlDriver in packages/platform):
/// statements run exactly as given, one at a time - transactions are plain
/// BEGIN/COMMIT statements, so they need this one connection, not a pool.
/// SQLite is bundled, the same version on every platform.
pub struct Database(Mutex<Connection>);

impl Database {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        let connection = Connection::open(path)?;
        connection.execute_batch("PRAGMA foreign_keys = ON")?;
        Ok(Self(Mutex::new(connection)))
    }

    #[cfg(test)]
    fn in_memory() -> Self {
        Self(Mutex::new(Connection::open_in_memory().unwrap()))
    }

    pub fn execute(&self, sql: &str, params: &[Param]) -> rusqlite::Result<SqlResult> {
        let connection = self.0.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let mut statement = connection.prepare(sql)?;
        if statement.column_count() == 0 {
            let changes = statement.execute(params_from_iter(params))?;
            return Ok(SqlResult {
                rows: vec![],
                changes,
                last_insert_rowid: connection.last_insert_rowid(),
            });
        }
        let names: Vec<String> = statement.column_names().map(String::from).collect();
        let mut rows = statement.query(params_from_iter(params))?;
        let mut result = vec![];
        while let Some(row) = rows.next()? {
            let mut object = Map::new();
            for (index, name) in names.iter().enumerate() {
                object.insert(name.clone(), json_of(row.get_ref(index)?));
            }
            result.push(object);
        }
        // Like node:sqlite in the tests: statements with rows (RETURNING too) report no changes.
        Ok(SqlResult {
            rows: result,
            changes: 0,
            last_insert_rowid: 0,
        })
    }
}

/// A bound value as it comes from the page - a blob as an array of bytes.
#[derive(Deserialize)]
#[serde(untagged)]
pub enum Param {
    Null,
    Integer(i64),
    Real(f64),
    Text(String),
    Blob(Vec<u8>),
}

impl ToSql for Param {
    fn to_sql(&self) -> rusqlite::Result<ToSqlOutput<'_>> {
        Ok(match self {
            Param::Null => ToSqlOutput::Borrowed(ValueRef::Null),
            Param::Integer(value) => ToSqlOutput::Borrowed(ValueRef::Integer(*value)),
            Param::Real(value) => ToSqlOutput::Borrowed(ValueRef::Real(*value)),
            Param::Text(value) => ToSqlOutput::Borrowed(ValueRef::Text(value.as_bytes())),
            Param::Blob(value) => ToSqlOutput::Borrowed(ValueRef::Blob(value)),
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SqlResult {
    rows: Vec<Map<String, Value>>,
    changes: usize,
    last_insert_rowid: i64,
}

pub fn json_of(value: ValueRef<'_>) -> Value {
    match value {
        ValueRef::Null => Value::Null,
        ValueRef::Integer(value) => value.into(),
        ValueRef::Real(value) => value.into(),
        ValueRef::Text(value) => String::from_utf8_lossy(value).into(),
        ValueRef::Blob(value) => value.iter().copied().map(Value::from).collect(),
    }
}

#[tauri::command]
pub async fn sql_execute(
    database: tauri::State<'_, Database>,
    sql: String,
    params: Vec<Param>,
) -> Result<SqlResult, String> {
    database.execute(&sql, &params).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rows(result: &SqlResult) -> Value {
        Value::from(result.rows.clone())
    }

    #[test]
    fn returns_rows_for_queries_and_changes_for_writes() {
        let database = Database::in_memory();
        database
            .execute("CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER, r REAL, b BLOB)", &[])
            .unwrap();

        let insert = database
            .execute(
                "INSERT INTO t (id, n, r, b) VALUES (?, ?, ?, ?)",
                &[
                    Param::Text("a".into()),
                    Param::Integer(1),
                    Param::Real(1.5),
                    Param::Blob(vec![1, 2]),
                ],
            )
            .unwrap();
        let update = database.execute("UPDATE t SET n = n + 1", &[]).unwrap();
        let select = database
            .execute("SELECT id, n, r, b, NULL AS empty FROM t", &[])
            .unwrap();

        assert_eq!((insert.changes, insert.last_insert_rowid), (1, 1));
        assert_eq!(update.changes, 1);
        assert_eq!(
            rows(&select),
            serde_json::json!([{ "id": "a", "n": 2, "r": 1.5, "b": [1, 2], "empty": null }])
        );
    }

    #[test]
    fn returns_the_rows_of_a_write_with_returning() {
        let database = Database::in_memory();
        database.execute("CREATE TABLE t (id TEXT PRIMARY KEY)", &[]).unwrap();

        let result = database
            .execute("INSERT INTO t (id) VALUES (?) RETURNING id", &[Param::Text("a".into())])
            .unwrap();

        assert_eq!(rows(&result), serde_json::json!([{ "id": "a" }]));
    }

    #[test]
    fn keeps_a_transaction_across_calls() {
        let database = Database::in_memory();
        database.execute("CREATE TABLE t (id TEXT PRIMARY KEY)", &[]).unwrap();

        database.execute("BEGIN", &[]).unwrap();
        database.execute("INSERT INTO t (id) VALUES ('a')", &[]).unwrap();
        database.execute("ROLLBACK", &[]).unwrap();

        assert_eq!(
            rows(&database.execute("SELECT id FROM t", &[]).unwrap()),
            serde_json::json!([])
        );
    }

    #[test]
    fn fails_on_invalid_sql() {
        let error = Database::in_memory().execute("SELEKT 1", &[]).err().unwrap();

        assert!(error.to_string().contains("syntax error"));
    }

    #[test]
    fn takes_params_as_the_page_sends_them() {
        let params: Vec<Param> = serde_json::from_str(r#"[null, 1, 1.5, "a", [1, 2]]"#).unwrap();

        assert!(matches!(
            params.as_slice(),
            [
                Param::Null,
                Param::Integer(1),
                Param::Real(_),
                Param::Text(_),
                Param::Blob(_)
            ]
        ));
    }
}
