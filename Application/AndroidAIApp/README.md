# AI Toolbox (Android)

Android implementation of a lightweight AI tool launcher. The app presents curated categories for popular free or trial AI services and opens each one inside an in-app browser (Chrome Custom Tabs) with a single tap.

## Project Layout

```
Application/AndroidAIApp/
?? build.gradle.kts          # Top-level Gradle configuration
?? settings.gradle.kts       # Module inclusion
?? gradle.properties         # Shared Gradle properties
?? app/
   ?? build.gradle.kts       # Android application module (Compose enabled)
   ?? src/main/
   ?  ?? AndroidManifest.xml
   ?  ?? java/com/dopamine/aiapps/MainActivity.kt
   ?  ?? res/...             # Strings, theme, adaptive icon assets
   ?? proguard-rules.pro
```

## Features

- Dark gradient aesthetic inspired by the Dopamine UI.
- Categorised list of tools (chat, media, productivity) with short descriptions.
- Opens links directly via Chrome Custom Tabs with graceful fallback behaviour.
- Fully built with Jetpack Compose for quick customisation and future expansion.

## Building & Running

1. Ensure **Android Studio Giraffe (or newer)** with JDK 17 support is installed.
2. From Android Studio, choose **File -> Open...** and select `Application/AndroidAIApp`.
3. Let Gradle sync; the project targets **compileSdk 34** and **minSdk 24**.
4. Choose an emulator or physical device and click **Run**.

### Command-line

If `gradlew` is available in your environment, run:

```bash
./gradlew :app:assembleDebug
```

You can create a Gradle wrapper via `gradle wrapper` should you need reproducible builds outside Android Studio.

## Parity with iOS Implementation

- Data: tool metadata lives in a single Kotlin object (`AiToolCatalog`) and can be replaced with remote JSON later.
- Navigation: each card launches the service in a custom tab with fallback to the default browser.
- Styling: Material 3 + Compose cards with subtle transparency and rounded corners.
- Difference: no API keys required, making it a solid foundation before deeper integrations.

## Next Steps

- Hook a remote data source (JSON, Firebase) to update the catalogue without a new release.
- Localise strings via `strings.xml` if you plan to support additional languages.
- Add `androidTest` coverage to verify link launching and error handling when no browser is available.
