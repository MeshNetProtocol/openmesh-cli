using System.Text;
using System.Text.Json;

namespace OpenMeshWin;

internal sealed class ProviderInstallWizardDialog : Form
{
    private sealed class InstallStep
    {
        public string Title { get; init; } = string.Empty;
        public string Status { get; set; } = "pending";
        public string Message { get; set; } = string.Empty;
    }

    private readonly Func<string, Task<CoreResponse>>? _installAction;
    private readonly string _importContent;
    private readonly bool _isLegacyMode;

    private readonly List<InstallStep> _steps =
    [
        new() { Title = "Initialize install" },
        new() { Title = "Validate config" },
        new() { Title = "Check routing_rules (optional)" },
        new() { Title = "Download rule-sets" },
        new() { Title = "Patch configuration" },
        new() { Title = "Create bootstrap config" },
        new() { Title = "Write config files" },
        new() { Title = "Register profile" },
        new() { Title = "Finalize" },
    ];

    private readonly Dictionary<string, int> _stepMap = new()
    {
        { "init", 0 },
        { "validate", 1 },
        { "write_rules", 2 },
        { "download_ruleset", 3 },
        { "patch_config", 4 },
        { "bootstrap_config", 5 },
        { "write_config", 6 },
        { "register", 7 },
        { "done", 8 }
    };

    private readonly Label _titleLabel = new();
    private readonly Label _providerNameLabel = new();
    private readonly Button _headerCloseButton = new();
    private readonly CheckBox _selectAfterInstallToggle = new();
    private readonly ListView _metaListView = new();
    private readonly ListView _stepsListView = new();
    private readonly Panel _errorPanel = new();
    private readonly Label _errorLabel = new();
    private readonly Button _copyErrorButton = new();
    private readonly Button _cancelButton = new();
    private readonly Button _startButton = new();
    private readonly Button _doneButton = new();
    private readonly Label _runningHintLabel = new();
    private readonly ProgressBar _runningProgressBar = new();

    private bool _isRunning;
    private bool _isFinished;
    private string _errorText = string.Empty;

    public CoreResponse? InstallResponse { get; private set; }

    private readonly string _overrideProviderName;

    public ProviderInstallWizardDialog(string importContent, Func<string, Task<CoreResponse>>? installAction = null, string? providerName = null)
    {
        _importContent = importContent;
        _installAction = installAction;
        _isLegacyMode = installAction != null;
        _overrideProviderName = providerName ?? string.Empty;

        Text = "Provider Install";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimizeBox = true;
        MaximizeBox = true;
        Width = 920;
        Height = 700;
        MinimumSize = new Size(760, 620);
        BackColor = Color.FromArgb(219, 234, 247);

        var rootPanel = new Panel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(14)
        };
        Controls.Add(rootPanel);

        var headerPanel = CreateCardPanel();
        headerPanel.SetBounds(14, 14, ClientSize.Width - 28, 96);
        headerPanel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        rootPanel.Controls.Add(headerPanel);

        _titleLabel.Text = "Install Provider";
        _titleLabel.Font = new Font("Segoe UI Semibold", 22F, FontStyle.Bold);
        _titleLabel.ForeColor = Color.FromArgb(58, 147, 219);
        _titleLabel.SetBounds(14, 10, 260, 36);
        headerPanel.Controls.Add(_titleLabel);

        _providerNameLabel.Text = ResolveProviderName(importContent);
        _providerNameLabel.Font = new Font("Segoe UI Semibold", 13F, FontStyle.Bold);
        _providerNameLabel.ForeColor = Color.FromArgb(45, 62, 80);
        _providerNameLabel.SetBounds(16, 50, 560, 28);
        _providerNameLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        headerPanel.Controls.Add(_providerNameLabel);

