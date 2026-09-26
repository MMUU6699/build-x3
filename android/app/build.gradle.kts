import java.util.Properties
import java.util.Base64
import java.nio.charset.StandardCharsets

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.psyche.kelivo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.psyche.kelivo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Flutter controls APK ABI filtering, including --split-per-abi.
        externalNativeBuild {
            cmake {
                abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.isIncludeAndroidResources = true
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

val requiredProotLibs = listOf(
    "armeabi-v7a/libproot_exec.so",
    "armeabi-v7a/libproot_loader.so",
    "armeabi-v7a/libtalloc.so",
    "armeabi-v7a/libandroid-shmem.so",
    "arm64-v8a/libproot_exec.so",
    "arm64-v8a/libproot_loader.so",
    "arm64-v8a/libtalloc.so",
    "arm64-v8a/libandroid-shmem.so",
    "x86_64/libproot_exec.so",
    "x86_64/libproot_loader.so",
    "x86_64/libtalloc.so",
    "x86_64/libandroid-shmem.so",
)

tasks.register<Exec>("fetchProot") {
    val repoRoot = rootProject.projectDir.parentFile
    commandLine("bash", repoRoot.resolve("tool/fetch_proot.sh").absolutePath)
    workingDir = repoRoot
    onlyIf {
        val jniLibs = layout.projectDirectory.dir("src/main/jniLibs")
        requiredProotLibs.any { name ->
            val so = jniLibs.file(name).asFile
            !so.isFile || so.length() == 0L
        }
    }
}

tasks.whenTaskAdded {
    if (name == "preBuild") {
        dependsOn("fetchProot")
    }
}
tasks.findByName("preBuild")?.dependsOn("fetchProot")

tasks.register("validateReleaseDartDefines") {
    doLast {
        val dartDefinesProp = project.findProperty("dart-defines") as? String
        var supabaseUrl = ""
        var supabaseKey = ""

        if (!dartDefinesProp.isNullOrBlank()) {
            val decodedEntries = dartDefinesProp.split(",").mapNotNull { entry ->
                try {
                    String(Base64.getDecoder().decode(entry.trim()), Charsets.UTF_8)
                } catch (e: Exception) {
                    null
                }
            }
            for (entry in decodedEntries) {
                val parts = entry.split("=", limit = 2)
                if (parts.size == 2) {
                    val k = parts[0].trim()
                    val v = parts[1].trim()
                    if (k == "SUPABASE_URL") supabaseUrl = v
                    if (k == "SUPABASE_PUBLISHABLE_KEY" || k == "SUPABASE_ANON_KEY") {
                        if (supabaseKey.isBlank() || k == "SUPABASE_PUBLISHABLE_KEY") {
                            supabaseKey = v
                        }
                    }
                }
            }
        }

        if (supabaseUrl.isBlank() || supabaseKey.isBlank()) {
            throw GradleException(
                """
                |========================================================================
                | RELEASE BUILD FAILED: Missing Required Supabase Configuration!
                |
                | Release builds MUST be provided with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY
                | (or SUPABASE_ANON_KEY).
                |
                | Current status:
                |   SUPABASE_URL = ${if (supabaseUrl.isBlank()) "<MISSING>" else supabaseUrl}
                |   SUPABASE_KEY = ${if (supabaseKey.isBlank()) "<MISSING>" else "<CONFIGURED>"}
                |
                | How to fix:
                |   1. Build with the config file:
                |      flutter build apk --release --dart-define-from-file=config/buildx.public.json
                |   2. Or use the official build script:
                |      ./tool/build_android.ps1  (Windows)
                |      ./tool/build_android.sh   (Linux / macOS)
                |========================================================================
                """.trimMargin()
            )
        }
    }
}

android.applicationVariants.all {
    if (buildType.name == "release") {
        preBuildProvider.configure {
            dependsOn("validateReleaseDartDefines")
        }
    }
}

dependencies {
    implementation("androidx.browser:browser:1.9.0")
    implementation("org.tukaani:xz:1.10")
    // Required for core library desugaring (used by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
