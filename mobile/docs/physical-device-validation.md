# Physical Android Validation Checklist

Use this checklist before any stage/prod rollout.

## Preconditions

- Backend stack is running and reachable from device network.
- `dev` APK is built:
  - `flutter build apk --debug --flavor dev --dart-define-from-file=env/dev.json`
- Device has USB debugging enabled and appears in `adb devices`.

## Automated smoke (recommended first)

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File .\tool\run_physical_device_smoke.ps1 -ApiBaseUrl http://<your-host-ip>:8080
```

## Manual validation

- Install app and open login screen.
- Login with demo user and verify channel list renders.
- Open channel room:
  - status shows `Dinleme modundasiniz`
  - PTT button appears.
- Deny microphone permission:
  - UI shows `Mikrofon izni gerekli`
  - retry button appears and does not crash app.
- Grant microphone permission and tap `Mikrofonu Tekrar Dene`:
  - UI transitions to `Mikrofon hazir`.
- Send runtime deep-link while app is foreground:
  - `walkietalkie://invite/open?invite=<token>`
  - verify invite screen opens and token pre-fills.
- Accept invite and verify navigation to channel room.

## Pass criteria

- No crash/ANR.
- Invite runtime flow works in both logged-in and logged-out boundary paths.
- PTT channel room remains usable even when microphone access is denied.