        _headerCloseButton.Text = "Close";
        _headerCloseButton.SetBounds(headerPanel.Width - 102, 16, 84, 34);
        _headerCloseButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _headerCloseButton.FlatStyle = FlatStyle.Flat;
        _headerCloseButton.FlatAppearance.BorderSize = 0;
        _headerCloseButton.BackColor = Color.FromArgb(236, 187, 66);
        _headerCloseButton.Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold);
        _headerCloseButton.Click += (_, _) => Close();
        headerPanel.Controls.Add(_headerCloseButton);

        var introPanel = CreateCardPanel();
        introPanel.SetBounds(14, 122, ClientSize.Width - 28, 74);
        introPanel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        rootPanel.Controls.Add(introPanel);

        var introText = new Label
        {
            Text = "Wizard installs imported content and activates profile. Optional rule files are handled when available.",
            Font = new Font("Segoe UI", 10.5F),
            ForeColor = Color.FromArgb(84, 102, 121),
            AutoSize = false
        };
        introText.SetBounds(14, 12, introPanel.Width - 260, 46);
        introText.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        introPanel.Controls.Add(introText);

        _selectAfterInstallToggle.Text = "Select after install";
        _selectAfterInstallToggle.Checked = true;
        _selectAfterInstallToggle.Enabled = false;
        _selectAfterInstallToggle.AutoSize = true;
        _selectAfterInstallToggle.Font = new Font("Segoe UI", 10F);
        _selectAfterInstallToggle.SetBounds(introPanel.Width - 194, 24, 170, 24);
        _selectAfterInstallToggle.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        introPanel.Controls.Add(_selectAfterInstallToggle);

        var metaPanel = CreateCardPanel();
        metaPanel.SetBounds(14, 208, ClientSize.Width - 28, 136);
        metaPanel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        rootPanel.Controls.Add(metaPanel);

        var metaTitle = new Label
        {
            Text = "Metadata",
            Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold),
            ForeColor = Color.FromArgb(95, 113, 132)
        };
        metaTitle.SetBounds(14, 8, 120, 22);
        metaPanel.Controls.Add(metaTitle);

        _metaListView.View = View.Details;
        _metaListView.HeaderStyle = ColumnHeaderStyle.None;
        _metaListView.FullRowSelect = false;
        _metaListView.GridLines = false;
        _metaListView.MultiSelect = false;
        _metaListView.SetBounds(14, 30, metaPanel.Width - 28, 92);
        _metaListView.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _metaListView.Columns.Add("k", 220);
        _metaListView.Columns.Add("v", 560);
        metaPanel.Controls.Add(_metaListView);
        FillMetaRows(importContent);

        var stepsPanel = CreateCardPanel();
        stepsPanel.SetBounds(14, 356, ClientSize.Width - 28, 220);
        stepsPanel.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        rootPanel.Controls.Add(stepsPanel);

        var stepsTitle = new Label
        {
            Text = "Install Steps",
            Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold),
            ForeColor = Color.FromArgb(95, 113, 132)
        };
        stepsTitle.SetBounds(14, 8, 120, 22);
        stepsPanel.Controls.Add(stepsTitle);

        _stepsListView.View = View.Details;
        _stepsListView.FullRowSelect = false;
        _stepsListView.GridLines = false;
        _stepsListView.MultiSelect = false;
        _stepsListView.HeaderStyle = ColumnHeaderStyle.None;
        _stepsListView.SetBounds(14, 30, stepsPanel.Width - 28, 176);
        _stepsListView.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _stepsListView.Columns.Add("Status", 96);
        _stepsListView.Columns.Add("Step", 460);
        _stepsListView.Columns.Add("Message", 260);
        stepsPanel.Controls.Add(_stepsListView);
        RenderSteps();

        _errorPanel.SetBounds(14, 586, ClientSize.Width - 28, 54);
        _errorPanel.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        _errorPanel.BackColor = Color.FromArgb(252, 228, 233);
        _errorPanel.Visible = false;
        rootPanel.Controls.Add(_errorPanel);

        _errorLabel.ForeColor = Color.FromArgb(168, 57, 70);
        _errorLabel.Font = new Font("Segoe UI", 9.5F);
        _errorLabel.SetBounds(12, 8, _errorPanel.Width - 110, 36);
        _errorLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _errorPanel.Controls.Add(_errorLabel);

        _copyErrorButton.Text = "Copy";
        _copyErrorButton.SetBounds(_errorPanel.Width - 82, 10, 70, 30);
        _copyErrorButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _copyErrorButton.FlatStyle = FlatStyle.Flat;
        _copyErrorButton.FlatAppearance.BorderSize = 0;
        _copyErrorButton.Click += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_errorText))
            {
                Clipboard.SetText(_errorText);
            }
        };
        _errorPanel.Controls.Add(_copyErrorButton);

        var actionPanel = new Panel();
        actionPanel.SetBounds(14, ClientSize.Height - 48, ClientSize.Width - 28, 34);
        actionPanel.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        rootPanel.Controls.Add(actionPanel);

        _cancelButton.Text = "Cancel";
        _cancelButton.SetBounds(0, 0, 86, 34);
        _cancelButton.FlatStyle = FlatStyle.Flat;
        _cancelButton.FlatAppearance.BorderSize = 0;
        _cancelButton.Click += (_, _) => Close();
        actionPanel.Controls.Add(_cancelButton);

        _runningProgressBar.SetBounds(actionPanel.Width - 364, 8, 120, 18);
        _runningProgressBar.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _runningProgressBar.Style = ProgressBarStyle.Marquee;
        _runningProgressBar.MarqueeAnimationSpeed = 25;
        _runningProgressBar.Visible = false;
        actionPanel.Controls.Add(_runningProgressBar);

        _runningHintLabel.SetBounds(actionPanel.Width - 240, 8, 160, 18);
        _runningHintLabel.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _runningHintLabel.ForeColor = Color.FromArgb(95, 113, 132);
        _runningHintLabel.Font = new Font("Segoe UI", 9F);
        _runningHintLabel.TextAlign = ContentAlignment.MiddleRight;
        _runningHintLabel.Visible = false;
        actionPanel.Controls.Add(_runningHintLabel);

        _startButton.Text = "Install";
        _startButton.SetBounds(actionPanel.Width - 168, 0, 80, 34);
        _startButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _startButton.FlatStyle = FlatStyle.Flat;
        _startButton.FlatAppearance.BorderSize = 0;
        _startButton.BackColor = Color.FromArgb(61, 148, 231);
        _startButton.ForeColor = Color.White;
        _startButton.Click += async (_, _) => await RunInstallAsync();
        actionPanel.Controls.Add(_startButton);

        // Start immediately
        // Shown += async (_, _) =>
        // {
        //     if (!_isRunning && !_isFinished)
        //     {
        //         await RunInstallAsync();
        //     }
        // };

        _doneButton.Text = "Done";
        _doneButton.SetBounds(actionPanel.Width - 82, 0, 80, 34);
        _doneButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _doneButton.FlatStyle = FlatStyle.Flat;
        _doneButton.FlatAppearance.BorderSize = 0;
        _doneButton.BackColor = Color.FromArgb(61, 148, 231);
        _doneButton.ForeColor = Color.White;
        _doneButton.Visible = false;
        _doneButton.Click += (_, _) =>
        {
            DialogResult = DialogResult.OK;
            Close();
        };
        actionPanel.Controls.Add(_doneButton);
    }

    private static Panel CreateCardPanel()
    {
        return new Panel
        {
            BackColor = Color.FromArgb(236, 245, 252),
            BorderStyle = BorderStyle.FixedSingle
        };
    }

    private string ResolveProviderName(string importContent)
    {
        if (!string.IsNullOrWhiteSpace(_overrideProviderName)) return _overrideProviderName;
        var meta = ParsePayloadMeta(importContent);
        return string.IsNullOrWhiteSpace(meta.ProviderName) ? "Imported Provider" : meta.ProviderName;
    }

    private void FillMetaRows(string importContent)
    {
        var meta = ParsePayloadMeta(importContent);
        AddMeta("provider_id", meta.ProviderId);
        AddMeta("provider_name", !string.IsNullOrWhiteSpace(_overrideProviderName) ? _overrideProviderName : meta.ProviderName);
        AddMeta("package_hash", meta.PackageHash);
        AddMeta("payload_bytes", Encoding.UTF8.GetByteCount(importContent).ToString());
        AddMeta("payload_format", meta.PayloadFormat);
    }

    private void AddMeta(string key, string value)
    {
        var row = new ListViewItem(new[] { key, string.IsNullOrWhiteSpace(value) ? "-" : value });
        _metaListView.Items.Add(row);
    }

    private void RenderSteps()
    {
        _stepsListView.BeginUpdate();
        _stepsListView.Items.Clear();
        foreach (var step in _steps)
        {
            _stepsListView.Items.Add(new ListViewItem(new[]
            {
                step.Status,
                step.Title,
                string.IsNullOrWhiteSpace(step.Message) ? "-" : step.Message
            }));
        }
        _stepsListView.EndUpdate();
    }

    private async Task RunInstallAsync()
    {
        if (_isRunning) return;

        _isRunning = true;
        _isFinished = false;
        _errorText = string.Empty;
        _errorPanel.Visible = false;
        _headerCloseButton.Enabled = false;
        _cancelButton.Enabled = false;
        _startButton.Enabled = false;
        _startButton.Text = "Running";
        _doneButton.Visible = false;
        _runningProgressBar.Visible = true;
        _runningHintLabel.Visible = true;
        _runningHintLabel.Text = "Installing...";
        ResetSteps();
        RenderSteps();

        try
        {
            if (_isLegacyMode && _installAction != null)
            {
                // Legacy path for backward compatibility or core-based install
                await MarkStepRunningAsync(0, "start legacy install");
                var response = await _installAction(_importContent);
                InstallResponse = response;
                if (!response.Ok)
                {
                    ShowError("Install failed: " + response.Message);
                    return;
                }
                
                // ... (existing legacy profile registration logic if we keep it) ...
                // For now, let's assume legacy mode handles everything opaquely or fails.
                // We should really migrate everything to ProviderInstaller.
                
                _isFinished = true;
                _doneButton.Visible = true;
            }
            else
            {
                // New ProviderInstaller Path
                var meta = ParsePayloadMeta(_importContent);
                var context = new ImportInstallContext
                {
                    ProviderId = meta.ProviderId,
                    ProviderName = !string.IsNullOrWhiteSpace(_overrideProviderName) ? _overrideProviderName : meta.ProviderName,
                    PackageHash = meta.PackageHash,
                    ConfigContent = _importContent,
                    SelectAfterInstall = _selectAfterInstallToggle.Checked
                };

                var installer = new ProviderInstaller();
                var progress = new Progress<InstallProgress>(p =>
                {
                    if (_stepMap.TryGetValue(p.Step, out var index))
                    {
                        // Mark previous steps as success
                        for (int i = 0; i < index; i++)
                        {
                            if (_steps[i].Status != "success")
                                SetStep(i, "success", "ok");
                        }
                        SetStep(index, "running", p.Message);
                    }
                });

                var success = await installer.InstallFromContextAsync(context, progress);
                
                if (success)
                {
                    // Mark all as success
                    for (int i = 0; i < _steps.Count; i++)
                    {
                         SetStep(i, "success", "ok");
                    }
                    
                    InstallResponse = new CoreResponse { Ok = true, Message = "Installed via ProviderInstaller" };
                    _isFinished = true;
                    _doneButton.Visible = true;
                }
                else
                {
                    ShowError("Installation failed. Check logs.");
                }
            }
        }
        catch (Exception ex)
        {
            ShowError("Install exception: " + ex.Message);
        }
        finally
        {
            _isRunning = false;
            _headerCloseButton.Enabled = true;
            _cancelButton.Enabled = true;
            _startButton.Enabled = true;
            _startButton.Text = _isFinished ? "Retry" : "Start";
            _runningProgressBar.Visible = false;
            _runningHintLabel.Visible = false;
        }
    }

    private void ShowError(string message)
    {
        _errorText = message;
        _errorLabel.Text = message;
        _errorPanel.Visible = true;
    }

    private void ResetSteps()
    {
        foreach (var step in _steps)
        {
            step.Status = "pending";
            step.Message = string.Empty;
        }
    }

    private Task MarkStepRunningAsync(int index, string message)
    {
        SetStep(index, "running", message);
        return Task.CompletedTask;
    }

    private Task MarkStepSuccessAsync(int index, string message)
    {
        SetStep(index, "success", message);
        return Task.CompletedTask;
    }

    private Task MarkStepFailureAsync(int index, string message)
    {
        SetStep(index, "failure", message);
        return Task.CompletedTask;
    }

    private void SetStep(int index, string status, string message)
    {
        if (index < 0 || index >= _steps.Count)
        {
            return;
        }
        _steps[index].Status = status;
        _steps[index].Message = message;
        RenderSteps();
    }

    private sealed class PayloadMeta
    {
        public string ProviderId { get; init; } = string.Empty;
        public string ProviderName { get; init; } = string.Empty;
        public string PackageHash { get; init; } = string.Empty;
        public string PayloadFormat { get; init; } = "json";
    }

    private static PayloadMeta ParsePayloadMeta(string importContent)
    {
        var raw = importContent.Trim();
        if (string.IsNullOrWhiteSpace(raw))
        {
            return new PayloadMeta();
        }

        var payloadFormat = "json";
        // Check if it's base64 encoded JSON
        if (!(raw.StartsWith("{") || raw.StartsWith("[")))
        {
            try
            {
                var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(raw));
                if (decoded.Trim().StartsWith("{") || decoded.Trim().StartsWith("["))
                {
                    raw = decoded.Trim();
                    payloadFormat = "base64-json";
                }
            }
            catch { }
        }

        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            
            if (root.ValueKind == JsonValueKind.Object)
            {
                var meta = new PayloadMeta
                {
                    ProviderId = ReadString(root, "provider_id", "id"),
                    ProviderName = ReadString(root, "provider_name", "name"),
                    PackageHash = ReadString(root, "package_hash", "hash"),
                    PayloadFormat = payloadFormat
                };
                
                // If it is a standard config json, it might not have provider_id or provider_name fields, 
                // but it should not be empty.
                // We trust the config content to be valid.
                
                return meta;
            }
        }
        catch { }

        return new PayloadMeta { PayloadFormat = "unknown" };
    }

    private static string ReadString(JsonElement root, string name, string alias = "")
    {
        if (root.ValueKind == JsonValueKind.Object)
        {
            if (root.TryGetProperty(name, out var prop) && prop.ValueKind == JsonValueKind.String)
                return prop.GetString() ?? string.Empty;
            if (!string.IsNullOrEmpty(alias) && root.TryGetProperty(alias, out var prop2) && prop2.ValueKind == JsonValueKind.String)
                return prop2.GetString() ?? string.Empty;
            
            // Also check for "provider_name" vs "name" if we passed alias "name"
            if (alias == "name" && root.TryGetProperty("provider_name", out var prop3) && prop3.ValueKind == JsonValueKind.String)
                return prop3.GetString() ?? string.Empty;
                
            // Also check for "provider_id" vs "id" if we passed alias "id"
            if (alias == "id" && root.TryGetProperty("provider_id", out var prop4) && prop4.ValueKind == JsonValueKind.String)
                return prop4.GetString() ?? string.Empty;
        }
        return string.Empty;
    }
}
