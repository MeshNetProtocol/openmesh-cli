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
- `-LatestIgnoreWarnChecks <check1,check2,...>`: ignore selected WARN checks before applying `-LatestFailOnWarn`.
- `-LatestAllowedWarnChecks <check1,check2,...>`: require WARN checks to stay inside allowlist.
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

Strict WARN gate (with controlled ignores):

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-RC-Quick-Gate.ps1 -SkipBuild -SkipGoCoreBuild -LatestFailOnWarn -LatestIgnoreWarnChecks build_winforms,build_go_core,admin_privilege
```

## Next (Admin/UAC Required)

After quick gate passes, run full release gate in a normal shell (will trigger UAC):

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P6-Release-Preflight.ps1 -ReleaseGateExtended -AutoElevate -ScmStrictConfiguration Release -ScmStrictServiceName OpenMeshWinServiceP6 -WintunPath .\openmesh-win\deps\wintun.dll
```

After ReleaseGateExtended passes, run strict latest readiness gate:

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-RC-Ready-Check.ps1 -LatestMaxAgeMinutes 30 -ShowLatestSummaryOnly
```
