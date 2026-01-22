# macOS（Developer ID）离线分发打包

这个目录的脚本用于把 `openmesh-apple` 里的 `OpenMeshMac`（包含 `vpn_extension_macos` Network Extension）打包成用户可安装的分发产物（默认 DMG，可选 PKG），并进行：

- Developer ID 代码签名（Hardened Runtime）
- Apple Notarization（notarytool）+ staple

> 说明：Network Extension 组件本身仍会在安装/首次启用时触发系统权限/配置提示（这是 macOS 的正常行为），但完成签名+公证后，Gatekeeper 不会把它当作“未验证来源”直接拦截。

## 前置条件

- 本机 Keychain 里已安装可用的 `Developer ID Application` 证书（可选：`Developer ID Installer` 用于 PKG）
- 已配置 notarytool keychain profile（示例：`xcrun notarytool store-credentials --keychain-profile notary-profile ...`）
- 如果启用了受限能力（本项目包含 `Network Extension`），需要确保对应 entitlement 已获得 Apple 授权；否则用户机器上可能出现 “can’t be opened / error=162 (Codesigning issue)”。

## 用法

在仓库根目录执行：

```bash
./openmesh-apple/scripts/release_macos_dev_id.sh
```

或处理你已经 build 出来的 `.app`：

```bash
./openmesh-apple/scripts/release_macos_dev_id.sh /path/to/OpenMeshMac.app
```

常用环境变量：

- `DEV_ID_APP`：Developer ID Application 证书名（必填/默认值需要按你的证书调整）
- `NOTARY_PROFILE`：notarytool profile 名
- `OUT_DIR`：输出目录（默认当前目录）
- `MAKE_PKG=1` + `DEV_ID_INSTALLER=...`：额外生成签名 PKG
- `NOTARIZE_DMG`：是否对 DMG 公证+staple（默认 1，推荐保持开启以减少用户侧拦截/提示）
- `PROVISION_PROFILE_APP`：可选：主 App 的 provisioning profile（仅在你确认系统要求时使用）
- `PROVISION_PROFILE_VPN_MAC`：可选：`vpn_extension_macos.appex` 的 provisioning profile

示例（同时产出 PKG）：

```bash
DEV_ID_APP="Developer ID Application: <Your Company>" \
DEV_ID_INSTALLER="Developer ID Installer: <Your Company>" \
NOTARY_PROFILE="notary-profile" \
MAKE_PKG=1 \
OUT_DIR="$(pwd)/dist" \
./openmesh-apple/scripts/release_macos_dev_id.sh
```
