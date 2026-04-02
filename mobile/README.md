# Mobile App

Flutter application scaffold for the walkie-talkie client.

## Planned Modules

- `core`: networking, websocket, storage, theme
- `features/auth`: login and registration
- `features/channels`: list, details, invite entry
- `features/ptt`: push-to-talk logic and UI
- `features/settings`: device and account settings

## Current Implemented Scope

- login request flow against backend
- channel listing and join bootstrap
- websocket-based speaker request and release
- websocket-based speaker lease renewal while speaking
- local microphone preparation using `flutter_webrtc`
- PTT state controller for connecting, listening, requesting, and speaking
- channel subscription and speaker state updates via broadcast events
- preliminary LiveKit room connection and microphone publish toggling
- controller-side room connection monitoring and reconnecting state
- device registration request after login for push-ready backend integration
- invite token / deep link parsing helper and invite accept screen
- startup invite token handoff from app entry to post-login accept flow
- persisted auth session storage and startup restore flow
- automatic refresh-token-based session recovery during app bootstrap
- automatic `401` refresh and request retry for authenticated API calls
- forced return to login when refresh recovery fails
- Firebase Messaging bootstrap for native push token acquisition
- invite token extraction from push-opened notifications
- automatic backend device registration sync using real push tokens
- basic channel administration screen for members, roles, channel settings, and invite revocation
- owner-visible admin entry, invite token copy flow, and audit event listing
- backend-sourced channel role visibility for owner/admin management entry and action gating
- confirmation dialogs for destructive admin actions and human-readable audit formatting
- readable timestamps and safer owner-transfer / member-removal / invite-revoke confirmations

## Android build (platform folder)

This repo ships Dart sources under `lib/` without a checked-in `android/` tree. Generate it once:

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_android.ps1
```

REST defaults: Android emulator uses `http://10.0.2.2:8080` and rewrites `localhost` in join payloads (WS, LiveKit, ICE) unless you set `--dart-define=API_BASE_URL=...` or `--dart-define=DEV_LOOPBACK_HOST=...`.

## Runtime deep-link verification (Android)

With backend/infra running and app open on emulator:

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File .\tool\verify_runtime_invite_deeplink.ps1
```

Optional parameters:

- `-ApiBaseUrl http://localhost:8080`
- `-DeviceId emulator-5554`
- `-PackageName com.codessy.walkietalkie`
- `-ValidateLoggedOutBoundary $true`

## Physical device smoke

With a real Android device attached (`adb devices`) and backend reachable:

```powershell
cd mobile
flutter build apk --debug --flavor dev --dart-define-from-file=env/dev.json
powershell -ExecutionPolicy Bypass -File .\tool\run_physical_device_smoke.ps1 -ApiBaseUrl http://<host-ip>:8080
```

Use `-AllowEmulator` only when you intentionally want emulator fallback.

## Flavors and env defines

Android flavors:

- `dev` -> `com.codessy.walkietalkie.dev`
- `stage` -> `com.codessy.walkietalkie.stage`
- `prod` -> `com.codessy.walkietalkie`

Sample runs:

```powershell
cd mobile
flutter run --flavor dev --dart-define-from-file=env/dev.json
flutter build apk --debug --flavor dev --dart-define-from-file=env/dev.json
flutter build apk --release --flavor prod --dart-define-from-file=env/prod.json
```

## Android release signing

Place `mobile/android/keystore.properties` (do not commit secrets) with:

```properties
storeFile=../keystore/upload-keystore.jks
storePassword=***
keyAlias=upload
keyPassword=***
```

If this file is absent, release builds fall back to debug signing for local/dev workflows.

## Release build command

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File .\tool\build_android_release.ps1 -Flavor prod -ApiBaseUrl https://api.example.com
```

Optional: add `-BuildApk` to produce release APK in addition to AAB.

## Configure GitHub release secrets

Use one command to populate required `mobile-release` workflow secrets:

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File .\tool\set_mobile_release_secrets.ps1 `
  -Repository <owner/repo> `
  -StageApiBaseUrl https://stage-api.yourdomain.com `
  -ProdApiBaseUrl https://api.yourdomain.com `
  -KeystorePropertiesPath .\android\keystore.properties `
  -KeystoreFilePath .\android\keystore\upload-keystore.jks `
  -PlayServiceAccountJsonPath .\android\play-service-account.json
```

Required secrets created by this script:

- `MOBILE_ANDROID_KEYSTORE_PROPERTIES`
- `MOBILE_ANDROID_KEYSTORE_BASE64`
- `MOBILE_API_BASE_URL_STAGE`
- `MOBILE_API_BASE_URL_PROD`

Optional (needed only for Play publish):

- `MOBILE_PLAY_SERVICE_ACCOUNT_JSON`

## Release workflow and Play internal publish

In GitHub Actions, run `mobile-release` and choose:

- `flavor`: `stage` or `prod`
- `build_apk`: `true` if you also need APK artifact
- `publish_internal`: `true` to upload AAB to Play internal track

When `publish_internal=true`, workflow uploads using `MOBILE_PLAY_SERVICE_ACCOUNT_JSON`.

You can trigger the workflow directly from local machine:

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File .\tool\trigger_mobile_release.ps1 `
  -Repository <owner/repo> `
  -Flavor stage `
  -BuildApk
```

`set_mobile_release_secrets.ps1` and `trigger_mobile_release.ps1` auto-download a portable `gh` binary if GitHub CLI is not installed globally.

## Additional QA docs

- `mobile/docs/physical-device-validation.md`
- `mobile/docs/ptt-quality-test-plan.md`

## Important Notes

- microphone permissions must be requested contextually
- background audio behavior must be reviewed against App Store and Play policies
- WebRTC publication should only start after backend grants speaker lock
- native Firebase and platform push steps are documented in `mobile/docs/native-push-setup.md`
