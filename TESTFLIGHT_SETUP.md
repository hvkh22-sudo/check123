# TestFlight setup — hand this to whoever helps (≈30 min, one time)

The PassCheck app is **built and passing CI** in the repo **github.com/hvkh22-sudo/check123**.
The code + fastlane + a manual "ship-testflight" GitHub Actions job are all ready. What's left is the
one-time signing setup below. Everything after that is one click to ship builds.

Accounts already set up: Apple Developer active (Team ID **645SRC2PTY**); GitHub repo exists; app bundle id **com.appstudio.passcheck**.

## Step 1 — App Store Connect API key
1. appstoreconnect.apple.com → **Users and Access** → **Integrations** tab → **App Store Connect API** (Team Keys).
2. **Generate API Key** → name "CI", **Access: App Manager** → Generate.
3. Note the **Key ID** and the **Issuer ID** (top of the Keys page).
4. **Download the .p8 file** (only downloadable once — keep it).

## Step 2 — Add 3 GitHub repo secrets
In **github.com/hvkh22-sudo/check123 → Settings → Secrets and variables → Actions → New repository secret**, add:
- `ASC_KEY_ID` = the Key ID
- `ASC_ISSUER_ID` = the Issuer ID
- `ASC_KEY_P8` = the **base64** of the .p8 file. Get it with, in a terminal:
  - macOS/Linux: `base64 -i AuthKey_XXXX.p8 | tr -d '\n'`
  - Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))`
  Paste the resulting string as the secret value.

## Step 3 — Run the upload
GitHub repo → **Actions** tab → **iOS CI** workflow → **Run workflow** (main branch). This runs the
`ship-testflight` job: it creates the app record in App Store Connect if needed, builds, signs (automatic,
via the API key), and uploads to TestFlight.

## Step 4 — On the App Store Connect side
- The build appears under **TestFlight** after processing (~5–15 min).
- Add the owner's Apple ID as an **internal tester**; install **TestFlight** on the iPhone and accept the invite.

## If the upload job fails
The job prints the error. Common ones:
- **App name taken**: edit `fastlane/Fastfile` → `produce(app_name: "…")` to something unique.
- **Signing / no distribution certificate**: ensure the API key role is App Manager; automatic signing with
  `-allowProvisioningUpdates` should create it. If not, set up `fastlane match` (see fastlane docs).
- **Export compliance**: first TestFlight build may ask about encryption — answer "No" (uses only standard/exempt crypto) in App Store Connect, or add `ITSAppUsesNonExemptEncryption = NO` to the app Info.plist.

Copy any error back to the studio chat and the app agent will fix the config and you re-run.
