Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile("d:\zappymobile\logo\Enything.png")
$bmp = new-object System.Drawing.Bitmap(1024, 1024)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

# Fill the background first with the deep blue
$color = $img.GetPixel(10, 10)
$brush = new-object System.Drawing.SolidBrush($color)
$graphics.FillRectangle($brush, 0, 0, 1024, 1024)

# We know text was removed at Y >= 650. The logo is likely Y: 100 to 600, X: 200 to 800.
# We'll take a crop of X=150, Y=100, W=724, H=724 and scale it to 1024x1024
$srcRect = new-object System.Drawing.Rectangle(150, 100, 724, 724)
$destRect = new-object System.Drawing.Rectangle(0, 0, 1024, 1024)

$graphics.DrawImage($img, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

$img.Dispose()
$bmp.Save("d:\zappymobile\logo\Enything_cropped.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()
