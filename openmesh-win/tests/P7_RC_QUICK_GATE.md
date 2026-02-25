# P7 RC Quick Gate

Last updated: 2026-02-25

## Purpose

`Run-P7-RC-Quick-Gate.ps1` is a command-only RC quick gate for P7.
It chains three checks:

1. Refresh latest P6 preflight text/json report.
2. Run latest-gates-smoke regression.
3. Gate latest summary with strict consistency/freshness requirements and emit latest-gate snapshot JSON.

## Script

- `openmesh-win/tests/Run-P7-RC-Quick-Gate.ps1`

## Parameters

- `-SkipBuild`: pass-through to preflight refresh step.
- `-SkipGoCoreBuild`: pass-through to preflight refresh step.
- `-SkipStopConflictingProcesses`: pass-through to preflight refresh step.
- `-LatestMaxAgeMinutes <n>`: freshness gate in latest check step (default `30`).
- `-LatestFailOnWarn`: enable WARN gate in latest check step.
- `-LatestGatesSmokeShowDetails`: show detailed case logs from latest-gates-smoke step.

## Outputs

- text report:
  - `openmesh-win/tests/reports/p7-rc-quick-gate-<timestamp>.txt`
- json report:
  - `openmesh-win/tests/reports/p7-rc-quick-gate-<timestamp>.json`
- latest gate snapshot:
  - `openmesh-win/tests/reports/p7-rc-quick-gate-latest-gate-snapshot.json`

## Acceptance

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-RC-Quick-Gate.ps1 -SkipBuild -SkipGoCoreBuild
```

Expected signal:

- `P7 RC quick gate passed.`
