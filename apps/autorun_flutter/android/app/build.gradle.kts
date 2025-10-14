plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("org.mozilla.rust-android-gradle.rust-android") version "0.9.3" apply false
}

android {
    namespace = "com.example.icp_autorun"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.icp_autorun"
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

    // Copy Rust shared libs (libicp_core.so) from the workspace target dirs into jniLibs
    applicationVariants.all {
        val variant = this
        val abiDirs = mapOf(
            "arm64-v8a" to "aarch64-linux-android",
            "armeabi-v7a" to "armv7-linux-androideabi",
            "x86_64" to "x86_64-linux-android",
            "x86" to "i686-linux-android",
        )
        // Resolve repo root (apps/autorun_flutter/android is three levels under repo root)
        val repoRoot = project.rootDir.parentFile?.parentFile?.parentFile ?: project.rootDir
        val rustCrateDir = File(repoRoot, "crates/icp_core")
        val jniLibsDir = File(project.projectDir, "src/main/jniLibs")

        tasks.named("merge${variant.name.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }}JniLibFolders").configure {
            doFirst {
                val missing = mutableListOf<String>()
                abiDirs.forEach { (abi, _) ->
                    val soFile = File(File(jniLibsDir, abi), "libicp_core.so")
                    if (!soFile.exists()) missing.add(abi)
                }
                if (missing.isNotEmpty()) throw GradleException("Missing libicp_core.so for ABIs: ${missing.joinToString(", ")}. Run: make android")
            }
        }
    }
}

// Deliberately do NOT try to build Rust here; fail fast if missing.

flutter {
    source = "../.."
}
