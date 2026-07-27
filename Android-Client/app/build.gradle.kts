import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun configValue(name: String, default: String = ""): String =
    providers.gradleProperty(name).orNull
        ?: System.getenv(name)
        ?: localProperties.getProperty(name)
        ?: default

fun String.asBuildConfigString(): String =
    "\"${replace("\\", "\\\\").replace("\"", "\\\"")}\""

fun requiredConfigValue(name: String): String =
    configValue(name).takeIf { it.isNotBlank() }
        ?: error("Missing required release configuration: $name")

val configuredVersionCode = configValue("GGESIM_VERSION_CODE", "11")
    .toIntOrNull()
    ?.takeIf { it in 1..2_100_000_000 }
    ?: error("GGESIM_VERSION_CODE must be an integer between 1 and 2100000000")
val configuredVersionName = configValue("GGESIM_VERSION_NAME", "0.7.0").ifBlank { "0.7.0" }
val releaseKeystorePath = configValue("ANDROID_KEYSTORE_PATH")

android {
    namespace = "com.tuluobo.ggesim"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.tuluobo.ggesim"
        minSdk = 28
        targetSdk = 36
        versionCode = configuredVersionCode
        versionName = configuredVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "GGESIM_CLIENT_ID", configValue("GGESIM_CLIENT_ID").asBuildConfigString())
        buildConfigField("String", "GGESIM_CLIENT_SECRET", configValue("GGESIM_CLIENT_SECRET").asBuildConfigString())
        buildConfigField(
            "String",
            "GGESIM_GUIDE_URL",
            configValue("GGESIM_GUIDE_URL", "https://shuzimumin.com/t/topic/102").asBuildConfigString()
        )
    }

    signingConfigs {
        if (releaseKeystorePath.isNotBlank()) {
            create("release") {
                storeFile = file(releaseKeystorePath)
                storePassword = requiredConfigValue("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = requiredConfigValue("ANDROID_KEY_ALIAS")
                keyPassword = requiredConfigValue("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.browser)
    implementation(libs.okhttp)
    implementation(libs.okhttp.urlconnection)
    implementation(libs.zxing.core)
    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.json)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
