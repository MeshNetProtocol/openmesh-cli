# P6 WiX MSI Wintun Guard

Last updated: 2026-02-24

## Scope in this iteration

- Extended MSI build script:
  - `openmesh-win/installer/Build-P6-Wix-Msi.ps1`
  - forwarded args to `Build-Package.ps1`:
    - `-RequireWintun`
    - `-AutoCopyWintun`
    - `-WintunSourcePath`
- Added acceptance script:
  - `openmesh-win/tests/Run-P6-Wix-Msi-Wintun-Guard.ps1`

## Behavior

- MSI pipeline now honors wintun gate options during package build.
- Main smoke/validate scripts also support these wintun gate options.
- Acceptance script validates:
  - missing explicit wintun path is rejected
  - explicit wintun path allows MSI build
  - resulting package zip contains:
    - `core\wintun.dll`
    - `service\wintun.dll`

## Acceptance

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P6-Wix-Msi-Wintun-Guard.ps1
```

Expected signal:

- `P6 wix msi wintun guard checks passed.`
