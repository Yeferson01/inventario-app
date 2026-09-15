import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local-only configuration; android/key.properties and *.jks/*.keystore are
// already ignored. storeFile may be absolute or relative to android/.
val releaseKeyProperties = Properties()
val releaseKeyPropertiesFile = rootProject.file("key.properties")
if (releaseKeyPropertiesFile.isFile) {
    releaseKeyPropertiesFile.inputStream().use { releaseKeyProperties.load(it) }
}
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseKeyProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.cronosmanagement.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cronosmanagement.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("pilotRelease") {
                storeFile = rootProject.file(releaseKeyProperties.getProperty("storeFile"))
                storePassword = releaseKeyProperties.getProperty("storePassword")
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never distribute a pilot APK silently signed with the debug key.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("pilotRelease") else null
        }
    }
}

val requirePilotReleaseSigning = tasks.register("requirePilotReleaseSigning") {
    doLast {
        check(hasReleaseSigning) {
            "Release signing is not configured. Supply the approved local android/key.properties; no debug fallback is allowed."
        }
        check(rootProject.file(releaseKeyProperties.getProperty("storeFile")).isFile) {
            "The approved release keystore is unavailable."
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(requirePilotReleaseSigning)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
