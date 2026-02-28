using System.Drawing.Drawing2D;

namespace OpenMeshWin;

internal sealed class ProviderInstallForm : Form
{
    private enum StepStatus
    {
        Pending,
        Running,
        Success,
        Failure
    }

    private sealed class StepState
    {
        public string Key { get; init; } = string.Empty;
        public string Title { get; init; } = string.Empty;
        public StepStatus Status { get; set; } = StepStatus.Pending;
        public string Message { get; set; } = string.Empty;
        public StepRow Row { get; set; } = null!;
    }

    private sealed class StepRow : Control
    {
        private StepStatus _status;
        private string _title = string.Empty;
        private string _message = string.Empty;

        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public StepStatus Status
        {
            get => _status;
            set { _status = value; Invalidate(); }
        }

        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public string Title
        {
            get => _title;
            set { _title = value; Invalidate(); }
        }

        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public string Message
        {
            get => _message;
            set { _message = value; Invalidate(); }
        }

        public StepRow()
        {
            DoubleBuffered = true;
            Height = 44;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            var iconRect = new Rectangle(0, 0, 20, 20);
            iconRect.X = 2;
            iconRect.Y = 12;

            DrawIcon(e.Graphics, iconRect, _status);

            var titleRect = new Rectangle(30, 6, Width - 34, 18);
            var msgRect = new Rectangle(30, 24, Width - 34, 16);

            using var titleFont = new Font("Segoe UI Semibold", 10.0F, FontStyle.Bold);
            using var msgFont = new Font("Segoe UI", 8.8F, FontStyle.Regular);

            using var titleBrush = new SolidBrush(Color.FromArgb(45, 62, 80));
            using var msgBrush = new SolidBrush(Color.FromArgb(110, 120, 130));

            e.Graphics.DrawString(_title, titleFont, titleBrush, titleRect, new StringFormat { Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap });

            if (!string.IsNullOrWhiteSpace(_message))
            {
                e.Graphics.DrawString(_message, msgFont, msgBrush, msgRect, new StringFormat { Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap });
            }
        }

        private static void DrawIcon(Graphics g, Rectangle rect, StepStatus status)
        {
            if (status == StepStatus.Pending)
            {
                using var pen = new Pen(Color.FromArgb(140, 150, 160), 2);
                g.DrawEllipse(pen, rect);
                return;
            }

            var fill = status switch
            {
                StepStatus.Running => Color.FromArgb(58, 147, 219),
                StepStatus.Success => Color.FromArgb(77, 196, 185),
                StepStatus.Failure => Color.FromArgb(224, 76, 92),
                _ => Color.FromArgb(140, 150, 160)
            };

            using (var brush = new SolidBrush(fill))
            {
                g.FillEllipse(brush, rect);
            }

            using var penWhite = new Pen(Color.White, 2);

            if (status == StepStatus.Success)
            {
                var p1 = new Point(rect.Left + 5, rect.Top + 10);
                var p2 = new Point(rect.Left + 9, rect.Top + 14);
                var p3 = new Point(rect.Left + 15, rect.Top + 6);
                g.DrawLines(penWhite, new[] { p1, p2, p3 });
            }
            else if (status == StepStatus.Failure)
            {
                g.DrawLine(penWhite, rect.Left + 6, rect.Top + 6, rect.Left + 14, rect.Top + 14);
                g.DrawLine(penWhite, rect.Left + 14, rect.Top + 6, rect.Left + 6, rect.Top + 14);
            }
            else if (status == StepStatus.Running)
            {
                using var pen = new Pen(Color.White, 2);
                g.DrawArc(pen, rect.Left + 4, rect.Top + 4, rect.Width - 8, rect.Height - 8, 30, 280);
                g.FillPolygon(Brushes.White, new[]
                {
                    new Point(rect.Right - 4, rect.Top + 9),
                    new Point(rect.Right - 6, rect.Top + 3),
                    new Point(rect.Right - 10, rect.Top + 7),
                });
            }
        }
    }

