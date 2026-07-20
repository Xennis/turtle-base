# macOS code signing (Developer ID)

Manual checklist for the certificate the `build-macos` job in
[.github/workflows/release.yml](../../.github/workflows/release.yml) uses to
sign the Release build (see `CODE_SIGN_IDENTITY[sdk=macosx*]` in
`macos/Runner.xcodeproj/project.pbxproj`). There's no API/Terraform
resource for any of this - it's all Apple Developer portal + Keychain
Access.

## 0. Prerequisites

- A paid [Apple Developer Program](https://developer.apple.com/programs/)
  membership (99$/year). A free Apple ID only gets you an "Apple
  Development" certificate, which isn't accepted for distribution outside
  the App Store.

## 1. Create a Certificate Signing Request (CSR)

On the Mac that will hold the private key:

- Keychain Access → app menu **Keychain Access** (top-left, next to the
   Apple logo) → **Certificate Assistant → Request a Certificate From a
  Certificate Authority...**
- Enter your email, "Saved to disk", leave "Let me specify key pair
  information" unchecked.

This also generates the matching private key locally in your keychain -
don't delete it before step 3.

## 2. Request the certificate from Apple

- [developer.apple.com/account](https://developer.apple.com/account) →
  **Certificates, Identifiers & Profiles → Certificates → +**.
- Type: **Developer ID Application** (not "Apple Development" or any App
  Store distribution type).
- Upload the CSR from step 1, download the resulting `.cer`.

## 3. Install it locally

Double click the `.cer` (or Keychain Access → `File → Import Items...` if
that doesn't do anything) to add it to the **login** keychain. It should
pair with the private key from step 1 - look for a disclosure triangle
under **My Certificates** revealing the key underneath.

If Keychain Access already has old/expired entries with the same name,
identify the right one by the disclosure triangle (only the one paired
with your new private key has it) and the expiry date (Developer ID
certificates are valid 5 years, so the new one expires furthest out).

## 4. Export as `.p12`

Right click the certificate (not just the key) → **Export...** → format
**Personal Information Exchange (.p12)** → set an export password.

**Back this `.p12` file and its password up in a password manager/vault.**
It's the only copy of your private key outside this Mac's keychain -
GitHub Actions secrets are write-only (you can set them but never read
them back), so they don't count as a backup. Losing this file means
revoking and re-issuing the certificate from scratch.

The `.cer` (public half) and the `.certSigningRequest` don't need backing
up: the `.cer` can be re-downloaded from the Apple Developer portal any
time, and the CSR has no reuse value once Apple has issued a certificate
from it.

## 5. Wire it into CI

```sh
base64 -i developerID_application.p12 | pbcopy
```

Add two repo secrets (Settings → Secrets and variables → Actions):

- `MACOS_CERTIFICATE_P12` - the base64 output above.
- `MACOS_CERTIFICATE_PASSWORD` - the export password from step 4.

No other secret is needed - the workflow generates a random password for
the temporary CI keychain at runtime and deletes that keychain again at
the end of the job.
