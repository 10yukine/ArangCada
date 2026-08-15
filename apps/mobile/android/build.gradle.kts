allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Pin every Android module -- app and plugins alike -- to a compileSdk that is
// actually installed locally.
//
// Why this exists: some plugins (permission_handler_android) request
// compileSdk 37. The SDK manager installs that platform into
// `platforms/android-37.0`, but Gradle resolves it by the hash string
// `android-37`, so the build dies with:
//   Failed to find target with hash string 'android-37'
// Platform 36 is installed and satisfies every plugin's minimum, so we hold
// the whole build there rather than chasing a preview platform.
//
// Remove this block once `platforms/android-37` resolves normally.
val pinnedCompileSdk = 36

subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { androidExtension ->
            (androidExtension as com.android.build.gradle.BaseExtension)
                .compileSdkVersion(pinnedCompileSdk)
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
