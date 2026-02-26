using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

using System.ComponentModel;

namespace OpenMeshWin;

internal class ProviderMarketForm : Form
{
    // Colors (matching MeshFluxMainForm)
    private static readonly Color MeshPageBackground = Color.FromArgb(219, 234, 247);
    private static readonly Color MeshCardBackground = Color.FromArgb(238, 246, 253);
    private static readonly Color MeshAccentBlue = Color.FromArgb(71, 167, 230);
    private static readonly Color MeshTextPrimary = Color.FromArgb(40, 56, 72);
    private static readonly Color MeshTextMuted = Color.FromArgb(102, 119, 138);
    private static readonly Color MeshAccentGreen = Color.FromArgb(46, 204, 113); // For Installed tag
    private static readonly Color MeshAccentCyan = Color.FromArgb(26, 188, 156); // For Action Button

    private readonly List<CoreProviderOffer> _allOffers;
    private readonly HashSet<string> _installedIds;
    private readonly Action<string> _onInstall;
    private readonly Action<string> _onUninstall;
    private readonly Action<string> _onActivate;
    private readonly Action _onRefresh;

    // UI Controls
    private Panel _topPanel = null!;
    private Label _titleLabel = null!;
    private Label _subtitleLabel = null!;
    private Button _closeButton = null!;
    private Panel _filterPanel = null!;
    private TextBox _searchTextBox = null!;
    private ComboBox _regionComboBox = null!;
    private ComboBox _sortComboBox = null!;
    private Button _refreshButton = null!;
    private Label _marketCountLabel = null!;
    private FlowLayoutPanel _cardsPanel = null!;
    private SegmentedControl _modeSegmentedControl = null!;


    private MarketTabMode _currentMode = MarketTabMode.Marketplace;

    public enum MarketTabMode
    {
        Marketplace,
        Installed
    }

    public ProviderMarketForm(
        List<CoreProviderOffer> offers, 
        HashSet<string> installedIds,
        Action<string> onInstall,
        Action<string> onUninstall,
        Action<string> onActivate,
        Action onRefresh)
    {
        _allOffers = offers ?? new List<CoreProviderOffer>();
        _installedIds = installedIds ?? new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        _onInstall = onInstall;
        _onUninstall = onUninstall;
        _onActivate = onActivate;
        _onRefresh = onRefresh;

        InitializeComponent();
        ApplyLayout();
        RenderCards();
    }

    private void InitializeComponent()
    {
        this.Text = "供应商市场";
        this.Size = new Size(900, 650);
        this.StartPosition = FormStartPosition.CenterScreen;
        this.FormBorderStyle = FormBorderStyle.None; // Custom title bar
        this.BackColor = MeshPageBackground;
        this.DoubleBuffered = true;

        // --- Top Panel ---
        _topPanel = new Panel
        {
            Dock = DockStyle.Top,
            Height = 80,
            BackColor = Color.Transparent,
            Padding = new Padding(24, 20, 24, 10)
        };

        _titleLabel = new Label
        {
            Text = "供应商市场",
            Font = new Font("Segoe UI", 16, FontStyle.Bold),
            ForeColor = MeshAccentBlue,
            AutoSize = true,
            Location = new Point(24, 20)
        };

        _subtitleLabel = new Label
        {
            Text = "搜索、排序、安装/更新供应商",
            Font = new Font("Segoe UI", 9, FontStyle.Regular),
            ForeColor = MeshTextMuted,
            AutoSize = true,
            Location = new Point(26, 52)
        };

        _closeButton = new Button
        {
            Text = "关闭",
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            ForeColor = MeshTextPrimary,
            BackColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Size = new Size(60, 30),
            Location = new Point(816, 25), // Will be anchored
            Cursor = Cursors.Hand
        };
        _closeButton.FlatAppearance.BorderSize = 0;
        _closeButton.Click += (s, e) => this.Close();
        ApplyRoundedRegion(_closeButton, 8);

        _modeSegmentedControl = new SegmentedControl
        {
            Location = new Point(600, 25),
            Size = new Size(200, 32),
            Option1 = "Marketplace",
            Option2 = "Installed",
            SelectedOption = 0
        };
        _modeSegmentedControl.OptionSelected += (idx) =>
        {
            _currentMode = idx == 0 ? MarketTabMode.Marketplace : MarketTabMode.Installed;
            RenderCards();
        };

        _topPanel.Controls.Add(_titleLabel);
        _topPanel.Controls.Add(_subtitleLabel);
        _topPanel.Controls.Add(_modeSegmentedControl);
        _topPanel.Controls.Add(_closeButton);

        // --- Filter Panel ---
        _filterPanel = new Panel
        {
            Dock = DockStyle.Top,
            Height = 100,
            BackColor = Color.Transparent,
            Padding = new Padding(24, 10, 24, 10)
        };

        // Search Box (Rounded via Paint or Panel)
        var searchPanel = new Panel
        {
            Size = new Size(400, 36),
            Location = new Point(24, 10),
            BackColor = Color.White
        };
        ApplyRoundedRegion(searchPanel, 8);
        
        _searchTextBox = new TextBox
        {
            BorderStyle = BorderStyle.None,
            Font = new Font("Segoe UI", 10),
            Location = new Point(10, 8),
            Width = 380,
            PlaceholderText = "搜索 (名称/作者/标签/简介)"
        };
        _searchTextBox.TextChanged += (s, e) => RenderCards();
        searchPanel.Controls.Add(_searchTextBox);

        // Filters
        var regionLabel = new Label { Text = "地区", AutoSize = true, Location = new Point(450, 18), Font = new Font("Segoe UI", 9, FontStyle.Bold), ForeColor = MeshTextPrimary };
        _regionComboBox = new ComboBox { Location = new Point(490, 15), Width = 100, DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat };
        _regionComboBox.Items.Add("全部");
        _regionComboBox.SelectedIndex = 0; // Default
        // Populate regions later

        var sortLabel = new Label { Text = "排序", AutoSize = true, Location = new Point(610, 18), Font = new Font("Segoe UI", 9, FontStyle.Bold), ForeColor = MeshTextPrimary };
        _sortComboBox = new ComboBox { Location = new Point(650, 15), Width = 120, DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat };
        _sortComboBox.Items.AddRange(new object[] { "更新时间↓", "价格↑", "价格↓" });
        _sortComboBox.SelectedIndex = 0;
        _sortComboBox.SelectedIndexChanged += (s, e) => RenderCards();

        _refreshButton = new Button
        {
            Text = "刷新",
            Location = new Point(800, 13),
            Size = new Size(60, 30),
            BackColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9, FontStyle.Regular),
            Cursor = Cursors.Hand
        };
        _refreshButton.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(_refreshButton, 6);
        _refreshButton.Click += (s, e) => _onRefresh?.Invoke();

