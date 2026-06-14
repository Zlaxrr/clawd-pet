# Pratinjau menu klik-kanan bertema Claude -> PNG (item "Dance" disorot).
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @"
using System;
using System.Drawing;
using System.Windows.Forms;
public class ClawdMenuColors : ProfessionalColorTable {
    static Color BG=Color.FromArgb(38,36,33), MARGIN=Color.FromArgb(31,29,27), SEP=Color.FromArgb(70,64,58), BORDER=Color.FromArgb(92,72,63);
    public override Color ToolStripDropDownBackground { get { return BG; } }
    public override Color MenuBorder { get { return BORDER; } }
    public override Color ImageMarginGradientBegin { get { return MARGIN; } }
    public override Color ImageMarginGradientMiddle { get { return MARGIN; } }
    public override Color ImageMarginGradientEnd { get { return MARGIN; } }
    public override Color SeparatorDark { get { return SEP; } }
    public override Color SeparatorLight { get { return SEP; } }
}
public class ClawdMenuRenderer : ToolStripProfessionalRenderer {
    public ClawdMenuRenderer() : base(new ClawdMenuColors()) { this.RoundedEdges = false; }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        Graphics g = e.Graphics;
        Rectangle r = new Rectangle(0, 0, e.Item.Width, e.Item.Height);
        if (e.Item.Selected || e.Item.Pressed) {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(60,47,41))) g.FillRectangle(b, r);
            using (SolidBrush c = new SolidBrush(Color.FromArgb(217,119,87))) g.FillRectangle(c, 0, 0, 3, r.Height);
        } else {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(38,36,33))) g.FillRectangle(b, r);
        }
    }
}
"@

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Renderer  = New-Object ClawdMenuRenderer
$menu.BackColor = [System.Drawing.Color]::FromArgb(38,36,33)
$menu.ForeColor = [System.Drawing.Color]::FromArgb(236,231,223)
$menu.ShowImageMargin = $false
$menu.Font = New-Object System.Drawing.Font('Segoe UI', 9)
foreach ($t in @('The Shadow','Climb the Wall','Drag the Window','Push a Window','Meteor Shower','Balloon Ride','Hello World!','Dance','Hide','Sleep','Wave')) { [void]$menu.Items.Add($t) }
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Bye Clawd (quit)')
foreach ($it in $menu.Items) { $it.ForeColor = [System.Drawing.Color]::FromArgb(236,231,223) }

$f = New-Object System.Windows.Forms.Form
$f.Show(); $f.Location = New-Object System.Drawing.Point(-2000,-2000)
$menu.Show($f, 0, 0)
$danceItem = $menu.Items | Where-Object { $_.Text -eq 'Dance' }
$danceItem.Select()
Start-Sleep -Milliseconds 150
$bmp = New-Object System.Drawing.Bitmap ([int]$menu.Width), ([int]$menu.Height)
$menu.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle 0,0,$menu.Width,$menu.Height))
$out = Join-Path $env:TEMP 'clawd-menu-preview.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$menu.Close(); $f.Close()
Write-Output $out
