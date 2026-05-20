Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile("d:\zappymobile\logo\Enything.png")
$bmp = new-object System.Drawing.Bitmap($img)
$img.Dispose()

$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$color = $bmp.GetPixel(10, 1000)
$brush = new-object System.Drawing.SolidBrush($color)
$rect = new-object System.Drawing.Rectangle(0, 650, 1024, 400)
$graphics.FillRectangle($brush, $rect)

$bmp.Save("d:\zappymobile\logo\Enything_clean.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()
