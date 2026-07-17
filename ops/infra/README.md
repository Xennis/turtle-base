# Google Cloud setup for Drive sync

Complete setup checklist for the Google Cloud project behind Drive sync
(see `lib/packages/crdt_file_sync/google_drive/`). Only the "enable the
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

Used by `DesktopDriveAuthenticator`'s loopback flow (`127.0.0.1`,
arbitrary free port) - Google's Desktop app client type doesn't require
pre-registering a fixed redirect URI. Google doesn't treat this secret
as confidential for installed apps (see
[RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252)), so
committing it isn't the security risk it would be for a server-side web
app - but it still doesn't belong hardcoded/committed; see step 5.

## 4. OAuth client - Android

Same **Clients** tab → Create client:

- Application type: **Android**.
- Package name: matches `applicationId` in
  `android/app/build.gradle.kts`.
- SHA-1 certificate fingerprint: from your signing key. For a local
  debug build:
  ```sh
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```
  Add a second Android OAuth client (or an additional fingerprint) for
  your release signing key once you have one.

Only the **Client ID** is needed (no secret - `google_sign_in` on
Android verifies via the signing certificate, not a client secret).

## 4a. OAuth client - Web application (also needed for Android!)

Counterintuitive but required: `google_sign_in` v7's Credential
Manager-based flow on Android needs a **second**, `serverClientId`
OAuth client in addition to the Android one above - even though this
app never requests server-side/offline access. Without it, sign-in
fails with `GoogleSignInException(code: clientConfigurationError,
"serverClientId must be provided on Android")`.

Same **Clients** tab → Create client:

- Application type: **Web application**.
- Name: anything recognizable, e.g. "turtle-base android server
  client".
- No redirect URI needed - this client is only ever referenced by its
  ID, never used to complete a redirect flow itself.
- Only the **Client ID** is needed (goes into
  `DriveClientConfig.androidServerClientId`, passed as `serverClientId`
  to `GoogleSignIn.instance.initialize()` - see
  `AndroidDriveAuthenticator`'s doc comment).

## 5. Fill in the app's config file

Copy
`lib/packages/crdt_file_sync/google_drive/client_config.dart.example` to
`client_config.dart` (same folder) and fill in the values from steps
3-4a. `client_config.dart` is gitignored - never commit your real
client ID/secret.

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