    private sealed class ManifestMeta
    {
        public string MarketUpdatedAt { get; set; } = string.Empty;
        public string MarketETag { get; set; } = string.Empty;
    }

    private readonly CoreProviderOffer _offer;
    private readonly Func<bool, IProgress<InstallProgress>, Task<bool>> _installAction;

    private readonly List<StepState> _steps;

    private readonly Panel _root = new();
    private readonly Panel _scroll = new();
    private readonly Panel _headerCard = new();
    private readonly Panel _introCard = new();
    private readonly Panel _metaCard = new();
    private readonly Panel _stepsCard = new();
    private readonly Panel _errorCard = new();
    private readonly Panel _footer = new();

    private readonly Label _title = new();
    private readonly Label _provider = new();
    private readonly Button _closeButton = new();
    private readonly Label _introText = new();
    private readonly CheckBox _selectAfterInstall = new();
    private readonly TextBox _metaText = new();
    private readonly FlowLayoutPanel _stepsFlow = new();
    private readonly Label _errorLabel = new();
    private readonly Button _copyError = new();
    private readonly Button _cancelButton = new();
    private readonly Button _primaryButton = new();
    private readonly ProgressBar _progress = new();
    private readonly Label _runningHint = new();

    private bool _isRunning;
    private bool _finished;
    private string _errorText = string.Empty;
    private string? _currentRunningStepKey;

    public bool InstallSuccess { get; private set; }
    public bool SelectAfterInstall => _selectAfterInstall.Checked;

    public ProviderInstallForm(CoreProviderOffer offer, Func<bool, IProgress<InstallProgress>, Task<bool>> installAction)
    {
        _offer = offer;
        _installAction = installAction;

        _steps = new List<StepState>
        {
            new() { Key = "fetch_detail", Title = "读取供应商详情" },
            new() { Key = "download_config", Title = "下载配置文件" },
            new() { Key = "validate_config", Title = "解析配置文件" },
            new() { Key = "download_routing_rules", Title = "下载 routing_rules.json（可选）" },
            new() { Key = "write_routing_rules", Title = "写入 routing_rules.json（可选）" },
            new() { Key = "download_rule_set", Title = "下载 rule-set（可选）" },
            new() { Key = "write_rule_set", Title = "写入 rule-set（可选）" },
            new() { Key = "write_config", Title = "写入 config.json" },
            new() { Key = "register_profile", Title = "注册到供应商列表" },
            new() { Key = "finalize", Title = "完成" }
        };

        Text = $"Install {offer.Name}";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimizeBox = true;
        MaximizeBox = true;
        Width = 720;
        Height = 640;
        MinimumSize = new Size(720, 640);
        BackColor = Color.FromArgb(219, 234, 247);

        _root.Dock = DockStyle.Fill;
        _root.Padding = new Padding(16);
        _root.BackColor = BackColor;
        Controls.Add(_root);

        ConfigureCard(_headerCard, 14);
        ConfigureCard(_introCard, 12);
        ConfigureCard(_metaCard, 12);
        ConfigureCard(_stepsCard, 12);
        ConfigureErrorCard(_errorCard);

        _headerCard.Dock = DockStyle.Top;
        _headerCard.Height = 76;
        _root.Controls.Add(_headerCard);

        _title.Text = "安装供应商";
        _title.Font = new Font("Segoe UI Semibold", 20F, FontStyle.Bold);
        _title.ForeColor = Color.FromArgb(58, 147, 219);
        _title.Location = new Point(14, 10);
        _title.Size = new Size(220, 34);
        _headerCard.Controls.Add(_title);

        _provider.Text = offer.Name;
        _provider.Font = new Font("Segoe UI Semibold", 12.5F, FontStyle.Bold);
        _provider.ForeColor = Color.FromArgb(45, 62, 80);
        _provider.Location = new Point(16, 44);
        _provider.Size = new Size(520, 24);
        _provider.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _headerCard.Controls.Add(_provider);

        _closeButton.Text = "关闭";
        _closeButton.FlatStyle = FlatStyle.Flat;
        _closeButton.FlatAppearance.BorderSize = 0;
        _closeButton.BackColor = Color.FromArgb(236, 187, 66);
        _closeButton.ForeColor = Color.Black;
        _closeButton.Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold);
        _closeButton.Size = new Size(84, 32);
        _closeButton.Location = new Point(_headerCard.Width - 98, 18);
        _closeButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _closeButton.Click += (_, _) => Close();
        _headerCard.Controls.Add(_closeButton);

