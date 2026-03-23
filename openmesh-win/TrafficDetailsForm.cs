using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using Microsoft.Win32;

namespace OpenMeshWin;

internal sealed class TrafficDetailsForm : Form
{
    private static readonly Color MeshBlue = Color.FromArgb(71, 167, 230);
    private static readonly Color MeshGreen = Color.FromArgb(60, 199, 128);
    private static readonly Color MeshBackgroundDark = Color.FromArgb(17, 26, 38);
    private static readonly Color MeshCardDark = Color.FromArgb(28, 42, 58);
    private static readonly Color MeshTextPrimaryDark = Color.White;
    private static readonly Color MeshTextSecondaryDark = Color.FromArgb(170, 185, 200);

    private static readonly Color MeshBackgroundLight = Color.FromArgb(235, 243, 251);
    private static readonly Color MeshCardLight = Color.White;
    private static readonly Color MeshTextPrimaryLight = Color.FromArgb(40, 56, 72);
    private static readonly Color MeshTextSecondaryLight = Color.FromArgb(100, 120, 140);

    private bool _isDarkMode = true;
    private Color _themeBg;
    private Color _themeCard;
    private Color _themeTextPrimary;
    private Color _themeTextSecondary;

    private readonly Label _headerLabel = new();
    private readonly Label _subtitleLabel = new();
    private readonly MetricCard _upTotalCard;
    private readonly MetricCard _downTotalCard;
    private readonly RateBadge _upRateBadge;
    private readonly RateBadge _downRateBadge;
    private readonly BigTrafficChartPanel _chartPanel = new();
    private readonly Panel _chartContainer = new();

    private Queue<float> _uploadHistory = new();
    private Queue<float> _downloadHistory = new();

    public TrafficDetailsForm()
    {
        Text = "流量合计";
        Size = new Size(580, 480);
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        MinimizeBox = false;
        DoubleBuffered = true;

        DetectTheme();

        BackColor = _themeBg;

        _headerLabel.Text = "流量合计";
        _headerLabel.Font = new Font("Segoe UI Semibold", 20F, FontStyle.Bold);
        _headerLabel.ForeColor = _themeTextPrimary;
        _headerLabel.SetBounds(24, 24, 200, 40);
        _headerLabel.BackColor = Color.Transparent;

        _subtitleLabel.Text = "连接态显示实时数据";
        _subtitleLabel.Font = new Font("Segoe UI Semibold", 10F, FontStyle.Bold);
        _subtitleLabel.ForeColor = _themeTextSecondary;
        _subtitleLabel.TextAlign = ContentAlignment.MiddleRight;
        _subtitleLabel.SetBounds(340, 32, 200, 24);
        _subtitleLabel.BackColor = Color.Transparent;

        _upTotalCard = new MetricCard("上行合计", MeshBlue, _isDarkMode);
        _upTotalCard.SetBounds(24, 78, 240, 84);

        _downTotalCard = new MetricCard("下行合计", MeshGreen, _isDarkMode);
        _downTotalCard.SetBounds(276, 78, 240, 84);

        _chartContainer.SetBounds(24, 182, 516, 240);
        _chartContainer.BackColor = _themeCard;
        ApplyRoundedRegion(_chartContainer, 14);

        _upRateBadge = new RateBadge("上行增量", MeshBlue, _isDarkMode);
        _upRateBadge.SetBounds(16, 16, 140, 26);
        _chartContainer.Controls.Add(_upRateBadge);

        _downRateBadge = new RateBadge("下行增量", MeshGreen, _isDarkMode);
        _downRateBadge.SetBounds(164, 16, 140, 26);
        _chartContainer.Controls.Add(_downRateBadge);

        _chartPanel.SetBounds(16, 52, 484, 172);
        _chartPanel.BackColor = Color.Transparent;
        _chartContainer.Controls.Add(_chartPanel);

        Controls.Add(_headerLabel);
        Controls.Add(_subtitleLabel);
        Controls.Add(_upTotalCard);
        Controls.Add(_downTotalCard);
        Controls.Add(_chartContainer);
    }

