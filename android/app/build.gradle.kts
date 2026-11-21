plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.gaboexperimetos.cyberhex"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gaboexperimetos.cyberhex"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Solo arm64-v8a (Redmi Note 13 / Snapdragon 685). Los demas ABI se
        // pueden habilitar pasando argumentos a build_android.sh.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Compila el núcleo nativo (Zig + C23) antes del APK.
//
// - Se cachea: solo se recompila si cambian los fuentes del núcleo.
// - Se puede saltar con `flutter build apk --android-project-arg=skipCoreBuild=true`
//   (útil si ya copiaste el .so a mano o si no tienes Zig/NDK instalados).
val skipCoreBuild = providers.gradleProperty("skipCoreBuild").orNull == "true"
val coreDir = rootProject.file("../core")
val coreLibsDir = file("src/main/jniLibs/arm64-v8a")

val buildCyberHexCore by tasks.registering(Exec::class) {
    group = "build"
    description = "Compila libcyberhex_core.so (Zig + C23) para arm64-v8a"
    workingDir = coreDir
    commandLine("./build_android.sh")
    inputs.dir(coreDir.resolve("src"))
    inputs.files(
        coreDir.resolve("build.zig"),
        coreDir.resolve("build.zig.zon"),
        coreDir.resolve("build_android.sh"),
    )
    outputs.dir(coreLibsDir)
    onlyIf { !skipCoreBuild }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(buildCyberHexCore)
}

flutter {
    source = "../.."
}
