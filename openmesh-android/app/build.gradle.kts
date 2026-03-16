plugins {
    id("com.android.application") version "9.1.0"
}

android {
    namespace = "com.meshnetprotocol.android"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.meshnetprotocol.android"
        minSdk = 24
        targetSdk = 34
        versionCode = 2
        versionName = "1.0.2"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    
    // 添加加密存储依赖（用于 WalletStore 和 PINStore）
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    
    // 添加协程支持
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    
    // JSON 解析（用于解析 Go 返回的网络列表等）
    implementation("org.json:json:20230227")
    
    // OpenMesh Go library (AAR) - 从 app/libs 引用
    implementation(files("libs/OpenMeshGo.aar"))
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
}
