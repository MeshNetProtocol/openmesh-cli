using System.Text;
using System.Text.Json;

namespace OpenMeshWin;

internal sealed class ProviderInstallForm : Form
{
    private sealed class InstallStep
    {
        public string Title { get; init; } = string.Empty;
        public string Status { get; set; } = "pending"; // pending, running, success, failure
        public string Message { get; set; } = string.Empty;
    }

    private readonly Func<Action<string, string>, Task<bool>> _installAction;
    private readonly string _providerId;
    private readonly string _providerName;
    private readonly List<InstallStep> _steps =
    [
        new() { Title = "Fetch provider details" },
        new() { Title = "Download config" },
        new() { Title = "Download rule-sets" },
        new() { Title = "Download routing rules (optional)" },
        new() { Title = "Patch configuration" },
        new() { Title = "Register profile" },
        new() { Title = "Finalize" },
    ];

    private readonly Label _titleLabel = new();
    private readonly Label _providerNameLabel = new();
    private readonly Button _headerCloseButton = new();
    private readonly ListView _stepsListView = new();
    private readonly Panel _errorPanel = new();
    private readonly Label _errorLabel = new();
    private readonly Button _copyErrorButton = new();
    private readonly Button _cancelButton = new();
    private readonly Button _doneButton = new();
    private readonly Label _runningHintLabel = new();
    private readonly ProgressBar _runningProgressBar = new();

    private bool _isRunning;
    // private bool _isFinished; // Removed unused warning
    private string _errorText = string.Empty;

    public bool InstallSuccess { get; private set; }

    public ProviderInstallForm(string providerId, string providerName, Func<Action<string, string>, Task<bool>> installAction)
    {
        _providerId = providerId;
        _providerName = providerName;
        _installAction = installAction;

        Text = $"Installing {providerName}";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MinimizeBox = false;
        MaximizeBox = false;
        Width = 720;
        Height = 500;
        BackColor = Color.White;

        var rootPanel = new Panel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(20)
        };
        Controls.Add(rootPanel);

        // Header
        _titleLabel.Text = "Installing Provider";
        _titleLabel.Font = new Font("Segoe UI Semibold", 16F, FontStyle.Bold);
        _titleLabel.ForeColor = Color.FromArgb(45, 62, 80);
        _titleLabel.SetBounds(20, 20, 400, 30);
        rootPanel.Controls.Add(_titleLabel);

        _providerNameLabel.Text = providerName;
        _providerNameLabel.Font = new Font("Segoe UI", 11F);
        _providerNameLabel.ForeColor = Color.Gray;
        _providerNameLabel.SetBounds(20, 55, 600, 25);
        rootPanel.Controls.Add(_providerNameLabel);

        // Steps List
        _stepsListView.View = View.Details;
        _stepsListView.FullRowSelect = true;
        _stepsListView.GridLines = false;
        _stepsListView.MultiSelect = false;
        _stepsListView.HeaderStyle = ColumnHeaderStyle.None;
        _stepsListView.SetBounds(20, 100, 660, 280);
        _stepsListView.Columns.Add("Status", 100);
        _stepsListView.Columns.Add("Step", 300);
        _stepsListView.Columns.Add("Message", 230);
        rootPanel.Controls.Add(_stepsListView);
        RenderSteps();

        // Error Panel
        _errorPanel.SetBounds(20, 390, 660, 50);
        _errorPanel.BackColor = Color.FromArgb(255, 235, 238);
        _errorPanel.Visible = false;
        rootPanel.Controls.Add(_errorPanel);

        _errorLabel.ForeColor = Color.FromArgb(198, 40, 40);
        _errorLabel.Font = new Font("Segoe UI", 9F);
        _errorLabel.SetBounds(10, 10, 560, 30);
        _errorPanel.Controls.Add(_errorLabel);

