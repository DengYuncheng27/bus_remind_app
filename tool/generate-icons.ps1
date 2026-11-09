param([string]$AdminWebRoot)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$source = [System.Drawing.Bitmap]::FromFile((Join-Path $projectRoot 'assets/branding/app-icon-source.png'))
$background = $source.GetPixel(0, 0)
$generated = [System.Collections.Generic.List[string]]::new()

function Write-Icon([string]$Path, [int]$Size, [double]$Scale = 1) {
    $absolute = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $projectRoot $Path }
    New-Item -ItemType Directory -Path (Split-Path $absolute -Parent) -Force | Out-Null
    # Opaque RGB output is required for iOS icons; platforms apply their own masks.
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        $graphics.Clear($background)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $edge = [int][Math]::Round($Size * $Scale)
        $offset = [int][Math]::Floor(($Size - $edge) / 2)
        if ($offset -gt 0) {
            # Extend the source edge pixels instead of adding a visibly different
            # flat-color border around the approved, subtly textured background.
            $end = $offset + $edge
            $tail = $Size - $end
            $slices = @(
                @(0, 0, $offset, $offset, 0, 0, 1, 1),
                @($offset, 0, $edge, $offset, 0, 0, $source.Width, 1),
                @($end, 0, $tail, $offset, ($source.Width - 1), 0, 1, 1),
                @(0, $offset, $offset, $edge, 0, 0, 1, $source.Height),
                @($end, $offset, $tail, $edge, ($source.Width - 1), 0, 1, $source.Height),
                @(0, $end, $offset, $tail, 0, ($source.Height - 1), 1, 1),
                @($offset, $end, $edge, $tail, 0, ($source.Height - 1), $source.Width, 1),
                @($end, $end, $tail, $tail, ($source.Width - 1), ($source.Height - 1), 1, 1)
            )
            foreach ($slice in $slices) {
                $rect = [System.Drawing.Rectangle]::new($slice[0], $slice[1], $slice[2], $slice[3])
                $graphics.DrawImage($source, $rect, $slice[4], $slice[5], $slice[6], $slice[7], [System.Drawing.GraphicsUnit]::Pixel, $attributes)
            }
        }
        $destination = [System.Drawing.Rectangle]::new($offset, $offset, $edge, $edge)
        $graphics.DrawImage($source, $destination, 0, 0, $source.Width, $source.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $bitmap.Save($absolute, [System.Drawing.Imaging.ImageFormat]::Png)
        $generated.Add($absolute)
    } finally {
        $attributes.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    Write-Icon 'assets/branding/app-icon.png' 512
    Write-Icon 'web/favicon.png' 32
    foreach ($size in 180, 192, 512) { Write-Icon "web/icons/xiabanwang-$size.png" $size }
    foreach ($size in 192, 512) {
        # Keep compatibility with the original Flutter asset paths.
        Write-Icon "web/icons/Icon-$size.png" $size
        # The entire mark stays inside the PWA maskable radius of 40%.
        Write-Icon "web/icons/Icon-maskable-$size.png" $size 0.82
    }
    $densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
    foreach ($density in $densities.Keys) {
        Write-Icon "android/app/src/main/res/mipmap-$density/ic_launcher.png" $densities[$density]
    }
    # Android adaptive layers are 108 dp. The mark fits the central 66 dp safe zone.
    Write-Icon 'android/app/src/main/res/drawable-nodpi/ic_launcher_adaptive.png' 432 0.66
    $catalog = Get-Content -LiteralPath (Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') -Raw | ConvertFrom-Json
    foreach ($entry in ($catalog.images | Sort-Object filename -Unique)) {
        $points = [double]::Parse($entry.size.Split('x')[0], [System.Globalization.CultureInfo]::InvariantCulture)
        $scale = [int]$entry.scale.TrimEnd('x')
        Write-Icon "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($entry.filename)" ([int]($points * $scale))
    }
    if ($AdminWebRoot) {
        foreach ($size in 32, 180, 192, 512) {
            Write-Icon (Join-Path $AdminWebRoot "icons/xiabanwang-$size.png") $size
        }
    }
    Write-Output "Generated $($generated.Count) icon assets from the approved source."
} finally {
    $source.Dispose()
}
