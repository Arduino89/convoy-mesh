plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Opt-in packaging only: keep the previous installed app and its private data.
// CI verifies this ID on the actual APK; the radio protocol is unchanged.
val convoyExperimental = providers.gradleProperty("convoyExperimental").orNull == "true"

android {
    namespace = "com.example.convoy_mesh"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (convoyExperimental) {
            "com.example.convoy_mesh.pedestrianexp1"
        } else {
            "com.example.convoy_mesh"
        }
        manifestPlaceholders["convoyAppLabel"] =
            if (convoyExperimental) "Convoy Mesh Exp" else "Convoy Mesh"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
