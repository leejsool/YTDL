import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명 정보는 저장소 밖(C:\myapp\key)에 둔다. 환경변수 YTDL_KEYSTORE_PROPS 로 다른 경로를 줄 수 있다.
// 파일이 없으면(다른 PC 등) 디버그 키로 서명되어 빌드는 되지만 배포용은 아니다.
val keystorePropsFile = File(System.getenv("YTDL_KEYSTORE_PROPS") ?: "C:/myapp/key/keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}
// storeFile 은 properties 파일과 같은 폴더에서 파일 이름만으로 찾는다.
val releaseKeystore = keystoreProps.getProperty("storeFile")
    ?.let { File(keystorePropsFile.parentFile, File(it).name) }
    ?.takeIf { it.exists() }

android {
    namespace = "com.ytdl.ytdl"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ytdl.ytdl"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // MediaStore 로 권한 없이 Music/Movies 에 저장하려고 Android 10(API 29) 이상으로 제한.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // youtubedl-android 가 python/ffmpeg 를 네이티브 라이브러리 폴더에서 실행하므로 필수.
            useLegacyPackaging = true
            // 32비트 x86 에뮬레이터는 지원하지 않음(APK 용량 절약).
            excludes += listOf("lib/x86/**")
        }
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    // yt-dlp + python + ffmpeg 를 앱에 내장해 주는 라이브러리
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
}
