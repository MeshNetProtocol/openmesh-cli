# P6 Service SCM Integration

Last updated: 2026-02-24

## Scope in this iteration

- Added Windows service register/unregister scripts:
  - `openmesh-win/installer/Register-OpenMeshWin-Service.ps1`
  - `openmesh-win/installer/Unregister-OpenMeshWin-Service.ps1`
- Integrated service registration into install/uninstall pipeline:
  - `openmesh-win/installer/Install-OpenMeshWin.ps1`
  - `openmesh-win/installer/Uninstall-OpenMeshWin.ps1`
- Included service scripts in package output:
  - `openmesh-win/installer/Build-Package.ps1`
- Extended preflight checks for SCM artifacts:
  - `openmesh-win/tests/Run-P6-Release-Preflight.ps1`
- Added SCM acceptance script:
  - `openmesh-win/tests/Run-P6-Service-SCM.ps1`
  - `openmesh-win/tests/Run-P6-Service-SCM-Strict.ps1`
  - `openmesh-win/tests/Run-P6-Admin-Validation.ps1`

## Behavior

- Install script supports optional service registration:
  - `-EnableService`
  - `-StartService`
  - `-ServiceStartupType Automatic|Manual|Disabled`
  - `-ServiceName <name>`
- Uninstall script removes service by default (unless `-SkipService`).
- Service registration scripts require administrator privileges.
- SCM acceptance script:
  - always validates script artifacts
  - runs full install/register/start/uninstall/remove lifecycle when elevated
  - supports strict admin gate (`-RequireAdmin`)
  - supports auto-elevation relaunch (`-AutoElevate`)
  - default mode degrades to warning-only when not elevated
- Strict script behavior:
  - tries UAC elevation directly when current shell is not elevated
  - if strict run fails, prints latest `p6-service-scm-*.txt` report automatically
- Admin validation wrapper:
  - runs SCM strict check and release preflight in one command
  - prints latest report paths and keeps console open by default

## Acceptance

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P6-Service-SCM.ps1
```

Expected signal:

- Elevated shell: `P6 service SCM checks passed.`
- Non-elevated shell: `P6 service SCM checks passed with warnings.`

Strict acceptance (recommended):

```powershell
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Run-P6-Service-SCM-Strict.ps1
```

Expected signal:

- `P6 service SCM checks passed.`
