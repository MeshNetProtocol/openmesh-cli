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
        versionCode = 3
        versionName = "1.0.3"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            storeFile = project.findProperty("RELEASE_STORE_FILE")?.let { rootProject.file(it) }
            storePassword = project.findProperty("RELEASE_STORE_PASSWORD") as String?
            keyAlias = project.findProperty("RELEASE_KEY_ALIAS") as String?
            keyPassword = project.findProperty("RELEASE_KEY_PASSWORD") as String?
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
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
    
    // 娣诲姞鍔犲瘑瀛樺偍渚濊禆锛堢敤浜?WalletStore 鍜?PINStore锛?
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    
    // 娣诲姞鍗忕▼鏀寔
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    
    // JSON 瑙ｆ瀽锛堢敤浜庤В鏋?Go 杩斿洖鐨勭綉缁滃垪琛ㄧ瓑锛?
    implementation("org.json:json:20230227")
    
    // OpenMesh Go library (AAR) - 浠?app/libs 寮曠敤
    implementation(files("libs/OpenMeshGo.aar"))
    implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")
}

