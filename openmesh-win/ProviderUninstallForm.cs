using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace OpenMeshWin;

internal sealed class ProviderUninstallForm : Form
{
    private static readonly Color PageBackground = Color.FromArgb(232, 241, 250);
    private static readonly Color CardBackground = Color.FromArgb(248, 251, 255);
    private static readonly Color CardBorder = Color.FromArgb(205, 222, 238);
    private static readonly Color AccentBlue = Color.FromArgb(71, 167, 230);
    private static readonly Color AccentAmber = Color.FromArgb(233, 179, 73);
    private static readonly Color TextPrimary = Color.FromArgb(34, 52, 70);
    private static readonly Color TextSecondary = Color.FromArgb(105, 121, 140);

    private readonly string _providerId;
    private readonly string _providerName;
    private readonly Func<IProgress<(string Step, string Message)>, Task> _uninstallAction;

    private readonly Label _titleLabel = new();
    private readonly Label _nameLabel = new();
    private readonly Label _idLabel = new();
    private readonly Button _headerCloseButton = new();

    private readonly Label _infoLabel = new();
    private readonly Label _stepsTitleLabel = new();
    private readonly Label _errorLabel = new();

    private readonly Button _cancelButton = new();
    private readonly Button _primaryButton = new();

    private readonly Dictionary<string, Label> _stepLabels = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _stepTitles = new(StringComparer.OrdinalIgnoreCase)
    {
        ["validate"] = "校验状态",
        ["remove_profile"] = "删除 Profile",
        ["remove_preferences"] = "清理映射",
        ["remove_files"] = "删除缓存文件",
        ["finalize"] = "完成"
    };

    private bool _isRunning;
    private bool _finished;

    public bool UninstallSuccess { get; private set; }

    public ProviderUninstallForm(string providerId, string providerName, Func<IProgress<(string Step, string Message)>, Task> uninstallAction)
    {
        _providerId = (providerId ?? string.Empty).Trim();
        _providerName = (providerName ?? string.Empty).Trim();
        _uninstallAction = uninstallAction;

        Text = "卸载供应商";
        StartPosition = FormStartPosition.CenterParent;
        MinimumSize = new Size(720, 560);
        Size = new Size(820, 600);
        BackColor = PageBackground;

        BuildUi();
        ResetStepUi();
    }

