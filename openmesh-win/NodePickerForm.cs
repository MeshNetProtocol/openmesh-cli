using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Net.Sockets;

namespace OpenMeshWin;

internal sealed class NodePickerForm : Form
{
    private sealed class NodeItem
    {
        public string Tag { get; init; } = string.Empty;
        public string Address { get; set; } = string.Empty;
        public int DelayMs { get; set; }
        public bool Selected { get; set; }
    }

    private sealed class DotIndicator : Control
    {
        private bool _selected;

        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public bool Selected
        {
            get => _selected;
            set { _selected = value; Invalidate(); }
        }

        public DotIndicator()
        {
            DoubleBuffered = true;
            Size = new Size(18, 18);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(1, 1, Width - 2, Height - 2);
            using var pen = new Pen(Color.FromArgb(140, 150, 160), 2);
            e.Graphics.DrawEllipse(pen, rect);
            if (Selected)
            {
                using var brush = new SolidBrush(Color.FromArgb(58, 147, 219));
                var inner = new Rectangle(rect.X + 5, rect.Y + 5, rect.Width - 10, rect.Height - 10);
                e.Graphics.FillEllipse(brush, inner);
            }
        }
    }

    private readonly ICoreClient _coreClient;
    private readonly Func<bool> _isConnected;
    private readonly long _profileId;
    private readonly string _providerName;
    private readonly NodeProfileMetadata _meta;
    private List<CoreOutboundGroup> _groups;
    private Dictionary<string, int> _delays;

    private string _groupTag;
    private readonly List<NodeItem> _nodes = new();

    private readonly Panel _root = new();
    private readonly MeshCardPanel _headerCard = new();
    private readonly MeshCardPanel _listCard = new();
    private readonly MeshCardPanel _hintCard = new();

    private readonly Label _titleLabel = new();
    private readonly Label _subtitleLabel = new();
    private readonly Button _closeButton = new();
    private readonly Button _testAllButton = new();
    private readonly Label _hintLabel = new();
    private readonly FlowLayoutPanel _list = new();

    private bool _testingAll;
    private bool _applying;
    private string _testingNode = string.Empty;

    public NodePickerForm(
        ICoreClient coreClient,
        Func<bool> isConnected,
        long profileId,
        string providerName,
        string groupTag,
        List<CoreOutboundGroup> groups,
        Dictionary<string, int> delays,
        NodeProfileMetadata meta)
    {
        _coreClient = coreClient;
        _isConnected = isConnected;
        _profileId = profileId;
        _providerName = providerName;
        _groupTag = groupTag ?? string.Empty;
        _groups = groups ?? [];
        _delays = delays ?? new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        _meta = meta ?? new NodeProfileMetadata();

        Text = "节点";
        StartPosition = FormStartPosition.CenterParent;
        Width = 760;
        Height = 640;
        MinimumSize = new Size(720, 640);
        BackColor = Color.FromArgb(219, 234, 247);

        _root.Dock = DockStyle.Fill;
        _root.Padding = new Padding(16);
        _root.BackColor = BackColor;
        Controls.Add(_root);

        ConfigureCard(_headerCard, 14);
        ConfigureCard(_listCard, 14);
        ConfigureHintCard(_hintCard);

        _headerCard.Dock = DockStyle.Top;
        _headerCard.Height = 84;
        _root.Controls.Add(_headerCard);

        _titleLabel.Text = "节点列表";
        _titleLabel.Font = new Font("Segoe UI Semibold", 20F, FontStyle.Bold);
        _titleLabel.ForeColor = Color.FromArgb(58, 147, 219);
        _titleLabel.Location = new Point(14, 12);
        _titleLabel.Size = new Size(200, 34);
        _headerCard.Controls.Add(_titleLabel);

        _subtitleLabel.Text = $"供应商：{_providerName}";
        _subtitleLabel.Font = new Font("Segoe UI", 10.5F, FontStyle.Regular);
        _subtitleLabel.ForeColor = Color.FromArgb(84, 102, 121);
        _subtitleLabel.Location = new Point(16, 48);
        _subtitleLabel.Size = new Size(520, 22);
        _subtitleLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _headerCard.Controls.Add(_subtitleLabel);

        _closeButton.Text = "关闭";
        _closeButton.FlatStyle = FlatStyle.Flat;
        _closeButton.FlatAppearance.BorderSize = 0;
        _closeButton.BackColor = Color.FromArgb(236, 187, 66);
        _closeButton.ForeColor = Color.Black;
        _closeButton.Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold);
        _closeButton.Size = new Size(84, 32);
        _closeButton.Location = new Point(_headerCard.Width - 98, 16);
        _closeButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _closeButton.Click += (_, _) => Close();
        _headerCard.Controls.Add(_closeButton);