    private void DetectTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            _isDarkMode = value is int i && i == 0;
        }
        catch
        {
            _isDarkMode = true;
        }

        if (_isDarkMode)
        {
            _themeBg = MeshBackgroundDark;
            _themeCard = MeshCardDark;
            _themeTextPrimary = MeshTextPrimaryDark;
            _themeTextSecondary = MeshTextSecondaryDark;
        }
        else
        {
            _themeBg = MeshBackgroundLight;
            _themeCard = MeshCardLight;
            _themeTextPrimary = MeshTextPrimaryLight;
            _themeTextSecondary = MeshTextSecondaryLight;
        }
    }

    public void UpdateData(CoreRuntimeStats runtime, Queue<float> uploadHistory, Queue<float> downloadHistory)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => UpdateData(runtime, uploadHistory, downloadHistory));
            return;
        }

        _upTotalCard.Value = FormatBytes(runtime.TotalUploadBytes);
        _downTotalCard.Value = FormatBytes(runtime.TotalDownloadBytes);
        _upRateBadge.Value = FormatRateShort(runtime.UploadRateBytesPerSec);
        _downRateBadge.Value = FormatRateShort(runtime.DownloadRateBytesPerSec);

        _chartPanel.SetSamples(uploadHistory, downloadHistory);
    }

    private static string FormatBytes(long bytes)
    {
        var value = Math.Max(0, bytes);
        var units = new[] { "B", "KB", "MB", "GB", "TB" };
        var unitIndex = 0;
        var scaled = (double)value;
        while (scaled >= 1024 && unitIndex < units.Length - 1)
        {
            scaled /= 1024;
            unitIndex++;
        }
        return $"{scaled:F1} {units[unitIndex]}";
    }

    private static string FormatRateShort(long bytesPerSec)
    {
        var value = (double)bytesPerSec;
        if (value >= 1024 * 1024) return $"{value / (1024 * 1024):F1} MB/s";
        if (value >= 1024) return $"{value / 1024:F1} KB/s";
        return $"{value:F0} B/s";
    }

    private static void ApplyRoundedRegion(Control control, int radius)
    {
        var rect = new Rectangle(0, 0, Math.Max(1, control.Width), Math.Max(1, control.Height));
        using var path = CreateRoundedPath(rect, radius);
        control.Region = new Region(path);
    }

    private static GraphicsPath CreateRoundedPath(Rectangle rect, int radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        if (radius <= 0) { path.AddRectangle(rect); return path; }
        path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private sealed class MetricCard : Panel
    {
        private readonly string _title;
        private readonly Color _accentColor;
        private readonly bool _darkMode;
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        private string _value = "0.0 B";
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        public string Value
        {
            get => _value;
            set { if (_value != value) { _value = value; Invalidate(); } }
        }

        public MetricCard(string title, Color accentColor, bool darkMode)
        {
            _title = title;
            _accentColor = accentColor;
            _darkMode = darkMode;
            DoubleBuffered = true;
            BackColor = darkMode ? MeshCardDark : MeshCardLight;
            ApplyRoundedRegion(this, 14);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            // Icon Circle
            var circleRect = new Rectangle(16, (Height - 40) / 2, 40, 40);
            using (var brush = new SolidBrush(Color.FromArgb(40, _accentColor)))
                e.Graphics.FillEllipse(brush, circleRect);
            using (var pen = new Pen(Color.FromArgb(80, _accentColor), 1.5F))
                e.Graphics.DrawEllipse(pen, circleRect);

            // Simple Chart Icon
            using (var iconBrush = new SolidBrush(_accentColor))
            {
                e.Graphics.FillRectangle(iconBrush, circleRect.X + 12, circleRect.Y + 22, 4, 8);
                e.Graphics.FillRectangle(iconBrush, circleRect.X + 18, circleRect.Y + 16, 4, 14);
                e.Graphics.FillRectangle(iconBrush, circleRect.X + 24, circleRect.Y + 12, 4, 18);
            }

            // Text
            var titleFont = new Font("Segoe UI Semibold", 10F, FontStyle.Bold);
            var valueFont = new Font("Consolas", 18F, FontStyle.Bold);
            var textX = circleRect.Right + 12;

            using (var titleBrush = new SolidBrush(_darkMode ? MeshTextSecondaryDark : MeshTextSecondaryLight))
                e.Graphics.DrawString(_title, titleFont, titleBrush, textX, 18);

            using (var valueBrush = new SolidBrush(_darkMode ? MeshTextPrimaryDark : MeshTextPrimaryLight))
                e.Graphics.DrawString(Value, valueFont, valueBrush, textX, 38);
        }
    }

    private sealed class RateBadge : Panel
    {
        private readonly string _label;
        private readonly Color _accentColor;
        private readonly bool _darkMode;
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        private string _value = "0.0 KB/s";
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        public string Value
        {
            get => _value;
            set { if (_value != value) { _value = value; Invalidate(); } }
        }

        public RateBadge(string label, Color accentColor, bool darkMode)
        {
            _label = label;
            _accentColor = accentColor;
            _darkMode = darkMode;
            DoubleBuffered = true;
            BackColor = Color.FromArgb(25, accentColor);
            ApplyRoundedRegion(this, 6);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            var font = new Font("Segoe UI", 9F, FontStyle.Bold);
            var arrow = _label.Contains("上行") ? "↑" : "↓";
            
            using (var accentBrush = new SolidBrush(_accentColor))
                e.Graphics.DrawString(arrow, font, accentBrush, 6, 5);

            using (var textBrush = new SolidBrush(_darkMode ? MeshTextPrimaryDark : MeshTextPrimaryLight))
            {
                e.Graphics.DrawString(_label, font, textBrush, 22, 5);
                var valueX = 22 + e.Graphics.MeasureString(_label, font).Width + 4;
                using var monofont = new Font("Consolas", 9F, FontStyle.Bold);
                e.Graphics.DrawString(Value, monofont, textBrush, valueX, 5);
            }
        }
    }

    private sealed class BigTrafficChartPanel : Panel
    {
        private float[] _uploadSamples = [];
        private float[] _downloadSamples = [];

        public BigTrafficChartPanel()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
        }

        public void SetSamples(IEnumerable<float> upload, IEnumerable<float> download)
        {
            _uploadSamples = [.. upload];
            _downloadSamples = [.. download];
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            var rect = ClientRectangle;
            
            // Grid lines
            using (var gridPen = new Pen(Color.FromArgb(20, Color.White), 1F))
            {
                // Horizontal
                for (int i = 0; i <= 5; i++)
                {
                    var y = rect.Top + (rect.Height * i / 5f);
                    e.Graphics.DrawLine(gridPen, rect.Left, y, rect.Right, y);
                }
                // Vertical
                for (int i = 0; i <= 10; i++)
                {
                    var x = rect.Left + (rect.Width * i / 10f);
                    e.Graphics.DrawLine(gridPen, x, rect.Top, x, rect.Bottom);
                }
            }

            if (_uploadSamples.Length < 2 && _downloadSamples.Length < 2) return;

            var maxValue = Math.Max(1024F, Math.Max(_uploadSamples.Any() ? _uploadSamples.Max() : 0, _downloadSamples.Any() ? _downloadSamples.Max() : 0));
            
            DrawSeries(e.Graphics, _uploadSamples, MeshBlue, maxValue, rect, true);
            DrawSeries(e.Graphics, _downloadSamples, MeshGreen, maxValue, rect, true);
        }

        private static void DrawSeries(Graphics g, float[] samples, Color color, float maxValue, Rectangle rect, bool fill)
        {
            if (samples.Length < 2) return;

            var points = new PointF[samples.Length];
            var width = rect.Width;
            var height = rect.Height - 10;
            for (var i = 0; i < samples.Length; i++)
            {
                var x = rect.Left + (width * i / (samples.Length - 1f));
                var normalized = Math.Clamp(samples[i] / maxValue, 0F, 1F);
                var y = rect.Bottom - (height * normalized);
                points[i] = new PointF(x, y);
            }

            if (fill)
            {
                using var fillPath = new GraphicsPath();
                fillPath.AddLines(points);
                fillPath.AddLine(points.Last(), new PointF(points.Last().X, rect.Bottom));
                fillPath.AddLine(new PointF(points.First().X, rect.Bottom), points.First());
                fillPath.CloseFigure();

                using var fillBrush = new LinearGradientBrush(
                    new Rectangle(0, rect.Top, 1, rect.Height),
                    Color.FromArgb(60, color),
                    Color.FromArgb(0, color),
                    90F);
                g.FillPath(fillBrush, fillPath);
            }

            using var pen = new Pen(color, 2.5F) { LineJoin = LineJoin.Round, StartCap = LineCap.Round, EndCap = LineCap.Round };
            g.DrawLines(pen, points);
        }
    }
}
