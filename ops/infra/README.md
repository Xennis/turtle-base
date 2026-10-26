# Google Cloud setup for Drive sync

Complete setup checklist for the Google Cloud project behind Drive sync
(see `packages/crdt_file_sync_google_drive/`). Only the "enable the
Drive API" part is actually managed by OpenTofu here; everything else
has no API and stays a manual Google Cloud Console checklist (see
"Why only the API is automated" below).

## 0. Prerequisites

- A Google Cloud project you control (create one at
  [console.cloud.google.com](https://console.cloud.google.com/) if you
  don't have one yet - project creation itself isn't managed here, it
  involves billing/org decisions out of scope for this config).
- `gcloud auth application-default login` so the `google` provider has
  credentials.

## 1. Enable the Drive API (automated)

```sh
cd ops/infra
cp opentofu.tfvars.example terraform.tfvars   # fill in your project id
tofu init
tofu plan
tofu apply
```

Note the vars file must be named exactly `terraform.tfvars` (or
`*.auto.tfvars`) to be picked up automatically - OpenTofu kept
Terraform's auto-load filename convention, there's no `opentofu.tfvars`
equivalent. `terraform.tfvars` is gitignored; `opentofu.tfvars.example`
is the committed template to copy it from.

## 2. Google Auth Platform

Google renamed/restructured this in 2024/2025 into its own top-level
nav item, **APIs & Services → Google Auth Platform**, split into tabs.
If this is the project's first time here, a "Get started" wizard covers
the same ground as below - just follow it in order.

- **Branding** tab: app name + a support email users can contact with
  consent questions. Anything recognizable, e.g. "turtle-base".
- **Audience** tab:
  - User type: **External** (no Google Workspace org).
  - Publishing status: keep **Testing** while developing (add your own
    Google account, and anyone else testing, under "Test users" - up
    to 100). Move to **In production** whenever real users need it -
    no Google review required, because the only scope requested below
    is non-sensitive.
- **Data access** tab: click "Add or remove scopes", add
  `https://www.googleapis.com/auth/drive.file` only. This is a
  **non-sensitive** scope - Google never requires app verification for
  it, even in production with unlimited users (unlike `drive.appdata`,
  which is sensitive and would need a review once past the
  100-test-user cap).

## 3. OAuth client - Desktop (Linux)

Google Auth Platform → **Clients** tab → Create client:

- Application type: **Desktop app**.
- Name: anything recognizable, e.g. "turtle-base desktop".
- Download the resulting **Client ID** and **Client secret**.

Used by `LoopbackGoogleAuthenticator`'s loopback flow (`127.0.0.1`,
arbitrary free port) - Google's Desktop app client type doesn't require
pre-registering a fixed redirect URI. Google doesn't treat this secret
as confidential for installed apps (see
[RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252)), so
committing it isn't the security risk it would be for a server-side web
app - but it still doesn't belong hardcoded/committed; see step 5.

## 4. OAuth client - Android

Same **Clients** tab → Create client:

- Application type: **Android**.
- Package name: matches `identifier` in `apps/shell/src-tauri/tauri.conf.json`
  (`org.xennis.apps.turtlebase`).
- SHA-1 certificate fingerprint: from your signing key. For a local
  debug build:
  ```sh
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```
  Add a second Android OAuth client (or an additional fingerprint) for
  your release signing key once you have one.

  To create a release signing key (one-time, keep it and its passwords
  outside the repo - never commit them):
  ```sh
  keytool -genkey -v -keystore release.keystore -alias <alias> -keyalg RSA -keysize 2048 -validity 10000 -storetype JKS
  ```
  Get its SHA-1 the same way as the debug example above:
  ```sh
  keytool -list -v -keystore release.keystore -alias <alias>
  ```
  Add that fingerprint to the Android OAuth client (or a second Android-type
  client) so both debug and release builds keep working. The keystore file
  and its passwords feed the release pipeline
  ([.github/workflows/release.yml](../../.github/workflows/release.yml)) via
  the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and
  `ANDROID_KEY_PASSWORD` repo secrets, plus the `ANDROID_KEY_ALIAS` repo
  **variable** (not a secret - the alias alone is useless without the
  keystore file and passwords, so it doesn't need encryption or log
  masking; add it under Settings → Secrets and variables → Actions →
  Variables). Locally all four are set via a gitignored
  `apps/shell/src-tauri/gen/android/key.properties` (see `app/build.gradle.kts` there).

  `ANDROID_KEYSTORE_BASE64` is the keystore file base64-encoded as a single
  line (the workflow decodes it back with `base64 -d`):
  ```sh
  base64 -w0 release.keystore
  ```
  (on macOS, `base64` has no `-w0` flag; use `base64 -i release.keystore`
  instead.) Copy the output into the `ANDROID_KEYSTORE_BASE64` GitHub
  secret.

The app references neither a client ID nor a secret on Android: Play
services' `AuthorizationClient` (see `AndroidPlatformPlugin.kt` in
`apps/shell/src-tauri/gen/android`) finds the client by package name and
signing certificate.
The Web application client the Flutter app needed for `google_sign_in`
(its `serverClientId`) isn't used anymore.

## 5. Pass the values to the app

Only the desktop app needs values: the Desktop app client's ID and
secret, as the environment variables `DRIVE_DESKTOP_CLIENT_ID` and
`DRIVE_DESKTOP_CLIENT_SECRET` - read when the app starts, and bundled in
when it's built for a release. See the
[`crdt-file-sync-google-drive` README's "Configuration"](../../packages/crdt-file-sync-google-drive/README.md#configuration)
section for supplying them locally and in CI.

## Why only the API is automated

The Terraform/OpenTofu `google` provider has no resource for the
Google Auth Platform consent screen (branding/audience/scopes) or for
creating standalone Desktop/Android/Web application OAuth 2.0 Client
IDs, and there's no `gcloud`/REST API alternative either - it's
Console-only. This isn't an oversight in this config; it's a real gap
in Google's own tooling, tracked upstream and still open as of writing:

- [Support Oauth consent screen scope configuration (#17649)](https://github.com/hashicorp/terraform-provider-google/issues/17649)
- [Create OAuth 2.0 Client ID (non-IAP) resource (#16452)](https://github.com/hashicorp/terraform-provider-google/issues/16452)

`google_iap_brand`/`google_iap_client` look like candidates but aren't:
they're narrow resources for Identity-Aware Proxy's legacy "brand"
concept (and built on the deprecated IAP OAuth Admin API), not the
general Google Auth Platform consent screen or standalone OAuth
clients.
