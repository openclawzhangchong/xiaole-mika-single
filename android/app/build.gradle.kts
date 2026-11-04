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
        // v6.8.2：**必须开启 core library desugaring**。
        // 原因：flutter_local_notifications 的 AAR 元数据显式要求它，
        // 否则 CI 在 `:app:checkReleaseAarMetadata` 直接失败：
        //   "Dependency ':flutter_local_notifications' requires core library desugaring to be enabled for :app"
        // （v6.8.1 就是因此构建失败、没产出 APK。）
        isCoreLibraryDesugaringEnabled = true
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

    signingConfigs {
        // 稳定签名（非 debug）：keystore 随仓库提交，保证每次构建证书指纹一致、可覆盖安装。
        // 密码走环境变量，默认值与 workflow env 保持一致（公开仓库，不追求保密）。
        create("release") {
            storeFile = file("xiaole-release.p12")
            storePassword = System.getenv("XIAOLE_KEYSTORE_PASSWORD") ?: "REDACTED-KEYSTORE-PASSWORD"
            keyAlias = "xiaole"
            keyPassword = System.getenv("XIAOLE_KEY_PASSWORD") ?: "REDACTED-KEYSTORE-PASSWORD"
            storeType = "pkcs12"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // v6.8.2：配合上面的 isCoreLibraryDesugaringEnabled —— 提供 Java 8+ API 的脱糖实现。
    // AGP 8.9.1 支持 desugar_jdk_libs 2.1.x。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
