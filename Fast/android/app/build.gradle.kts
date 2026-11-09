plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // 👈 هذا السطر هو المسؤول عن تفعيل إشعارات OneSignal و Firebase في الخلفية
    id("com.google.gms.google-services")
}

val releaseStorePath = System.getenv("CM_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("CM_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("CM_KEY_ALIAS")
val releaseKeyPassword = System.getenv("CM_KEY_PASSWORD")

android {
    namespace = "com.example.taiz_express"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
defaultConfig {
    applicationId = "com.maeen.fastdelivery"
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = System.getenv("GOOGLE_MAPS_API_KEY") ?: ""
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!releaseStorePath.isNullOrBlank()) {
            create("production") {
                storeFile = file(releaseStorePath)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (!releaseStorePath.isNullOrBlank()) signingConfigs.getByName("production") else signingConfigs.getByName("debug")
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
