using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace OpenMeshWin;

internal sealed class ProviderMarketForm : Form
{
    private static readonly Color PageBackground = Color.FromArgb(232, 241, 250);
    private static readonly Color CardBackground = Color.FromArgb(248, 251, 255);
    private static readonly Color CardBorder = Color.FromArgb(205, 222, 238);
    private static readonly Color AccentBlue = Color.FromArgb(71, 167, 230);
    private static readonly Color AccentCyan = Color.FromArgb(89, 230, 245);
    private static readonly Color AccentAmber = Color.FromArgb(233, 179, 73);
    private static readonly Color DangerRed = Color.FromArgb(224, 76, 90);
    private static readonly Color TextPrimary = Color.FromArgb(34, 52, 70);
    private static readonly Color TextSecondary = Color.FromArgb(105, 121, 140);

    private readonly Func<string, Task> _onInstallOrUpdate;
    private readonly Func<string, Task> _onUninstall;
    private readonly Func<Task> _onRefresh;

    private readonly Label _titleLabel = new() { Text = "供应商市场", AutoSize = true };
    private readonly Label _subtitleLabel = new() { Text = "搜索、排序、安装/更新供应商", AutoSize = true };

    private readonly Button _marketModeButton = new() { Text = "Marketplace" };
    private readonly Button _installedModeButton = new() { Text = "Installed" };
    private readonly Button _refreshButton = new() { Text = "刷新" };
    private readonly Button _closeButton = new() { Text = "关闭" };