        _copyErrorButton.Text = "Copy";
        _copyErrorButton.SetBounds(580, 10, 70, 30);
        _copyErrorButton.FlatStyle = FlatStyle.Flat;
        _copyErrorButton.Click += (_, _) => { if (!string.IsNullOrEmpty(_errorText)) Clipboard.SetText(_errorText); };
        _errorPanel.Controls.Add(_copyErrorButton);

        // Footer Actions
        _cancelButton.Text = "Cancel";
        _cancelButton.SetBounds(20, 410, 100, 35);
        _cancelButton.Click += (_, _) => Close();
        rootPanel.Controls.Add(_cancelButton);

        _doneButton.Text = "Done";
        _doneButton.SetBounds(580, 410, 100, 35);
        _doneButton.BackColor = Color.FromArgb(61, 148, 231);
        _doneButton.ForeColor = Color.White;
        _doneButton.FlatStyle = FlatStyle.Flat;
        _doneButton.Visible = false;
        _doneButton.Click += (_, _) => { DialogResult = DialogResult.OK; Close(); };
        rootPanel.Controls.Add(_doneButton);

        _runningProgressBar.SetBounds(140, 420, 300, 15);
        _runningProgressBar.Style = ProgressBarStyle.Marquee;
        _runningProgressBar.Visible = false;
        rootPanel.Controls.Add(_runningProgressBar);

        // Start immediately
        Shown += async (_, _) => await RunInstallAsync();
    }

    private void RenderSteps()
    {
        _stepsListView.BeginUpdate();
        _stepsListView.Items.Clear();
        foreach (var step in _steps)
        {
            var item = new ListViewItem(step.Status.ToUpper());
            item.SubItems.Add(step.Title);
            item.SubItems.Add(step.Message);
            
            // Set colors based on status
            if (step.Status == "success") item.ForeColor = Color.Green;
            else if (step.Status == "failure") item.ForeColor = Color.Red;
            else if (step.Status == "running") item.ForeColor = Color.Blue;
            else item.ForeColor = Color.Gray;

            _stepsListView.Items.Add(item);
        }
        _stepsListView.EndUpdate();
    }

    private async Task RunInstallAsync()
    {
        if (_isRunning) return;
        _isRunning = true;
        _cancelButton.Enabled = false;
        _runningProgressBar.Visible = true;

        try
        {
            InstallSuccess = await _installAction(UpdateProgress);
            
            if (InstallSuccess)
        {
            // _isFinished = true;
            _doneButton.Visible = true;
            _cancelButton.Visible = false;
            _runningProgressBar.Visible = false;
        }
            else
            {
                ShowError("Installation failed. Please check logs.");
                _cancelButton.Enabled = true;
                _cancelButton.Text = "Close";
            }
        }
        catch (Exception ex)
        {
            ShowError($"Error: {ex.Message}");
            _cancelButton.Enabled = true;
            _cancelButton.Text = "Close";
        }
        finally
        {
            _isRunning = false;
            _runningProgressBar.Visible = false;
        }
    }

    private void UpdateProgress(string stepKey, string message)
    {
        if (InvokeRequired)
        {
            Invoke(new Action<string, string>(UpdateProgress), stepKey, message);
            return;
        }

        // Simple mapping for now - in real implementation we might want precise step mapping
        // Here we just find the currently running step or update the last one
        
        // This logic can be refined based on Go Core's progress reporting
        // For now, let's just update the UI to show activity
        
        var activeStep = _steps.FirstOrDefault(s => s.Status == "running") 
                         ?? _steps.FirstOrDefault(s => s.Status == "pending");

        if (activeStep != null)
        {
            activeStep.Status = "running";
            activeStep.Message = message;
            
            // If message indicates completion of a phase, mark success and move next
            if (message.Contains("complete", StringComparison.OrdinalIgnoreCase) || 
                message.Contains("done", StringComparison.OrdinalIgnoreCase))
            {
                activeStep.Status = "success";
            }
            
            RenderSteps();
        }
    }

    private void ShowError(string message)
    {
        _errorText = message;
        _errorLabel.Text = message;
        _errorPanel.Visible = true;
    }
}
