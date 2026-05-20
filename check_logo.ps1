Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile("d:\zappymobile\logo\Enything.png")
$bmp = new-object System.Drawing.Bitmap($img)
$w = $bmp.Width
$h = $bmp.Height
Write-Host "Width: $w, Height: $h"
$p1 = $bmp.GetPixel(0,0)
$p2 = $bmp.GetPixel($w-1,0)
$p3 = $bmp.GetPixel(0,$h-1)
$p4 = $bmp.GetPixel($w-1,$h-1)
Write-Host "Top-Left: $p1"
Write-Host "Top-Right: $p2"
Write-Host "Bottom-Left: $p3"
Write-Host "Bottom-Right: $p4"
$img.Dispose()
$bmp.Dispose()
