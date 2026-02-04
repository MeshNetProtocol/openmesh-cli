# 钱包 API 确认：Go 库与 iOS 调用情况

## 1. Go 库中的钱包 API（已确认存在）

**代码位置：** `go-cli-lib/interface/wallet.go`  
**入口：** `AppLib` 通过 gomobile 导出为 `OMOpenmeshAppLib`，工厂函数 `OMOpenmeshNewLib()`。

| API | Go 方法签名 | xcframework 导出（OMOpenmesh.objc.h） |
|-----|-------------|--------------------------------------|
| 生成助记词 | `GenerateMnemonic12() (string, error)` | `generateMnemonic12:` |
| 创建钱包 | `CreateEvmWallet(mnemonic, password) (string, error)` | `createEvmWallet:password:` |
| 解密钱包 | `DecryptEvmWallet(keystoreJSON, password) (*WalletSecretsV1, error)` | `decryptEvmWallet:password:` |
| 代币余额 | `GetTokenBalance(address, tokenName, networkName) (string, error)` | `getTokenBalance:tokenName:networkName:` |
| 支持网络列表 | `GetSupportedNetworks() (string, error)` 返回 JSON 数组 | `getSupportedNetworks` |
| x402 支付 | `MakeX402Payment(url, privateKeyHex) (string, error)` | `makeX402Payment:privateKeyHex:` |

**xcframework 路径：** `openmesh-apple/lib/OpenMeshGo.xcframework`  
已检查 `ios-arm64/.../Headers/OMOpenmesh.objc.h`，上述方法及 `OMOpenmeshNewLib()`、`OMOpenmeshWalletSecretsV1` 均存在。

---

## 2. iOS 侧调用情况：当前全部为桩

**GoEngine**（`MeshFluxIos/core/GoEngine.swift`）中：

- `lib` 类型为 `(any OpenmeshAppLibProtocol)?`
- 在 **initLocked(config:)** 里仅执行：`self.lib = StubAppLib()`  
- **从未调用** `OMOpenmeshNewLib()`，因此从未使用 OpenMeshGo 中的真实实现。

**StubAppLib**（`MeshFluxIos/core/OpenmeshAppLibStub.swift`）：

- 实现 `OpenmeshAppLibProtocol`
- `generateMnemonic12`、`createEvmWallet`、`decryptEvmWallet`、`getTokenBalance`、`getSupportedNetworks` 均 **throw GoEngineError.notReadyYet**（或等价占位行为）
- `initApp` 为 no-op；`getVpnStatus` 返回固定占位值

因此：

- **生成助记词、创建/解密钱包、查余额、支持网络、x402 支付** 在 iOS 上目前都是 **桩函数**，没有走到 Go 的真实实现。

---

## 3. 小结

| 项目 | 结论 |
|------|------|
| Go 库是否包含钱包 API | ✅ 是，`go-cli-lib/interface/wallet.go` 且已通过 gomobile 导出 |
| 当前 xcframework 是否包含上述 API | ✅ 是，`OpenMeshGo.xcframework` 的 `OMOpenmesh.objc.h` 中均有 |
| iOS 是否已真实调用 Go | ❌ 否，GoEngine 固定使用 `StubAppLib()`，未使用 `OMOpenmeshNewLib()` |

若要在 iOS 上真实调用钱包能力，需要修改 `GoEngine.initLocked`：优先调用 `OMOpenmeshNewLib()`，若返回非 nil 则使用该实例作为 `lib`，仅在返回 nil 时回退到 `StubAppLib()`；同时需处理 `OMOpenmeshWalletSecretsV1` 与现有 `WalletSecretsV1` 类型在协议中的适配。
