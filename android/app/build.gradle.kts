import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (gitignored) on a
// developer machine, or from environment variables in CI. Keys are never
// committed (SPEC.md §5.3).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(property: String, env: String): String? =
    keyProperties.getProperty(property) ?: System.getenv(env)

val releaseStoreFile = signingValue("storeFile", "TERRENOS_KEYSTORE_PATH")

android {
    namespace = "pt.terrenos.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "pt.terrenos.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // SPEC.md §5.2
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // dev and prod install side by side, for testing sync between two app
    // instances on one phone. foss leaves out Google Play Services (Nearby)
    // for F-Droid; it syncs by file only (SPEC.md §5.3).
    buildFeatures {
        resValues = true
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("dev") {
            dimension = "distribution"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Terrenos Dev")
        }
        create("prod") {
            dimension = "distribution"
            resValue("string", "app_name", "Terrenos")
        }
        create("foss") {
            dimension = "distribution"
            resValue("string", "app_name", "Terrenos")
        }
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("storePassword", "TERRENOS_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "TERRENOS_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "TERRENOS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without release keys (e.g. a contributor's machine), release
            // builds are signed with the debug key so `flutter run --release`
            // still works. Such builds can't be uploaded to Google Play.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
