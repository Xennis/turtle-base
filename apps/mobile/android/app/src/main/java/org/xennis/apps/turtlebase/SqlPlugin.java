package org.xennis.apps.turtlebase;

import androidx.sqlite.SQLite;
import androidx.sqlite.SQLiteConnection;
import androidx.sqlite.SQLiteStatement;
import androidx.sqlite.driver.bundled.BundledSQLiteDriver;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * One SQLite connection for the app's SqlDriver (see packages/platform):
 * statements run exactly as given, on SQLite bundled with the app rather
 * than Android's own, which is too old for upserts on older devices.
 * Capacitor calls plugin methods one at a time on its plugin thread, so the
 * connection is never used concurrently.
 */
@CapacitorPlugin(name = "TurtleSql")
public class SqlPlugin extends Plugin {

    private SQLiteConnection connection;

    @PluginMethod
    public void open(PluginCall call) {
        String name = call.getString("name");
        if (name == null || name.contains("/")) {
            call.reject("Not a database name: " + name);
            return;
        }
        if (connection == null) {
            connection = new BundledSQLiteDriver().open(getContext().getDatabasePath(name).getAbsolutePath());
            SQLite.execSQL(connection, "PRAGMA foreign_keys = ON");
        }
        call.resolve();
    }

    @PluginMethod
    public void execute(PluginCall call) {
        if (connection == null) {
            call.reject("Database not opened");
            return;
        }
        String sql = call.getString("sql");
        JSArray params = call.getArray("params", new JSArray());
        try {
            JSArray rows = new JSArray();
            try (SQLiteStatement statement = connection.prepare(sql)) {
                bind(statement, params);
                while (statement.step()) rows.put(rowOf(statement));
            }
            JSObject result = new JSObject();
            result.put("rows", rows);
            try (SQLiteStatement statement = connection.prepare("SELECT changes(), last_insert_rowid()")) {
                statement.step();
                result.put("changes", statement.getLong(0));
                result.put("lastInsertRowid", statement.getLong(1));
            }
            call.resolve(result);
        } catch (Exception e) {
            call.reject(e.getMessage(), e);
        }
    }

    @PluginMethod
    public void close(PluginCall call) {
        if (connection != null) {
            connection.close();
            connection = null;
        }
        call.resolve();
    }

    private static void bind(SQLiteStatement statement, JSONArray params) throws JSONException {
        for (int i = 0; i < params.length(); i++) {
            Object value = params.get(i);
            int index = i + 1;
            if (value == JSONObject.NULL) statement.bindNull(index);
            else if (value instanceof Integer || value instanceof Long) statement.bindLong(index, ((Number) value).longValue());
            else if (value instanceof Number) statement.bindDouble(index, ((Number) value).doubleValue());
            else if (value instanceof String) statement.bindText(index, (String) value);
            else throw new IllegalArgumentException("Can't bind parameter " + index + ": " + value);
        }
    }

    private static JSObject rowOf(SQLiteStatement statement) throws JSONException {
        JSObject row = new JSObject();
        for (int i = 0; i < statement.getColumnCount(); i++) {
            String name = statement.getColumnName(i);
            switch (statement.getColumnType(i)) {
                case SQLite.SQLITE_DATA_INTEGER:
                    row.put(name, statement.getLong(i));
                    break;
                case SQLite.SQLITE_DATA_FLOAT:
                    row.put(name, statement.getDouble(i));
                    break;
                case SQLite.SQLITE_DATA_TEXT:
                    row.put(name, statement.getText(i));
                    break;
                case SQLite.SQLITE_DATA_NULL:
                    row.put(name, JSONObject.NULL);
                    break;
                default:
                    throw new IllegalStateException("Blob column " + name + " - the app stores none");
            }
        }
        return row;
    }
}
