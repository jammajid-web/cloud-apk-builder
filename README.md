# ChatWave Android

Flutter + Dart messaging client backed by the existing Supabase ChatWave project.

## Implemented in this source

- Supabase Google OAuth sign-in and profile editing
- Direct conversations and user-created groups
- Realtime text messages, typing state, read receipts / blue ticks
- Image, video, document and voice-note uploads to the private `chat-media` bucket (45 MB client limit)
- Voice-note recording and playback; image preview and external opening for video/documents
- Hide-chat-for-me and admin group deletion using the existing database RPCs
- Firebase Cloud Messaging device-token registration and an Edge Function for message push delivery
- AdMob banner, interstitial (every 10 sent text messages in a chat screen) and rewarded ad
- Generated Android launcher icon and splash screen

Voice/video calling is intentionally not included yet, as requested.

## Required GitHub Actions secrets

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `GOOGLE_SERVICES_JSON` (complete `google-services.json` contents; package must be `com.chatwave.app`)
- `ADMOB_APP_ID`
- `ADMOB_BANNER_ID`
- `ADMOB_INTERSTITIAL_ID`
- `ADMOB_REWARDED_ID`

The workflow builds a release APK artifact named `ChatWave-final-APK`.

## Supabase / Google setup

1. Enable Google in Supabase Authentication providers and configure the Google OAuth client ID/secret.
2. Add `com.chatwave.app://login-callback` to Supabase Auth URL Configuration's redirect allow list.
3. Add the same redirect URI to the Google provider setup where applicable. Android OAuth credentials must include the signing certificate SHA-1 for the installed build.
4. Deploy the push function:

   ```sh
   supabase functions deploy send-chat-notification --project-ref lqjkgkasfpdlyiyahdst
   ```

5. Add a Supabase Edge Function secret named `FIREBASE_SERVICE_ACCOUNT` containing the Firebase service-account JSON. The service account needs Firebase Cloud Messaging send permission. Never put this JSON in the Android app or GitHub source.
6. Enable Firebase Cloud Messaging in the Firebase project.

The existing Supabase schema is used as-is. The app expects the `profiles`, `conversations`, `conversation_members`, `messages`, `message_receipts`, `typing_status`, `user_presence`, and `device_tokens` tables, plus the existing `create_direct_conversation`, `create_group_conversation`, `hide_conversation`, and `delete_group_conversation` RPCs and the private `chat-media` bucket.

## Important production notes

- Push delivery requires the Edge Function deployment and `FIREBASE_SERVICE_ACCOUNT` secret above; token registration alone does not send notifications.
- Google sign-in requires the provider setup in Supabase and a matching Android package/signing fingerprint.
- AdMob production inventory may remain limited until the app is reviewed/approved by Google.
- The release workflow uses the generated Android debug signing configuration unless a production keystore is added. For Play Store publishing, configure a private release keystore and keep its passwords in GitHub Actions secrets.
- The in-chat notice accurately states that this build is not end-to-end encrypted. Do not advertise E2EE until a reviewed encryption/key-management protocol is implemented.
