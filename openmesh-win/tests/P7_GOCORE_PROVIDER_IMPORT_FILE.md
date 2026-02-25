# P7 Go Core Provider Import File

## 目标

验证 Go Core 的本地离线导入能力：

- 动作：`provider_import_file`
- 数据源：本地 JSON 文件（单条或 `providers` 列表）
- 行为：导入后进入当前市场列表，并可通过 `provider_market_list` 读取到

## 脚本

`openmesh-win/tests/Run-P7-GoCore-Provider-Import-File.ps1`

## 执行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-GoCore-Provider-Import-File.ps1
```

可选参数：

- `-GoCoreExePath <path>`
- `-SkipStopConflictingProcesses`

## 验证点

1. 生成临时 provider 导入 JSON。
2. 调用 `provider_import_file` 成功。
3. 返回中的 `providers` 包含导入 provider。
4. 再调用 `provider_market_list`，仍可查询到导入 provider。