    private void BuildUi()
    {
        var root = new Panel { Dock = DockStyle.Fill, BackColor = PageBackground, Padding = new Padding(16) };

        var headerCard = CreateCard();
        headerCard.SetBounds(16, 14, 772, 142);

        _titleLabel.Text = "卸载供应商";
        _titleLabel.Font = new Font("Segoe UI", 20F, FontStyle.Bold);
        _titleLabel.ForeColor = AccentBlue;
        _titleLabel.AutoSize = true;
        _titleLabel.Location = new Point(20, 14);

        _nameLabel.Text = string.IsNullOrWhiteSpace(_providerName) ? _providerId : _providerName;
        _nameLabel.Font = new Font("Segoe UI", 16F, FontStyle.Bold);
        _nameLabel.ForeColor = TextPrimary;
        _nameLabel.AutoSize = true;
        _nameLabel.Location = new Point(20, 54);

        _idLabel.Text = _providerId;
        _idLabel.Font = new Font("Consolas", 11.5F, FontStyle.Regular);
        _idLabel.ForeColor = TextSecondary;
        _idLabel.AutoSize = true;
        _idLabel.Location = new Point(20, 98);

        ConfigureButton(_headerCloseButton, "关闭", AccentAmber, Color.FromArgb(23, 31, 43));
        _headerCloseButton.SetBounds(680, 14, 74, 36);
        _headerCloseButton.Click += (_, _) => Close();

        headerCard.Controls.Add(_titleLabel);
        headerCard.Controls.Add(_nameLabel);
        headerCard.Controls.Add(_idLabel);
        headerCard.Controls.Add(_headerCloseButton);

        var infoCard = CreateCard();
        infoCard.SetBounds(16, 168, 772, 66);
        _infoLabel.Text = "将从本地移除该供应商对应 profile、映射与缓存文件。若当前 VPN 正在使用该 profile，请先断开连接再卸载。";
        _infoLabel.Font = new Font("Segoe UI", 11F, FontStyle.Bold);
        _infoLabel.ForeColor = TextSecondary;
        _infoLabel.AutoSize = false;
        _infoLabel.SetBounds(18, 14, 736, 42);
        infoCard.Controls.Add(_infoLabel);

        var stepsCard = CreateCard();
        stepsCard.SetBounds(16, 246, 772, 246);

        _stepsTitleLabel.Text = "卸载步骤";
        _stepsTitleLabel.Font = new Font("Segoe UI", 15F, FontStyle.Bold);
        _stepsTitleLabel.ForeColor = TextPrimary;
        _stepsTitleLabel.AutoSize = true;
        _stepsTitleLabel.Location = new Point(20, 14);
        stepsCard.Controls.Add(_stepsTitleLabel);

        var stepKeys = new[] { "validate", "remove_profile", "remove_preferences", "remove_files", "finalize" };
        for (var i = 0; i < stepKeys.Length; i++)
        {
            var key = stepKeys[i];
            var row = new Label
            {
                AutoSize = false,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Segoe UI", 13F, FontStyle.Bold),
                ForeColor = TextPrimary,
                BackColor = Color.Transparent,
                Bounds = new Rectangle(24, 50 + (i * 36), 720, 32)
            };
            _stepLabels[key] = row;
            stepsCard.Controls.Add(row);
        }

        _errorLabel.Visible = false;
        _errorLabel.AutoSize = false;
        _errorLabel.Font = new Font("Segoe UI", 10.5F, FontStyle.Bold);
        _errorLabel.ForeColor = Color.FromArgb(202, 68, 72);
        _errorLabel.BackColor = Color.Transparent;
        _errorLabel.SetBounds(20, 500, 640, 24);

        var bottomLine = new Panel { BackColor = CardBorder, Bounds = new Rectangle(16, 530, 772, 1) };

        ConfigureButton(_cancelButton, "取消", Color.FromArgb(220, 233, 246), TextPrimary);
        _cancelButton.SetBounds(16, 544, 82, 36);
        _cancelButton.Click += (_, _) => Close();

        ConfigureButton(_primaryButton, "开始卸载", AccentBlue, Color.White);
        _primaryButton.SetBounds(664, 544, 124, 36);
        _primaryButton.Click += async (_, _) => await OnPrimaryButtonClickAsync();

        root.Controls.Add(headerCard);
        root.Controls.Add(infoCard);
        root.Controls.Add(stepsCard);
        root.Controls.Add(_errorLabel);
        root.Controls.Add(bottomLine);
        root.Controls.Add(_cancelButton);
        root.Controls.Add(_primaryButton);

        root.Resize += (_, _) =>
        {
            var w = root.ClientSize.Width;
            var h = root.ClientSize.Height;

            headerCard.SetBounds(16, 14, w - 32, 142);
            _headerCloseButton.Left = headerCard.Width - _headerCloseButton.Width - 16;

            infoCard.SetBounds(16, 168, w - 32, 66);
            _infoLabel.Width = infoCard.Width - 36;

            var bottomTop = h - 42;
            _cancelButton.SetBounds(16, bottomTop, 82, 36);
            _primaryButton.SetBounds(w - _primaryButton.Width - 16, bottomTop, 124, 36);

            bottomLine.SetBounds(16, bottomTop - 12, w - 32, 1);

            var stepsBottom = bottomTop - 18;
            var stepsHeight = Math.Max(220, stepsBottom - 246);
            stepsCard.SetBounds(16, 246, w - 32, stepsHeight);

            _errorLabel.SetBounds(20, stepsCard.Bottom + 6, Math.Max(200, w - 240), 24);

            var rowWidth = stepsCard.Width - 52;
            var y = 50;
            foreach (var key in stepKeys)
            {
                _stepLabels[key].SetBounds(24, y, rowWidth, 32);
                y += 36;
            }
        };

        Controls.Add(root);
    }

    private async Task OnPrimaryButtonClickAsync()
    {
        if (_finished)
        {
            DialogResult = DialogResult.OK;
            Close();
            return;
        }
        if (_isRunning)
        {
            return;
        }
        await StartUninstallAsync();
    }

