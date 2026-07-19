# PassCheck — Setup (owner steps to get the first cloud build running)

This folder is a ready-to-push iOS app skeleton. It builds in the cloud (GitHub Actions macOS) — **no Mac needed.** The Swift here was authored on Windows and is **not yet compiled**; the first CI run verifies it (small first-run fixes are normal and expected).

## What YOU do (the account/paid parts — I can't do these for you)
1. **Apple Developer Program — $99/yr** (tab already opened). Enroll with your Apple ID. After enrolling, copy your **Team ID** from the Membership page.
2. **GitHub** (tab already opened). Create/confirm an account, then create a **new private repo** named `passcheck`.
3. **iPhone** — confirm you have one (needed later to test the camera/Vision features via TestFlight).

## Then tell me two things
- Your **GitHub username** (so I finalize the repo/CI details).
- Your **Apple Team ID** (I'll drop it into `project.yml` → `DEVELOPMENT_TEAM`).

## Push this folder to your repo (I'll give exact commands, or run these)
From `apps/passport-photo/ios/PassCheck/`:
```
git init -b main
git add .
git commit -m "PassCheck skeleton"
git remote add origin https://github.com/<your-username>/passcheck.git
git push -u origin main   # (push is your call — the studio never pushes without your OK)
```
The moment it's pushed, GitHub Actions runs `.github/workflows/ios.yml` → generates the Xcode project, builds, and runs the tests. We read the result and fix anything the first build surfaces.

## What happens after the first green build
- Gate 4 (architecture) is effectively proven buildable → we start **B1: the head-height (R-A) accuracy spike** (the #1 technical risk) against the sample set (`../../qa/SAMPLE_SET_SPEC.md`), then build the screens per `../../design/UX_SPEC.md`.
- TestFlight (to test on your iPhone) needs signing secrets — a later, separate step documented in `../CI_SETUP.md`. Upload always stays manual.

## Cost recap
- Apple Developer: $99/yr (the only mandatory spend now).
- GitHub Actions: free tier likely covers a small app; overage ~$0.06/min. Effective all-in ≈ $8–15/mo.
