# Android Release Signing

## Cloud-enabled release helper

Set the values in the current PowerShell process without committing them, then
use the helper. It validates both values, rejects placeholders, and never echoes
the publishable key.

```powershell
$env:SUPABASE_URL = 'https://YOUR_REAL_PROJECT_REF.supabase.co'
$env:SUPABASE_PUBLISHABLE_KEY = 'YOUR_REAL_PUBLIC_PUBLISHABLE_KEY'
powershell -NoProfile -File .\tool\build_release.ps1 -Platform windows
powershell -NoProfile -File .\tool\build_release.ps1 -Platform apk
powershell -NoProfile -File .\tool\build_release.ps1 -Platform aab
```

The helper passes both values through `--dart-define`. Ordinary local/debug
launches remain usable without cloud configuration. After each owner build,
open Household Settings and verify configuration is reported as configured,
signed-out startup has no red connectivity error, sign-in restores the correct
membership/link state, offline retry leaves local data accessible, and
close/reopen reports the current session accurately.

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

## D14 closure — 2026-08-02

Owner acceptance confirms that both the owner-signed APK and AAB build. The APK
signature verifies against the following identity and is not Android Debug
signed:

```text
CN=Enos Pebrian
OU=Pilgrim Tracker
O=Tebu Nai
L=Denpasar
ST=Bali
C=ID
```

The Android application ID remains `com.enospebrian.pilgrimtracker`, the
product remains Pilgrim Tracker `1.0.0+1`, and the validated owner keystore must
continue to be retained securely. This approval covers controlled private
deployment to Enos and Grace; it does not claim Play Store publication.

## Temporary technical builds

Without owner credentials, debug signing requires an explicit opt-in:

```powershell
$env:PILGRIM_ALLOW_DEBUG_RELEASE_SIGNING = "true"
flutter build apk --release
flutter build appbundle --release
```

These artifacts are installable technical test builds only. They are not Play
closed-beta ready and must never establish the production signing identity.

## Historical D14 Final result — 2026-07-30

This blocked attempt is superseded by the successful owner artifact evidence
recorded in the 2026-08-02 closure above.

The configured external keystore and `pilgrimtracker` alias passed certificate
inspection with the expected Enos owner identity. The single permitted signed
APK build did not report a credential error; Gradle's Java daemon terminated
because native memory was exhausted. No new signed APK or AAB was produced.

Before the next controlled attempt, close memory-intensive applications and
enable a Windows pagefile or deliberately lower the current Gradle JVM memory
limits. Then build one release APK, verify it with `apksigner --print-certs`,
and only after that succeeds build the release AAB. Do not replace the working
keystore or guess credentials.

## D14A recovery result — 2026-07-30

The recovery environment is now correctly constrained to a 4096 MiB Gradle
heap and 1024 MiB metaspace. Windows reports a 9479 MiB pagefile and sufficient
free virtual memory. The external owner keystore, `pilgrimtracker` alias, Enos
certificate identity, and non-debug release-signing path all passed preflight.

The one permitted APK command was launched, but the execution wrapper stopped
it before Flutter or Gradle produced build output. No process survived and no
APK was created. Per the no-retry rule, no second APK command and no AAB command
were run. This is a build-execution harness failure, not a signing failure.
