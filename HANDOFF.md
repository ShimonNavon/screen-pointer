# Screen Pointer handoff — October 23, 2026

## User's intended experience

Open the Mac app when showing something to a coding agent. No Control–Option–P workflow. Mark a target, or record a walkthrough with on-screen marks and typed notes while clicking freely between apps. The linked agent should inspect the evidence and respond. Publish an actual demonstration recording on the project page once it really works.

## Implemented

- Native Swift/AppKit/SwiftUI app, installed at `~/Applications/Screen Pointer.app`.
- Top button **Show something to my agent** hides the panel, waits five seconds, and attempts a marked screenshot at the mouse position. The point shortcut was removed.
- Walkthrough recorder, one-stroke drawing, timestamped notes, saved frames and session metadata.
- Read-only MCP tools: `latest_point`, `latest_recording`, `recording_frames`.
- OpenCode review helper attaches notes and selected images, starts a separate named session, and disables tools for that review.
- Promotional image, real app-panel screenshot, README and public project guide. No real demo video has been published.

## Unresolved blocker — do not claim capture works

The app still reports Screen Recording permission denied. System Settings displays Screen Pointer enabled, while `CGPreflightScreenCaptureAccess()` returns false. Earlier actual ScreenCaptureKit point capture failed with error -3801. The recording, note interaction and OpenCode review have **not** passed an end-to-end test.

Repeated app restarts, user-facing permission toggles and app-scoped `tccutil reset ScreenCapture com.navonsimon.screen-pointer` did not produce a verified successful capture. A system authentication sheet appeared once but was gone when inspected again. No OS reboot was performed by the agent. No TCC database was edited, no system security was disabled, and no permissions for other apps were reset.

## Latest signing change

Previous builds were ad-hoc signed, giving each build a different code-hash identity. There are no Apple Development/Developer ID signing identities on this Mac.

`tools/sign_app.py` now creates/reuses a persistent local certificate in an isolated keychain. The installed app was re-signed successfully. Both `codesign --verify --strict` and an update test (copy bundle, change Info.plist, re-sign, compare designated requirements) passed. The requirement binds the bundle ID and certificate fingerprint. **This proves signature stability, not that macOS capture permission has been repaired.**

Private signing state is outside the repository at `~/Library/Application Support/Screen Pointer/Signing/`. Preserve it; do not print, publish, commit or regenerate its private material. The helper temporarily adds its keychain to the user search list, restores the list afterward, and locks the keychain after signing. It makes no certificate trust-store changes.

The updated `build.sh` signs/verifies a staging bundle before installation and requires Screen Pointer to be quit. Its full staged-install path has not been run since this last change; the signing helper itself was run and verified. OpenSSL 3 from Homebrew was used; the helper's PKCS#12 export uses `-legacy`.

The last signing-related permission reset was followed by relaunch and a denied recording attempt. Settings continued showing enabled. Automatic OpenCode review is currently **off** from the local permission test; preserve the user's preference when testing. Do not upload test screenshots or recordings automatically.

## Relevant paths and deployment

- Repository branch: `agent-pointing`.
- App code: `Sources/main.swift`, `Sources/PointCapture.swift`, `Sources/RecordingSession.swift`.
- Agent bridge: `tools/point_mcp.py`, `tools/recordings.py`, `tools/send_review.py`.
- Point captures: `~/Library/Application Support/Screen Pointer/Points/`.
- Recordings: `~/Movies/Screen Pointer/Sessions/`.
- Project guide: https://projects.navonsimon.com/screen-pointer.html (source in `~/Developer/my-projects`).
- App site: https://screen-pointer.navonsimon.com/ (this repo's `site/`).
- Kubernetes namespace `screen-pointer`, NodePort 30099, public media PVC.
- Build ledger: `~/Developer/build-ledger/versions.json`.

## Remaining work

1. Diagnose the actual capture denial without weakening macOS protections; distinguish signing, permission state and API behavior.
2. Verify a real button-driven point capture and have the agent correctly identify the target.
3. Verify walkthrough recording, normal app clicks, drawing, notes, stopping, frame extraction and OpenCode response.
4. Record a safe public demo, inspect it, publish it to the project website, and update preview/verification claims only after success.
5. Update the website's older shortcut instructions to match the latest button-first app, then update the build ledger for deployment changes.

The user asked to stop troubleshooting and push this handoff so another agent can continue.