        _footer.Dock = DockStyle.Bottom;
        _footer.Height = 56;
        _footer.BackColor = Color.Transparent;
        _root.Controls.Add(_footer);

        _cancelButton.Text = "取消";
        _cancelButton.FlatStyle = FlatStyle.Flat;
        _cancelButton.FlatAppearance.BorderSize = 0;
        _cancelButton.BackColor = Color.FromArgb(236, 245, 252);
        _cancelButton.ForeColor = Color.FromArgb(45, 62, 80);
        _cancelButton.Font = new Font("Segoe UI", 10F);
        _cancelButton.Size = new Size(86, 34);
        _cancelButton.Location = new Point(0, 12);
        _cancelButton.Click += (_, _) => Close();
        _footer.Controls.Add(_cancelButton);

        _primaryButton.Text = "开始安装";
        _primaryButton.FlatStyle = FlatStyle.Flat;
        _primaryButton.FlatAppearance.BorderSize = 0;
        _primaryButton.BackColor = Color.FromArgb(58, 147, 219);
        _primaryButton.ForeColor = Color.White;
        _primaryButton.Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold);
        _primaryButton.Size = new Size(96, 34);
        _primaryButton.Location = new Point(_footer.Width - 96, 12);
        _primaryButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _primaryButton.Click += async (_, _) =>
        {
            if (_finished) Close();
            else if (!_isRunning) await RunInstallAsync();
        };
        _footer.Controls.Add(_primaryButton);

        _progress.Style = ProgressBarStyle.Marquee;
        _progress.MarqueeAnimationSpeed = 25;
        _progress.Visible = false;
        _progress.Size = new Size(120, 16);
        _progress.Location = new Point(_footer.Width - 96 - 140, 20);
        _progress.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _footer.Controls.Add(_progress);

        _runningHint.Visible = false;
        _runningHint.Font = new Font("Segoe UI", 9F);
        _runningHint.ForeColor = Color.FromArgb(95, 113, 132);
        _runningHint.AutoEllipsis = true;
        _runningHint.TextAlign = ContentAlignment.MiddleRight;
        _runningHint.Size = new Size(360, 18);
        _runningHint.Location = new Point(_footer.Width - 96 - 140 - 372, 18);
        _runningHint.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _footer.Controls.Add(_runningHint);

        _scroll.Dock = DockStyle.Fill;
        _scroll.AutoScroll = true;
        _scroll.BackColor = Color.Transparent;
        _scroll.Padding = new Padding(0, 12, 0, 0);
        _root.Controls.Add(_scroll);

        _introCard.Width = _root.ClientSize.Width - 0;
        _introCard.Height = 92;
        _introCard.Location = new Point(0, 0);
        _introCard.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _scroll.Controls.Add(_introCard);

        _introText.Text = "此安装向导会把供应商配置落盘并做基础自检。若该供应商声明了 rule-set，会尝试在安装阶段下载；若 URL 在当前网络不可达，将在首次连接后自动初始化（无需弹窗）。";
        _introText.Font = new Font("Segoe UI", 10F);
        _introText.ForeColor = Color.FromArgb(84, 102, 121);
        _introText.Location = new Point(14, 12);
        _introText.Size = new Size(_introCard.Width - 28, 44);
        _introText.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _introText.AutoEllipsis = true;
        _introCard.Controls.Add(_introText);

        _selectAfterInstall.Text = "安装完成后切换到该供应商";
        _selectAfterInstall.Checked = true;
        _selectAfterInstall.Font = new Font("Segoe UI", 10F);
        _selectAfterInstall.ForeColor = Color.FromArgb(45, 62, 80);
        _selectAfterInstall.Location = new Point(14, 58);
        _selectAfterInstall.Size = new Size(_introCard.Width - 28, 24);
        _selectAfterInstall.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _introCard.Controls.Add(_selectAfterInstall);

        _metaCard.Width = _root.ClientSize.Width - 0;
        _metaCard.Height = 170;
        _metaCard.Location = new Point(0, _introCard.Bottom + 12);
        _metaCard.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _scroll.Controls.Add(_metaCard);

        var metaTitle = new Label
        {
            Text = "元数据",
            Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold),
            ForeColor = Color.FromArgb(95, 113, 132),
            Location = new Point(14, 10),
            Size = new Size(120, 20)
        };
        _metaCard.Controls.Add(metaTitle);

        _metaText.Multiline = true;
        _metaText.ReadOnly = true;
        _metaText.BorderStyle = BorderStyle.None;
        _metaText.BackColor = _metaCard.BackColor;
        _metaText.Font = new Font("Consolas", 9F);
        _metaText.ForeColor = Color.FromArgb(45, 62, 80);
        _metaText.Location = new Point(14, 34);
        _metaText.Size = new Size(_metaCard.Width - 28, _metaCard.Height - 44);
        _metaText.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        _metaText.ScrollBars = ScrollBars.None;
        _metaText.Text = BuildMetaText();
        _metaCard.Controls.Add(_metaText);

        _stepsCard.Width = _root.ClientSize.Width - 0;
        _stepsCard.Height = 320;
        _stepsCard.Location = new Point(0, _metaCard.Bottom + 12);
        _stepsCard.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _scroll.Controls.Add(_stepsCard);

        var stepsTitle = new Label
        {
            Text = "安装步骤",
            Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold),
            ForeColor = Color.FromArgb(95, 113, 132),
            Location = new Point(14, 10),
            Size = new Size(120, 20)
        };
        _stepsCard.Controls.Add(stepsTitle);

        _stepsFlow.Location = new Point(14, 34);
        _stepsFlow.Size = new Size(_stepsCard.Width - 28, _stepsCard.Height - 44);
        _stepsFlow.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
        _stepsFlow.FlowDirection = FlowDirection.TopDown;
        _stepsFlow.WrapContents = false;
        _stepsFlow.AutoScroll = true;
        _stepsFlow.Padding = new Padding(0);
        _stepsFlow.BackColor = _stepsCard.BackColor;
        _stepsCard.Controls.Add(_stepsFlow);

        foreach (var step in _steps)
        {
            var row = new StepRow
            {
                Title = step.Title,
                Status = StepStatus.Pending,
                Width = _stepsFlow.ClientSize.Width - 22
            };
            step.Row = row;
            _stepsFlow.Controls.Add(row);
        }

        _errorCard.Width = _root.ClientSize.Width - 0;
        _errorCard.Height = 64;
        _errorCard.Location = new Point(0, _stepsCard.Bottom + 12);
        _errorCard.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _errorCard.Visible = false;
        _scroll.Controls.Add(_errorCard);

        _errorLabel.Font = new Font("Segoe UI", 9.2F);
        _errorLabel.ForeColor = Color.FromArgb(224, 76, 92);
        _errorLabel.Location = new Point(34, 12);
        _errorLabel.Size = new Size(_errorCard.Width - 120, 40);
        _errorLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _errorLabel.AutoEllipsis = true;
        _errorCard.Controls.Add(_errorLabel);

        _copyError.Text = "复制";
        _copyError.FlatStyle = FlatStyle.Flat;
        _copyError.FlatAppearance.BorderSize = 0;
        _copyError.BackColor = Color.FromArgb(236, 245, 252);
        _copyError.ForeColor = Color.FromArgb(45, 62, 80);
        _copyError.Font = new Font("Segoe UI", 9F);
        _copyError.Size = new Size(70, 30);
        _copyError.Location = new Point(_errorCard.Width - 84, 16);
        _copyError.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _copyError.Click += (_, _) => { if (!string.IsNullOrWhiteSpace(_errorText)) Clipboard.SetText(_errorText); };
        _errorCard.Controls.Add(_copyError);

        _headerCard.Resize += (_, _) => { _provider.Width = _headerCard.Width - 140; };
        _metaCard.Resize += (_, _) => { _metaText.Width = _metaCard.Width - 28; _metaText.Height = _metaCard.Height - 44; };
        _stepsCard.Resize += (_, _) => { _stepsFlow.Width = _stepsCard.Width - 28; _stepsFlow.Height = _stepsCard.Height - 44; ResizeStepRows(); };
        _errorCard.Resize += (_, _) => { _errorLabel.Width = _errorCard.Width - 120; _copyError.Left = _errorCard.Width - 84; };

        Shown += (_, _) => UpdateButtons();
    }

    private static void ConfigureCard(Panel card, int radius)
    {
        card.BackColor = Color.FromArgb(236, 245, 252);
        card.Padding = new Padding(0);
        card.Paint += (_, e) =>
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var path = GetRoundedPath(new Rectangle(0, 0, card.Width - 1, card.Height - 1), radius);
            using var pen = new Pen(Color.FromArgb(210, 225, 238), 1);
            e.Graphics.DrawPath(pen, path);
        };
    }

    private static void ConfigureErrorCard(Panel card)
    {
        card.BackColor = Color.FromArgb(252, 228, 233);
        card.Padding = new Padding(0);
        card.Paint += (_, e) =>
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var path = GetRoundedPath(new Rectangle(0, 0, card.Width - 1, card.Height - 1), 12);
            using var pen = new Pen(Color.FromArgb(228, 146, 156), 1);
            e.Graphics.DrawPath(pen, path);
            using var brush = new SolidBrush(Color.FromArgb(224, 76, 92));
            e.Graphics.FillPolygon(brush, new[]
            {
                new Point(16, 14),
                new Point(26, 34),
                new Point(6, 34)
            });
            using var p = new Pen(Color.White, 2);
            e.Graphics.DrawLine(p, 16, 22, 16, 28);
            e.Graphics.FillEllipse(Brushes.White, 15, 30, 2, 2);
        };
    }

    private static GraphicsPath GetRoundedPath(Rectangle bounds, int radius)
    {
        int d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private string BuildMetaText()
    {
        var localHash = InstalledProviderManager.Instance.GetLocalPackageHash(_offer.Id);
        var pending = InstalledProviderManager.Instance.GetPendingRuleSets(_offer.Id);
        var manifest = MarketManifestCache.Instance.GetSnapshot();

        string pendingText = pending.Count == 0 ? "-" : string.Join(", ", pending);
        string updatedAt = string.IsNullOrWhiteSpace(manifest.UpdatedAt) ? "-" : manifest.UpdatedAt;
        string etag = string.IsNullOrWhiteSpace(manifest.ETag) ? "-" : manifest.ETag;

        return string.Join(Environment.NewLine, new[]
        {
            $"provider_id: {_offer.Id}",
            "provider_hash: -",
            $"package_hash: {(string.IsNullOrWhiteSpace(_offer.PackageHash) ? "-" : _offer.PackageHash)}",
            $"local_installed_package_hash: {(string.IsNullOrWhiteSpace(localHash) ? "-" : localHash)}",
            $"pending_rule_sets: {pendingText}",
            $"market_updated_at: {updatedAt}",
            $"market_etag: {etag}"
        });
    }

    private void ResizeStepRows()
    {
        foreach (var s in _steps)
        {
            s.Row.Width = _stepsFlow.ClientSize.Width - 22;
        }
    }

    private void UpdateButtons()
    {
        _closeButton.Enabled = !_isRunning;
        _cancelButton.Enabled = !_isRunning;
        _selectAfterInstall.Enabled = !_isRunning && !_finished;

        if (_finished)
        {
            _progress.Visible = false;
            _runningHint.Visible = false;
            _primaryButton.Visible = true;
            _primaryButton.Text = "完成";
            _primaryButton.BackColor = Color.FromArgb(58, 147, 219);
            return;
        }

        if (_isRunning)
        {
            _primaryButton.Visible = false;
            _progress.Visible = true;
            _runningHint.Visible = true;
            return;
        }

        _progress.Visible = false;
        _runningHint.Visible = false;
        _primaryButton.Visible = true;
        _primaryButton.Text = string.IsNullOrWhiteSpace(_errorText) ? "开始安装" : "重试";
        _primaryButton.BackColor = Color.FromArgb(58, 147, 219);
    }

    private async Task RunInstallAsync()
    {
        if (_isRunning) return;

        _errorText = string.Empty;
        _errorCard.Visible = false;
        _finished = false;
        _isRunning = true;
        _currentRunningStepKey = null;
        InstallSuccess = false;

        foreach (var s in _steps)
        {
            s.Status = StepStatus.Pending;
            s.Message = string.Empty;
            s.Row.Status = StepStatus.Pending;
            s.Row.Message = string.Empty;
        }

        UpdateButtons();

        try
        {
            var progress = new Progress<InstallProgress>(p =>
            {
                UpdateProgress(p.Step, p.Message);
            });

            InstallSuccess = await _installAction(_selectAfterInstall.Checked, progress);
            if (!InstallSuccess)
            {
                throw new Exception("安装返回失败");
            }

            var runningIndex = _steps.FindIndex(x => x.Status == StepStatus.Running);
            if (runningIndex >= 0)
            {
                _steps[runningIndex].Status = StepStatus.Success;
                _steps[runningIndex].Row.Status = StepStatus.Success;
            }

            var finalize = _steps.FirstOrDefault(x => x.Key == "finalize");
            if (finalize != null)
            {
                finalize.Status = StepStatus.Success;
                finalize.Row.Status = StepStatus.Success;
                finalize.Message = "完成";
                finalize.Row.Message = "完成";
            }

            _metaText.Text = BuildMetaText();
            _finished = true;
        }
        catch (Exception ex)
        {
            InstallSuccess = false;
            var msg = ex.Message;
            MarkFailure(msg);
        }
        finally
        {
            _isRunning = false;
            UpdateButtons();
        }
    }

    private void UpdateProgress(string stepKey, string message)
    {
        if (InvokeRequired)
        {
            Invoke(new Action<string, string>(UpdateProgress), stepKey, message);
            return;
        }

        if (_currentRunningStepKey != stepKey)
        {
            var running = _steps.FirstOrDefault(s => s.Status == StepStatus.Running);
            if (running != null)
            {
                running.Status = StepStatus.Success;
                running.Row.Status = StepStatus.Success;
            }
            _currentRunningStepKey = stepKey;
        }

        var current = _steps.FirstOrDefault(s => s.Key == stepKey);
        if (current == null)
        {
            _runningHint.Text = message;
            return;
        }

        current.Status = StepStatus.Running;
        current.Message = message;
        current.Row.Status = StepStatus.Running;
        current.Row.Message = message;

        if (!string.IsNullOrWhiteSpace(message) && message.StartsWith("跳过", StringComparison.OrdinalIgnoreCase))
        {
            current.Status = StepStatus.Success;
            current.Row.Status = StepStatus.Success;
        }

        _runningHint.Text = message.Length > 0 ? message : $"正在执行：{current.Title}…";
    }

    private void MarkFailure(string message)
    {
        if (InvokeRequired)
        {
            Invoke(new Action<string>(MarkFailure), message);
            return;
        }

        _errorText = $"安装失败：{message}";
        _errorLabel.Text = _errorText;
        _errorCard.Visible = true;

        var running = _steps.FirstOrDefault(s => s.Status == StepStatus.Running);
        if (running != null)
        {
            running.Status = StepStatus.Failure;
            running.Row.Status = StepStatus.Failure;
            running.Message = message;
            running.Row.Message = message;
        }
        else
        {
            var firstPending = _steps.FirstOrDefault(s => s.Status == StepStatus.Pending);
            if (firstPending != null)
            {
                firstPending.Status = StepStatus.Failure;
                firstPending.Row.Status = StepStatus.Failure;
                firstPending.Message = message;
                firstPending.Row.Message = message;
            }
        }

        UpdateButtons();
    }
}
