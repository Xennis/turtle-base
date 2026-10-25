use keyring_core::{Entry, Error};

/// The keyring service the app's secrets are kept under - the user is the key.
const SERVICE: &str = "org.xennis.apps.turtlebase";

/// The platform's credential store as keyring's default: the Secret Service
/// (libsecret) on Linux, the Keychain on macOS, the Keystore on Android.
/// Without one (e.g. no Secret Service running) the app starts anyway, only
/// keeping secrets fails.
pub fn use_platform_store() {
    #[cfg(target_os = "linux")]
    let store = zbus_secret_service_keyring_store::Store::new();
    #[cfg(target_os = "macos")]
    let store = apple_native_keyring_store::keychain::Store::new();
    #[cfg(target_os = "android")]
    let store = android_native_keyring_store::Store::new();
    match store {
        Ok(store) => keyring_core::set_default_store(store),
        Err(error) => eprintln!("No OS keyring for secrets: {error}"),
    }
}

/// Blocking calls into the keyring - off the async runtime's threads.
async fn with_entry<T: Send + 'static>(
    key: String,
    action: impl FnOnce(Entry) -> keyring_core::Result<T> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(move || Entry::new(SERVICE, &key).and_then(action))
        .await
        .map_err(|error| error.to_string())?
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn secrets_get(key: String) -> Result<Option<String>, String> {
    with_entry(key, |entry| match entry.get_password() {
        Err(Error::NoEntry) => Ok(None),
        result => result.map(Some),
    })
    .await
}

#[tauri::command]
pub async fn secrets_set(key: String, value: String) -> Result<(), String> {
    with_entry(key, move |entry| entry.set_password(&value)).await
}

#[tauri::command]
pub async fn secrets_remove(key: String) -> Result<(), String> {
    with_entry(key, |entry| match entry.delete_credential() {
        Err(Error::NoEntry) => Ok(()),
        result => result,
    })
    .await
}
