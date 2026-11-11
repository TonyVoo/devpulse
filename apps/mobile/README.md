# DevPulse mobile

Flutter 3.47 · Riverpod 3 · go_router 18 · Dio · Drift · flutter_secure_storage.
Architecture: [docs/MOBILE_ARCHITECTURE.md](../../docs/MOBILE_ARCHITECTURE.md).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift code generation
flutter analyze && flutter test                             # unit + widget tests

# Run against the local API (`make up` from the repo root)
flutter run --dart-define=API_BASE_URL=http://localhost:8000          # iOS simulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000           # Android emulator

# End-to-end on a simulator/emulator against the real API
flutter test integration_test -d <device-id> --dart-define=API_BASE_URL=http://localhost:8000
```

Layout: `lib/core` (config, network, auth tokens, database, design system),
`lib/features/<feature>/{domain,data,presentation}`, `lib/app` (providers, router).