        // Status Line
        _marketCountLabel = new Label
        {
            Text = "Market 0/0",
            Location = new Point(24, 60),
            AutoSize = true,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            ForeColor = MeshTextMuted,
            BackColor = Color.FromArgb(200, 220, 240),
            Padding = new Padding(4, 2, 4, 2)
        };
        // Hacky rounded label background needs Paint event, skipping for simplicity or use Paint

        _filterPanel.Controls.Add(searchPanel);
        _filterPanel.Controls.Add(regionLabel);
        _filterPanel.Controls.Add(_regionComboBox);
        _filterPanel.Controls.Add(sortLabel);
        _filterPanel.Controls.Add(_sortComboBox);
        _filterPanel.Controls.Add(_refreshButton);
        _filterPanel.Controls.Add(_marketCountLabel);

        // --- Cards Panel ---
        _cardsPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            Padding = new Padding(24, 0, 24, 20),
            BackColor = Color.Transparent
        };

        this.Controls.Add(_cardsPanel);
        this.Controls.Add(_filterPanel);
        this.Controls.Add(_topPanel);

        // Draggable Form
        _topPanel.MouseDown += (s, e) => { if (e.Button == MouseButtons.Left) { ReleaseCapture(); SendMessage(Handle, WM_NCLBUTTONDOWN, HT_CAPTION, 0); } };
    }

    private void ApplyLayout()
    {
        // Adjust control positions if needed
        _closeButton.Left = this.Width - _closeButton.Width - 24;
        _modeSegmentedControl.Left = _closeButton.Left - _modeSegmentedControl.Width - 20;
    }

    public void UpdateData(List<CoreProviderOffer> offers, HashSet<string> installedIds)
    {
        _allOffers.Clear();
        _allOffers.AddRange(offers);
        _installedIds.Clear();
        foreach(var id in installedIds) _installedIds.Add(id);
        
        // Update Region Combo
        var currentRegion = _regionComboBox.SelectedItem as string;
        var regions = _allOffers.Select(o => o.Region).Distinct().OrderBy(r => r).ToList();
        _regionComboBox.Items.Clear();
        _regionComboBox.Items.Add("全部");
        _regionComboBox.Items.AddRange(regions.ToArray());
        if (!string.IsNullOrEmpty(currentRegion) && _regionComboBox.Items.Contains(currentRegion))
            _regionComboBox.SelectedItem = currentRegion;
        else
            _regionComboBox.SelectedIndex = 0;

        RenderCards();
    }

    private void RenderCards()
    {
        _cardsPanel.SuspendLayout();
        _cardsPanel.Controls.Clear();

        var query = _searchTextBox.Text.Trim();
        var region = _regionComboBox.SelectedItem as string;
        var sortMode = _sortComboBox.SelectedIndex;

        var filtered = _allOffers.Where(o =>
        {
            // Mode Filter
            bool isInstalled = _installedIds.Contains(o.Id);
            if (_currentMode == MarketTabMode.Installed && !isInstalled) return false;

            // Search Filter
            if (!string.IsNullOrEmpty(query))
            {
                if (!o.Name.Contains(query, StringComparison.OrdinalIgnoreCase) &&
                    !o.Description.Contains(query, StringComparison.OrdinalIgnoreCase) &&
                    !o.Id.Contains(query, StringComparison.OrdinalIgnoreCase))
                    return false;
            }

            // Region Filter
            if (region != "全部" && !string.IsNullOrEmpty(region) && !string.Equals(o.Region, region, StringComparison.OrdinalIgnoreCase))
                return false;

            return true;
        });

        // Sort
        if (sortMode == 1) // Price asc
            filtered = filtered.OrderBy(o => o.PricePerGb);
        else if (sortMode == 2) // Price desc
            filtered = filtered.OrderByDescending(o => o.PricePerGb);
        // Default (0) could be update time, but we don't have that field yet in CoreProviderOffer, 
        // so we use Name or just keep list order.
        // Assuming list order is roughly updated time or relevance.

        var resultList = filtered.ToList();
        _marketCountLabel.Text = $"{(_currentMode == MarketTabMode.Installed ? "Installed" : "Market")} {resultList.Count}/{_allOffers.Count}";

        foreach (var offer in resultList)
        {
            var isInstalled = _installedIds.Contains(offer.Id);
            var card = new ProviderCardControl(offer, isInstalled)
            {
                Width = _cardsPanel.ClientSize.Width - 50, // Full width minus scrollbar/padding
                Margin = new Padding(0, 0, 0, 12)
            };
            
            card.InstallClicked += () => _onInstall?.Invoke(offer.Id);
            card.UninstallClicked += () => _onUninstall?.Invoke(offer.Id);
            card.ActivateClicked += () => _onActivate?.Invoke(offer.Id);
            
            _cardsPanel.Controls.Add(card);
        }

        _cardsPanel.ResumeLayout();
    }

    // Win32 for dragging
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    public static extern bool ReleaseCapture();
    public const int WM_NCLBUTTONDOWN = 0xA1;
    public const int HT_CAPTION = 0x2;

    private void ApplyRoundedRegion(Control control, int radius)
    {
        var bounds = new Rectangle(0, 0, control.Width, control.Height);
        var path = new GraphicsPath();
        path.AddArc(bounds.X, bounds.Y, radius, radius, 180, 90);
        path.AddArc(bounds.X + bounds.Width - radius, bounds.Y, radius, radius, 270, 90);
        path.AddArc(bounds.X + bounds.Width - radius, bounds.Y + bounds.Height - radius, radius, radius, 0, 90);
        path.AddArc(bounds.X, bounds.Y + bounds.Height - radius, radius, radius, 90, 90);
        path.CloseAllFigures();
        control.Region = new Region(path);
    }
}

public class SegmentedControl : Control
{
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string Option1 { get; set; } = "Option 1";
    
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string Option2 { get; set; } = "Option 2";
    
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public int SelectedOption { get; set; } = 0;
    public event Action<int>? OptionSelected;

    public SegmentedControl()
    {
        this.DoubleBuffered = true;
        this.Cursor = Cursors.Hand;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = this.ClientRectangle;
        rect.Width -= 1; rect.Height -= 1;

        // Background
        using (var bgBrush = new SolidBrush(Color.FromArgb(220, 225, 230)))
        using (var path = GetRoundedPath(rect, 8))
        {
            e.Graphics.FillPath(bgBrush, path);
        }

        // Selected Pill
        var halfWidth = rect.Width / 2;
        var selectedRect = new Rectangle(SelectedOption == 0 ? 2 : halfWidth, 2, halfWidth - 2, rect.Height - 4);
        
        using (var pillBrush = new SolidBrush(Color.FromArgb(180, 190, 200))) // Darker gray for selected
        using (var path = GetRoundedPath(selectedRect, 6))
        {
            e.Graphics.FillPath(pillBrush, path);
        }

        // Text
        using (var font = new Font("Segoe UI", 9, FontStyle.Bold))
        using (var textBrush = new SolidBrush(Color.FromArgb(60, 70, 80)))
        {
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            e.Graphics.DrawString(Option1, font, textBrush, new Rectangle(0, 0, halfWidth, rect.Height), sf);
            e.Graphics.DrawString(Option2, font, textBrush, new Rectangle(halfWidth, 0, halfWidth, rect.Height), sf);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        var halfWidth = this.Width / 2;
        var newSelection = e.X < halfWidth ? 0 : 1;
        if (newSelection != SelectedOption)
        {
            SelectedOption = newSelection;
            Invalidate();
            OptionSelected?.Invoke(SelectedOption);
        }
    }

    private GraphicsPath GetRoundedPath(Rectangle rect, int radius)
    {
        var path = new GraphicsPath();
        path.AddArc(rect.X, rect.Y, radius, radius, 180, 90);
        path.AddArc(rect.Right - radius, rect.Y, radius, radius, 270, 90);
        path.AddArc(rect.Right - radius, rect.Bottom - radius, radius, radius, 0, 90);
        path.AddArc(rect.X, rect.Bottom - radius, radius, radius, 90, 90);
        path.CloseAllFigures();
        return path;
    }
}

internal class ProviderCardControl : Panel
{
    private readonly CoreProviderOffer _offer;
    private readonly bool _isInstalled;
    
