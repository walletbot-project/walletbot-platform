import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

val hasReleaseKeystore = !keystoreProperties.isEmpty

// A debug-signed APK cannot be installed over a release-signed one (and every
// CI runner generates its own throwaway debug key), so a silent fallback here
// produces artifacts that fail with INSTALL_FAILED_UPDATE_INCOMPATIBLE on any
// device that already has another build. Fail the CI build instead: the
// workflow is expected to write key.properties from repository secrets.
if (!hasReleaseKeystore && System.getenv("CI") != null) {
    throw GradleException(
        "android/key.properties is missing. CI must write it (and the keystore " +
            "it points at) from repository secrets before building, otherwise the " +
            "APK is signed with the runner's throwaway debug key and will not " +
            "install over any other build."
    )
}

android {
    namespace = "live.walletbot.app"
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
        applicationId = "live.walletbot.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = rootProject.file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    // Every build type shares one signing identity, so a device can move
    // between local, staging and production builds without an uninstall.
    // `configureEach` also covers the `profile` type the Flutter plugin adds.
    buildTypes.configureEach {
        signingConfig = if (hasReleaseKeystore) {
            signingConfigs.getByName("release")
        } else {
            signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
