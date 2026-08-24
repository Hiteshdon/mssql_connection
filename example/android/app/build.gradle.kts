plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// mssql_connection ships native FreeTDS libraries but is intentionally a
// pure Dart package (not a registered Flutter plugin, so it also works in
// plain Dart backend/CLI projects). That means Flutter's automatic
// native-library bundling does not apply, so this task runs the package's
// setup command before every build, copying its bundled libraries into
// app/src/main/jniLibs automatically -- no manual step needed after
// `flutter clean` or upgrading the package.
tasks.register<Exec>("mssqlConnectionSetup") {
    workingDir = rootProject.projectDir.parentFile // the Flutter project root
    commandLine("dart", "run", "mssql_connection:setup")
    isIgnoreExitValue = true
}

tasks.named("preBuild") {
    dependsOn("mssqlConnectionSetup")
}
