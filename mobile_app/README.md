# couple_vault (Flutter app)

The Flutter frontend for Couple's Private Vault. See the
[project root README](../README.md) for the full setup guide (backend
deployment, admin panel, building/installing this app) and
[../project.md](../project.md) / [../DECISIONS.md](../DECISIONS.md) for the
spec and implementation decisions.

## Build

```bash
flutter pub get
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

## Notes

- Android only has been build-verified end-to-end (debug + release APK).
  iOS platform files are scaffolded (`ios/`) but not build-verified here —
  no Apple toolchain in this environment.
- `flutter build apk` currently disables Kotlin incremental compilation
  (`android/gradle.properties`) — a Windows-only fix for a Kotlin
  cross-drive path bug when the project and Gradle/pub caches are on
  different drives. Harmless on Linux/macOS CI or a same-drive setup.
