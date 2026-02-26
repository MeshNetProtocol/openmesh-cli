# Windows Market & Profile Alignment Plan (Aligned with macOS App)

This document outlines the plan to align the Windows application's JSON configuration parsing, storage, and management logic with the macOS application. The goal is to ensure identical behavior in profile installation, configuration patching, and Core startup, thereby resolving connectivity issues (DNS/Routing) caused by incorrect configuration handling.

## 1. Core Concept Alignment (Profile vs. Provider)

| Concept | macOS (`Profile.swift`, `Database.swift`) | Current Windows (`InstalledProviderManager.cs`) | Target Alignment (Windows) |
| :--- | :--- | :--- | :--- |
| **Profile** | A database record with `id` (int64), `name`, `type`, `path` (to config.json), `order`. This is what the UI lists and what the Core runs. | Does not exist explicitly. Windows tracks *Providers* and assumes 1:1 mapping. | **Create `ProfileManager` class**. Store profiles in `profiles.json` (simpler than SQLite for now, matching macOS schema). |
| **Provider** | Metadata from Market. Linked to a Profile via `SharedPreferences`. | The primary entity tracked in `installed_providers.json`. | Keep `InstalledProviderManager` for metadata (package hash, etc.), but link it to a **Profile ID**. |
| **Config Storage** | `.../providers/{providerID}/config.json` | Similar, but path handling is ad-hoc. | **Strictly follow** `.../providers/{providerID}/config.json` structure. |
| **Rule Sets** | `.../providers/{providerID}/rule-set/*.srs` | Downloaded to `rule-set` folder. | Verify path logic matches macOS exactly. |

## 2. Implementation Steps

### Step 1: Implement `ProfileManager` (Data Layer)
*   **Goal**: Create a robust way to store and retrieve "Profiles" that the Core will run.
*   **Action**:
    *   Create `Profile.cs` model: `Id` (long), `Name`, `Type` (Local/Remote), `Path`, `Order`.
    *   Create `ProfileManager.cs`:
        *   `Load()` / `Save()` using `profiles.json`.
        *   `Create(Profile p)`: Auto-increment ID.
        *   `Get(long id)`, `List()`.
        *   `Update(Profile p)`, `Delete(long id)`.

### Step 2: Refactor `ProviderInstallWizard` (Logic Layer)
*   **Goal**: Ensure the installation process creates a *Profile* record, not just a file on disk.
*   **Action**:
    *   Update `ProviderInstallWizardDialog.cs`:
        *   Instead of just calling `_coreClient.InstallProviderAsync`, it should:
            1.  Download & Patch Config (keep existing logic if correct).
            2.  **NEW**: Call `ProfileManager.Create()` to register the new profile.
            3.  **NEW**: Update `InstalledProviderManager` to map `ProfileID <-> ProviderID`.
            4.  **NEW**: Activate the new profile by ID.

### Step 3: Align Config Patching (Critical for DNS/Routing)
*   **Goal**: Ensure `config.json` is patched exactly like macOS to support local paths and rule sets.
*   **Action**:
    *   Review `MarketService.swift` -> `patchConfigRuleSetsToLocalPaths`.
    *   Review `makeBootstrapConfigData`.
    *   **Verify**: Ensure Windows app is correctly replacing remote rule-set paths with absolute local paths (`d:\...\rule-set\tag.srs`) before saving `config.json`.
    *   **Verify**: Ensure `dns` and `route` sections are preserved and not corrupted.

### Step 4: Update Core Startup Logic
*   **Goal**: Ensure the Go Core receives the correct config path.
*   **Action**:
    *   Update `MeshFluxMainForm.cs` -> `StartVpnAsync`.
    *   Instead of `_coreClient.StartVpn(providerId)`, it should use `ProfileManager.Get(selectedProfileId).Path`.
    *   Pass the **absolute path** of the `config.json` to the Go Core.

### Step 5: Verify & Test
*   **Action**:
    1.  **Clean Install**: Delete old `profiles.json` and `installed_providers.json`.
    2.  **Import/Install**: Install a provider (e.g., via Market or Import).
    3.  **Check Files**: Verify `profiles.json` has a record. Verify `config.json` exists and has correct paths.
    4.  **Start VPN**: Click "Start". Verify Core logs show successful load.
    5.  **Test Connectivity**: Access `openmesh-api.ribencong.workers.dev`. If config is correct, DNS/Routing should work.

## 3. Execution Order

1.  **Stop**: I will stop any running processes.
2.  **Code**: I will implement `Profile.cs` and `ProfileManager.cs`.
3.  **Refactor**: I will update `ProviderInstallWizardDialog.cs` and `MeshFluxMainForm.cs`.
4.  **Verify**: I will ask you to test the new flow.

---
**Status**: Ready to start Step 1.
