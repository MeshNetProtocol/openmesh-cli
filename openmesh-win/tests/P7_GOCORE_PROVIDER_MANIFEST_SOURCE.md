# P7 Go Core Provider Manifest Source

## 目标

验证 Go Core provider 市场可从外部清单加载，而不是仅依赖内置默认列表。

## 支持的数据源优先级

1. `OPENMESH_WIN_PROVIDER_MARKET_FILE`
2. `runtime/provider_market.json`（`openmesh-win-core.exe` 同目录下的 `runtime`）
3. `OPENMESH_WIN_PROVIDER_MARKET_URL`
4. 内置默认 providers（兜底）

## 脚本

`openmesh-win/tests/Run-P7-GoCore-Provider-Manifest-Source.ps1`

## 执行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-GoCore-Provider-Manifest-Source.ps1
```

## 验证点

1. 启动前写入 `runtime/provider_market.json` 自定义清单。
2. `provider_market_list` 返回自定义清单中的 provider。
3. 非法 provider 条目（如空 `id`）会被过滤。
4. 测试结束后自动清理临时清单文件。
