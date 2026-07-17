$path = "e:\Enything\supabase\migrations\20260896000000_100x_unauthenticated_ghost_order_ddos.sql"
$text = [System.IO.File]::ReadAllText($path)
$text = $text -replace '\\u003e', '>' -replace '\\u003c', '<'
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
Write-Host "Fixed escape characters and BOM."
