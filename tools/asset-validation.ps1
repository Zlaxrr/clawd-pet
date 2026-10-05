Add-Type -AssemblyName System.Drawing

function Test-ClawdAsset([string]$Path) {
    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($Path)
        $format = if ([IO.Path]::GetExtension($Path) -eq '.png') {
            [System.Drawing.Imaging.ImageFormat]::Png
        } else {
            [System.Drawing.Imaging.ImageFormat]::Gif
        }
        return ($image.RawFormat.Guid -eq $format.Guid -and $image.Width -gt 0 -and $image.Height -gt 0)
    } catch { return $false }
    finally { if ($null -ne $image) { $image.Dispose() } }
}
