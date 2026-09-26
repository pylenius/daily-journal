# Publishes Journal for x64 and ARM64 and packs them into windows\out\:
#   Journal-Setup-<version>.exe   one installer for both architectures
#   Journal-<version>-win-x64.zip, Journal-<version>-win-arm64.zip   portable copies
#
# Run from anywhere on Windows with the .NET 10 SDK and Inno Setup 6 (winget install JRSoftware.InnoSetup).
param([string]$Version)

$ErrorActionPreference = 'Stop'
$windows = Split-Path $PSScriptRoot -Parent
$project = Join-Path $windows 'src\Journal.App\Journal.App.csproj'
$out = Join-Path $windows 'out'
if (-not $Version) { $Version = ([xml](Get-Content $project)).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1 }

$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup' }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
foreach ($rid in 'win-x64', 'win-arm64') {
    $dir = Join-Path $out "Journal-$rid"
    dotnet publish $project -c Release -r $rid -o $dir -p:Version=$Version -nologo -v q
    if ($LASTEXITCODE) { throw "publish $rid failed" }
    Compress-Archive -Path "$dir\*" -DestinationPath (Join-Path $out "Journal-$Version-$rid.zip")
}

& $iscc /Q "/DAppVersion=$Version" "/DSrcX64=$out\Journal-win-x64" "/DSrcArm64=$out\Journal-win-arm64" "/DOutDir=$out" (Join-Path $PSScriptRoot 'Journal.iss')
if ($LASTEXITCODE) { throw 'installer build failed' }

Get-ChildItem $out -File | ForEach-Object { '{0,-40} {1,8:N1} MB' -f $_.Name, ($_.Length / 1MB) }
