# Android Release Signing

## Configuration

`android/app/build.gradle.kts` loads release values from the untracked file:

```text
android/key.properties
```

Start from `android/key.properties.example`:

```properties
storePassword=REPLACE_ME
keyPassword=REPLACE_ME
keyAlias=REPLACE_ME
storeFile=REPLACE_ME
```

`key.properties`, `*.jks`, and `*.keystore` are ignored. Keep the keystore
outside the repository and use an absolute forward-slash path for `storeFile`.

## Create an owner-controlled upload key

Run this outside the repository and answer the password prompts locally:

```bat
keytool -genkeypair -v -keystore "%USERPROFILE%\PilgrimTrackerSecrets\pilgrim-tracker-upload.jks" -alias pilgrimtracker -keyalg RSA -keysize 4096 -validity 10000
```

Back up the keystore and passwords securely in at least two owner-controlled
locations. Losing the signing key can prevent future application upgrades.
Never commit or paste the passwords, keystore, or completed properties file.

## Owner-signed builds

After creating `android/key.properties`:

```bat
flutter build apk --release
flutter build appbundle --release
```

## Temporary technical builds

Without owner credentials, debug signing requires an explicit opt-in:

```powershell
$env:PILGRIM_ALLOW_DEBUG_RELEASE_SIGNING = "true"
flutter build apk --release
flutter build appbundle --release
```

These artifacts are installable technical test builds only. They are not Play
closed-beta ready and must never establish the production signing identity.
