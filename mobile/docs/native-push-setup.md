# Native Push Setup

This repository currently contains the Dart/Flutter application layer but does not yet include generated `android/` and `ios/` platform folders. Before native push can work on a device, create those folders with standard Flutter tooling and then apply the setup below.

## 1. Generate platform projects

Run from `mobile/`:

```bash
flutter create .
```

If only one platform is needed:

```bash
flutter create --platforms=android,ios .
```

## 2. Add Firebase project files

Required files:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Generate them from the Firebase console for the exact Android application ID and iOS bundle ID used by the app.

## 3. Android setup

Update `android/build.gradle` or `android/settings.gradle` according to the current Flutter/Firebase plugin layout and make sure the Google services plugin is applied.

Expected items:

- Google services Gradle plugin available to the Android build
- `com.google.gms.google-services` applied in `android/app/build.gradle`
- notification permission handling for Android 13+
- default notification channel metadata if foreground notifications will be shown

Recommended Android manifest capabilities:

- `android.permission.POST_NOTIFICATIONS`
- `android.permission.INTERNET`
- optional boot/background handling only if your product policy requires it

## 4. iOS setup

In Xcode for `ios/Runner.xcworkspace`:

- enable Push Notifications capability
- enable Background Modes with Remote notifications
- confirm the bundle identifier matches the Firebase app
- confirm APNs key or certificate is configured in Firebase

## 5. Firebase initialization

Preferred production path:

```bash
flutterfire configure
```

That command generates `firebase_options.dart`. This repository currently uses `Firebase.initializeApp()` without generated options so local builds do not break while native setup is still incomplete. Once platform folders exist, replacing the generic initialization with generated options is recommended.

## 6. Backend contract

The backend expects device registration payloads with:

- `platform`: `android` or `ios`
- `pushToken`: native FCM/APNs bridge token
- `appVersion`: current app version

The current Flutter layer already sends these fields after login and on token refresh.

## 7. Verification checklist

- app launches on Android and iOS without Firebase initialization errors
- login registers a real device token in backend `/v1/devices`
- foreground invite push is received by the app
- tapping a background/terminated invite push opens invite acceptance flow
- token refresh updates the backend device record
