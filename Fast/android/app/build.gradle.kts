plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.maeen.fastdelivery.fast"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // 1. تفعيل مكتبة الـ Desugaring لحل مشاكل التوافق مع الإشعارات
        coreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.maeen.fastdelivery.fast"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // تفعيل الـ MultiDex إذا احتجت لها
        multiDexEnabled = true
    }

    // 2. إعدادات التوقيع بربطه بملف key.properties الذي أنشأناه
    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val properties = java.util.Properties()
                properties.load(java.io.FileInputStream(keystorePropertiesFile))
                
                storeFile = file(properties.getProperty("storeFile"))
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 3. ربط الـ release بمفتاح التوقيع الخاص بك بدلاً من الـ debug
            signingConfig = signingConfigs.getByName("release")
            
            // يمكنك تفعيل التصغير (Minification) لاحقاً إذا رغبت
            isMinifyEnabled = false
            isShrinkResources = false
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

// 4. إضافة تبعية الـ Desugaring المطلوبة للإشعارات في نهاية الملف
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
