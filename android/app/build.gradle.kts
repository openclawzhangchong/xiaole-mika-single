plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zcstudy.xiaole"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zcstudy.xiaole"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // record_android 插件要求最低 SDK 版本为 23
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // v4.6.1：**只保留 ARM 架构**。
        // 原因：sherpa_onnx 会为 4 个 ABI（arm64-v8a / armeabi-v7a / x86 / x86_64）各打包一份
        // libonnxruntime.so（体积很大）。x86/x86_64 仅供模拟器使用，打包它们会让
        // CI runner 磁盘耗尽（v4.6.0 构建失败：`No space left on device`，剩 29MB）。
        // 真机只需 ARM：arm64-v8a（主流）+ armeabi-v7a（兼容旧机型）。
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
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

flutter {
    source = "../.."
}
