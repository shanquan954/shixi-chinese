$scriptPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptPath
Set-Location $root

$infoPath = Join-Path $root 'info.json'
if (-Not (Test-Path $infoPath)) {
    Write-Error "info.json not found: $infoPath"
    exit 1
}

$info = Get-Content -Raw -Encoding UTF8 $infoPath | ConvertFrom-Json
if (-not $info.name -or -not $info.version) {
    Write-Error "info.json missing name or version"
    exit 1
}

$destination = "$($info.name)_$($info.version).zip"
$destinationPath = Join-Path $root $destination
$root = (Get-Item $root).FullName.TrimEnd('\\')

$ignoreFilePath = Join-Path $root '.zipignore'
$ignorePatterns = @()
if (Test-Path $ignoreFilePath) {
    $ignorePatterns = Get-Content -Path $ignoreFilePath -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
}

$ignorePatterns += '.zipignore'
$ignorePatterns += '*.zip'
$ignorePatterns += "$($info.name)_$($info.version).zip"

function Test-ZipIgnore {
    param(
        [string]$relativePath,
        [string]$pattern
    )

    $pattern = $pattern.Trim() -replace '\\','/'
    if ($pattern.EndsWith('/')) {
        $pattern = "$pattern*"
    }

    if ($relativePath -eq $pattern -or $relativePath -like $pattern) {
        return $true
    }

    if ($pattern -notmatch '[*?\[]' -and ($relativePath -eq $pattern -or $relativePath -like "$pattern/*")) {
        return $true
    }

    return $false
}

$filesToPack = Get-ChildItem -Path $root -Recurse -File |
    Where-Object {
        $_.FullName -ne $scriptPath -and
        $_.FullName -ne $destinationPath -and
        $_.Extension -ne '.zip'
    } |
    Where-Object {
        $relative = $_.FullName.Substring($root.Length + 1) -replace '\\','/'
        foreach ($pattern in $ignorePatterns) {
            if (Test-ZipIgnore -relativePath $relative -pattern $pattern) {
                return $false
            }
        }
        return $true
    }

# Use a top-level folder inside the zip so Factorio recognizes the mod structure
$topFolder = "$($info.name)_$($info.version)"

if (Test-Path $destinationPath) { Remove-Item -Force $destinationPath }

[Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') | Out-Null

# Use numeric value for ZipArchiveMode.Create (1) for compatibility
$zip = [System.IO.Compression.ZipFile]::Open($destinationPath, 1)
if ($null -eq $zip) {
    Write-Error "Failed to open zip: $destinationPath"
    exit 1
}
try {
    foreach ($file in $filesToPack) {
        $relative = $file.FullName.Substring($root.Length + 1) -replace '\\','/'
        $entryName = $topFolder + '/' + $relative
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName)
    }
} finally {
    if ($zip) { $zip.Dispose() }
}

Write-Host "Created: $destination"