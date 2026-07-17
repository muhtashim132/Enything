$json = Get-Content 'for_updates.json' -Raw -Encoding Unicode
if ($json -match '"rows": \[(.*?)\]\s*,\s*"warning"') {
    $rows_str = $matches[1]
    $regex = '(?s)\{\s*"proname":\s*"(.*?)",\s*"prosrc":\s*"(.*?)"\s*\}'
    $matches = [regex]::Matches($rows_str, $regex)
    
    foreach ($match in $matches) {
        $proname = $match.Groups[1].Value
        $prosrc = $match.Groups[2].Value
        # Replace \n with actual newlines for easier scanning
        $prosrc = $prosrc -replace '\\n', "`n"
        
        $lines = $prosrc -split "`n"
        for ($i=0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            if ($line -match '(?i)FOR\s+UPDATE') {
                Write-Host "FUNCTION: $proname"
                Write-Host "LINE: $line"
                Write-Host "---"
            }
        }
    }
}
