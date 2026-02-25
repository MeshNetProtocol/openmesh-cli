# P7 Soak

Last updated: 2026-02-25

## Purpose

`Run-P7-Soak.ps1` performs repeated RC readiness checks for a long-running stability window.
Each iteration runs `Run-P7-RC-Ready-Check.ps1` with strict latest gates.

## Script

- `openmesh-win/tests/Run-P7-Soak.ps1`

## Parameters

- `-DurationMinutes <n>`: soak duration (default `1440`, i.e. 24h).
- `-IntervalSeconds <n>`: interval between checks (default `300`).
- `-LatestMaxAgeMinutes <n>`: freshness limit passed to ready-check (default `30`).

## Outputs

- `openmesh-win/tests/reports/p7-soak-<timestamp>.txt`
- `openmesh-win/tests/reports/p7-soak-<timestamp>.json`

## Acceptance

Quick smoke:

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-Soak.ps1 -DurationMinutes 1 -IntervalSeconds 20 -LatestMaxAgeMinutes 30
```

24h run:

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P7-Soak.ps1 -DurationMinutes 1440 -IntervalSeconds 300 -LatestMaxAgeMinutes 30
```
