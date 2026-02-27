using System.Text;

namespace OpenMeshWin;

internal sealed class OfflineImportInstallResult
{
    public string ImportContent { get; init; } = string.Empty;
    public string ProviderName { get; init; } = string.Empty;
}

internal sealed class OfflineImportInstallDialog : Form
{
    private readonly TextBox _nameTextBox = new();
    private readonly TextBox _urlTextBox = new();
    private readonly TextBox _contentTextBox = new();
    private readonly Button _fetchUrlButton = new();
    private readonly Button _pickFileButton = new();
    private readonly Button _clearButton = new();
    private readonly Button _installButton = new();
    private readonly Button _closeButton = new();

    private readonly Label _fetchingOverlayLabel = new();
    private readonly Panel _fetchingOverlay = new();

    public OfflineImportInstallResult? Result { get; private set; }

    public OfflineImportInstallDialog()
    {
        Text = "离线导入安装";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        Width = 960;
        Height = 700;
        BackColor = Color.FromArgb(219, 234, 247);

        // Add Overlay for Loading State
        _fetchingOverlay.Dock = DockStyle.Fill;
        _fetchingOverlay.BackColor = Color.FromArgb(100, 0, 0, 0); // Semi-transparent black
        _fetchingOverlay.Visible = false;
        Controls.Add(_fetchingOverlay);
        _fetchingOverlay.BringToFront();

        _fetchingOverlayLabel.AutoSize = false;
        _fetchingOverlayLabel.TextAlign = ContentAlignment.MiddleCenter;
        _fetchingOverlayLabel.Dock = DockStyle.Fill;
        _fetchingOverlayLabel.ForeColor = Color.White;
        _fetchingOverlayLabel.Font = new Font("Segoe UI Semibold", 16F, FontStyle.Bold);
        _fetchingOverlayLabel.Text = "正在从 URL 拉取内容，请耐心等待...";
        _fetchingOverlay.Controls.Add(_fetchingOverlayLabel);

        var headerPanel = new Panel
        {
            Left = 16,
            Top = 16,
            Width = ClientSize.Width - 32,
            Height = 110,
            BackColor = Color.FromArgb(236, 245, 252),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        Controls.Add(headerPanel);

        var headerTitle = new Label
        {
            Text = "离线导入安装",
            Font = new Font("Segoe UI Semibold", 22F, FontStyle.Bold),
            ForeColor = Color.FromArgb(60, 163, 227),
            Left = 18,
            Top = 18,
            Width = 360,
            Height = 40
        };
        headerPanel.Controls.Add(headerTitle);

        var hintLabel = new Label
        {
            Text = "当市场域名需要 VPN 才可访问时，可先导入 JSON/base64 或 URL 内容来安装供应商配置。",
            Font = new Font("Segoe UI", 12F, FontStyle.Regular),
            ForeColor = Color.FromArgb(84, 102, 121),
            Left = 18,
            Top = 62,
            Width = headerPanel.Width - 170,
            Height = 28,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        headerPanel.Controls.Add(hintLabel);

        _closeButton.Text = "关闭";
        _closeButton.Width = 92;
        _closeButton.Height = 42;
        _closeButton.Left = headerPanel.Width - 112;
        _closeButton.Top = 20;
        _closeButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _closeButton.FlatStyle = FlatStyle.Flat;
        _closeButton.FlatAppearance.BorderSize = 0;
        _closeButton.BackColor = Color.FromArgb(240, 196, 63);
        _closeButton.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
        _closeButton.Click += (_, _) =>
        {
            DialogResult = DialogResult.Cancel;
            Close();
        };
        headerPanel.Controls.Add(_closeButton);

        _nameTextBox.Left = 20;
        _nameTextBox.Top = 140;
        _nameTextBox.Width = ClientSize.Width - 40;
        _nameTextBox.Height = 34;
        _nameTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _nameTextBox.Font = new Font("Segoe UI", 11F, FontStyle.Regular);
        _nameTextBox.PlaceholderText = "供应商名称 (可选)";
        Controls.Add(_nameTextBox);

        _urlTextBox.Left = 20;
        _urlTextBox.Top = 184;
        _urlTextBox.Width = ClientSize.Width - 330;
        _urlTextBox.Height = 34;
        _urlTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _urlTextBox.Font = new Font("Segoe UI", 11F, FontStyle.Regular);
        _urlTextBox.PlaceholderText = "URL (可选): http:// 或 https://";
        Controls.Add(_urlTextBox);

        _fetchUrlButton.Left = _urlTextBox.Right + 12;
        _fetchUrlButton.Top = 184;
        _fetchUrlButton.Width = 140;
        _fetchUrlButton.Height = 34;
        _fetchUrlButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _fetchUrlButton.Text = "从 URL 拉取";
        _fetchUrlButton.FlatStyle = FlatStyle.Flat;
        _fetchUrlButton.FlatAppearance.BorderSize = 0;
        _fetchUrlButton.BackColor = Color.FromArgb(61, 148, 231);
        _fetchUrlButton.ForeColor = Color.White;
        _fetchUrlButton.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
        _fetchUrlButton.Click += async (_, _) => await FetchFromUrlAsync();
        Controls.Add(_fetchUrlButton);

        _pickFileButton.Left = _fetchUrlButton.Right + 8;
        _pickFileButton.Top = 184;
        _pickFileButton.Width = 110;
        _pickFileButton.Height = 34;
        _pickFileButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _pickFileButton.Text = "选择文件";
        _pickFileButton.FlatStyle = FlatStyle.Flat;
        _pickFileButton.FlatAppearance.BorderSize = 0;
        _pickFileButton.BackColor = Color.FromArgb(227, 235, 244);
        _pickFileButton.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
        _pickFileButton.Click += (_, _) => PickFile();
        Controls.Add(_pickFileButton);

        _contentTextBox.Left = 20;
        _contentTextBox.Top = 228;
        _contentTextBox.Width = ClientSize.Width - 40;
        _contentTextBox.Height = ClientSize.Height - 320;
        _contentTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _contentTextBox.Multiline = true;
        _contentTextBox.ScrollBars = ScrollBars.Vertical;
        _contentTextBox.AcceptsReturn = true;
        _contentTextBox.AcceptsTab = true;
        _contentTextBox.Font = new Font("Consolas", 10.5F, FontStyle.Regular);
        _contentTextBox.WordWrap = true;
        Controls.Add(_contentTextBox);

        _clearButton.Text = "清空";
        _clearButton.Width = 82;
        _clearButton.Height = 36;
        _clearButton.Left = 20;
        _clearButton.Top = ClientSize.Height - 54;
        _clearButton.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
        _clearButton.FlatStyle = FlatStyle.Flat;
        _clearButton.FlatAppearance.BorderSize = 0;
        _clearButton.BackColor = Color.FromArgb(227, 235, 244);
        _clearButton.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
        _clearButton.Click += (_, _) => ClearInput();
        Controls.Add(_clearButton);

        _installButton.Text = "安装导入内容";
        _installButton.Width = 162;
        _installButton.Height = 40;
        _installButton.Left = ClientSize.Width - 182;
        _installButton.Top = ClientSize.Height - 56;
        _installButton.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
        _installButton.FlatStyle = FlatStyle.Flat;
        _installButton.FlatAppearance.BorderSize = 0;
        _installButton.BackColor = Color.FromArgb(61, 148, 231);
        _installButton.ForeColor = Color.White;
        _installButton.Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold);
        _installButton.Click += (_, _) => ConfirmInstall();
        Controls.Add(_installButton);
    }

    private void SetFetchingState(bool isFetching, string message = "")
    {
        _fetchingOverlay.Visible = isFetching;
        _fetchingOverlayLabel.Text = message;
        _nameTextBox.Enabled = !isFetching;
        _urlTextBox.Enabled = !isFetching;
        _fetchUrlButton.Enabled = !isFetching;
        _pickFileButton.Enabled = !isFetching;
        _contentTextBox.Enabled = !isFetching;
        _clearButton.Enabled = !isFetching;
        _installButton.Enabled = !isFetching;
        _closeButton.Enabled = !isFetching;
        
        if (isFetching)
        {
            Cursor = Cursors.WaitCursor;
        }
        else
        {
            Cursor = Cursors.Default;
        }
    }

    private async Task FetchFromUrlAsync()
    {
        var rawUrl = _urlTextBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(rawUrl))
        {
            MessageBox.Show(this, "请先填写 URL。", "离线导入安装", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri) ||
            (!string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) &&
             !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)))
        {
            MessageBox.Show(this, "URL 必须是 http:// 或 https://。", "离线导入安装", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        SetFetchingState(true, "正在从 URL 拉取内容...");

        // Retry Logic: 3 times, 20s timeout
        int maxRetries = 3;
        string lastError = "";
        
        for (int i = 0; i < maxRetries; i++)
        {
            try
            {
                if (i > 0) SetFetchingState(true, $"正在重试 ({i}/{maxRetries})...");
                
                using var handler = new HttpClientHandler();
                // Basic SSL bypass for debug if needed, but standard logic should apply
                // handler.ServerCertificateCustomValidationCallback = ... 
                
                using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
                http.DefaultRequestHeaders.UserAgent.ParseAdd("OpenMeshWin/1.0");
                
                var payload = await http.GetStringAsync(uri);
                if (string.IsNullOrWhiteSpace(payload))
                {
                    throw new Exception("返回内容为空");
                }
                
                _contentTextBox.Text = payload;
                
                // Try to infer name from URL if empty
                if (string.IsNullOrWhiteSpace(_nameTextBox.Text))
                {
                    try
                    {
                        var segments = uri.Segments;
                        if (segments.Length > 0)
                        {
                            var last = segments.Last().Trim('/');
                            if (!string.IsNullOrWhiteSpace(last))
                            {
                                var name = Path.GetFileNameWithoutExtension(last);
                                if (!string.IsNullOrWhiteSpace(name))
                                {
                                    _nameTextBox.Text = name;
                                }
                            }
                        }
                    }
                    catch { }
                }

                SetFetchingState(false);
                return; // Success
            }
            catch (Exception ex)
            {
                lastError = ex.Message;
                // Wait a bit before retry
                await Task.Delay(1000);
            }
        }

        SetFetchingState(false);
        MessageBox.Show(this, $"URL 拉取失败 (重试 {maxRetries} 次后):\n{lastError}", "离线导入安装", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private void PickFile()
    {
        using var picker = new OpenFileDialog
        {
            Title = "选择离线导入文件",
            Filter = "JSON/Text files (*.json;*.txt)|*.json;*.txt|All files (*.*)|*.*",
            RestoreDirectory = true
        };
        if (picker.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        try
        {
            _contentTextBox.Text = File.ReadAllText(picker.FileName, Encoding.UTF8);
            if (string.IsNullOrWhiteSpace(_nameTextBox.Text))
            {
                _nameTextBox.Text = Path.GetFileNameWithoutExtension(picker.FileName);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"读取文件失败：{ex.Message}", "离线导入安装", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void ClearInput()
    {
        _urlTextBox.Text = string.Empty;
        _contentTextBox.Text = string.Empty;
    }

    private void ConfirmInstall()
    {
        var content = _contentTextBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(content))
        {
            MessageBox.Show(this, "请先粘贴/拉取导入内容。", "离线导入安装", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        Result = new OfflineImportInstallResult
        {
            ImportContent = content,
            ProviderName = _nameTextBox.Text.Trim()
        };
        DialogResult = DialogResult.OK;
        Close();
    }
}

