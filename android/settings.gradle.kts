pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    // 嵌入 Mika(com.wangzan101.mika)所需的插件;版本与宿主 Kotlin 2.1.0 对齐
    id("com.android.library") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.jvm") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0" apply false
    id("com.google.protobuf") version "0.9.5" apply false
}

// Mika 自己的版本目录(嵌入后 Mika 不再是根工程,libs.* 访问器改用 mikaLibs.*)
versionCatalogs {
    create("mikaLibs") {
        from(files("../mika/gradle/libs.versions.toml"))
    }
}

include(":app")

// Mika 源码以本地目录方式并入(CI 把 Mika 仓库检出到 <repo>/mika)
include(":mika-core")
project(":mika-core").projectDir = file("../mika/core")
include(":mika-app")
project(":mika-app").projectDir = file("../mika/app")
