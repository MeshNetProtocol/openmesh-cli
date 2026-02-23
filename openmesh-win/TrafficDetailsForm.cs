namespace OpenMeshWin;

internal sealed class TrafficDetailsForm : Form
{
    private readonly Label _summaryLabel = new();
    private readonly Label _rateLabel = new();
    private readonly ListView _listView = new()
    {
        View = View.Details,
        FullRowSelect = true,
        GridLines = true,
        HideSelection = false
    };

    public TrafficDetailsForm(CoreRuntimeStats runtime, List<CoreConnection> connections)
    {
        Text = "OpenMesh - Traffic Details";
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(860, 460);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        _summaryLabel.SetBounds(14, 12, 830, 24);
        _summaryLabel.Text = $"Uptime: {runtime.UptimeSeconds}s | Memory: {runtime.MemoryMb:F2} MB | Threads: {runtime.ThreadCount} | Connections: {runtime.ConnectionCount}";

        _rateLabel.SetBounds(14, 34, 830, 24);
        _rateLabel.Text = $"Upload Rate: {FormatBytes(runtime.UploadRateBytesPerSec)}/s | Download Rate: {FormatBytes(runtime.DownloadRateBytesPerSec)}/s | Total: {FormatBytes(runtime.TotalUploadBytes + runtime.TotalDownloadBytes)}";

        _listView.SetBounds(14, 64, 830, 380);
        _listView.Columns.Add("ID", 45);
        _listView.Columns.Add("Process", 130);
        _listView.Columns.Add("Destination", 220);
        _listView.Columns.Add("Proto", 60);
        _listView.Columns.Add("Outbound", 100);
        _listView.Columns.Add("Upload", 90);
        _listView.Columns.Add("Download", 90);
        _listView.Columns.Add("Last Seen", 170);
        _listView.Columns.Add("State", 60);

        foreach (var connection in connections)
        {
            var row = new ListViewItem(connection.Id.ToString());
            row.SubItems.Add(connection.ProcessName);
            row.SubItems.Add(connection.Destination);
            row.SubItems.Add(connection.Protocol);
            row.SubItems.Add(connection.Outbound);
            row.SubItems.Add(FormatBytes(connection.UploadBytes));
            row.SubItems.Add(FormatBytes(connection.DownloadBytes));
            row.SubItems.Add(connection.LastSeenUtc);
            row.SubItems.Add(connection.State);
            _listView.Items.Add(row);
        }

        Controls.Add(_summaryLabel);
        Controls.Add(_rateLabel);
        Controls.Add(_listView);
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

        return unitIndex == 0 ? $"{value} {units[unitIndex]}" : $"{scaled:F1} {units[unitIndex]}";
    }
}
