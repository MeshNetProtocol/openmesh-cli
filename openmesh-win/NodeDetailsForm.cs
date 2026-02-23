namespace OpenMeshWin;

internal sealed class NodeDetailsForm : Form
{
    private readonly Label _summaryLabel = new();
    private readonly ListView _listView = new()
    {
        View = View.Details,
        FullRowSelect = true,
        GridLines = true,
        HideSelection = false
    };

    public NodeDetailsForm(
        List<CoreOutboundGroup> groups,
        string lastUrlTestGroup,
        Dictionary<string, int> lastUrlTestDelays)
    {
        Text = "OpenMesh - Node Details";
        StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(760, 420);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        _summaryLabel.SetBounds(14, 12, 730, 24);
        _summaryLabel.Text = $"Groups: {groups.Count} | Last URLTest Group: {(string.IsNullOrWhiteSpace(lastUrlTestGroup) ? "N/A" : lastUrlTestGroup)}";

        _listView.SetBounds(14, 42, 730, 360);
        _listView.Columns.Add("Group", 120);
        _listView.Columns.Add("Node", 160);
        _listView.Columns.Add("Type", 90);
        _listView.Columns.Add("Selected", 70);
        _listView.Columns.Add("Last Delay", 90);
        _listView.Columns.Add("Selectable", 80);
        _listView.Columns.Add("Notes", 110);

        foreach (var group in groups)
        {
            foreach (var item in group.Items)
            {
                var isSelected = string.Equals(group.Selected, item.Tag, StringComparison.OrdinalIgnoreCase);
                var row = new ListViewItem(group.Tag);
                row.SubItems.Add(item.Tag);
                row.SubItems.Add(item.Type);
                row.SubItems.Add(isSelected ? "Yes" : "No");

                var hasDelay = lastUrlTestDelays.TryGetValue(item.Tag, out var delay);
                row.SubItems.Add(hasDelay ? $"{delay} ms" : "-");
                row.SubItems.Add(group.Selectable ? "Yes" : "No");
                row.SubItems.Add(string.Equals(lastUrlTestGroup, group.Tag, StringComparison.OrdinalIgnoreCase) ? "URLTested" : "");
                _listView.Items.Add(row);
            }
        }

        Controls.Add(_summaryLabel);
        Controls.Add(_listView);
    }
}
