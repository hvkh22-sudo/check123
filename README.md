# PassCheck (iOS)

Honest, on-device US passport-photo compliance checker. Checks a phone photo against the official spec, tells you plainly what passes and what it can't guarantee. 100% on-device, no accounts, no subscription, no AI/background editing.

- **Build:** cloud CI (GitHub Actions macOS) via XcodeGen — no Mac required. See `SETUP.md`.
- **Status:** B0 skeleton (app entry + data models + tests). Not yet compiled — first CI run verifies it.
- **Specs:** product `../../PRD.md`, architecture `../../ARCHITECTURE.md`, engine `../COMPLIANCE_ENGINE_SPEC.md`, rules `../RULES_US_PASSPORT.md`, UX `../../design/UX_SPEC.md`, backlog `../BUILD_BACKLOG.md`.
- **iOS 15+**, SwiftUI, Vision/Core Image (on-device only), StoreKit 2 (one-time export, no subscription).
