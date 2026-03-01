using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Text.Json;

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
    private readonly string _profilePath;
    private List<CoreOutboundGroup> _groups;
    private Dictionary<string, int> _delays;
    private readonly List<string> _profileNodeOrder = [];
    private readonly Dictionary<string, string> _profileAddressByTag = new(StringComparer.OrdinalIgnoreCase);
    private string _profileDefaultNode = string.Empty;
    private string _profileGroupTag = string.Empty;

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
    private readonly Panel _list = new();

    private bool _testingAll;
    private bool _applying;
    private string _testingNode = string.Empty;

    public NodePickerForm(
        ICoreClient coreClient,
        Func<bool> isConnected,
        long profileId,
        string providerName,
        string profilePath,
        string groupTag,
        List<CoreOutboundGroup> groups,
        Dictionary<string, int> delays,
        NodeProfileMetadata meta)
    {
        _coreClient = coreClient;
        _isConnected = isConnected;
        _profileId = profileId;
        _providerName = providerName;
        _profilePath = profilePath ?? string.Empty;
        _groupTag = groupTag ?? string.Empty;
        _groups = groups ?? [];
        _delays = delays ?? new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        _meta = meta ?? new NodeProfileMetadata();
        LoadProfileSnapshotFromDisk();

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
        _list.AutoScroll = true;
        _list.BackColor = _listCard.BackColor;
        _list.Padding = new Padding(12);
        _list.SizeChanged += (s, e) => LayoutNodeRows();
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
        LoadProfileSnapshotFromDisk();
        _nodes.Clear();

        var connected = _isConnected();
        var currentGroupTag = (_groupTag ?? string.Empty).Trim();
        var selectedOutbound = string.Empty;
        var stored = SelectedOutboundStore.Instance.Get(_profileId);
        if (stored != null && string.Equals(stored.GroupTag, currentGroupTag, StringComparison.OrdinalIgnoreCase))
        {
            selectedOutbound = stored.OutboundTag ?? string.Empty;
        }
        if (string.IsNullOrWhiteSpace(selectedOutbound))
        {
            selectedOutbound = _profileDefaultNode;
        }
        if (string.IsNullOrWhiteSpace(selectedOutbound))
        {
            _meta.GroupDefaultOutboundByTag.TryGetValue(currentGroupTag, out selectedOutbound);
        }

        var offlineGroupTag = ResolveOfflineGroupTag(currentGroupTag, selectedOutbound ?? string.Empty);
        if (string.IsNullOrWhiteSpace(offlineGroupTag))
        {
            offlineGroupTag = currentGroupTag;
        }
        if (!string.IsNullOrWhiteSpace(offlineGroupTag) &&
            !string.Equals(_groupTag, offlineGroupTag, StringComparison.OrdinalIgnoreCase))
        {
            _groupTag = offlineGroupTag;
        }

        var nodeByTag = new Dictionary<string, NodeItem>(StringComparer.OrdinalIgnoreCase);
        var orderedTags = new List<string>();
        var liveDelayByTag = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        void UpsertNode(string tag, int delay, bool selectedHint)
        {
            tag = (tag ?? string.Empty).Trim();
            if (tag.Length == 0) return;

            if (!nodeByTag.TryGetValue(tag, out var node))
            {
                var address = ResolveNodeAddress(tag);
                node = new NodeItem
                {
                    Tag = tag,
                    Address = address,
                    DelayMs = delay > 0 ? delay : 0,
                    Selected = selectedHint
                };
                nodeByTag[tag] = node;
                orderedTags.Add(tag);
                return;
            }

            if (delay > 0)
            {
                node.DelayMs = delay;
            }
            if (selectedHint)
            {
                node.Selected = true;
            }
            if (string.IsNullOrWhiteSpace(node.Address))
            {
                node.Address = ResolveNodeAddress(tag);
            }
        }

        var liveGroup = _groups.FirstOrDefault(g => string.Equals(g.Tag, offlineGroupTag, StringComparison.OrdinalIgnoreCase))
            ?? _groups.FirstOrDefault(g => string.Equals(g.Tag, currentGroupTag, StringComparison.OrdinalIgnoreCase));
        if (liveGroup != null)
        {
            var liveSelected = (liveGroup.Selected ?? string.Empty).Trim();
            if (!string.IsNullOrWhiteSpace(liveSelected))
            {
                selectedOutbound = liveSelected;
            }
            foreach (var it in liveGroup.Items ?? [])
            {
                var tag = it.Tag ?? string.Empty;
                if (tag.Length == 0) continue;
                var delay = it.UrlTestDelay;
                if (delay <= 0 && _delays.TryGetValue(tag, out var d2)) delay = d2;
                if (delay > 0)
                {
                    liveDelayByTag[tag] = delay;
                }
            }
        }

        var baseTags = new List<string>();
        if (_profileNodeOrder.Count > 0)
        {
            baseTags.AddRange(_profileNodeOrder);
        }
        else if (_meta.GroupOutboundsByTag.TryGetValue(offlineGroupTag, out var offlineOutbounds) && offlineOutbounds.Count > 0)
        {
            foreach (var tag in offlineOutbounds)
            {
                baseTags.Add(tag);
            }
        }
        else if (liveGroup != null)
        {
            foreach (var it in liveGroup.Items ?? [])
            {
                var tag = (it.Tag ?? string.Empty).Trim();
                if (!string.IsNullOrWhiteSpace(tag))
                {
                    baseTags.Add(tag);
                }
            }
        }

        foreach (var tag in baseTags)
        {
            var delay = 0;
            if (_delays.TryGetValue(tag, out var d))
            {
                delay = d;
            }
            else if (liveDelayByTag.TryGetValue(tag, out var dl))
            {
                delay = dl;
            }
            UpsertNode(tag, delay, !string.IsNullOrWhiteSpace(selectedOutbound) && string.Equals(tag, selectedOutbound, StringComparison.OrdinalIgnoreCase));
        }

        if (!string.IsNullOrWhiteSpace(selectedOutbound) &&
            !nodeByTag.ContainsKey(selectedOutbound))
        {
            var delay = _delays.TryGetValue(selectedOutbound, out var d) ? d : 0;
            UpsertNode(selectedOutbound, delay, true);
        }

        foreach (var tag in orderedTags)
        {
            if (nodeByTag.TryGetValue(tag, out var node))
            {
                _nodes.Add(node);
            }
        }

        if (_profileNodeOrder.Count > 0 && _nodes.Count < _profileNodeOrder.Count)
        {
            foreach (var tag in _profileNodeOrder)
            {
                if (_nodes.Any(n => string.Equals(n.Tag, tag, StringComparison.OrdinalIgnoreCase))) continue;
                var delay = _delays.TryGetValue(tag, out var d) ? d : 0;
                _nodes.Add(new NodeItem
                {
                    Tag = tag,
                    Address = ResolveNodeAddress(tag),
                    DelayMs = delay,
                    Selected = !string.IsNullOrWhiteSpace(selectedOutbound) && string.Equals(tag, selectedOutbound, StringComparison.OrdinalIgnoreCase)
                });
            }
        }

        if (liveGroup != null)
        {
            foreach (var it in liveGroup.Items ?? [])
            {
                var tag = (it.Tag ?? string.Empty).Trim();
                if (string.IsNullOrWhiteSpace(tag)) continue;
                if (_nodes.Any(n => string.Equals(n.Tag, tag, StringComparison.OrdinalIgnoreCase))) continue;
                var delay = 0;
                if (_delays.TryGetValue(tag, out var d3))
                {
                    delay = d3;
                }
                else if (liveDelayByTag.TryGetValue(tag, out var d4))
                {
                    delay = d4;
                }
                _nodes.Add(new NodeItem
                {
                    Tag = tag,
                    Address = ResolveNodeAddress(tag),
                    DelayMs = delay,
                    Selected = !string.IsNullOrWhiteSpace(selectedOutbound) && string.Equals(tag, selectedOutbound, StringComparison.OrdinalIgnoreCase)
                });
            }
        }

        AppLogger.Log($"node-picker refresh: profile={_profilePath}, group={_groupTag}, parsed=[{string.Join(",", _profileNodeOrder)}], rendered=[{string.Join(",", _nodes.Select(n => n.Tag))}], selected={selectedOutbound}");

        RenderNodes(connected);
    }

    private string ResolveOfflineGroupTag(string currentGroupTag, string selectedOutbound)
    {
        currentGroupTag = (currentGroupTag ?? string.Empty).Trim();
        selectedOutbound = (selectedOutbound ?? string.Empty).Trim();

        if (!string.IsNullOrWhiteSpace(_profileGroupTag))
        {
            return _profileGroupTag;
        }

        if (!string.IsNullOrWhiteSpace(currentGroupTag) && _meta.GroupOutboundsByTag.ContainsKey(currentGroupTag))
        {
            return currentGroupTag;
        }

        if (!string.IsNullOrWhiteSpace(selectedOutbound))
        {
            foreach (var kv in _meta.GroupOutboundsByTag)
            {
                if (kv.Value.Any(tag => string.Equals(tag, selectedOutbound, StringComparison.OrdinalIgnoreCase)))
                {
                    return kv.Key;
                }
            }
        }

        var preferred = _meta.PickPreferredGroupTag();
        if (!string.IsNullOrWhiteSpace(preferred) && _meta.GroupOutboundsByTag.ContainsKey(preferred))
        {
            return preferred;
        }

        return string.Empty;
    }

    private string ResolveNodeAddress(string tag)
    {
        if (_profileAddressByTag.TryGetValue(tag, out var addr) && !string.IsNullOrWhiteSpace(addr))
        {
            return addr;
        }
        return _meta.OutboundAddressByTag.TryGetValue(tag, out var metaAddr) ? metaAddr : string.Empty;
    }

    private void LoadProfileSnapshotFromDisk()
    {
        _profileNodeOrder.Clear();
        _profileAddressByTag.Clear();
        _profileDefaultNode = string.Empty;
        _profileGroupTag = string.Empty;

        if (string.IsNullOrWhiteSpace(_profilePath) || !File.Exists(_profilePath))
        {
            return;
        }

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(_profilePath));
            var root = UnwrapConfigRoot(doc.RootElement);
            if (!root.TryGetProperty("outbounds", out var outbounds) || outbounds.ValueKind != JsonValueKind.Array)
            {
                return;
            }

            var addressByTag = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var selectorItemsByTag = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            var selectorDefaultByTag = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var fallbackNodes = new List<string>();
            string? preferredSelectorTag = null;
            string? fallbackSelectorTag = null;

            foreach (var outbound in outbounds.EnumerateArray())
            {
                if (outbound.ValueKind != JsonValueKind.Object) continue;
                var tag = GetString(outbound, "tag");
                if (string.IsNullOrWhiteSpace(tag)) continue;
                var type = (GetString(outbound, "type") ?? string.Empty).Trim().ToLowerInvariant();

                if (type == "selector" || type == "urltest" || type == "url_test")
                {
                    fallbackSelectorTag ??= tag;
                    if (preferredSelectorTag == null)
                    {
                        var lowerTag = tag.ToLowerInvariant();
                        if (lowerTag == "proxy" || lowerTag == "auto")
                        {
                            preferredSelectorTag = tag;
                        }
                    }

                    var itemTags = new List<string>();
                    if (outbound.TryGetProperty("outbounds", out var itemOutbounds) && itemOutbounds.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in itemOutbounds.EnumerateArray())
                        {
                            var itemTag = item.ValueKind == JsonValueKind.String ? (item.GetString() ?? string.Empty).Trim() : string.Empty;
                            if (string.IsNullOrWhiteSpace(itemTag)) continue;
                            if (!itemTags.Contains(itemTag, StringComparer.OrdinalIgnoreCase))
                            {
                                itemTags.Add(itemTag);
                            }
                        }
                    }
                    selectorItemsByTag[tag] = itemTags;
                    var defaultTag = (GetString(outbound, "default") ?? string.Empty).Trim();
                    if (!string.IsNullOrWhiteSpace(defaultTag))
                    {
                        selectorDefaultByTag[tag] = defaultTag;
                    }
                    continue;
                }

                var address = ResolveOutboundAddress(outbound);
                if (!string.IsNullOrWhiteSpace(address))
                {
                    addressByTag[tag] = address!;
                    if (!fallbackNodes.Contains(tag, StringComparer.OrdinalIgnoreCase))
                    {
                        fallbackNodes.Add(tag);
                    }
                }
            }

            foreach (var kv in addressByTag)
            {
                _profileAddressByTag[kv.Key] = kv.Value;
            }

            var chosenSelectorTag = preferredSelectorTag ?? fallbackSelectorTag ?? string.Empty;
            if (!string.IsNullOrWhiteSpace(chosenSelectorTag))
            {
                _profileGroupTag = chosenSelectorTag;
                if (selectorDefaultByTag.TryGetValue(chosenSelectorTag, out var selected))
                {
                    _profileDefaultNode = selected;
                }

                if (selectorItemsByTag.TryGetValue(chosenSelectorTag, out var tags) && tags.Count > 0)
                {
                    _profileNodeOrder.AddRange(tags);
                }
            }

            if (_profileNodeOrder.Count == 0)
            {
                _profileNodeOrder.AddRange(fallbackNodes);
            }
            if (string.IsNullOrWhiteSpace(_profileDefaultNode) && _profileNodeOrder.Count > 0)
            {
                _profileDefaultNode = _profileNodeOrder[0];
            }
        }
        catch
        {
            AppLogger.Log($"node-picker parse profile failed: {_profilePath}");
        }
    }

    private static JsonElement UnwrapConfigRoot(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object) return root;
        if (root.TryGetProperty("config", out var config) && config.ValueKind == JsonValueKind.Object) return config;
        if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Object)
        {
            if (data.TryGetProperty("config", out var cfg) && cfg.ValueKind == JsonValueKind.Object) return cfg;
        }
        if (root.TryGetProperty("result", out var result) && result.ValueKind == JsonValueKind.Object)
        {
            if (result.TryGetProperty("config", out var cfg) && cfg.ValueKind == JsonValueKind.Object) return cfg;
        }
        return root;
    }

    private static string? GetString(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var prop)) return null;
        return prop.ValueKind == JsonValueKind.String ? prop.GetString() : null;
    }

    private static string? ResolveOutboundAddress(JsonElement outbound)
    {
        var host = GetString(outbound, "server")
            ?? GetString(outbound, "address")
            ?? GetString(outbound, "host")
            ?? GetString(outbound, "server_address");
        if (string.IsNullOrWhiteSpace(host))
        {
            return null;
        }

        if (TryGetInt(outbound, "server_port", out var serverPort) && serverPort > 0)
        {
            return $"{host}:{serverPort}";
        }
        if (TryGetInt(outbound, "port", out var port) && port > 0)
        {
            return $"{host}:{port}";
        }

        return host;
    }

    private static bool TryGetInt(JsonElement obj, string name, out int value)
    {
        value = 0;
        if (!obj.TryGetProperty(name, out var prop)) return false;
        if (prop.ValueKind == JsonValueKind.Number && prop.TryGetInt32(out var i))
        {
            value = i;
            return true;
        }
        if (prop.ValueKind == JsonValueKind.String && int.TryParse(prop.GetString(), out var s))
        {
            value = s;
            return true;
        }
        return false;
    }

    private void RenderNodes(bool connected)
    {
        _list.SuspendLayout();
        _list.Controls.Clear();

        if (_nodes.Count == 0)
        {
            var empty = new Label
            {
                Text = "暂无节点数据",
                ForeColor = Color.FromArgb(84, 102, 121),
                Font = new Font("Segoe UI", 10F, FontStyle.Regular),
                AutoSize = true
            };
            _list.Controls.Add(empty);
            LayoutNodeRows();
            _list.ResumeLayout();
            _list.AutoScrollPosition = new Point(0, 0);
            return;
        }

        if (_nodes.All(n => !n.Selected))
        {
            _nodes[0].Selected = true;
        }

        foreach (var node in _nodes)
        {
            _list.Controls.Add(BuildNodeRow(node, connected));
        }

        LayoutNodeRows();
        _list.ResumeLayout();
        _list.AutoScrollPosition = new Point(0, 0);
        BeginInvoke((Action)ResetListScrollToTop);
        AppLogger.Log($"node-picker ui render: controls={_list.Controls.Count}, first={(_nodes.Count > 0 ? _nodes[0].Tag : string.Empty)}");
    }

    private void ResetListScrollToTop()
    {
        _list.AutoScrollPosition = new Point(0, 0);
    }

    private void LayoutNodeRows()
    {
        if (_list.Controls.Count == 0)
        {
            _list.AutoScrollMinSize = new Size(0, 0);
            return;
        }

        var width = Math.Max(520, _list.ClientSize.Width - 24);
        var x = _list.Padding.Left;
        var y = _list.Padding.Top;

        foreach (Control c in _list.Controls)
        {
            if (c is Label)
            {
                c.Location = new Point(x, y);
                y += c.Height;
                continue;
            }

            c.Width = width;
            c.Location = new Point(x, y);
            y += c.Height + 10;
        }

        y += _list.Padding.Bottom;
        _list.AutoScrollMinSize = new Size(0, y);
    }

    private Control BuildNodeRow(NodeItem node, bool connected)
    {
        var card = new MeshCardPanel
        {
            Width = Math.Max(520, _list.ClientSize.Width - 24),
            Height = 58,
            BackColor = Color.FromArgb(244, 250, 255),
            BorderColor = Color.FromArgb(205, 224, 240),
            CornerRadius = 14,
            Margin = new Padding(0)
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
            Location = new Point(card.Width - 118, 18),
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
            Location = new Point(card.Width - 42, 16),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            Enabled = connected && !_testingAll && !_applying
        };
        testButton.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(testButton, 14);
        testButton.Click += async (_, _) => await RunTestOneAsync(node.Tag);
        card.Controls.Add(testButton);

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
            delayLabel.Left = card.Width - 118;
            testButton.Left = card.Width - 42;
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
                MessageBox.Show(this, resp.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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
        if (string.IsNullOrWhiteSpace(_groupTag))
        {
            MessageBox.Show(this, "未找到可测速的出站组。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
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
                UpdateNodeDelays(onlyTag: _testingNode);
            }
            else
            {
                MessageBox.Show(this, resp.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "测速失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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

    private void UpdateNodeDelays(string? onlyTag = null)
    {
        onlyTag = (onlyTag ?? string.Empty).Trim();
        foreach (var n in _nodes)
        {
            if (!string.IsNullOrWhiteSpace(onlyTag) && !string.Equals(n.Tag, onlyTag, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
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

}

