plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
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
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.maeen.fastdelivery"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = System.getenv("GOOGLE_MAPS_API_KEY") ?: ""
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

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
