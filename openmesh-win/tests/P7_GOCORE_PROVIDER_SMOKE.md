# P7 Go Core Provider Smoke

## 目标

通过命名管道直接验证 Go Core 的 provider 基础动作闭环：

- `provider_market_list`
- `provider_install`
- `provider_activate`
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
4. `provider_install` 后 `profilePath` 自动切到 provider profile。
5. 执行 `provider_activate` 可重复激活已安装 provider。
6. 再次 `provider_market_list`，已安装状态可见。
7. 执行 `provider_uninstall` 后，`installedProviderIds` 不再包含该 provider。
8. 若卸载的是当前激活 provider，`profilePath` 自动回退到 default profile。
9. 再次 `provider_market_list`，卸载状态可见。
