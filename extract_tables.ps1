$tables = @{}
Get-ChildItem -Path "d:\Enything\lib" -Filter "*.dart" -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $matches = [regex]::Matches($content, "\.from\('([^']+)'\)")
    foreach ($m in $matches) {
        $tables[$m.Groups[1].Value] = $true
    }
}
$tables.Keys | Sort-Object