    private async Task StartUninstallAsync()
    {
        _isRunning = true;
        _errorLabel.Visible = false;
        _finished = false;
        ResetStepUi();
        ToggleButtonsForRunning(true);

        var progress = new Progress<(string Step, string Message)>(item =>
        {
            var key = NormalizeStepKey(item.Step);
            if (string.IsNullOrEmpty(key) || !_stepLabels.ContainsKey(key)) return;

            foreach (var pair in _stepLabels)
            {
                if (pair.Key == key)
                {
                    SetStepVisual(pair.Key, StepVisual.Running, item.Message);
                }
                else if (GetStepVisual(pair.Key) == StepVisual.Running)
                {
                    SetStepVisual(pair.Key, StepVisual.Success, string.Empty);
                }
            }
        });

        try
        {
            await _uninstallAction(progress);
            foreach (var key in _stepLabels.Keys.ToList())
            {
                var current = GetStepVisual(key);
                if (current == StepVisual.Pending || current == StepVisual.Running)
                {
                    SetStepVisual(key, StepVisual.Success, string.Empty);
                }
            }

            UninstallSuccess = true;
            _finished = true;
            _primaryButton.Text = "完成";
            _cancelButton.Enabled = false;
        }
        catch (Exception ex)
        {
            SetStepVisual("finalize", StepVisual.Failed, "失败");
            _errorLabel.Text = ex.Message;
            _errorLabel.Visible = true;
        }
        finally
        {
            _isRunning = false;
            ToggleButtonsForRunning(false);
        }
    }

    private void ToggleButtonsForRunning(bool running)
    {
        _headerCloseButton.Enabled = !running;
        _cancelButton.Enabled = !running && !_finished;
        _primaryButton.Enabled = true;
        _primaryButton.Text = _finished ? "完成" : (running ? "卸载中..." : "开始卸载");
    }

    private void ResetStepUi()
    {
        foreach (var key in _stepLabels.Keys)
        {
            SetStepVisual(key, StepVisual.Pending, string.Empty);
        }
    }

    private void SetStepVisual(string key, StepVisual visual, string message)
    {
        if (!_stepLabels.TryGetValue(key, out var label)) return;

        var title = _stepTitles.TryGetValue(key, out var t) ? t : key;
        var suffix = string.IsNullOrWhiteSpace(message) ? string.Empty : $"  -  {message}";

        label.Tag = visual;
        label.Text = visual switch
        {
            StepVisual.Pending => $"[ ]  {title}{suffix}",
            StepVisual.Running => $"[~]  {title}{suffix}",
            StepVisual.Success => $"[OK] {title}{suffix}",
            StepVisual.Failed => $"[X]  {title}{suffix}",
            _ => $"[ ]  {title}{suffix}"
        };

        label.ForeColor = visual switch
        {
            StepVisual.Pending => TextSecondary,
            StepVisual.Running => AccentBlue,
            StepVisual.Success => Color.FromArgb(54, 174, 115),
            StepVisual.Failed => Color.FromArgb(202, 68, 72),
            _ => TextSecondary
        };
    }

    private StepVisual GetStepVisual(string key)
    {
        if (_stepLabels.TryGetValue(key, out var label) && label.Tag is StepVisual visual)
        {
            return visual;
        }
        return StepVisual.Pending;
    }

    private static string NormalizeStepKey(string raw)
    {
        var s = (raw ?? string.Empty).Trim().ToLowerInvariant();
        return s switch
        {
            "validate" => "validate",
            "remove_profile" => "remove_profile",
            "remove_preferences" => "remove_preferences",
            "remove_files" => "remove_files",
            "finalize" => "finalize",
            _ => string.Empty
        };
    }

    private static Panel CreateCard()
    {
        var panel = new Panel { BackColor = CardBackground };
        panel.Paint += (_, e) =>
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(0, 0, panel.Width - 1, panel.Height - 1);
            using var path = RoundRect(rect, 16);
            using var fill = new SolidBrush(CardBackground);
            using var border = new Pen(CardBorder, 1);
            e.Graphics.FillPath(fill, path);
            e.Graphics.DrawPath(border, path);
            panel.Region = new Region(path);
        };
        return panel;
    }

    private static void ConfigureButton(Button button, string text, Color backColor, Color foreColor)
    {
        button.Text = text;
        button.BackColor = backColor;
        button.ForeColor = foreColor;
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.Font = new Font("Segoe UI", 12F, FontStyle.Bold);
        button.Cursor = Cursors.Hand;
        button.Paint += (_, _) =>
        {
            using var path = RoundRect(new Rectangle(0, 0, button.Width, button.Height), 12);
            button.Region = new Region(path);
        };
    }

    private static GraphicsPath RoundRect(Rectangle rect, int radius)
    {
        var r = Math.Max(4, radius);
        var d = r * 2;
        var path = new GraphicsPath();
        path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private enum StepVisual
    {
        Pending,
        Running,
        Success,
        Failed
    }
}
