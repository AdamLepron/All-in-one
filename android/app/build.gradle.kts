import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.allinone.all_in_one"
    compileSdk = 37 // required by permission_handler
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.allinone.all_in_one"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob application id; the test one until a real one is passed with
        // -PadmobAppId=ca-app-pub-…~… (or in android/gradle.properties).
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("admobAppId") as String?)
                ?: "ca-app-pub-3940256099942544~3347511713"
    }

    // Test-only key, committed so every test APK carries the same signature and
    // installs over the previous one. Replace with a private key before store release.
    signingConfigs {
        create("test") {
            storeFile = file("test.keystore")
            storePassword = "allinone"
            keyAlias = "test"
            keyPassword = "allinone"
        }
    }

    // Store release: put your private key's details in android/key.properties
    // (never committed; see docs/store/PUBLICATION.md). Without that file the
    // test key above is used, so test APKs keep installing over each other.
    val keyFile = rootProject.file("key.properties")
    if (keyFile.exists()) {
        val keys = Properties().apply { keyFile.inputStream().use { load(it) } }
        signingConfigs {
            create("store") {
                storeFile = file(keys.getProperty("storeFile"))
                storePassword = keys.getProperty("storePassword")
                keyAlias = keys.getProperty("keyAlias")
                keyPassword = keys.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("store") ?: signingConfigs.getByName("test")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Video editing: trimming, joining, speed, rotation and audio mixing.
    implementation("androidx.media3:media3-transformer:1.11.1")
    implementation("androidx.media3:media3-effect:1.11.1")
    implementation("androidx.media3:media3-common:1.11.1")
    // Table of contents and text search in PDF files.
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
}
