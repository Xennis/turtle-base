# turtle-base

## System dependencies (Linux)

`flutter_secure_storage` stores AI API keys via the freedesktop.org Secret Service (libsecret) on Linux. Install the packages listed under "Linux" on <https://pub.dev/packages/flutter_secure_storage#linux> (dev + runtime libsecret packages) and make sure a keyring service (e.g. GNOME Keyring) is running, or reading/writing a key will fail.