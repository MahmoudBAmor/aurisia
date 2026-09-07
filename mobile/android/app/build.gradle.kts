import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseSigningFile.isFile) {
    releaseSigningFile.inputStream().use(releaseSigningProperties::load)
}
val requiredReleaseSigningKeys = setOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val missingReleaseSigningKeys = requiredReleaseSigningKeys.filter {
    releaseSigningProperties.getProperty(it).isNullOrBlank()
}
if (releaseSigningFile.isFile && missingReleaseSigningKeys.isNotEmpty()) {
    error("key.properties is missing: ${missingReleaseSigningKeys.sorted().joinToString()}")
}
val hasReleaseSigning = releaseSigningFile.isFile && missingReleaseSigningKeys.isEmpty()
val requiresReleaseSigning = providers.environmentVariable(
    "AURISIA_REQUIRE_RELEASE_SIGNING",
).map { it.equals("true", ignoreCase = true) }.getOrElse(false)
if (requiresReleaseSigning && !hasReleaseSigning) {
    error(
        "AURISIA_REQUIRE_RELEASE_SIGNING=true but mobile/android/key.properties " +
            "is missing or incomplete.",
    )
}

android {
    namespace = "com.aurisia.aurisia_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aurisia.aurisia_mobile"
        // llama.cpp's verified ARM64 runtime requires Android 8 or newer.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
                storeFile = file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Local proof-of-concept builds remain installable without secrets.
            // Store builds set AURISIA_REQUIRE_RELEASE_SIGNING=true so this
            // explicit fallback can never be published accidentally.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "release" else "debug",
            )
            // Vosk uses JNA direct mapping. Its Java class and member names are
            // part of the JNI contract and must survive R8 optimization.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            // JNA still publishes binaries for ABIs Android no longer
            // supports. Excluding them avoids invalid APK entries and stops
            // OneDrive from materializing obsolete mips/armeabi directories.
            excludes += setOf(
                "**/armeabi/**",
                "**/mips/**",
                "**/mips64/**",
            )
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
    implementation("net.java.dev.jna:jna:5.18.1@aar")
    implementation("com.alphacephei:vosk-android:0.3.75@aar")
}

// Flutter stages the AOT Dart snapshot as libapp.so through a generated JNI
// source directory. With redirected Windows build directories, Gradle can
// otherwise execute a cold release build before that staging task has observed
// the newly registered Flutter compile task. The resulting APK installs but
// crashes in FlutterJNI because it contains libflutter.so without libapp.so.
val releaseFlutterJniDirectory =
    layout.buildDirectory.dir("generated/jniLibs/copyJniLibsflutterBuildRelease")
val releaseFlutterAbis =
    providers.gradleProperty("target-platform")
        .orElse("android-arm,android-arm64,android-x64")
        .map { platforms ->
            platforms.split(',').map { platform ->
                when (platform.trim()) {
                    "android-arm" -> "armeabi-v7a"
                    "android-arm64" -> "arm64-v8a"
                    "android-x64" -> "x86_64"
                    else -> error("Unsupported Flutter target platform: $platform")
                }
            }
        }

tasks.matching { it.name == "copyJniLibsflutterBuildRelease" }.configureEach {
    dependsOn("compileFlutterBuildRelease")
}

val verifyFlutterReleaseJni by tasks.registering {
    group = "verification"
    description = "Fails a release build when its compiled Dart library was not staged."
    dependsOn("copyJniLibsflutterBuildRelease")
    inputs.dir(releaseFlutterJniDirectory)
    inputs.property("targetAbis", releaseFlutterAbis)

    doLast {
        val root = releaseFlutterJniDirectory.get().asFile
        releaseFlutterAbis.get().forEach { abi ->
            val library = root.resolve("$abi/libapp.so")
            check(library.isFile && library.length() > 0L) {
                "Flutter release library is missing or empty: ${library.absolutePath}"
            }
        }
    }
}

tasks.matching { it.name == "mergeReleaseNativeLibs" }.configureEach {
    dependsOn(verifyFlutterReleaseJni)
}
