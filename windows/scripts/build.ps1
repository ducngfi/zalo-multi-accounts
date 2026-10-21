# Builds Zalo Switcher for Windows.
#   windows\build\publish\Zalo Switcher\   ZaloSwitcher.exe (the app) and zalo-profiles.exe (the command-line tool),
#                                      each a self-contained single-file x64 program: no .NET install needed
#   -Installer                         also windows\build\ZaloSwitcher-Setup-<version>.exe, the installer
#   -Test                              run the tests first
param([switch]$Test, [switch]$Installer)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'build'
$out = Join-Path $build 'publish\Zalo Switcher'
$version = ([xml](Get-Content (Join-Path $root 'Directory.Build.props'))).Project.PropertyGroup.Version

function Publish($project, $folder, [switch]$SingleFile) {
    $single = if ($SingleFile) { 'true' } else { 'false' }
    dotnet publish (Join-Path $root $project) -nologo -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=$single -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
        -p:DebugType=none -o $folder
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $project" }
}

if ($Test) {
    dotnet test (Join-Path $root 'tests\ZaloProfiles.Core.Tests') -nologo
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
}

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
Publish 'src\ZaloSwitcher' $out -SingleFile
Publish 'src\zalo-profiles' $out -SingleFile
Get-ChildItem $out -Filter *.pdb | Remove-Item
Write-Host "Built into $out"

if ($Installer) {
    # The installer carries both programs in one folder that shares a single copy of the .NET runtime,
    # which makes it about half the size of the two single-file programs.
    $payload = Join-Path $build 'payload'
    $zip = Join-Path $build 'payload.zip'
    foreach ($path in $payload, $zip) { if (Test-Path $path) { Remove-Item -Recurse -Force $path } }
    Publish 'src\ZaloSwitcher' $payload
    Publish 'src\zalo-profiles' $payload
    Get-ChildItem $payload -Filter *.pdb | Remove-Item
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

    $setupOut = Join-Path $build 'setup'
    dotnet build (Join-Path $root 'src\ZaloSwitcherSetup') -nologo -c Release "-p:PayloadZip=$zip" -o $setupOut
    if ($LASTEXITCODE -ne 0) { throw 'Build failed: installer' }
    $setup = Join-Path $build "ZaloSwitcher-Setup-$version.exe"
    Copy-Item (Join-Path $setupOut 'ZaloSwitcherSetup.exe') $setup -Force
    Write-Host "Installer: $setup"
}

Get-ChildItem $out, (Join-Path $build '*.exe') -ErrorAction SilentlyContinue |
    Format-Table Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }

