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
    // Colors
    private static readonly Color MeshPageBackground = Color.FromArgb(242, 246, 250); // Mac-like light gray/blue
    private static readonly Color MeshCardBackground = Color.White;
    private static readonly Color MeshAccentBlue = Color.FromArgb(0, 122, 255); // Mac Blue
    private static readonly Color MeshTextPrimary = Color.FromArgb(0, 0, 0);
    private static readonly Color MeshTextSecondary = Color.FromArgb(142, 142, 147);
    private static readonly Color MeshDivider = Color.FromArgb(229, 229, 234);

    private readonly List<CoreProviderOffer> _allOffers;
    private readonly HashSet<string> _installedIds;
    private readonly Action<string> _onInstall;
    private readonly Action<string> _onUninstall;
    private readonly Action<string> _onActivate;
    private readonly Action _onRefresh;

    // UI Controls
    private Panel _headerPanel = null!;
    private Panel _filterPanel = null!;
    private FlowLayoutPanel _cardsPanel = null!;
    // private SegmentedControl _modeSegmentedControl = null!; // Removed
    private TextBox _searchTextBox = null!;
    private ComboBox _regionComboBox = null!;
    private ComboBox _sortComboBox = null!;
    private Label _countLabel = null!;

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
        UpdateData(_allOffers, _installedIds);
    }

    private void InitializeComponent()
    {
        this.Text = "供应商市场";
        this.Size = new Size(900, 650);
        this.BackColor = MeshPageBackground;
        this.FormBorderStyle = FormBorderStyle.None;
        this.DoubleBuffered = true;

        // --- Header Panel (Title + Segmented Control + Close) ---
        _headerPanel = new Panel
        {
            Dock = DockStyle.Top,
            Height = 70,
            BackColor = Color.Transparent,
            Padding = new Padding(20, 0, 20, 0)
        };

        var titleLabel = new Label
        {
            Text = "推荐供应商",
            Font = new Font("Segoe UI", 16, FontStyle.Bold),
            ForeColor = MeshAccentBlue,
            AutoSize = true,
            Location = new Point(20, 20)
        };
        
        // Action Buttons (Mac Style)
        var btnImport = new Button
        {
            Text = "导入安装", // Icon could be added via Image property if available
            Size = new Size(100, 32),
            Location = new Point(780, 20), // Will anchor
            FlatStyle = FlatStyle.Flat,
            BackColor = MeshAccentBlue,
            ForeColor = Color.White,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            Cursor = Cursors.Hand
        };
        btnImport.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(btnImport, 8);
        // btnImport.Click += ... (Handle import)

        var btnMarket = new Button
        {
            Text = "供应商市场",
            Size = new Size(110, 32),
            Location = new Point(660, 20), // Will anchor
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(229, 229, 234), // Light Gray
            ForeColor = Color.Black,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            Cursor = Cursors.Hand
        };
        btnMarket.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(btnMarket, 8);
        btnMarket.Click += (s, e) => 
        {
            // Toggle mode or just refresh for now
            _currentMode = MarketTabMode.Marketplace;
            RenderCards();
        };

        _headerPanel.Controls.Add(titleLabel);
        _headerPanel.Controls.Add(btnMarket);
        _headerPanel.Controls.Add(btnImport);

        // Anchor support
        _headerPanel.Resize += (s, e) =>
        {
            btnImport.Left = _headerPanel.Width - btnImport.Width - 20;
            btnMarket.Left = btnImport.Left - btnMarket.Width - 15;
        };

        // --- Filter Panel ---
        _filterPanel = new Panel
        {
            Dock = DockStyle.Top,
            Height = 60,
            BackColor = Color.FromArgb(255, 255, 255, 255), // Slight translucent or solid?
        };
        // Draw bottom border for filter panel
        _filterPanel.Paint += (s, e) =>
        {
             using var pen = new Pen(MeshDivider);
             e.Graphics.DrawLine(pen, 0, _filterPanel.Height - 1, _filterPanel.Width, _filterPanel.Height - 1);
        };

        // Search Box Container
        var searchContainer = new Panel
        {
            Size = new Size(300, 32),
            Location = new Point(20, 14),
            BackColor = Color.White
        };
        searchContainer.Paint += (s, e) =>
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var path = GetRoundedPath(searchContainer.ClientRectangle, 16);
            using var pen = new Pen(Color.FromArgb(200, 200, 200));
            e.Graphics.DrawPath(pen, path);
        };
        
        _searchTextBox = new TextBox
        {
            BorderStyle = BorderStyle.None,
            Location = new Point(10, 8),
            Width = 280,
            PlaceholderText = "搜索 (名称/作者/标签/简介)",
            Font = new Font("Segoe UI", 9)
        };
        _searchTextBox.TextChanged += (s, e) => RenderCards();
        searchContainer.Controls.Add(_searchTextBox);

        // Filters
        var regionLabel = new Label { Text = "地区", AutoSize = true, Location = new Point(340, 22), Font = new Font("Segoe UI", 9), ForeColor = MeshTextSecondary };
        _regionComboBox = new ComboBox { Location = new Point(380, 18), Width = 100, DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat };
        _regionComboBox.Items.Add("全部");
        _regionComboBox.SelectedIndex = 0;
        _regionComboBox.SelectedIndexChanged += (s, e) => RenderCards();

        var sortLabel = new Label { Text = "排序", AutoSize = true, Location = new Point(500, 22), Font = new Font("Segoe UI", 9), ForeColor = MeshTextSecondary };
        _sortComboBox = new ComboBox { Location = new Point(540, 18), Width = 120, DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat };
        _sortComboBox.Items.AddRange(new object[] { "更新时间↓", "价格↑", "价格↓" });
        _sortComboBox.SelectedIndex = 0;
        _sortComboBox.SelectedIndexChanged += (s, e) => RenderCards();

        var refreshButton = new Button
        {
            Text = "刷新",
            Size = new Size(60, 28),
            Location = new Point(700, 16),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.White,
            Font = new Font("Segoe UI", 9)
        };
        refreshButton.FlatAppearance.BorderSize = 0;
        ApplyRoundedRegion(refreshButton, 6);
        refreshButton.Click += (s, e) => _onRefresh?.Invoke();

        _countLabel = new Label
        {
            Text = "Market 0/0",
            AutoSize = true,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            ForeColor = MeshTextSecondary,
            Location = new Point(800, 22) // Will align right
        };

        _filterPanel.Controls.Add(searchContainer);
        _filterPanel.Controls.Add(regionLabel);
        _filterPanel.Controls.Add(_regionComboBox);
        _filterPanel.Controls.Add(sortLabel);
        _filterPanel.Controls.Add(_sortComboBox);
        _filterPanel.Controls.Add(refreshButton);
        _filterPanel.Controls.Add(_countLabel);
        
        _filterPanel.Resize += (s, e) =>
        {
            refreshButton.Left = _filterPanel.Width - refreshButton.Width - 20;
             // Push others left if needed, simplified for now
        };

        // --- Cards Panel ---
        _cardsPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            Padding = new Padding(20, 20, 20, 20),
            BackColor = MeshPageBackground,
            FlowDirection = FlowDirection.TopDown, // Force vertical list
            WrapContents = false // Do not wrap, ensure single column
        };
        _cardsPanel.Resize += (s, e) => RenderCards(); // Re-layout cards on resize

        this.Controls.Add(_cardsPanel);
        this.Controls.Add(_filterPanel);
        this.Controls.Add(_headerPanel);

        // Defer initial render to Load event
        this.Load += (s, e) => RenderCards();
    }

    public void UpdateData(List<CoreProviderOffer> offers, HashSet<string> installedIds)
    {
        _allOffers.Clear();
        _allOffers.AddRange(offers);
        _installedIds.Clear();
        foreach(var id in installedIds) _installedIds.Add(id);

        // Update Regions
        var currentRegion = _regionComboBox.SelectedItem as string;
        var regions = _allOffers.Select(o => o.Region).Distinct().OrderBy(r => r).ToList();
        _regionComboBox.Items.Clear();
        _regionComboBox.Items.Add("全部");
        _regionComboBox.Items.AddRange(regions.ToArray());
        if (!string.IsNullOrEmpty(currentRegion) && _regionComboBox.Items.Contains(currentRegion))
             _regionComboBox.SelectedItem = currentRegion;
        else
             _regionComboBox.SelectedIndex = 0;

        if (this.IsHandleCreated) RenderCards();
    }

    private void RenderCards()
    {
        _cardsPanel.SuspendLayout();
        
        // Filter
        var query = _searchTextBox.Text.Trim();
        var region = _regionComboBox.SelectedItem as string;
        var sortMode = _sortComboBox.SelectedIndex;

        var filtered = _allOffers.Where(o =>
        {
            bool isInstalled = _installedIds.Contains(o.Id);
            if (_currentMode == MarketTabMode.Installed && !isInstalled) return false;

            if (!string.IsNullOrEmpty(query))
            {
                if (!o.Name.Contains(query, StringComparison.OrdinalIgnoreCase) &&
                    !o.Description.Contains(query, StringComparison.OrdinalIgnoreCase))
                    return false;
            }

            if (region != "全部" && !string.IsNullOrEmpty(region) && !string.Equals(o.Region, region, StringComparison.OrdinalIgnoreCase))
                return false;

            return true;
        });

        // Sort
        if (sortMode == 1) filtered = filtered.OrderBy(o => o.PricePerGb);
        else if (sortMode == 2) filtered = filtered.OrderByDescending(o => o.PricePerGb);

        var resultList = filtered.ToList();
        _countLabel.Text = $"{(_currentMode == MarketTabMode.Installed ? "Installed" : "Market")} {resultList.Count}";

        // Smart update to avoid flicker? For now just rebuild
        _cardsPanel.Controls.Clear();

        // macOS Style: Full Width List Layout
        // Always take full width minus padding
        // If client size is 0 (not visible yet), use default or skip
        if (_cardsPanel.ClientSize.Width == 0) 
        {
             _cardsPanel.ResumeLayout();
             return;
        }

        int scrollBarWidth = SystemInformation.VerticalScrollBarWidth + 5; 
        int totalPadding = 40; // 20 left + 20 right
        int cardWidth = _cardsPanel.ClientSize.Width - totalPadding;
        
        // If vertical scrollbar is likely to appear, subtract its width to avoid horizontal scrollbar
        // Estimate height needed vs available height
        if (resultList.Count * 165 > _cardsPanel.ClientSize.Height) 
        {
            cardWidth -= scrollBarWidth;
        }

        // Safety check
        if (cardWidth < 300) cardWidth = 300; 

        foreach (var offer in resultList)
        {
            var isInstalled = _installedIds.Contains(offer.Id);
            var card = new ProviderCardControl(offer, isInstalled)
            {
                Width = cardWidth,
                Margin = new Padding(0, 0, 0, 15) // Bottom margin only
            };
            
            card.InstallClicked += () => _onInstall?.Invoke(offer.Id);
            card.UninstallClicked += () => _onUninstall?.Invoke(offer.Id);
            card.ActivateClicked += () => _onActivate?.Invoke(offer.Id);
            
            _cardsPanel.Controls.Add(card);
        }

        _cardsPanel.ResumeLayout();
    }

    private static void ApplyRoundedRegion(Control control, int radius)
    {
        using var path = GetRoundedPath(new Rectangle(0, 0, control.Width, control.Height), radius);
        control.Region = new Region(path);
    }

    private static GraphicsPath GetRoundedPath(Rectangle rect, int radius)
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

