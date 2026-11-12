import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Apply the Flutter plugin after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing can be supplied through Codemagic environment variables or
// android/key.properties (copied from key.properties.example).
val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.isFile) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
}

fun signingValue(environmentName: String, propertyName: String): String? {
    return System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
}

val releaseStorePath = signingValue("CM_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("CM_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("CM_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("CM_KEY_PASSWORD", "keyPassword")

val releaseSigningValues = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword
)
val hasAnyReleaseSigningValue = releaseSigningValues.any { !it.isNullOrBlank() }
val hasCompleteReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }

if (hasAnyReleaseSigningValue && !hasCompleteReleaseSigning) {
    throw GradleException(
        "Incomplete Android release signing configuration. Set all four CM_KEYSTORE_* variables " +
            "or complete android/key.properties."
    )
}

if (hasCompleteReleaseSigning && !rootProject.file(releaseStorePath!!).isFile) {
    throw GradleException("Release keystore was not found: ${rootProject.file(releaseStorePath!!).path}")
}

if (!hasCompleteReleaseSigning) {
    logger.warn(
        "WARNING: Release builds are using the DEBUG key. This is for local testing only; " +
            "configure a private upload keystore before uploading to Google Play."
    )
}

android {
    // Keep this namespace aligned with the package declared by MainActivity.kt.
    namespace = "com.example.taiz_express"

    // AGP 8.10.x supports compileSdk 36 (Android 16).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // This applicationId matches the Android client in google-services.json.
        // Do not change it after publishing the app on Google Play.
        applicationId = "com.maeen.fastdelivery"
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            (System.getenv("GOOGLE_MAPS_API_KEY") ?: project.findProperty("GOOGLE_MAPS_API_KEY") as? String).orEmpty()

        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasCompleteReleaseSigning) {
            create("production") {
                storeFile = rootProject.file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Without a configured upload key, the release build remains usable
            // for local testing but is NOT suitable for Google Play submission.
            signingConfig = if (hasCompleteReleaseSigning) {
                signingConfigs.getByName("production")
            } else {
                signingConfigs.getByName("debug")
            }
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
    // Required by flutter_local_notifications for Java 8+ API desugaring.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