    public event Action? InstallClicked;
    public event Action? UninstallClicked;
    public event Action? ActivateClicked;

    public ProviderCardControl(CoreProviderOffer offer, bool isInstalled)
    {
        _offer = offer;
        _isInstalled = isInstalled;
        this.Height = 110;
        this.BackColor = Color.White;
        this.DoubleBuffered = true;
        
        // Shadow/Border handled in Paint
        
        // Setup Controls
        var nameLabel = new Label
        {
            Text = _offer.Name,
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Color.Black,
            AutoSize = true,
            Location = new Point(20, 15)
        };

        var descLabel = new Label
        {
            Text = string.IsNullOrEmpty(_offer.Description) ? "暂无描述" : _offer.Description,
            Font = new Font("Segoe UI", 9, FontStyle.Regular),
            ForeColor = Color.Gray,
            AutoSize = true,
            Location = new Point(20, 40)
        };

        var infoLabel = new Label
        {
            Text = $"OpenMesh Team  {_offer.PricePerGb:F2} USD/GB  {_offer.Region}",
            Font = new Font("Segoe UI", 8.5f, FontStyle.Regular),
            ForeColor = Color.DimGray,
            AutoSize = true,
            Location = new Point(20, 65)
        };

        // Action Button
        var actionBtn = new Button
        {
            Text = _isInstalled ? "Reinstall" : "Install", // Or "Uninstall" based on context, but screenshot shows "Reinstall" for installed
            BackColor = Color.FromArgb(100, 220, 240), // Cyan-ish
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            Size = new Size(80, 30),
            Location = new Point(this.Width - 100, 15), // Will anchor
            Cursor = Cursors.Hand
        };
        actionBtn.FlatAppearance.BorderSize = 0;
        actionBtn.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        actionBtn.Click += (s, e) => InstallClicked?.Invoke(); // Simplified logic for now

        // Round the button
        var path = new GraphicsPath();
        var radius = 15; // Pill shape
        path.AddArc(0, 0, radius, radius, 180, 90);
        path.AddArc(actionBtn.Width - radius, 0, radius, radius, 270, 90);
        path.AddArc(actionBtn.Width - radius, actionBtn.Height - radius, radius, radius, 0, 90);
        path.AddArc(0, actionBtn.Height - radius, radius, radius, 90, 90);
        actionBtn.Region = new Region(path);

        this.Controls.Add(nameLabel);
        this.Controls.Add(descLabel);
        this.Controls.Add(infoLabel);
        this.Controls.Add(actionBtn);

        // Installed Tag
        if (_isInstalled)
        {
            var tagLabel = new Label
            {
                Text = "Installed",
                ForeColor = Color.FromArgb(46, 204, 113),
                BackColor = Color.FromArgb(235, 250, 240),
                Font = new Font("Segoe UI", 8, FontStyle.Bold),
                AutoSize = true,
                Location = new Point(nameLabel.Right + 10, 17),
                Padding = new Padding(4, 2, 4, 2)
            };
            this.Controls.Add(tagLabel);
        }
        
        // Mock Tags (bottom row)
        // ... omitted for brevity, would require dynamic placement
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        // Rounded Border/Background
        var rect = this.ClientRectangle;
        rect.Width -= 1; rect.Height -= 1;
        using (var pen = new Pen(Color.FromArgb(220, 230, 240), 1))
        using (var path = GetRoundedPath(rect, 12))
        {
            e.Graphics.DrawPath(pen, path);
        }
    }

    private GraphicsPath GetRoundedPath(Rectangle rect, int radius)
    {
        var path = new GraphicsPath();
        path.AddArc(rect.X, rect.Y, radius, radius, 180, 90);
        path.AddArc(rect.Right - radius, rect.Y, radius, radius, 270, 90);
        path.AddArc(rect.Right - radius, rect.Bottom - radius, radius, radius, 0, 90);
        path.AddArc(rect.X, rect.Bottom - radius, radius, radius, 90, 90);
        path.CloseAllFigures();
        return path;
    }
}
