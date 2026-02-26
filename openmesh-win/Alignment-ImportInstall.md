# Import & Install Alignment Plan (Windows vs macOS)

This document outlines the gap analysis and alignment plan for the "Import & Install" feature between the Windows and macOS applications.

## 1. Gap Analysis

| Feature | macOS (`OfflineImportViewIOS.swift`, `MarketService.swift`) | Windows (`OfflineImportInstallDialog.cs`, `ProviderInstallWizardDialog.cs`) | Gap / Action Required |
| :--- | :--- | :--- | :--- |
| **Input Methods** | Supports Text Paste, File Picker, URL Fetch. | Supports Text Paste, File Picker, URL Fetch. | **Aligned**. |
| **URL Fetch Logic** | 3 Retries, Timeout (20s), SSL Error Diagnostics, WebView Fallback. | Basic `HttpClient` fetch, no retries, no WebView fallback. | **Critical Gap**: Add retry logic, better timeout handling, and SSL diagnostics. (WebView fallback is complex on WinForms, maybe skip for now). |
| **Loading State** | Full-screen overlay with "Fetching..." text. Disables interactions. | Basic button disable state. | **Gap**: Implement a proper overlay or modal loading state in `OfflineImportInstallDialog`. |
| **Install Wizard** | Step-based UI (`ImportedInstallWizardView`). Shows specific steps: Validate, Download Rules, Write Config, etc. | `ProviderInstallWizardDialog` has steps but logic is opaque (hidden in `_installAction`). | **Critical Gap**: Refactor `ProviderInstallWizardDialog` to accept an `ImportInstallContext` and execute specific steps visibly, matching macOS `MarketService.installProviderFromImportedConfig`. |
| **Rule-Set Download** | Concurrent (Max 2), Timeout (20s/file), Progress reporting per file. | Sequential or handled opaquely by Core. | **Gap**: Implement concurrent download logic in C# if not using Core's internal logic. (Core might handle this, need to verify). **Decision**: Implement in C# to match macOS control/feedback. |
| **Profile Registration** | Explicitly creates `Profile` in DB, links to `ProviderID` in `SharedPreferences`. | Recently added `ProfileManager`, but `ProviderInstallWizard` logic is incomplete/hacky. | **Gap**: Solidify `ProfileManager` usage. Ensure `ProviderID` is generated/resolved correctly (e.g. `imported-uuid`) and linked. |
| **Post-Install** | Updates `InstalledProviderManager`, sends notifications, optionally switches profile. | Basic update. | **Gap**: Ensure `InstalledProviderManager` is updated correctly with hash/pending rules. |

## 2. Alignment Plan

### Phase 1: Enhance Input Dialog (`OfflineImportInstallDialog.cs`)
*   **Objective**: Match macOS UX for fetching content.
*   **Tasks**:
    1.  Add `IsFetching` state with visual feedback (overlay or progress bar).
    2.  Implement `FetchFromUrlAsync` with:
        *   3 Retries.
        *   Timeout (10s -> 20s).
        *   Detailed error reporting (SSL, DNS).
    3.  Validate content (basic JSON check) before allowing "Install".

### Phase 2: Implement `ImportInstallWizard` Logic
*   **Objective**: Replicate `MarketService.installProviderFromImportedConfig` logic in C#.
*   **Tasks**:
    1.  Create `ImportInstallContext` class (Config Data, Provider Name, ID, etc.).
    2.  Refactor `ProviderInstallWizardDialog` (or create new `ImportInstallWizardDialog`) to:
        *   **Step 1: Validate Config**: Parse JSON, check structure.
        *   **Step 2: Download Routing Rules**: If `routing_rules.json` URL exists.
        *   **Step 3: Download Rule-Sets**:
            *   Extract `rule-set` URLs from config.
            *   Download concurrently (SemaphoreSlim).
            *   Update UI with specific file progress.
        *   **Step 4: Patch Config**:
            *   Replace remote `rule-set` paths with local absolute paths.
            *   Generate `config_full.json` and `config.json` (Bootstrap).
        *   **Step 5: Write Files**:
            *   Create directory structure: `providers/{id}/`.
            *   Write `config.json`.
        *   **Step 6: Register Profile**:
            *   Call `ProfileManager.Create`.
            *   Update `InstalledProviderManager`.

### Phase 3: Post-Install Actions
*   **Objective**: Ensure app state is consistent.
*   **Tasks**:
    1.  Refresh Dashboard/Market UI.
    2.  (Optional) Auto-select new profile.

## 3. Implementation Details (C#)

```csharp
// Example Context
public class ImportInstallContext
{
    public string ProviderId { get; set; }
    public string ProviderName { get; set; }
    public string ConfigContent { get; set; }
    // ...
}
```

## 4. Execution Strategy
I will start by refactoring the `OfflineImportInstallDialog` to handle the fetch logic robustly. Then I will implement the specific installation logic in a new `ImportInstaller` service (or within the Wizard) to match the macOS `MarketService` exact flow.
