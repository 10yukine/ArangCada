import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json for FCM only -- no other Firebase
    // product is used or enabled.
    id("com.google.gms.google-services")
}

// Release signing reads android/key.properties (gitignored, never
// committed): storeFile, storePassword, keyAlias, keyPassword. Without it a
// release build stops, so an APK signed with the public debug key cannot be
// handed out by accident. For a local test build on a machine without the
// key, set ARANGCADA_ALLOW_DEBUG_SIGNING=1.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// Check the selected task graph, not configuration: Gradle configures the
// release build type even when a recipient only asks for a debug build.
gradle.taskGraph.whenReady {
    if (keyProperties.isEmpty() &&
        System.getenv("ARANGCADA_ALLOW_DEBUG_SIGNING") != "1" &&
        allTasks.any { it.project == project && it.name.contains("Release", ignoreCase = true) }
    ) {
        throw GradleException(
            "android/key.properties is missing, so this release build has no signing key. " +
                "Add it, or set ARANGCADA_ALLOW_DEBUG_SIGNING=1 for a local test build.",
        )
    }
}

// GOOGLE_MAPS_API_KEY from --dart-define(-from-file), which Flutter hands to
// Gradle as comma-separated base64 "KEY=value" entries. The Maps SDK only
// reads its key from the manifest. Blank means the app keeps MapLibre.
val googleMapsApiKey: String = (project.findProperty("dart-defines") as String? ?: "")
    .split(",")
    .filter { it.isNotBlank() }
    .map { String(Base64.getDecoder().decode(it)) }
    .firstOrNull { it.startsWith("GOOGLE_MAPS_API_KEY=") }
    ?.substringAfter("=")
    ?: ""

android {
    namespace = "ph.calamba.arangcada"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires core library desugaring
        // (https://developer.android.com/studio/write/java8-support.html) --
        // the release build otherwise fails at :app:checkReleaseAarMetadata
        // with "Dependency ':flutter_local_notifications' requires core
        // library desugaring to be enabled for :app."
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ph.calamba.arangcada"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["googleMapsApiKey"] = googleMapsApiKey
    }

    signingConfigs {
        if (keyProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            // R8 code + resource shrinking. The Flutter Gradle plugin already
            // turns both on for release and adds proguard-android-optimize.txt,
            // Flutter's keep rules and ./proguard-rules.pro (if present);
            // these lines only make it visible to readers and store checks.
            // Keep rules plugins need ship inside the plugins themselves.
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Required by isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
