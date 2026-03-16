# OpenMesh Android 发布指南 (Google Play)

本指南介绍如何从零开始为 OpenMesh Android 项目生成签名的发布文件（AAB 和 APK）。

---

## 1. 环境准备 (Prerequisites)

在开始之前，请确保你的开发环境已安装：
*   **JDK 17**: 用于运行 Gradle 构建。
*   **Android SDK**: 确保安装了对应版本的平台工具（Platform-API 34）。
*   **Go**: 如果需要更新核心库，需安装 Go 环境。
*   **PowerShell**: 用于运行打包脚本。

---

## 2. 生成签名密钥 (Key Generation)

如果你还没有发布密钥，可以使用以下命令生成一个新的密钥库（Keystore）文件。

1.  打开命令行（Terminal/PowerShell）。
2.  运行以下命令：
    ```bash
    keytool -genkey -v -keystore my-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias my-key-alias
    ```
3.  按照提示设置密码并填写证书信息。
4.  **重要**: 请妥善保存生成的 `my-release-key.jks` 文件及其密码，丢失将无法更新 Google Play 上的应用。

---

## 3. 配置项目签名 (Configuring Signing)

项目已经配置为从 `signing.properties` 文件中读取签名信息。

1.  在项目根目录（`openmesh-android/`）创建文件 `signing.properties`。
2.  填入以下内容（替换为你自己的路径和密码）：
    ```properties
    RELEASE_STORE_FILE=my-release-key.jks
    RELEASE_STORE_PASSWORD=你的密钥库密码
    RELEASE_KEY_ALIAS=你的别名
    RELEASE_KEY_PASSWORD=你的别名密码
    ```
    *注：`RELEASE_STORE_FILE` 建议使用相对项目根目录的路径。*

---

## 4. 执行编译发布 (Building)

为了简化操作，我们在 `install` 目录下提供了一键脚本：

### 方法 A: 使用 Batch 文件 (推荐)
直接双击运行：
`install\release-google-play.bat`

### 方法 B: 使用 PowerShell 脚本
在命令行中运行：
```powershell
.\install\release-google-play.ps1
```

**脚本功能：**
1.  **可选构建 Go 库**: 脚本会询问是否需要重新编译加密核心库（Go 模块）。
2.  **生成 AAB**: 用于上传到 Google Play 管理中心。
3.  **生成 APK**: 用于本地手动安装测试。

---

## 5. 输出文件存放位置 (Outputs)

所有的构建产物都存放在 `app/build/outputs/` 目录下。

*   **Google Play 发布包 (AAB)**:
    `app\build\outputs\bundle\release\app-release.aab`
*   **安装包 (APK)**:
    `app\build\outputs\apk\release\app-release.apk`

---

## 6. 注意事项 (Notes)

*   **Google Play 需要 AAB**: 从 2021 年起，Google Play 强制要求新应用使用 `.aab` 格式提交。
*   **安全**: `signing.properties` 和 `.jks` 文件已被加入 `.gitignore`，请勿将其提交到公共代码仓库。
*   **版本管理**: 发布新版本前，请在 `app/build.gradle.kts` 中手动增加 `versionCode`。
