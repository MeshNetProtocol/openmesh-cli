using System.Drawing;
using System.Windows.Forms;

namespace OpenMeshWin;

internal sealed class ProviderUninstallForm : Form
{
    private readonly string _providerId;
    private readonly string _providerName;
    private readonly Func<IProgress<(string Step, string Message)>, Task> _uninstallAction;

    private readonly Label _titleLabel = new();
    private readonly Label _providerLabel = new();
    private readonly ListBox _stepsListBox = new();
    private readonly Label _statusLabel = new();
    private readonly Button _cancelButton = new();
    private readonly Button _startButton = new();

    public bool UninstallSuccess { get; private set; }

    public ProviderUninstallForm(
        string providerId,
        string providerName,
        Func<IProgress<(string Step, string Message)>, Task> uninstallAction)
    {
        _providerId = (providerId ?? string.Empty).Trim();
        _providerName = (providerName ?? string.Empty).Trim();
        _uninstallAction = uninstallAction;

        Text = "卸载供应商";
        StartPosition = FormStartPosition.CenterParent;
        MinimumSize = new Size(700, 520);
        Size = new Size(760, 560);

        BuildUi();
    }

    private void BuildUi()
    {
        var root = new Panel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(16),
            BackColor = Color.FromArgb(232, 241, 250)
        };

        _titleLabel.Text = "卸载供应商";
        _titleLabel.Font = new Font("Segoe UI", 18F, FontStyle.Bold);
        _titleLabel.ForeColor = Color.FromArgb(71, 167, 230);
        _titleLabel.AutoSize = true;
        _titleLabel.Location = new Point(16, 12);

        _providerLabel.Text = string.IsNullOrWhiteSpace(_providerName)
            ? _providerId
            : $"{_providerName} ({_providerId})";
        _providerLabel.Font = new Font("Segoe UI", 10F, FontStyle.Regular);
        _providerLabel.AutoSize = true;
        _providerLabel.Location = new Point(18, 50);

        _stepsListBox.Font = new Font("Consolas", 10F);
        _stepsListBox.BackColor = Color.White;
        _stepsListBox.BorderStyle = BorderStyle.FixedSingle;
        _stepsListBox.SetBounds(16, 90, 708, 370);

        _statusLabel.Text = "将删除本地 profile、映射和 provider 文件。";
        _statusLabel.AutoSize = true;
        _statusLabel.ForeColor = Color.FromArgb(105, 121, 140);
        _statusLabel.Location = new Point(18, 470);

        _cancelButton.Text = "取消";
        _cancelButton.SetBounds(548, 488, 84, 32);
        _cancelButton.Click += (_, _) => Close();

        _startButton.Text = "开始卸载";
        _startButton.SetBounds(640, 488, 84, 32);
        _startButton.BackColor = Color.FromArgb(71, 167, 230);
        _startButton.ForeColor = Color.White;
        _startButton.FlatStyle = FlatStyle.Flat;
        _startButton.FlatAppearance.BorderSize = 0;
        _startButton.Click += async (_, _) => await StartUninstallAsync();

        root.Controls.Add(_titleLabel);
        root.Controls.Add(_providerLabel);
        root.Controls.Add(_stepsListBox);
        root.Controls.Add(_statusLabel);
        root.Controls.Add(_cancelButton);
        root.Controls.Add(_startButton);
        Controls.Add(root);
    }

    private async Task StartUninstallAsync()
    {
        _startButton.Enabled = false;
        _cancelButton.Enabled = false;
        _stepsListBox.Items.Clear();
        _statusLabel.Text = "正在卸载...";

        var progress = new Progress<(string Step, string Message)>(item =>
        {
            _stepsListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] {item.Step}: {item.Message}");
            _stepsListBox.TopIndex = Math.Max(0, _stepsListBox.Items.Count - 1);
        });

        try
        {
            await _uninstallAction(progress);
            UninstallSuccess = true;
            _statusLabel.Text = "卸载完成";
            DialogResult = DialogResult.OK;
            Close();
        }
        catch (Exception ex)
        {
            _stepsListBox.Items.Add($"[{DateTime.Now:HH:mm:ss}] ERROR: {ex.Message}");
            _statusLabel.Text = "卸载失败";
            _startButton.Enabled = true;
            _cancelButton.Enabled = true;
        }
    }
}