        _testAllButton.Text = "全部测速";
        _testAllButton.FlatStyle = FlatStyle.Flat;
        _testAllButton.FlatAppearance.BorderSize = 0;
        _testAllButton.BackColor = Color.FromArgb(167, 210, 252);
        _testAllButton.ForeColor = Color.FromArgb(40, 106, 196);
        _testAllButton.Font = new Font("Segoe UI Semibold", 9.2F, FontStyle.Bold);
        _testAllButton.Size = new Size(100, 30);
        _testAllButton.Location = new Point(_headerCard.Width - 210, 16);
        _testAllButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _testAllButton.Click += async (_, _) => await RunTestAllAsync();
        _headerCard.Controls.Add(_testAllButton);

        _hintCard.Dock = DockStyle.Top;
        _hintCard.Height = 42;
        _hintCard.Visible = false;
        _root.Controls.Add(_hintCard);

        _hintLabel.Text = "当前未连接 VPN，可查看节点列表，但无法测速或切换。";
        _hintLabel.Font = new Font("Segoe UI", 9.2F, FontStyle.Regular);
        _hintLabel.ForeColor = Color.FromArgb(130, 90, 32);
        _hintLabel.Location = new Point(12, 12);
        _hintLabel.Size = new Size(_hintCard.Width - 24, 20);
        _hintLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        _hintCard.Controls.Add(_hintLabel);

        _listCard.Dock = DockStyle.Fill;
        _root.Controls.Add(_listCard);

        _list.Dock = DockStyle.Fill;
        _list.FlowDirection = FlowDirection.TopDown;
        _list.WrapContents = false;
        _list.AutoScroll = true;
        _list.BackColor = _listCard.BackColor;
        _list.Padding = new Padding(12);
        _listCard.Controls.Add(_list);

