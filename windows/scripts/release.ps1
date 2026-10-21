# Tests, builds and packages a release into windows\build\release\:
#   ZaloSwitcher-Setup-<version>.exe          the installer (most people want this)
#   ZaloSwitcher-<version>-windows-x64.zip    both programs, to run without installing
#   SHA256SUMS-windows.txt                    their checksums
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'build.ps1') -Test -Installer

$version = ([xml](Get-Content (Join-Path $root 'Directory.Build.props'))).Project.PropertyGroup.Version
$build = Join-Path $root 'build'
$release = Join-Path $build 'release'
if (Test-Path $release) { Remove-Item -Recurse -Force $release }
New-Item -ItemType Directory $release | Out-Null

Copy-Item (Join-Path $build "ZaloSwitcher-Setup-$version.exe") $release
Compress-Archive -Path (Join-Path $build 'publish\Zalo Switcher') -DestinationPath (Join-Path $release "ZaloSwitcher-$version-windows-x64.zip")
$sums = Get-ChildItem $release | Sort-Object Name | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
}
$sums | Set-Content -Encoding ascii (Join-Path $release 'SHA256SUMS-windows.txt')
Write-Host "Release files in $release"
Get-ChildItem $release | Format-Table Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }

