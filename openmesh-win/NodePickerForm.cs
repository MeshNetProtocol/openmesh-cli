﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿﻿using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Text;
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

    private sealed class CircleIndicator : Control
    {
        private bool _selected;

        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public bool Selected
        {
            get => _selected;
            set { _selected = value; Invalidate(); }
        }

        public CircleIndicator()
        {
            DoubleBuffered = true;
            Size = new Size(24, 24);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(2, 2, Width - 4, Height - 4);
            
            if (Selected)
            {
                // Blue filled circle with white inner dot
                using var brush = new SolidBrush(Color.FromArgb(58, 147, 219));
                e.Graphics.FillEllipse(brush, rect);
                
                using var whiteBrush = new SolidBrush(Color.White);
                var inner = new Rectangle(rect.X + 6, rect.Y + 6, rect.Width - 12, rect.Height - 12);
                e.Graphics.FillEllipse(whiteBrush, inner);
            }
            else
            {
                // Gray border circle
                using var pen = new Pen(Color.FromArgb(180, 190, 200), 2);
                e.Graphics.DrawEllipse(pen, rect);
            }
        }
    }

    private sealed class MaskOverlay : Panel
    {
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public Color OverlayColor { get; set; } = Color.FromArgb(120, 0, 0, 0);

        public MaskOverlay()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            SetStyle(ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            using var brush = new SolidBrush(OverlayColor);
            e.Graphics.FillRectangle(brush, ClientRectangle);
            base.OnPaint(e);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            if (Parent is null)
            {
                base.OnPaintBackground(e);
                return;
            }

            using var bmp = new Bitmap(Parent.Width, Parent.Height);
            Parent.DrawToBitmap(bmp, new Rectangle(0, 0, Parent.Width, Parent.Height));
            e.Graphics.DrawImageUnscaled(bmp, -Left, -Top);
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

    private readonly FlowLayoutPanel _rootLayout = new();
    private readonly MeshCardPanel _headerCard = new();
    private readonly MeshCardPanel _hintCard = new();
    private readonly Panel _listContainer = new();
    private readonly FlowLayoutPanel _list = new();
    private readonly Panel _maskPanel = new();
    private readonly Label _maskLabel = new();
    
    private readonly Label _titleLabel = new();

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

        // Mask Panel (Transparent Black)
        _maskPanel.Dock = DockStyle.Fill;
        _maskPanel.BackColor = Color.FromArgb(90, 0, 0, 0);
        _maskPanel.Visible = false;
        _maskPanel.Cursor = Cursors.WaitCursor;
        
        _maskLabel.Text = "正在处理...";
        _maskLabel.ForeColor = Color.White;
        _maskLabel.Font = new Font("Segoe UI", 12F, FontStyle.Bold);
        _maskLabel.AutoSize = true;
        _maskLabel.BackColor = Color.Transparent;
        _maskPanel.Controls.Add(_maskLabel);
        
        _maskPanel.SizeChanged += (s, e) =>
        {
            _maskLabel.Location = new Point(
                (_maskPanel.Width - _maskLabel.Width) / 2,
                (_maskPanel.Height - _maskLabel.Height) / 2
            );
        };
        
        // Add Mask first (bottom) or last (top)? 
        // We want Mask to be on top of everything.
        // Controls.Add appends to the end of the collection.
        // But FlowLayoutPanel _rootLayout is Dock=Fill.
        // We need _rootLayout to be below _maskPanel.
        // Standard Windows Forms Z-order: 0 is Top.
        // So we add _maskPanel, then _rootLayout, then bring mask to front?
        // Actually, let's add _rootLayout first, then _maskPanel.
        
        // Root Layout: FlowLayoutPanel (TopDown)
        _rootLayout.Dock = DockStyle.Fill;
        _rootLayout.FlowDirection = FlowDirection.TopDown;
        _rootLayout.WrapContents = false;
        _rootLayout.AutoScroll = false;
        _rootLayout.Padding = new Padding(16);
        _rootLayout.BackColor = BackColor;
        Controls.Add(_rootLayout);
        
        Controls.Add(_maskPanel);
        _maskPanel.BringToFront();

        // 1. Header Card
        ConfigureCard(_headerCard, 14);
        _headerCard.Height = 84;
        _headerCard.Width = 760 - 32 - 16; // Initial guess
        _rootLayout.Controls.Add(_headerCard);

        _titleLabel.Text = "节点列表";
        _titleLabel.Font = new Font("Segoe UI Semibold", 20F, FontStyle.Bold);
        _titleLabel.ForeColor = Color.FromArgb(58, 147, 219);
        _titleLabel.Location = new Point(14, 12);
        _titleLabel.Size = new Size(200, 34);
        _headerCard.Controls.Add(_titleLabel);

        var subtitleLabel = new Label
        {
            Text = $"供应商：{_providerName}",
            Font = new Font("Segoe UI", 10.5F, FontStyle.Regular),
            ForeColor = Color.FromArgb(84, 102, 121),
            Location = new Point(16, 48),
            Size = new Size(520, 22),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        _headerCard.Controls.Add(subtitleLabel);

        var closeButton = new Button
        {
            Text = "关闭",
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(236, 187, 66),
            ForeColor = Color.Black,
            Font = new Font("Segoe UI Semibold", 10.5F, FontStyle.Bold),
            Size = new Size(84, 32),
            Location = new Point(_headerCard.Width - 98, 16),
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        closeButton.FlatAppearance.BorderSize = 0;
        closeButton.Click += (_, _) => Close();
        _headerCard.Controls.Add(closeButton);

        var testAllButton = new Button
        {
            Text = "⚡ 全部测速",
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(255, 153, 51),
            ForeColor = Color.White,
            Font = new Font("Segoe UI Semibold", 9.2F, FontStyle.Bold),
            Size = new Size(110, 30),
            Location = new Point(_headerCard.Width - 220, 16),
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        testAllButton.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(testAllButton, 15);
        testAllButton.Click += async (_, _) => await RunTestAllAsync(testAllButton);
        _headerCard.Controls.Add(testAllButton);

        // 2. Hint Card
        ConfigureHintCard(_hintCard);
        _hintCard.Height = 42;
        _hintCard.Visible = false;
        _rootLayout.Controls.Add(_hintCard);

        var hintLabel = new Label
        {
            Text = "当前未连接 VPN，可查看节点列表，但无法测速或切换。",
            Font = new Font("Segoe UI", 9.2F, FontStyle.Regular),
            ForeColor = Color.FromArgb(130, 90, 32),
            Location = new Point(12, 12),
            Size = new Size(500, 20),
            AutoSize = true
        };
        _hintCard.Controls.Add(hintLabel);

        // 3. List Container (White Card Background)
        // We use a Panel container to simulate the card background, inside it is the FlowLayoutPanel
        _listContainer.BackColor = Color.White;
        _listContainer.Padding = new Padding(12);
        // Initial size, will be resized by Layout event
        _listContainer.Size = new Size(700, 400); 
        _rootLayout.Controls.Add(_listContainer);
        ApplyRoundedRegion(_listContainer, 14);

        _list.Dock = DockStyle.Fill;
        _list.AutoScroll = true;
        _list.FlowDirection = FlowDirection.TopDown;
        _list.WrapContents = false;
        _list.BackColor = Color.White;
        _list.Padding = new Padding(0, 0, 12, 0); // Right padding for scrollbar space
        _listContainer.Controls.Add(_list);

        // Resize Logic
        _rootLayout.SizeChanged += (s, e) =>
        {
            var w = _rootLayout.ClientSize.Width - _rootLayout.Padding.Horizontal;
            var h = _rootLayout.ClientSize.Height - _rootLayout.Padding.Vertical;
            
            _headerCard.Width = w;
            _hintCard.Width = w;
            _listContainer.Width = w;
            
            // Calculate remaining height for list
            var usedHeight = _headerCard.Height + _rootLayout.Padding.Vertical + 16; // 16 gap
            if (_hintCard.Visible) usedHeight += _hintCard.Height + 16;
            
            _listContainer.Height = Math.Max(100, _rootLayout.ClientSize.Height - usedHeight);
            
            // Re-layout list items
            foreach(Control c in _list.Controls) c.Width = _list.ClientSize.Width - 24;
        };

        Shown += (_, _) =>
        {
            EnsureGroupTag();
            RefreshNodesFromState();
            RefreshConnectedGate(testAllButton, hintLabel);
        };
    }

    public void UpdateLiveState(List<CoreOutboundGroup> groups, Dictionary<string, int> delays)
    {
        _groups = groups ?? [];
        _delays = delays ?? new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        EnsureGroupTag();
        RefreshNodesFromState();
        RefreshConnectedGate(null, null); // controls might not be available yet if called too early, but usually OK
    }

    private void EnsureGroupTag()
    {
        if (!string.IsNullOrWhiteSpace(_groupTag) && _groups.Any(g => string.Equals(g.Tag, _groupTag, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        foreach (var candidate in GetPreferredGroupTagCandidates())
        {
            var matched = _groups.FirstOrDefault(g => string.Equals(g.Tag, candidate, StringComparison.OrdinalIgnoreCase));
            if (matched != null)
            {
                _groupTag = matched.Tag;
                return;
            }
        }
        var firstSelectable = _groups.FirstOrDefault(g => g.Selectable);
        if (firstSelectable != null) { _groupTag = firstSelectable.Tag; return; }
        var first = _groups.FirstOrDefault();
        if (first != null) { _groupTag = first.Tag; return; }
        var offline = _meta.PickPreferredGroupTag();
        if (!string.IsNullOrWhiteSpace(offline)) { _groupTag = offline; }
    }

    private static string[] GetPreferredGroupTagCandidates()
        => ["primary-selector", "proxy", "auto", "select", "main", "node"];

    private void SetLoading(bool loading, string message = "正在处理...")
    {
        if (loading)
        {
            _maskLabel.Text = message;
            _maskLabel.Location = new Point(
                (_maskPanel.Width - _maskLabel.Width) / 2,
                (_maskPanel.Height - _maskLabel.Height) / 2
            );
            _maskPanel.Visible = true;
            _maskPanel.BringToFront();
            Cursor = Cursors.WaitCursor;
        }
        else
        {
            _maskPanel.Visible = false;
            Cursor = Cursors.Default;
        }
        _list.Enabled = !loading; 
    }

    private void RefreshConnectedGate(Button? testAllButton = null, Label? hintLabel = null)
    {
        var connected = _isConnected();
        
        // If controls not passed, try to find them (for UpdateLiveState case)
        if (testAllButton == null)
        {
             // It's tricky to find them without fields, but UpdateLiveState is rarely called before constructor finishes
             // In worst case we skip UI update here, and wait for Shown event or next cycle
             return; 
        }

        _hintCard.Visible = !connected;
        testAllButton.Enabled = connected && !_testingAll && !_applying;
        if (!connected)
        {
            testAllButton.BackColor = Color.FromArgb(200, 200, 200);
        }
        else
        {
            testAllButton.BackColor = Color.FromArgb(255, 153, 51);
        }
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
            if (!string.IsNullOrWhiteSpace(liveSelected) && string.IsNullOrWhiteSpace(selectedOutbound))
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

        if (!string.IsNullOrWhiteSpace(selectedOutbound) &&
            !_nodes.Any(n => string.Equals(n.Tag, selectedOutbound, StringComparison.OrdinalIgnoreCase)))
        {
            var delay = _delays.TryGetValue(selectedOutbound, out var d5) ? d5 : 0;
            _nodes.Add(new NodeItem
            {
                Tag = selectedOutbound,
                Address = ResolveNodeAddress(selectedOutbound),
                DelayMs = delay,
                Selected = true
            });
        }

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
                        if (GetPreferredGroupTagCandidates().Any(candidate =>
                                string.Equals(tag, candidate, StringComparison.OrdinalIgnoreCase)))
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
            else if (fallbackNodes.Count > 0)
            {
                foreach (var tag in fallbackNodes)
                {
                    if (!_profileNodeOrder.Contains(tag, StringComparer.OrdinalIgnoreCase))
                    {
                        _profileNodeOrder.Add(tag);
                    }
                }
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
                AutoSize = true,
                Location = new Point(20, 20)
            };
            _list.Controls.Add(empty);
            _list.ResumeLayout();
            return;
        }

        if (_nodes.All(n => !n.Selected))
        {
            _nodes[0].Selected = true;
        }

        var width = Math.Max(520, _list.ClientSize.Width - 24);

        foreach (var node in _nodes)
        {
            try
            {
                var card = BuildNodeRow(node, connected);
                card.Width = width;
                card.Margin = new Padding(0, 0, 0, 10);
                
                _list.Controls.Add(card);
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Error building node {node.Tag}: {ex.Message}");
            }
        }
        
        _list.ResumeLayout();
        _list.PerformLayout();
        
        // Show in Title for now
        _titleLabel.Text = $"节点列表";
        
        // Force scroll to top
        _list.AutoScrollPosition = new Point(0, 0);
    }

    private void LayoutNodeRows()
    {
        if (_list.Controls.Count == 0) return;

        var width = Math.Max(520, _list.ClientSize.Width - 24);
        foreach (Control c in _list.Controls)
        {
            if (c is MeshCardPanel)
            {
                c.Width = width;
            }
        }
    }

    private Control BuildNodeRow(NodeItem node, bool connected)
    {
        var card = new MeshCardPanel
        {
            Tag = node.Tag, // Add Tag for identification
            Width = Math.Max(520, _list.ClientSize.Width - 24),
            Height = 64,
            BackColor = Color.FromArgb(250, 252, 254),
            // BackColor = Color.Yellow, // DEBUG COLOR
            BorderColor = node.Selected ? Color.FromArgb(58, 147, 219) : Color.FromArgb(205, 224, 240),
            CornerRadius = 16,
            Margin = new Padding(0)
        };

        var indicator = new CircleIndicator
        {
            Selected = node.Selected,
            Location = new Point(20, 20)
        };
        card.Controls.Add(indicator);

        var nameLabel = new Label
        {
            Text = node.Tag,
            Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold),
            ForeColor = Color.FromArgb(45, 62, 80),
            AutoEllipsis = true,
            Location = new Point(56, 12),
            Size = new Size(card.Width - 200, 22),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        card.Controls.Add(nameLabel);

        var activeBadge = new Label
        {
            Text = "ACTIVE",
            Visible = node.Selected,
            BackColor = Color.FromArgb(212, 238, 246),
            ForeColor = Color.FromArgb(40, 106, 196),
            Font = new Font("Segoe UI Semibold", 7F, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(56 + TextRenderer.MeasureText(node.Tag, nameLabel.Font).Width + 8, 15),
            Size = new Size(48, 16)
        };
        ApplyRoundedRegion(activeBadge, 6);
        card.Controls.Add(activeBadge);

        var addressText = string.IsNullOrWhiteSpace(node.Address) ? "-" : node.Address;
        var addrLabel = new Label
        {
            Text = $"🌐  {addressText}",
            Font = new Font("Segoe UI", 9F, FontStyle.Regular),
            ForeColor = Color.FromArgb(140, 150, 160),
            AutoEllipsis = true,
            Location = new Point(56, 36),
            Size = new Size(card.Width - 200, 18),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };
        card.Controls.Add(addrLabel);

        // Flash/Lightning Icon (Text placeholder for now)
        var testButton = new Button
        {
            Text = "⚡",
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(255, 153, 51),
            ForeColor = Color.White,
            Font = new Font("Segoe UI Symbol", 10F, FontStyle.Bold),
            Size = new Size(32, 32),
            Location = new Point(card.Width - 48, 16),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            Enabled = connected && !_testingAll && !_applying
        };
        testButton.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(testButton, 16);
        testButton.Click += async (_, _) => await RunTestOneAsync(node.Tag);
        card.Controls.Add(testButton);

        var delayLabel = new Label
        {
            Text = node.DelayMs > 0 ? $"{node.DelayMs}" : "-",
            Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold),
            ForeColor = DelayColor(node.DelayMs),
            TextAlign = ContentAlignment.MiddleRight,
            Location = new Point(card.Width - 100, 22),
            Size = new Size(40, 20),
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        card.Controls.Add(delayLabel);

        void clickHandler(object? _, EventArgs __) { _ = SelectNodeAsync(node.Tag); }
        if (connected)
        {
            card.Cursor = Cursors.Hand;
            card.Click += clickHandler;
            nameLabel.Click += clickHandler;
            addrLabel.Click += clickHandler;
            indicator.Click += clickHandler;
        }

        card.Resize += (_, _) =>
        {
            nameLabel.Width = Math.Max(60, card.Width - 200);
            addrLabel.Width = Math.Max(60, card.Width - 200);
            testButton.Left = card.Width - 48;
            delayLabel.Left = card.Width - 100;
            if (activeBadge.Visible)
            {
                activeBadge.Left = 56 + TextRenderer.MeasureText(node.Tag, nameLabel.Font).Width + 8;
            }
        };

        return card;
    }

    private async Task RunTestAllAsync(Button testAllButton)
    {
        if (!_isConnected())
        {
            MessageBox.Show(this, "请先连接 VPN。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (_testingAll || _applying) return;
        if (string.IsNullOrWhiteSpace(_groupTag))
        {
            MessageBox.Show(this, "未找到可测速的出站组。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        _testingAll = true;
        SetLoading(true, "正在测速...");
        testAllButton.Text = "⏳";
        testAllButton.Enabled = false;

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
            testAllButton.Text = "⚡ 全部测速";
            SetLoading(false);
            RefreshConnectedGate(testAllButton, null);
            RefreshNodesFromState();
        }
    }

    private async Task RunTestOneAsync(string nodeTag)
    {
        if (!_isConnected())
        {
            MessageBox.Show(this, "请先连接 VPN。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        nodeTag = nodeTag ?? string.Empty;
        if (_testingAll || _applying) return;
        if (string.IsNullOrWhiteSpace(_groupTag))
        {
            MessageBox.Show(this, "未找到可测速的出站组。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        _testingNode = nodeTag;
        _testingAll = true;
        SetLoading(true, "正在测速...");

        // Find the specific card and show loading state
        Control? targetCard = null;
        Button? targetBtn = null;
        foreach (Control c in _list.Controls)
        {
            if (c is MeshCardPanel p)
            {
                // We need to identify the card. 
                // Currently BuildNodeRow doesn't set Tag on card, but let's assume we can find it via label text or by adding Tag in BuildNodeRow
                // Let's modify BuildNodeRow to set Tag on the card first.
                if (string.Equals(p.Tag as string, nodeTag, StringComparison.OrdinalIgnoreCase))
                {
                    targetCard = p;
                    foreach(Control inner in p.Controls) { if (inner is Button b) targetBtn = b; }
                    break;
                }
            }
        }

        string originalBtnText = targetBtn?.Text ?? "⚡";
        if (targetBtn != null) targetBtn.Text = "⏳";

        try
        {
            var resp = await _coreClient.UrlTestAsync(_groupTag);
            if (resp.Ok)
            {
                _delays = resp.Delays ?? new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                
                // Only update the specific node in UI
                if (targetCard != null)
                {
                    var newDelay = 0;
                    if (_delays.TryGetValue(nodeTag, out var d)) newDelay = d;
                    
                    // Find delay label
                    Label? delayLbl = null;
                    foreach(Control inner in targetCard.Controls) 
                    { 
                        if (inner is Label l && l.TextAlign == ContentAlignment.MiddleRight) 
                            delayLbl = l; 
                    }
                    
                    if (delayLbl != null)
                    {
                        delayLbl.Text = newDelay > 0 ? $"{newDelay}" : "-";
                        delayLbl.ForeColor = DelayColor(newDelay);
                    }
                }
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
            _testingNode = string.Empty;
            if (targetBtn != null) targetBtn.Text = "⚡"; // Restore icon
            SetLoading(false);
            
            // Do NOT call RefreshNodesFromState() to avoid full redraw
            // But we need to update internal state? 
            // _delays is already updated. Next time RefreshNodesFromState is called (e.g. on Show), it will be correct.
        }
    }

    private void UpdateNodeDelays()
    {
        foreach (Control c in _list.Controls)
        {
            if (c is MeshCardPanel card)
            {
                // Simple refresh, full redraw is safer
            }
        }
        RefreshNodesFromState();
    }

    private async Task SelectNodeAsync(string tag)
    {
        if (_applying || _testingAll)
        {
            return;
        }

        var effectiveGroupTag = !string.IsNullOrWhiteSpace(_profileGroupTag) ? _profileGroupTag : _groupTag;
        if (string.IsNullOrWhiteSpace(effectiveGroupTag))
        {
            return;
        }

        var current = _nodes.FirstOrDefault(n => n.Selected);
        if (current != null && string.Equals(current.Tag, tag, StringComparison.OrdinalIgnoreCase))
        {
            return; // Already selected
        }

        if (!_isConnected())
        {
            _groupTag = effectiveGroupTag;
            SelectedOutboundStore.Instance.Set(_profileId, effectiveGroupTag, tag);
            foreach (var node in _nodes)
            {
                node.Selected = string.Equals(node.Tag, tag, StringComparison.OrdinalIgnoreCase);
            }
            RenderNodes(false);
            return;
        }

        _applying = true;
        SetLoading(true, $"正在切换到 {tag}...");

        try
        {
            var result = await _coreClient.SelectOutboundAsync(effectiveGroupTag, tag);
            if (result.Ok)
            {
                _groupTag = effectiveGroupTag;
                SelectedOutboundStore.Instance.Set(_profileId, effectiveGroupTag, tag);
                // The UI will be updated on the next tick from the main form,
                // which calls UpdateLiveState. For immediate feedback:
                foreach (var node in _nodes)
                {
                    node.Selected = string.Equals(node.Tag, tag, StringComparison.OrdinalIgnoreCase);
                }
                RenderNodes(_isConnected());
            }
            else
            {
                MessageBox.Show($"切换节点失败: {result.Message}", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"切换节点时发生错误: {ex.Message}", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            _applying = false;
            SetLoading(false);
        }
    }

    private void ConfigureCard(MeshCardPanel card, int radius)
    {
        card.BackColor = Color.White;
        card.BorderColor = Color.White;
        card.CornerRadius = radius;
        card.Padding = new Padding(0);
        card.Margin = new Padding(0);
    }

    private void ConfigureHintCard(MeshCardPanel card)
    {
        card.BackColor = Color.FromArgb(255, 244, 229);
        card.BorderColor = Color.FromArgb(255, 230, 204);
        card.CornerRadius = 8;
        card.Padding = new Padding(0);
        card.Margin = new Padding(0, 0, 0, 16);
    }

    private Color DelayColor(int delay)
    {
        if (delay <= 0) return Color.Gray;
        if (delay < 200) return Color.FromArgb(46, 204, 113);
        if (delay < 500) return Color.FromArgb(241, 196, 15);
        return Color.FromArgb(231, 76, 60);
    }

    [System.Runtime.InteropServices.DllImport("Gdi32.dll", EntryPoint = "CreateRoundRectRgn")]
    private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);

    private void ApplyRoundedRegion(Control control, int radius)
    {
        control.Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, control.Width, control.Height, radius, radius));
    }
}
