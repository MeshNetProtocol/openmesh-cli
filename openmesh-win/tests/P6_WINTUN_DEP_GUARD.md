# P6 Wintun Dependency Guard

Last updated: 2026-02-24

## Scope in this iteration

- Extended package/install scripts with wintun dependency controls:
  - `openmesh-win/installer/Build-Package.ps1`
  - `openmesh-win/installer/Install-OpenMeshWin.ps1`
  - new args:
    - `-RequireWintun`
    - `-AutoCopyWintun`
    - `-WintunSourcePath <path>`
- Added acceptance script:
  - `openmesh-win/tests/Run-P6-Wintun-Guard.ps1`

## Behavior

- `-RequireWintun`:
  - build/install fails if no `wintun.dll` is available.
- `-WintunSourcePath`:
  - explicit source path override for `wintun.dll`.
  - invalid explicit path fails fast.
- `-AutoCopyWintun`:
  - if wintun source is resolved, copies `wintun.dll` into:
    - package/install `core\wintun.dll`
    - package/install `service\wintun.dll`

## Acceptance

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P6-Wintun-Guard.ps1
```

Expected signal:

- `P6 wintun guard checks passed.`
