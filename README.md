# build-x3

Build X is an autonomous agent and chat client for mobile and desktop, powered by NVIDIA Nemotron with Chat and Work modes.

## Start chatting

1. Install Flutter 3.44.9 or newer and run `flutter pub get`.
2. Run `flutter run` for a supported device.
3. Open **Settings → Mistral connection** and save your Mistral API key.

The key is kept in platform secure storage. Build X retains a remote Mistral conversation ID for each local chat so subsequent turns continue the same conversation. API usage may incur charges under your Mistral account.

Search settings can store a skill and a browser account for future use. Browser sign-in automation is not implemented. Memory entries can be reviewed, edited, archived, and deleted in **Settings → Memory**.

## Supabase authentication

Authentication is fail-closed: the app does not open the workspace when its
Supabase configuration is missing or cannot be initialized. Supply the project
URL and publishable key at compile time without committing either value:

```bash
flutter run \
  --dart-define=SUPABASE_URL=<your-project-url> \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-publishable-key>
```

Use the same two `--dart-define` arguments for release builds. Configure
`buildx://login-callback` as an allowed redirect URL in Supabase Auth and in the
Google provider configuration.

The Dart package identifier and existing on-disk data format retain their original identifiers for compatibility. This project is based on the [upstream source](https://github.com/Chevey339/kelivo); its license is in [LICENSE](LICENSE).
