# P7 Go Core Provider Smoke

## 目标

用命名管道直接验证 Go Core 的 provider 基础动作闭环：

- `provider_market_list`
- `provider_install`
- `provider_uninstall`

## 脚本

`openmesh-win/tests/Run-P7-GoCore-Provider-Smoke.ps1`

## 执行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-GoCore-Provider-Smoke.ps1
```

可选参数：

- `-GoCoreExePath <path>`
- `-SkipStopConflictingProcesses`

## 验证点

1. `provider_market_list` 返回至少一个 provider。
2. 对未知 provider 执行 `provider_install` 必须失败。
3. 对真实 provider 执行 `provider_install` 后，`installedProviderIds` 包含该 provider。
4. 再次 `provider_market_list`，已安装状态可见。
5. 执行 `provider_uninstall` 后，`installedProviderIds` 不再包含该 provider。
6. 再次 `provider_market_list`，卸载状态可见。
