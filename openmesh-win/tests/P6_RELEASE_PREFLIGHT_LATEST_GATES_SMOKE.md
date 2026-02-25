# P6 Release Preflight Latest Gates Smoke

Last updated: 2026-02-24

## Purpose

Validate `Run-P6-Release-Preflight.ps1 -ShowLatest` gate matrix in one shot.

## Script

- `openmesh-win/tests/Run-P6-Release-Preflight-Latest-Gates-Smoke.ps1`

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P6-Release-Preflight-Latest-Gates-Smoke.ps1
```

Optional detailed logs:

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P6-Release-Preflight-Latest-Gates-Smoke.ps1 -ShowDetails
```

## Expected

- Output contains: `P6 latest gates smoke passed.`
- Report files generated:
  - `openmesh-win/tests/reports/p6-release-preflight-latest-gates-smoke-<timestamp>.txt`
  - `openmesh-win/tests/reports/p6-release-preflight-latest-gates-smoke-<timestamp>.json`
