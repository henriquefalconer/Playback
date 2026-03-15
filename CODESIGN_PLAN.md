# Codesign Plan: Keychain Certificate Signing

## Status: COMPLETE

All steps implemented and verified. The build pipeline now uses a self-signed `macos-codesigning` certificate from the login keychain instead of ad-hoc signing.

### What was done

1. **Created `macos-codesigning` certificate** — self-signed code signing cert in login keychain, trusted for code signing
2. **Updated `scripts/build-and-install.sh`** — uses `macos-codesigning` identity, re-signs with entitlements + hardened runtime, verifies signature before install
3. **Updated `smoke-test.sh`** — uses `macos-codesigning` identity instead of ad-hoc
4. **Updated `project.pbxproj`** — Manual signing with `CODE_SIGN_IDENTITY = "macos-codesigning"` for both Debug and Release, removed `DEVELOPMENT_TEAM`
5. **Deleted unused scripts** — `status.sh`, `stop-prod.sh`, `uninstall.sh`, `verify-production-build.sh`
6. **Deleted `src/Playback/Matchfile`** — Fastlane Match not used
7. **Updated docs** — `specs/build-process.md`, `README.md`, `AGENTS.md` updated to reflect self-signed cert, removed Developer ID/notarization references

### Verification

- `security find-identity -v -p codesigning` shows 1 valid identity: `macos-codesigning`
- `build-and-install.sh` builds, signs, verifies, and installs successfully
- `smoke-test.sh` builds and passes (5-second run, no crashes)
- `codesign -dvv /Applications/Playback.app` shows: Authority=macos-codesigning, flags=runtime
