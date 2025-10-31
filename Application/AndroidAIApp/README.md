# AI Toolbox (Android)

Android implementation of the AI catalog experience introduced in the iOS Dopamine application. The app is a standalone Jetpack Compose project that presents the same curated categories and launches each tool in the system browser.

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

- Dark-themed gradient background mirroring the Dopamine aesthetic.
- Categorised list of AI services (chat assistants, creative tools, productivity copilots).
- Tappable cards that open the selected service in the user's browser with graceful error handling.
- Material 3 theming with adaptive typography and preview support.

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

- Data: Uses the same curated catalog as the Objective-C view controller (`DOAIApplicationsViewController`).
- Navigation: Both platforms push a dedicated screen from the main action hub and deep-link to external URLs.
- Styling: Android replicates the modal card style with rounded corners, translucency, and dark gradients.
- Differences: Android leverages Compose's `LazyColumn` instead of UIKit stacks and relies on Material 3 typography/token defaults.

## Next Steps

- Hook into a shared data source if the catalog needs server-driven updates.
- Localize strings (`strings.xml`) once translations are available to mirror the existing `.strings` files on iOS.
- Add instrumented UI tests (`androidTest`) for navigation and intent dispatch if this becomes part of a larger Android product.
