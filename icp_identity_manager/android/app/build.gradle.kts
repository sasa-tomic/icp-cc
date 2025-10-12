plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.icp_identity_manager"
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
        applicationId = "com.example.icp_identity_manager"
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
        val projectRoot = project.rootDir.parentFile // icp-cc
        val rustCrateDir = File(projectRoot, "rust/icp_core")
        val targetDir1 = File(rustCrateDir, "target")
        val targetDir2 = File(projectRoot, "target")
        val jniLibsDir = File(project.projectDir, "src/main/jniLibs")

        tasks.named("merge${variant.name.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }}JniLibFolders").configure {
            doFirst {
                abiDirs.forEach { (abi, triple) ->
                    val outDir = File(jniLibsDir, abi)
                    outDir.mkdirs()
                    val candidates = listOf(
                        File(targetDir1, "${triple}/release/libicp_core.so"),
                        File(targetDir1, "${triple}/debug/libicp_core.so"),
                        File(targetDir2, "${triple}/release/libicp_core.so"),
                        File(targetDir2, "${triple}/debug/libicp_core.so"),
                    )
                    val src = candidates.firstOrNull { it.exists() }
                    if (src != null) {
                        val dst = File(outDir, "libicp_core.so")
                        src.copyTo(dst, overwrite = true)
                        println("Copied Rust lib to ${dst}")
                    } else {
                        println("Warning: libicp_core.so not found for ABI ${abi}; build Rust targets or set up cargo-ndk")
                    }
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
