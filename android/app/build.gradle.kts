import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

buildscript {
    if (file("agconnect-services.json").isFile) {
        repositories {
            google()
            mavenCentral()
            maven("https://developer.huawei.com/repo/") {
                content { includeGroupByRegex("com[.]huawei[.].*") }
            }
        }
        dependencies {
            classpath("com.huawei.agconnect:agcp:1.9.6.301") {
                // Use the Gradle and Android APIs supplied by this Flutter project.
                exclude(group = "org.gradle", module = "gradle-plugin")
                exclude(group = "com.android.tools.build", module = "gradle")
            }
        }
    }
}

val huaweiPush = file("agconnect-services.json").isFile
if (huaweiPush) apply(plugin = "com.huawei.agconnect")

val vendorProperties = Properties()
val vendorFile = rootProject.file("vendor-push.properties")
if (vendorFile.isFile) vendorFile.reader(Charsets.UTF_8).use { vendorProperties.load(it) }
val vendorFields = mapOf(
    "xiaomi" to listOf("XIAOMI_APPID", "XIAOMI_APPKEY"),
    "honor" to listOf("HONOR_APPID"),
    "oppo" to listOf("OPPO_APPID", "OPPO_APPKEY", "OPPO_APPSECRET"),
    "vivo" to listOf("VIVO_APPID", "VIVO_APPKEY"),
)
require(vendorProperties.stringPropertyNames().all { it in vendorFields.values.flatten() }) {
    "Unexpected field in vendor-push.properties"
}
val enabledVendors = vendorFields.filterValues { fields ->
    val configured = fields.any { vendorProperties.containsKey(it) }
    require(!configured || fields.all { !vendorProperties.getProperty(it).isNullOrBlank() }) {
        "Incomplete push configuration. Required fields: ${fields.joinToString()}"
    }
    configured
}

val releaseProperties = Properties()
val releaseFile = rootProject.file("key.properties")
if (releaseFile.exists()) releaseFile.inputStream().use { releaseProperties.load(it) }

android {
    namespace = "space.su7.xiabanwang"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "space.su7.xiabanwang"
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
        val dartDefines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(",").filter { it.isNotEmpty() }.associate {
                val decoded = String(Base64.getDecoder().decode(it))
                decoded.substringBefore("=") to decoded.substringAfter("=")
            }
        manifestPlaceholders["JPUSH_PKGNAME"] = applicationId!!
        manifestPlaceholders["JPUSH_APPKEY"] = dartDefines["JPUSH_APP_KEY"] ?: ""
        manifestPlaceholders["JPUSH_CHANNEL"] = "default"
        for ((vendor, fields) in enabledVendors) {
            for (field in fields) {
                val value = vendorProperties.getProperty(field).trim()
                manifestPlaceholders[field] = if (vendor == "oppo") "OP-$value" else value
            }
        }
    }

    signingConfigs {
        create("release") {
            if (releaseFile.exists()) {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

// Match the native JPush version bundled by jpush_flutter 3.6.0.
dependencies {
    val jpushVersion = "6.3.0"
    for (vendor in enabledVendors.keys) {
        implementation("cn.jiguang.sdk.plugin:$vendor:$jpushVersion")
    }
    if (huaweiPush) implementation("cn.jiguang.sdk.plugin:huawei:$jpushVersion")
    if ("oppo" in enabledVendors) implementation("com.google.code.gson:gson:2.10.1")
}
