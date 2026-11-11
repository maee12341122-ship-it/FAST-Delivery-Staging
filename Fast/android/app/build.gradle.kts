plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
    id "com.google.gms.google-services"
}

android {
    namespace "com.example.taiz_express"
    compileSdkVersion flutter.compileSdkVersion
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled true
    }

    kotlinOptions {
        jvmTarget = '17'
    }

    defaultConfig {
        applicationId "com.maeen.fastdelivery"
        minSdkVersion flutter.minSdkVersion
        targetSdkVersion flutter.targetSdkVersion
        versionCode flutter.versionCode
        versionName flutter.versionName
        multiDexEnabled true
    }

    signingConfigs {
        production {
            def releaseStorePath = System.getenv("CM_KEYSTORE_PATH")
            if (releaseStorePath != null && !releaseStorePath.isEmpty()) {
                storeFile file(releaseStorePath)
                storePassword System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias System.getenv("CM_KEY_ALIAS")
                keyPassword System.getenv("CM_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.hasProperty("production") ? signingConfigs.getByName("production") : signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source "../.."
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'
}
