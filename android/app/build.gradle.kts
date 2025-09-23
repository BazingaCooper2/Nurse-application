import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin must be applied last
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Apply google-services plugin
}

android {
    namespace = "com.nursetracker.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.nursetracker.app"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_11
            targetCompatibility = JavaVersion.VERSION_11
            isCoreLibraryDesugaringEnabled = true
        }
    }

    // 🔑 Signing configuration
    signingConfigs {
        create("release") {
            val keystoreProperties = Properties()
            val keystoreFile = rootProject.file("key.properties")
            if (keystoreFile.exists()) {
                keystoreProperties.load(FileInputStream(keystoreFile))
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")   // ✅ link signing
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging") // FCM
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}
