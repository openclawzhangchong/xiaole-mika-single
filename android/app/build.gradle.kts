plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zcstudy.xiaole"
    // Mika 的 library 用 compileSdk 36,宿主必须 >= 它
    compileSdk = 36
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
        // 嵌入 Mika 后清单合并要求宿主 minSdk >= library 的 minSdk(30)。
        // 真机是 Android 12(API 31),Android 11 以下不再支持。
        minSdk = 30
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
        // 稳定签名（非 debug）：keystore 不入库，构建时由 CI 从 secret 解码到本路径，用完即删。
        // 铁律「同包名必须同签名」：证书 SHA-256 必须与发布基线一致，见 docs/embed-mika.md。
        create("release") {
            storeFile = file("xiaole-release.p12")
            storePassword = System.getenv("XIAOLE_KEYSTORE_PASSWORD")
                ?: error("XIAOLE_KEYSTORE_PASSWORD 未设置（本地构建请自行导出 secret 到环境变量）")
            keyAlias = "xiaole"
            keyPassword = System.getenv("XIAOLE_KEY_PASSWORD")
                ?: error("XIAOLE_KEY_PASSWORD 未设置（本地构建请自行导出 secret 到环境变量）")
            storeType = "pkcs12"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            // 嵌入 Mika:保留运行时动态加载的类(内置助手 HelperMain 等),
            // R8 看不到静态引用会把它们剥掉,导致手机操作的 shell 连接起不来。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // 从 Mika 的 application 模块搬过来:沙箱程序要从 nativeLibraryDir 直接执行,安装时必须解到磁盘;
    // rootfs.tar.xz 已是 xz,不再压一遍。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    androidResources {
        noCompress += "xz"
    }
}

flutter {
    source = "../.."
}

dependencies {
    // v6.8.2：配合上面的 isCoreLibraryDesugaringEnabled —— 提供 Java 8+ API 的脱糖实现。
    // AGP 8.9.1 支持 desugar_jdk_libs 2.1.x。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // 同一个 APK 里的 Mika 引擎(任务执行、手机能力、内置模型调用),不再走 adb forward / PC 网关。
    // mika-core 也要显式依赖:它对 mika-app 是 implementation,不会传递到本模块的编译类路径,
    // 而 MikaBridge 直接用到 RemoteTaskHub/RemoteStatus 这些 core 类型。
    implementation(project(":mika-app"))
    implementation(project(":mika-core"))
    // RemoteStatus.describe() 的返回类型是 kotlinx.serialization 的 JsonObject;
    // mika-core 用 implementation 引它,不传递,这里补上编译类路径(版本取 Mika 的目录)。
    implementation(mikaLibs.kotlinx.serialization.json)
}
