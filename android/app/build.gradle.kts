plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin must be applied last
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nursetracker.app"
    compileSdk = flutter.compileSdkVersion

    // ✅ Force specific NDK version for consistency (optional)
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.nursetracker.app"  // ✅ Must match Manifest + Google API restriction
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true   // ✅ Helpful if method count grows
    }

    // ✅ Java 17 + desugaring support
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // ⚠️ Replace this with your real release keystore before publishing
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // ✅ Prevents "ClassNotFoundException: MainActivity" issues
    packaging {
        resources.excludes += setOf("META-INF/*")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")

    // ✅ Required for Java 8+ APIs on older devices
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // ✅ If you start hitting multidex errors
    implementation("androidx.multidex:multidex:2.0.1")
}