        Shown += (_, _) =>
        {
            EnsureGroupTag();
            RefreshNodesFromState();
            RefreshConnectedGate();
        };
    }

    public void UpdateLiveState(List<CoreOutboundGroup> groups, Dictionary<string, int> delays)
    {
        _groups = groups ?? [];
        _delays = delays ?? new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        EnsureGroupTag();
        RefreshNodesFromState();
        RefreshConnectedGate();
    }

    private void EnsureGroupTag()
    {
        if (!string.IsNullOrWhiteSpace(_groupTag) && _groups.Any(g => string.Equals(g.Tag, _groupTag, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        if (_groups.Any(g => string.Equals(g.Tag, "proxy", StringComparison.OrdinalIgnoreCase))) { _groupTag = "proxy"; return; }
        if (_groups.Any(g => string.Equals(g.Tag, "auto", StringComparison.OrdinalIgnoreCase))) { _groupTag = "auto"; return; }
        var firstSelectable = _groups.FirstOrDefault(g => g.Selectable);
        if (firstSelectable != null) { _groupTag = firstSelectable.Tag; return; }
        var first = _groups.FirstOrDefault();
        if (first != null) { _groupTag = first.Tag; return; }
        var offline = _meta.PickPreferredGroupTag();
        if (!string.IsNullOrWhiteSpace(offline)) { _groupTag = offline; }
    }

    private void RefreshConnectedGate()
    {
        var connected = _isConnected();
        _hintCard.Visible = !connected;
        _testAllButton.Enabled = connected && !_testingAll && !_applying;
    }

    private void RefreshNodesFromState()
    {
        _nodes.Clear();

        var connected = _isConnected();
        var liveGroup = _groups.FirstOrDefault(g => string.Equals(g.Tag, _groupTag, StringComparison.OrdinalIgnoreCase));
        var selectedOutbound = string.Empty;
        if (liveGroup != null)
        {
            selectedOutbound = liveGroup.Selected ?? string.Empty;
            foreach (var it in liveGroup.Items ?? [])
            {
                var tag = it.Tag ?? string.Empty;
                if (tag.Length == 0) continue;
                var address = _meta.OutboundAddressByTag.TryGetValue(tag, out var addr) ? addr : string.Empty;
                var delay = it.UrlTestDelay;
                if (delay <= 0 && _delays.TryGetValue(tag, out var d2)) delay = d2;
                _nodes.Add(new NodeItem
                {
                    Tag = tag,
                    Address = address,
                    DelayMs = delay,
                    Selected = string.Equals(tag, selectedOutbound, StringComparison.OrdinalIgnoreCase)
                });
            }
        }
        else if (_meta.GroupOutboundsByTag.TryGetValue(_groupTag, out var outbounds))
        {
            _meta.GroupDefaultOutboundByTag.TryGetValue(_groupTag, out selectedOutbound);
            var stored = SelectedOutboundStore.Instance.Get(_profileId);
            if (stored != null && string.Equals(stored.GroupTag, _groupTag, StringComparison.OrdinalIgnoreCase))
            {
                selectedOutbound = stored.OutboundTag;
            }

            foreach (var tag in outbounds)
            {
                var address = _meta.OutboundAddressByTag.TryGetValue(tag, out var addr) ? addr : string.Empty;
                var delay = _delays.TryGetValue(tag, out var d) ? d : 0;
                _nodes.Add(new NodeItem
                {
                    Tag = tag,
                    Address = address,
                    DelayMs = delay,
                    Selected = !string.IsNullOrWhiteSpace(selectedOutbound) && string.Equals(tag, selectedOutbound, StringComparison.OrdinalIgnoreCase)
                });
            }
        }

        if (_nodes.Count == 0)
        {
            _list.Controls.Clear();
            var empty = new Label
            {
                Text = "暂无节点数据",
                ForeColor = Color.FromArgb(84, 102, 121),
                Font = new Font("Segoe UI", 10F, FontStyle.Regular),
                AutoSize = true
            };
            _list.Controls.Add(empty);
            return;
        }

        if (_nodes.All(n => !n.Selected))
        {
            var first = _nodes[0];
            first.Selected = true;
        }

        _list.SuspendLayout();
        _list.Controls.Clear();
        foreach (var node in _nodes)
        {
            _list.Controls.Add(BuildNodeRow(node, connected));
        }
        _list.ResumeLayout();
    }

    private Control BuildNodeRow(NodeItem node, bool connected)
    {
        var card = new MeshCardPanel
        {
            Width = Math.Max(520, _list.ClientSize.Width - 22),
            Height = 58,
            BackColor = Color.FromArgb(244, 250, 255),
            BorderColor = Color.FromArgb(205, 224, 240),
            CornerRadius = 14,
            Margin = new Padding(0, 0, 0, 10)
        };

        var indicator = new DotIndicator
        {
            Selected = node.Selected,
            Location = new Point(14, 20)
        };
        card.Controls.Add(indicator);

        var nameLabel = new Label
        {
            Text = node.Tag,
            Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold),
            ForeColor = Color.FromArgb(45, 62, 80),
            AutoEllipsis = true,
            Location = new Point(40, 12),
            Size = new Size(card.Width - 220, 18),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        card.Controls.Add(nameLabel);

        var activeBadge = new Label
        {
            Text = "ACTIVE",
            Visible = node.Selected,
            BackColor = Color.FromArgb(212, 238, 246),
            ForeColor = Color.FromArgb(40, 106, 196),
            Font = new Font("Segoe UI Semibold", 7.8F, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(40 + TextRenderer.MeasureText(node.Tag, nameLabel.Font).Width + 8, 12),
            Size = new Size(52, 16)
        };
        ApplyRoundedRegion(activeBadge, 8);
        card.Controls.Add(activeBadge);

        var addressText = string.IsNullOrWhiteSpace(node.Address) ? "-" : node.Address;
        var addrLabel = new Label
        {
            Text = $"IP  {addressText}",
            Font = new Font("Segoe UI", 8.7F, FontStyle.Regular),
            ForeColor = Color.FromArgb(84, 102, 121),
            AutoEllipsis = true,
            Location = new Point(40, 32),
            Size = new Size(card.Width - 220, 18),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        card.Controls.Add(addrLabel);

        var delayLabel = new Label
        {
            Text = node.DelayMs > 0 ? $"{node.DelayMs} ms" : "",
            Font = new Font("Segoe UI Semibold", 9F, FontStyle.Bold),
            ForeColor = DelayColor(node.DelayMs),
            TextAlign = ContentAlignment.MiddleRight,
            Location = new Point(card.Width - 170, 18),
            Size = new Size(70, 20),
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        card.Controls.Add(delayLabel);

        var testButton = new Button
        {
            Text = "Test",
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(236, 245, 252),
            ForeColor = Color.FromArgb(40, 106, 196),
            Font = new Font("Segoe UI Semibold", 9F, FontStyle.Bold),
            Size = new Size(44, 28),
            Location = new Point(card.Width - 90, 16),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            Enabled = connected && !_testingAll && !_applying
        };
        testButton.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(testButton, 14);
        testButton.Click += async (_, _) => await RunTestOneAsync(node.Tag);
        card.Controls.Add(testButton);

        var actionButton = new Button
        {
            Text = "›",
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(236, 245, 252),
            ForeColor = Color.FromArgb(45, 62, 80),
            Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold),
            Size = new Size(32, 28),
            Location = new Point(card.Width - 42, 16),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            Enabled = connected && !_testingAll && !_applying && !node.Selected
        };
        actionButton.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(actionButton, 14);
        actionButton.Click += async (_, _) => await SelectNodeAsync(node.Tag);
        card.Controls.Add(actionButton);

        void clickHandler(object? _, EventArgs __) { _ = SelectNodeAsync(node.Tag); }
        if (connected)
        {
            card.Cursor = Cursors.Hand;
            card.Click += clickHandler;
            nameLabel.Click += clickHandler;
            addrLabel.Click += clickHandler;
        }

        card.Resize += (_, _) =>
        {
            nameLabel.Width = Math.Max(60, card.Width - 220);
            addrLabel.Width = Math.Max(60, card.Width - 220);
            delayLabel.Left = card.Width - 170;
            testButton.Left = card.Width - 90;
            actionButton.Left = card.Width - 42;
        };

        return card;
    }

    private async Task RunTestAllAsync()
    {
        if (!_isConnected())
        {
            MessageBox.Show(this, "请先连接 VPN。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            RefreshConnectedGate();
            return;
        }

        if (_testingAll || _applying) return;
        if (string.IsNullOrWhiteSpace(_groupTag))
        {
            MessageBox.Show(this, "未找到可测速的出站组。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        _testingAll = true;
        _testAllButton.Text = "测速中…";
        RefreshConnectedGate();

        try
        {
            var resp = await _coreClient.UrlTestAsync(_groupTag);
            if (resp.Ok)
            {
                _delays = resp.Delays ?? new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                UpdateNodeDelays();
            }
            else
            {
                if (!await TryFallbackTcpTestAsync(resp.Message))
                {
                    MessageBox.Show(this, resp.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }
        catch (Exception ex)
        {
            if (!await TryFallbackTcpTestAsync(ex.Message))
            {
                MessageBox.Show(this, ex.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
        finally
        {
            _testingAll = false;
            _testAllButton.Text = "全部测速";
            RefreshConnectedGate();
            RefreshNodesFromState();
        }
    }

    private async Task RunTestOneAsync(string nodeTag)
    {
        if (!_isConnected())
        {
            MessageBox.Show(this, "请先连接 VPN。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            RefreshConnectedGate();
            return;
        }

        if (_testingAll || _applying) return;
        _testingNode = nodeTag ?? string.Empty;
        _testingAll = true;
        _testAllButton.Text = "测速中…";
        RefreshConnectedGate();

        try
        {
            var resp = await _coreClient.UrlTestAsync(_groupTag);
            if (resp.Ok)
            {
                _delays = resp.Delays ?? new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                UpdateNodeDelays();
            }
            else
            {
                if (!await TryFallbackTcpTestAsync(resp.Message, onlyNodeTag: _testingNode))
                {
                    MessageBox.Show(this, resp.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }
        catch (Exception ex)
        {
            if (!await TryFallbackTcpTestAsync(ex.Message, onlyNodeTag: _testingNode))
            {
                MessageBox.Show(this, ex.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
        finally
        {
            _testingAll = false;
            _testAllButton.Text = "全部测速";
            _testingNode = string.Empty;
            RefreshConnectedGate();
            RefreshNodesFromState();
        }
    }

    private void UpdateNodeDelays()
    {
        foreach (var n in _nodes)
        {
            if (_delays.TryGetValue(n.Tag, out var d))
            {
                n.DelayMs = d;
            }
        }
    }

    private async Task SelectNodeAsync(string outboundTag)
    {
        if (!_isConnected())
        {
            MessageBox.Show(this, "请先连接 VPN。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            RefreshConnectedGate();
            return;
        }

        if (_testingAll || _applying) return;
        if (string.IsNullOrWhiteSpace(_groupTag) || string.IsNullOrWhiteSpace(outboundTag)) return;

        if (_nodes.Any(n => n.Selected && string.Equals(n.Tag, outboundTag, StringComparison.OrdinalIgnoreCase))) return;

        _applying = true;
        RefreshConnectedGate();

        try
        {
            var resp = await _coreClient.SelectOutboundAsync(_groupTag, outboundTag);
            if (!resp.Ok)
            {
                MessageBox.Show(this, resp.Message, "切换失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            foreach (var n in _nodes)
            {
                n.Selected = string.Equals(n.Tag, outboundTag, StringComparison.OrdinalIgnoreCase);
            }

            SelectedOutboundStore.Instance.Set(_profileId, _groupTag, outboundTag);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "切换失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        finally
        {
            _applying = false;
            RefreshConnectedGate();
            RefreshNodesFromState();
        }
    }

    private static Color DelayColor(int ms)
    {
        if (ms <= 0) return Color.FromArgb(84, 102, 121);
        if (ms < 120) return Color.FromArgb(60, 199, 128);
        if (ms < 300) return Color.FromArgb(236, 187, 66);
        return Color.FromArgb(224, 76, 92);
    }

    private static void ConfigureCard(Panel card, int radius)
    {
        card.BackColor = Color.FromArgb(236, 245, 252);
        if (card is MeshCardPanel meshCard)
        {
            meshCard.BorderColor = Color.FromArgb(205, 224, 240);
            meshCard.CornerRadius = radius;
        }
    }

    private static void ConfigureHintCard(Panel card)
    {
        card.BackColor = Color.FromArgb(252, 242, 218);
        if (card is MeshCardPanel meshCard)
        {
            meshCard.BorderColor = Color.FromArgb(236, 208, 126);
            meshCard.CornerRadius = 12;
        }
    }

    private static void ApplyRoundedRegion(Control control, int radius)
    {
        var rect = new Rectangle(0, 0, Math.Max(1, control.Width), Math.Max(1, control.Height));
        using var path = CreateRoundedPath(rect, Math.Max(2, radius));
        control.Region = new Region(path);
    }

    private static GraphicsPath CreateRoundedPath(Rectangle rect, int radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private async Task<bool> TryFallbackTcpTestAsync(string message, string? onlyNodeTag = null)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return false;
        }

        var msg = message.Trim();
        if (msg.IndexOf("unsupported action", StringComparison.OrdinalIgnoreCase) < 0)
        {
            return false;
        }

        var targets = _nodes
            .Where(n => string.IsNullOrWhiteSpace(onlyNodeTag) || string.Equals(n.Tag, onlyNodeTag, StringComparison.OrdinalIgnoreCase))
            .Select(n => (n.Tag, n.Address))
            .Where(x => !string.IsNullOrWhiteSpace(x.Address))
            .ToList();

        if (targets.Count == 0)
        {
            return false;
        }

        var result = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        using var semaphore = new SemaphoreSlim(6);
        var tasks = targets.Select(async t =>
        {
            await semaphore.WaitAsync();
            try
            {
                var ms = await ProbeTcpDelayAsync(t.Address!, timeoutMs: 2500);
                lock (result)
                {
                    result[t.Tag] = ms;
                }
            }
            finally
            {
                semaphore.Release();
            }
        }).ToList();

        await Task.WhenAll(tasks);

        if (result.Count == 0)
        {
            return false;
        }

        _delays = result;
        UpdateNodeDelays();
        return true;
    }

    private static async Task<int> ProbeTcpDelayAsync(string address, int timeoutMs)
    {
        if (string.IsNullOrWhiteSpace(address))
        {
            return 0;
        }

        string host = address;
        int port = 0;

        var idx = address.LastIndexOf(':');
        if (idx > 0 && idx < address.Length - 1)
        {
            host = address.Substring(0, idx);
            var portStr = address.Substring(idx + 1);
            if (!int.TryParse(portStr, out port))
            {
                port = 0;
            }
        }

        if (string.IsNullOrWhiteSpace(host) || port <= 0 || port > 65535)
        {
            return 0;
        }

        var sw = Stopwatch.StartNew();
        using var client = new TcpClient();
        var connectTask = client.ConnectAsync(host, port);
        var completed = await Task.WhenAny(connectTask, Task.Delay(timeoutMs));
        if (completed != connectTask)
        {
            return 0;
        }

        await connectTask;
        sw.Stop();
        return (int)Math.Clamp(sw.ElapsedMilliseconds, 1, 5000);
    }
}