// --- Custom Controls ---

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
        this.Height = 30;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = this.ClientRectangle;
        rect.Width -= 1; rect.Height -= 1;

        // Background (Light Gray)
        using (var bgBrush = new SolidBrush(Color.FromArgb(229, 229, 234)))
        using (var path = GetRoundedPath(rect, 6))
        {
            e.Graphics.FillPath(bgBrush, path);
        }

        // Selected Pill (White with shadow)
        var halfWidth = (rect.Width - 4) / 2;
        var selectedRect = new Rectangle(SelectedOption == 0 ? 2 : halfWidth + 2, 2, halfWidth, rect.Height - 4);
        
        using (var pillBrush = new SolidBrush(Color.White))
        using (var path = GetRoundedPath(selectedRect, 6))
        {
            e.Graphics.FillPath(pillBrush, path);
            // Shadow could be drawn here
        }

        // Text
        using (var font = new Font("Segoe UI", 9, FontStyle.Regular))
        using (var textBrush = new SolidBrush(Color.Black))
        using (var selectedTextBrush = new SolidBrush(Color.Black))
        {
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            e.Graphics.DrawString(Option1, font, SelectedOption == 0 ? selectedTextBrush : textBrush, new Rectangle(0, 0, halfWidth + 2, rect.Height), sf);
            e.Graphics.DrawString(Option2, font, SelectedOption == 1 ? selectedTextBrush : textBrush, new Rectangle(halfWidth + 2, 0, halfWidth, rect.Height), sf);
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

    private readonly Button _actionButton;

    public ProviderCardControl(CoreProviderOffer offer, bool isInstalled)
    {
        _offer = offer;
        _isInstalled = isInstalled;
        this.Height = 150; // Increased height to prevent overlap
        this.BackColor = Color.Transparent; // We paint background
        this.DoubleBuffered = true;

        // Context Menu for advanced actions
        var contextMenu = new ContextMenuStrip();
        if (_isInstalled)
        {
            var uninstallItem = new ToolStripMenuItem("Uninstall");
            uninstallItem.Click += (s, e) => UninstallClicked?.Invoke();
            contextMenu.Items.Add(uninstallItem);

            var activateItem = new ToolStripMenuItem("Activate");
            activateItem.Click += (s, e) => ActivateClicked?.Invoke();
            contextMenu.Items.Add(activateItem);
        }
        else
        {
            var installItem = new ToolStripMenuItem("Install");
            installItem.Click += (s, e) => InstallClicked?.Invoke();
            contextMenu.Items.Add(installItem);
        }
        this.ContextMenuStrip = contextMenu;

        // Action Button
        var btnText = "Install";
        var btnColor = Color.FromArgb(0, 122, 255); // Blue

        if (_isInstalled)
        {
            if (_offer.UpgradeAvailable)
            {
                btnText = "Update";
                btnColor = Color.Orange;
            }
            else
            {
                btnText = "Reinstall";
                btnColor = Color.FromArgb(0, 199, 190); // Cyan/Teal
            }
        }

        _actionButton = new Button
        {
            Text = btnText,
            BackColor = btnColor,
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            Size = new Size(80, 28),
            Cursor = Cursors.Hand
        };
        _actionButton.FlatAppearance.BorderSize = 0;
        _actionButton.Click += (s, e) => InstallClicked?.Invoke();
        
        // Round button
        using var path = GetRoundedPath(new Rectangle(0, 0, _actionButton.Width, _actionButton.Height), 14);
        _actionButton.Region = new Region(path);

        this.Controls.Add(_actionButton);
        
        // Handle layout in Layout event or Resize
        this.Resize += (s, e) =>
        {
             _actionButton.Location = new Point(this.Width - _actionButton.Width - 20, 20);
        };
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        // Card Background (White with rounded corners)
        var rect = new Rectangle(0, 0, this.Width - 1, this.Height - 1);
        using (var bgBrush = new SolidBrush(Color.White))
        using (var borderPen = new Pen(Color.FromArgb(229, 229, 234))) // Mac Divider Color (Subtle)
        using (var path = GetRoundedPath(rect, 12))
        {
            e.Graphics.FillPath(bgBrush, path);
            e.Graphics.DrawPath(borderPen, path);
        }

        // Title
        using (var titleFont = new Font("Segoe UI", 12, FontStyle.Bold)) // Larger Title
        using (var titleBrush = new SolidBrush(Color.Black))
        {
            e.Graphics.DrawString(_offer.Name, titleFont, titleBrush, 24, 24); // More padding
        }

        // Author (Subtitle)
        using (var authorFont = new Font("Segoe UI", 9, FontStyle.Regular))
        using (var authorBrush = new SolidBrush(Color.Gray))
        {
            e.Graphics.DrawString("OpenMesh Team", authorFont, authorBrush, 24, 50);
        }

        // Description
        using (var descFont = new Font("Segoe UI", 9, FontStyle.Regular))
        using (var descBrush = new SolidBrush(Color.DimGray))
        {
            var desc = string.IsNullOrEmpty(_offer.Description) ? "暂无描述" : _offer.Description;
            // Limit to 2 lines
            var layoutRect = new RectangleF(24, 75, this.Width - 150, 35); // Adjusted layout
            var format = new StringFormat { Trimming = StringTrimming.EllipsisCharacter };
            e.Graphics.DrawString(desc, descFont, descBrush, layoutRect, format);
        }

        // Tags (Bottom)
        var tags = new List<string> { "Official" };
        if (_offer.Name.Contains("AI", StringComparison.OrdinalIgnoreCase)) 
        {
            tags.Add("AI");
            tags.Add("SplitTunnel");
            tags.Add("ForceProxy");
        }
        else 
        {
            tags.Add("Online");
        }
        
        int tagX = 24;
        using (var tagBgBrush = new SolidBrush(Color.FromArgb(242, 242, 247))) // Mac Field Background
        using (var tagTextBrush = new SolidBrush(Color.FromArgb(99, 99, 102))) // Mac Secondary Label
        using (var tagFont = new Font("Segoe UI", 8, FontStyle.Bold))
        {
            foreach (var tag in tags)
            {
                var tagSize = TextRenderer.MeasureText(tag, tagFont);
                var tagRect = new Rectangle(tagX, 118, tagSize.Width + 16, 22); 
                
                using (var tagPath = GetRoundedPath(tagRect, 10))
                {
                    e.Graphics.FillPath(tagBgBrush, tagPath);
                }
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                e.Graphics.DrawString(tag, tagFont, tagTextBrush, tagRect, sf);
                
                tagX += tagRect.Width + 8;
            }
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
