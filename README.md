# ChatWave Flutter + Supabase starter

This is the initial Flutter Android project scaffold for ChatWave. It is **not yet a complete messenger**.

## Stack
- Flutter / Dart
- `supabase_flutter` for Supabase Auth and database access
- Android-first; designed to expand to iOS later

## Requirements
- Flutter stable SDK (see https://docs.flutter.dev/get-started/install)
- Android Studio + Android SDK
- A Supabase project you control

## Setup
1. Open this folder as a Flutter project in Android Studio or VS Code.
2. Run `flutter pub get`.
3. Pass your Supabase project URL and **publishable key** (or legacy anon key for an existing project) using `--dart-define` when running/building.
4. Never put a `service_role` or secret key in the mobile app.
5. Run `flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY`.

The app intentionally does not modify your existing Supabase database. Before adding chat queries, inspect the current tables, RLS policies, Storage buckets, Auth providers and Realtime publication so the native app matches the existing backend rather than creating duplicate tables.

## Google sign-in
The starter includes Supabase initialization and a sign-in screen placeholder. Google OAuth requires configuring the Google provider in Supabase, the correct Android application ID / SHA fingerprints, and a verified redirect/deep-link return path. Complete those settings before testing Google login on a device.

## Current scope
Included:
- Flutter project metadata and Android app scaffold
- Supabase client initialization
- Configurable Supabase URL and public key
- Basic ChatWave landing / sign-in placeholder UI
- GitHub Actions Android debug APK workflow

Not included yet:
- Working Google OAuth flow
- Chat list, direct/group messaging, message subscriptions
- File/voice uploads and Storage policies
- WebRTC calls
- FCM token registration and server-side push delivery
- Admin/group management

## Build
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The GitHub workflow builds a debug APK and uploads it as an artifact. It does not publish a signed production release.
