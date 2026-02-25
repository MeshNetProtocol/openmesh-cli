# P7 RC Ready Check

Last updated: 2026-02-25

## Purpose

`Run-P7-RC-Ready-Check.ps1` validates RC readiness from the latest preflight artifacts only.
It applies strict latest gates:

- `LatestRequireNoFail`
- `LatestFailOnWarn`
- `LatestRequireTextJsonConsistent`
- `LatestRequireSameGeneratedAtUtc`
- `LatestMaxAgeMinutes`

## Script

- `openmesh-win/tests/Run-P7-RC-Ready-Check.ps1`

## Parameters

- `-LatestMaxAgeMinutes <n>`: max accepted age for latest report (default `15`).
- `-ShowLatestSummaryOnly`: pass through to latest check output mode.

## Outputs

- `openmesh-win/tests/reports/p7-rc-ready-check-<timestamp>.txt`
- `openmesh-win/tests/reports/p7-rc-ready-check-latest-gate-snapshot.json`

## Acceptance

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-RC-Ready-Check.ps1 -LatestMaxAgeMinutes 30 -ShowLatestSummaryOnly
```

Expected signal:

- `P7 RC ready check passed.`