    private readonly TextBox _searchTextBox = new() { PlaceholderText = "搜索 名称/作者/标签/简介 (支持本地及在线)" };
    private readonly Label _regionLabel = new() { Text = "地区", AutoSize = true };
    private readonly ComboBox _regionComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Label _sortLabel = new() { Text = "排序", AutoSize = true };
    private readonly ComboBox _sortComboBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };

    private readonly FlowLayoutPanel _metaPanel = new()
    {
        FlowDirection = FlowDirection.LeftToRight,
        WrapContents = true,
        AutoScroll = false,
        Padding = new Padding(0, 4, 0, 4),
        BackColor = Color.Transparent
    };

    private readonly FlowLayoutPanel _cardsPanel = new()
    {
        Dock = DockStyle.Fill,
        AutoScroll = true,
        FlowDirection = FlowDirection.TopDown,
        WrapContents = false,
        Padding = new Padding(16, 10, 16, 16),
        BackColor = PageBackground
    };

    private readonly Label _emptyLabel = new()
    {
        Text = "暂无数据",
        ForeColor = TextSecondary,
        AutoSize = true,
        Visible = false
    };

    private readonly List<CoreProviderOffer> _offers = [];
    private readonly HashSet<string> _installedIds = new(StringComparer.OrdinalIgnoreCase);

    private bool _isBusy;
    private ViewMode _mode = ViewMode.Marketplace;

    private enum ViewMode
    {
        Marketplace,
        Installed
    }

    private enum SortMode
    {
        UpdatedDesc,
        PriceAsc,
        PriceDesc
    }

    public ProviderMarketForm(
        List<CoreProviderOffer> offers,
        HashSet<string> installedIds,
        Func<string, Task> onInstallOrUpdate,
        Func<string, Task> onUninstall,
        Func<Task> onRefresh)
    {
        _onInstallOrUpdate = onInstallOrUpdate;
        _onUninstall = onUninstall;
        _onRefresh = onRefresh;

        Text = "供应商市场";
        Size = new Size(980, 700);
        MinimumSize = new Size(860, 600);
        StartPosition = FormStartPosition.CenterParent;
        BackColor = PageBackground;

        BuildLayout();
        WireEvents();
        UpdateData(offers, installedIds);
    }

    public void UpdateData(List<CoreProviderOffer> offers, HashSet<string> installedIds)
    {
        _offers.Clear();
        if (offers is not null)
        {
            _offers.AddRange(offers);
        }

        _installedIds.Clear();
        if (installedIds is not null)
        {
            foreach (var id in installedIds)
            {
                _installedIds.Add(id);
            }
        }

        RebuildRegionOptions();
        RenderCards();
    }

    private void BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            BackColor = PageBackground,
            Padding = new Padding(14, 12, 14, 12)
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 76));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 98));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        root.Controls.Add(BuildHeader(), 0, 0);
        root.Controls.Add(BuildToolbar(), 0, 1);
        root.Controls.Add(_cardsPanel, 0, 2);

        _cardsPanel.Controls.Add(_emptyLabel);
        Controls.Add(root);

        ApplyModeButtonStyle(_marketModeButton, active: true);
        ApplyModeButtonStyle(_installedModeButton, active: false);
        ApplyToolbarModeState();

        _sortComboBox.Items.AddRange([
            "更新时间 ↓",
            "价格 ↑ (USD/GB)",
            "价格 ↓ (USD/GB)"
        ]);
        _sortComboBox.SelectedIndex = 0;
    }

    private Control BuildHeader()
    {
        var panel = CreateCardContainer();
        panel.Padding = new Padding(14, 10, 14, 10);

        _titleLabel.Font = new Font("Segoe UI", 14F, FontStyle.Bold);
        _titleLabel.ForeColor = AccentBlue;

        _subtitleLabel.Font = new Font("Segoe UI", 9F, FontStyle.Regular);
        _subtitleLabel.ForeColor = TextSecondary;

        var left = new Panel { Dock = DockStyle.Left, Width = 330, BackColor = Color.Transparent };
        left.Controls.Add(_titleLabel);
        left.Controls.Add(_subtitleLabel);
        _titleLabel.Location = new Point(0, 2);
        _subtitleLabel.Location = new Point(1, 34);

        var segmented = new Panel { Size = new Size(232, 32), BackColor = Color.FromArgb(220, 231, 241) };
        segmented.Paint += (_, e) =>
        {
            using var path = UiPaths.RoundRect(segmented.ClientRectangle, 10);
            segmented.Region = new Region(path);
        };

        ConfigureModeButton(_marketModeButton);
        ConfigureModeButton(_installedModeButton);
        _marketModeButton.SetBounds(2, 2, 113, 28);
        _installedModeButton.SetBounds(117, 2, 113, 28);
        segmented.Controls.Add(_marketModeButton);
        segmented.Controls.Add(_installedModeButton);

        ConfigureActionButton(_closeButton, AccentAmber, Color.White);
        _closeButton.Size = new Size(78, 30);

        panel.Controls.Add(left);
        panel.Controls.Add(segmented);
        panel.Controls.Add(_closeButton);

        panel.Resize += (_, _) =>
        {
            segmented.Left = (panel.Width - segmented.Width) / 2;
            segmented.Top = (panel.Height - segmented.Height) / 2;
            _closeButton.Left = panel.Width - _closeButton.Width - 12;
            _closeButton.Top = (panel.Height - _closeButton.Height) / 2;
        };

        return panel;
    }

    private Control BuildToolbar()
    {
        var panel = CreateCardContainer();
        panel.Padding = new Padding(12, 10, 12, 10);
        _metaPanel.Location = new Point(0, 46);
        _metaPanel.Height = 26;
        _metaPanel.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right;

        _searchTextBox.BorderStyle = BorderStyle.FixedSingle;
        _searchTextBox.Font = new Font("Segoe UI", 9F);

        _regionLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        _regionLabel.ForeColor = TextPrimary;
        _sortLabel.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        _sortLabel.ForeColor = TextPrimary;

        _regionComboBox.Font = new Font("Segoe UI", 9F);
        _sortComboBox.Font = new Font("Segoe UI", 9F);

        ConfigureActionButton(_refreshButton, AccentBlue, Color.White);

        _searchTextBox.SetBounds(0, 8, 440, 28);
        _regionLabel.SetBounds(450, 12, 36, 20);
        _regionComboBox.SetBounds(488, 8, 92, 28);
        _sortLabel.SetBounds(588, 12, 36, 20);
        _sortComboBox.SetBounds(626, 8, 144, 28);
        _refreshButton.SetBounds(0, 7, 68, 30);

        panel.Controls.Add(_searchTextBox);
        panel.Controls.Add(_regionLabel);
        panel.Controls.Add(_regionComboBox);
        panel.Controls.Add(_sortLabel);
        panel.Controls.Add(_sortComboBox);
        panel.Controls.Add(_refreshButton);
        panel.Controls.Add(_metaPanel);

        panel.Resize += (_, _) =>
        {
            var right = panel.Width - 12;
            _refreshButton.Left = right - _refreshButton.Width;

            var sortMaxWidth = Math.Max(120, _refreshButton.Left - 8 - _sortComboBox.Left);
            _sortComboBox.Width = sortMaxWidth;
            _metaPanel.Width = Math.Max(220, panel.Width - 24);
        };

        return panel;
    }

    private void WireEvents()
    {
        _marketModeButton.Click += (_, _) => SetMode(ViewMode.Marketplace);
        _installedModeButton.Click += (_, _) => SetMode(ViewMode.Installed);
        _closeButton.Click += (_, _) => Close();

        _searchTextBox.TextChanged += (_, _) => RenderCards();
        _regionComboBox.SelectedIndexChanged += (_, _) => RenderCards();
        _sortComboBox.SelectedIndexChanged += (_, _) => RenderCards();

        _refreshButton.Click += async (_, _) => await RunWithBusyAsync(_onRefresh);

        _cardsPanel.Resize += (_, _) => RenderCards();
    }

    private void SetMode(ViewMode mode)
    {
        if (_mode == mode)
        {
            return;
        }

        _mode = mode;
        ApplyModeButtonStyle(_marketModeButton, active: _mode == ViewMode.Marketplace);
        ApplyModeButtonStyle(_installedModeButton, active: _mode == ViewMode.Installed);
        ApplyToolbarModeState();
        RenderCards();
    }

    private void RenderCards()
    {
        if (!IsHandleCreated)
        {
            return;
        }

        var query = (_searchTextBox.Text ?? string.Empty).Trim();
        var normalizedQuery = query.ToLowerInvariant();
        var region = _regionComboBox.SelectedItem as string ?? "全部";
        var sortMode = (SortMode)Math.Max(0, _sortComboBox.SelectedIndex);

        IEnumerable<CoreProviderOffer> list = _offers;
        if (_mode == ViewMode.Installed)
        {
            // Installed tab is local-first and local-filtered only.
            list = list
                .Where(o => _installedIds.Contains(o.Id))
                .OrderBy(o => o.Name, StringComparer.OrdinalIgnoreCase);
            list = list.Where(o => FilterByQuery(o, normalizedQuery));
        }
        else
        {
            // Marketplace must only show server-backed offers.
            list = list.Where(o => !o.IsLocalOnly);
            list = list.Where(o => FilterByQuery(o, normalizedQuery) && FilterByRegion(o, region));
            list = SortOffers(list, sortMode);
        }

        var result = list.ToList();
        RebuildMeta(query, region, sortMode, result.Count);

        _cardsPanel.SuspendLayout();
        try
        {
            _cardsPanel.Controls.Clear();
            _cardsPanel.Controls.Add(_emptyLabel);

            if (result.Count == 0)
            {
                _emptyLabel.Text = _mode == ViewMode.Marketplace ? "没有匹配的供应商" : "暂无已安装供应商";
                _emptyLabel.Visible = true;
                _emptyLabel.Margin = new Padding(6, 12, 6, 6);
                return;
            }

            _emptyLabel.Visible = false;
            var cardWidth = Math.Max(300, _cardsPanel.ClientSize.Width - 48 - SystemInformation.VerticalScrollBarWidth);

            foreach (var offer in result)
            {
                var isInstalled = _installedIds.Contains(offer.Id);
                var card = new ProviderMarketCardControl(
                    offer,
                    isInstalled,
                    _mode,
                    onInstallOrUpdate: () => RunWithBusyAsync(() => _onInstallOrUpdate(offer.Id)),
                    onUninstall: () => RunWithBusyAsync(() => _onUninstall(offer.Id)));
                card.Width = cardWidth;
                card.Margin = new Padding(0, 0, 0, 10);
                _cardsPanel.Controls.Add(card);
            }
        }
        finally
        {
            _cardsPanel.ResumeLayout();
        }
    }

    private IEnumerable<CoreProviderOffer> SortOffers(IEnumerable<CoreProviderOffer> source, SortMode mode)
    {
        return mode switch
        {
            SortMode.PriceAsc => source.OrderBy(o => o.PricePerGb <= 0 ? decimal.MaxValue : o.PricePerGb),
            SortMode.PriceDesc => source.OrderByDescending(o => o.PricePerGb),
            _ => source.OrderByDescending(o => ParseDateOrMin(o.UpdatedAt))
        };
    }

    private static DateTime ParseDateOrMin(string value)
    {
        return DateTime.TryParse(value, out var dt) ? dt : DateTime.MinValue;
    }

    private bool FilterByQuery(CoreProviderOffer offer, string query)
    {
        if (string.IsNullOrEmpty(query))
        {
            return true;
        }

        var haystack = string.Join(' ', new[]
        {
            offer.Id,
            offer.Name,
            offer.Author,
            offer.Description,
            string.Join(' ', offer.Tags)
        }).ToLowerInvariant();

        return haystack.Contains(query);
    }

    private bool FilterByRegion(CoreProviderOffer offer, string region)
    {
        if (string.IsNullOrWhiteSpace(region) || region == "全部")
        {
            return true;
        }

        foreach (var tag in offer.Tags)
        {
            var normalized = NormalizeRegionTag(tag);
            if (string.Equals(normalized, region, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return string.Equals(offer.Region, region, StringComparison.OrdinalIgnoreCase);
    }

    private void RebuildRegionOptions()
    {
        var current = _regionComboBox.SelectedItem as string ?? "全部";

        var regions = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "全部" };
        foreach (var offer in _offers)
        {
            if (!string.IsNullOrWhiteSpace(offer.Region))
            {
                regions.Add(offer.Region.Trim().ToUpperInvariant());
            }

            foreach (var tag in offer.Tags)
            {
                var region = NormalizeRegionTag(tag);
                if (!string.IsNullOrWhiteSpace(region))
                {
                    regions.Add(region);
                }
            }
        }

        _regionComboBox.BeginUpdate();
        try
        {
            _regionComboBox.Items.Clear();
            foreach (var region in regions.OrderBy(r => r == "全部" ? string.Empty : r, StringComparer.OrdinalIgnoreCase))
            {
                _regionComboBox.Items.Add(region);
            }

            var index = _regionComboBox.Items.IndexOf(current);
            _regionComboBox.SelectedIndex = index >= 0 ? index : 0;
        }
        finally
        {
            _regionComboBox.EndUpdate();
        }
    }

    private static string NormalizeRegionTag(string rawTag)
    {
        var tag = (rawTag ?? string.Empty).Trim();
        if (tag.StartsWith("region:", StringComparison.OrdinalIgnoreCase))
        {
            var value = tag.Substring("region:".Length).Trim();
            return string.IsNullOrWhiteSpace(value) ? string.Empty : value.ToUpperInvariant();
        }

        return tag.Length == 2 && tag.All(char.IsLetter) ? tag.ToUpperInvariant() : string.Empty;
    }

    private void RebuildMeta(string query, string region, SortMode sortMode, int count)
    {
        _metaPanel.SuspendLayout();
        try
        {
            _metaPanel.Controls.Clear();
            _metaPanel.Controls.Add(CreateMetaPill(_mode == ViewMode.Marketplace ? "Market" : "Installed", $"{count}/{TotalCount()}"));

            if (_mode == ViewMode.Marketplace && region != "全部")
            {
                _metaPanel.Controls.Add(CreateMetaPill("Region", region));
            }

            if (_mode == ViewMode.Marketplace)
            {
                _metaPanel.Controls.Add(CreateMetaPill("Sort", sortMode switch
                {
                    SortMode.PriceAsc => "价格 ↑",
                    SortMode.PriceDesc => "价格 ↓",
                    _ => "更新时间"
                }));
            }

            if (!string.IsNullOrWhiteSpace(query))
            {
                _metaPanel.Controls.Add(CreateMetaPill("Query", TruncateForPill(query, 26)));
            }
        }
        finally
        {
            _metaPanel.ResumeLayout();
        }
    }

    private int TotalCount()
    {
        return _mode == ViewMode.Marketplace
            ? _offers.Count(o => !o.IsLocalOnly)
            : _offers.Count(o => _installedIds.Contains(o.Id));
    }

    private static string TruncateForPill(string text, int maxLen)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Length <= maxLen)
        {
            return text;
        }

        return text[..Math.Max(0, maxLen - 1)] + "…";
    }

    private Control CreateMetaPill(string title, string value)
    {
        var pill = new Label
        {
            AutoSize = true,
            Text = $"{title}: {value}",
            BackColor = Color.FromArgb(220, 235, 248),
            ForeColor = TextPrimary,
            Font = new Font("Segoe UI", 8.6F, FontStyle.Bold),
            Padding = new Padding(8, 5, 8, 5),
            Margin = new Padding(0, 2, 8, 2)
        };

        pill.Paint += (_, e) =>
        {
            using var path = UiPaths.RoundRect(new Rectangle(0, 0, pill.Width - 1, pill.Height - 1), 10);
            pill.Region = new Region(path);
            using var pen = new Pen(Color.FromArgb(181, 210, 236), 1);
            e.Graphics.DrawPath(pen, path);
        };

        return pill;
    }

    private static Panel CreateCardContainer()
    {
        var panel = new Panel
        {
            Dock = DockStyle.Fill,
            BackColor = CardBackground
        };

        panel.Paint += (_, e) =>
        {
            var rect = new Rectangle(0, 0, panel.Width - 1, panel.Height - 1);
            using var path = UiPaths.RoundRect(rect, 12);
            using var border = new Pen(CardBorder, 1);
            panel.Region = new Region(path);
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            e.Graphics.DrawPath(border, path);
        };

        return panel;
    }

    private static void ConfigureActionButton(Button button, Color backColor, Color foreColor)
    {
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.BackColor = backColor;
        button.ForeColor = foreColor;
        button.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        button.Cursor = Cursors.Hand;
        button.Paint += (_, _) =>
        {
            using var path = UiPaths.RoundRect(new Rectangle(0, 0, button.Width, button.Height), 10);
            button.Region = new Region(path);
        };
    }

    private static void ConfigureModeButton(Button button)
    {
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        button.Cursor = Cursors.Hand;
    }

    private static void ApplyModeButtonStyle(Button button, bool active)
    {
        button.BackColor = active ? Color.White : Color.FromArgb(220, 231, 241);
        button.ForeColor = active ? TextPrimary : TextSecondary;
    }

    private void ApplyToolbarModeState()
    {
        var isMarketplace = _mode == ViewMode.Marketplace;
        _regionLabel.Visible = isMarketplace;
        _regionComboBox.Visible = isMarketplace;
        _sortLabel.Visible = isMarketplace;
        _sortComboBox.Visible = isMarketplace;
    }

    private async Task RunWithBusyAsync(Func<Task> action)
    {
        if (_isBusy)
        {
            return;
        }

        try
        {
            _isBusy = true;
            ToggleBusyState(true);
            await action();
        }
        finally
        {
            ToggleBusyState(false);
            _isBusy = false;
            RenderCards();
        }
    }

    private void ToggleBusyState(bool busy)
    {
        _refreshButton.Enabled = !busy;
        _marketModeButton.Enabled = !busy;
        _installedModeButton.Enabled = !busy;
        UseWaitCursor = busy;
    }

    private static class UiPaths
    {
        public static System.Drawing.Drawing2D.GraphicsPath RoundRect(Rectangle rect, int radius)
        {
            var r = Math.Max(2, radius);
            var diameter = r * 2;
            var path = new System.Drawing.Drawing2D.GraphicsPath();

            path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    private sealed class ProviderMarketCardControl : Panel
    {
        private readonly CoreProviderOffer _offer;
        private readonly bool _isInstalled;
        private readonly ViewMode _mode;
        private readonly Func<Task> _onInstallOrUpdate;
        private readonly Func<Task> _onUninstall;

        public ProviderMarketCardControl(CoreProviderOffer offer, bool isInstalled, ViewMode mode, Func<Task> onInstallOrUpdate, Func<Task> onUninstall)
        {
            _offer = offer;
            _isInstalled = isInstalled;
            _mode = mode;
            _onInstallOrUpdate = onInstallOrUpdate;
            _onUninstall = onUninstall;

            Height = mode == ViewMode.Installed ? 168 : 148;
            BackColor = CardBackground;
            Padding = new Padding(12, 10, 12, 10);

            BuildContent();
            Paint += (_, e) =>
            {
                var rect = new Rectangle(0, 0, Width - 1, Height - 1);
                using var path = UiPaths.RoundRect(rect, 10);
                using var pen = new Pen(CardBorder, 1);
                Region = new Region(path);
                e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using var stripBrush = new SolidBrush(Color.FromArgb(123, 224, 236));
                e.Graphics.FillRectangle(stripBrush, 0, 0, 4, Height);
                e.Graphics.DrawPath(pen, path);
            };
        }

        private void BuildContent()
        {
            var title = new Label
            {
                Text = _offer.Name,
                Font = new Font("Segoe UI", 11F, FontStyle.Bold),
                ForeColor = TextPrimary,
                AutoSize = true,
                Location = new Point(12, 10)
            };

            var author = new Label
            {
                Text = string.IsNullOrWhiteSpace(_offer.Author) ? "OpenMesh Team" : _offer.Author,
                Font = new Font("Segoe UI", 8.8F),
                ForeColor = TextSecondary,
                AutoSize = true,
                Location = new Point(12, 34)
            };

            var description = new Label
            {
                Text = string.IsNullOrWhiteSpace(_offer.Description) ? "暂无描述" : _offer.Description,
                Font = new Font("Segoe UI", 9F),
                ForeColor = TextPrimary,
                AutoEllipsis = true,
                MaximumSize = new Size(10000, 34),
                Location = new Point(12, 54),
                Size = new Size(560, 34)
            };

            var details = new Label
            {
                Text = BuildDetailsLine(_offer),
                Font = new Font("Consolas", 8.4F),
                ForeColor = TextSecondary,
                AutoSize = true,
                Location = new Point(12, 92)
            };

            var chipPanel = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                AutoScroll = false,
                BackColor = Color.Transparent,
                Location = new Point(12, _mode == ViewMode.Installed ? 114 : 112),
                Size = new Size(650, 24)
            };

            AddStatusChips(chipPanel);
            AddTagChips(chipPanel);

            Controls.Add(title);
            Controls.Add(author);
            Controls.Add(description);
            Controls.Add(details);
            Controls.Add(chipPanel);

            if (_mode == ViewMode.Marketplace)
            {
                var action = CreateActionButton(GetPrimaryActionText(), GetPrimaryActionColor(), async () => await _onInstallOrUpdate());
                action.SetBounds(Width - 96, 12, 84, 30);
                Controls.Add(action);

                Resize += (_, _) =>
                {
                    description.Width = Math.Max(220, Width - 230);
                    chipPanel.Width = Math.Max(220, Width - 220);
                    action.Left = Width - action.Width - 12;
                };
            }
            else
            {
                var reinstall = CreateActionButton("Reinstall", AccentCyan, async () => await _onInstallOrUpdate());
                var update = CreateActionButton("Update", AccentAmber, async () => await _onInstallOrUpdate());
                var uninstall = CreateActionButton("Uninstall", DangerRed, async () => await _onUninstall());

                update.Enabled = _offer.UpgradeAvailable;

                reinstall.SetBounds(Width - 202, 12, 90, 28);
                update.SetBounds(Width - 106, 12, 90, 28);
                uninstall.SetBounds(Width - 106, 46, 90, 28);

                Controls.Add(reinstall);
                Controls.Add(update);
                Controls.Add(uninstall);

                Resize += (_, _) =>
                {
                    description.Width = Math.Max(220, Width - 340);
                    chipPanel.Width = Math.Max(220, Width - 330);
                    reinstall.Left = Width - reinstall.Width - update.Width - 18;
                    update.Left = Width - update.Width - 12;
                    uninstall.Left = Width - uninstall.Width - 12;
                };
            }
        }

        private void AddStatusChips(FlowLayoutPanel panel)
        {
            if (_offer.UpgradeAvailable)
            {
                panel.Controls.Add(CreateChip("Update", AccentAmber, filled: true));
            }
            else if (_isInstalled)
            {
                panel.Controls.Add(CreateChip("Installed", Color.FromArgb(66, 177, 124), filled: true));
            }

            if (_offer.PendingRuleSets.Count > 0)
            {
                panel.Controls.Add(CreateChip("Init", AccentBlue, filled: true));
            }
        }

        private void AddTagChips(FlowLayoutPanel panel)
        {
            foreach (var tag in _offer.Tags.Take(6))
            {
                panel.Controls.Add(CreateChip(tag, AccentBlue, filled: false));
            }
        }

        private static string BuildDetailsLine(CoreProviderOffer offer)
        {
            var price = offer.PricePerGb > 0 ? $"{offer.PricePerGb:0.00} USD/GB" : "0.00 USD/GB";
            var updated = string.IsNullOrWhiteSpace(offer.UpdatedAt) ? "-" : offer.UpdatedAt;
            var author = string.IsNullOrWhiteSpace(offer.Author) ? "OpenMesh Team" : offer.Author;
            return $"{author}   {price}   {updated}";
        }

        private string GetPrimaryActionText()
        {
            if (_offer.UpgradeAvailable)
            {
                return "Update";
            }

            return _isInstalled ? "Reinstall" : "Install";
        }

        private Color GetPrimaryActionColor()
        {
            if (_offer.UpgradeAvailable)
            {
                return AccentAmber;
            }

            return _isInstalled ? AccentCyan : AccentBlue;
        }

        private static Control CreateChip(string text, Color tint, bool filled)
        {
            var chip = new Label
            {
                AutoSize = true,
                Text = text,
                Font = new Font("Segoe UI", 8F, FontStyle.Bold),
                ForeColor = filled ? Color.White : TextSecondary,
                BackColor = filled ? tint : Color.FromArgb(227, 238, 247),
                Padding = new Padding(8, 4, 8, 4),
                Margin = new Padding(0, 0, 6, 0)
            };

            chip.Paint += (_, e) =>
            {
                using var path = UiPaths.RoundRect(new Rectangle(0, 0, chip.Width - 1, chip.Height - 1), 8);
                chip.Region = new Region(path);
                using var border = new Pen(filled ? tint : Color.FromArgb(191, 214, 232), 1);
                e.Graphics.DrawPath(border, path);
            };

            return chip;
        }

        private static Button CreateActionButton(string text, Color backColor, Func<Task> onClick)
        {
            var button = new Button
            {
                Text = text,
                FlatStyle = FlatStyle.Flat,
                BackColor = backColor,
                ForeColor = Color.White,
                Cursor = Cursors.Hand,
                Font = new Font("Segoe UI", 8.8F, FontStyle.Bold)
            };
            button.FlatAppearance.BorderSize = 0;
            button.Click += async (_, _) => await onClick();
            button.Paint += (_, _) =>
            {
                using var path = UiPaths.RoundRect(new Rectangle(0, 0, button.Width, button.Height), 11);
                button.Region = new Region(path);
            };
            return button;
        }
    }
}
