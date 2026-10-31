<#
Builds Mothball for Windows and packs the installer.

  scripts\build-windows.ps1                 build for this machine's architecture
  scripts\build-windows.ps1 -SkipInstaller  build the app folder only

Flutter builds for the machine it runs on, so run it on an x64 PC (or
windows-latest in CI) for the x64 installer and on an Arm64 PC (windows-11-arm)
for the Arm64 one.

Needs Go, Flutter and Inno Setup 6 (iscc.exe). Output, in build\windows-release:
  Mothball-<version>-windows-<arch>-setup.exe   the installer
  Mothball-<version>-windows-<arch>.zip         the same files, portable (Scoop)
  mothball-<version>-windows-<arch>.exe         the command line tool on its own
#>
param(
  [switch]$SkipInstaller
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# Architecture of this machine, as Flutter and Go name it.
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$GoArch = if ($Arch -eq 'arm64') { 'arm64' } else { 'amd64' }
$Version = ((Select-String -Path app\pubspec.yaml -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value)
Write-Host "Building Mothball $Version for Windows $Arch"

$Out = Join-Path $Root 'build\windows-release'
$Stage = Join-Path $Out "stage-$Arch"
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force "$Stage\app", "$Stage\bin" | Out-Null

# 1. The command line tool and its windowless twin for the background service.
$env:CGO_ENABLED = '0'
$env:GOOS = 'windows'
$env:GOARCH = $GoArch
$ld = "-s -w -X main.version=$Version"
go build -trimpath -ldflags $ld -o "$Stage\bin\mothball.exe" ./cli/mothball
if ($LASTEXITCODE) { throw 'go build failed' }
go build -trimpath -ldflags "$ld -H=windowsgui" -o "$Stage\bin\mothballw.exe" ./cli/mothball
if ($LASTEXITCODE) { throw 'go build (windowless) failed' }
Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED

# 2. The desktop app.
Push-Location app
flutter build windows --release
if ($LASTEXITCODE) { Pop-Location; throw 'flutter build failed' }
Pop-Location
$Built = "app\build\windows\$Arch\runner\Release"
if (-not (Test-Path "$Built\Mothball.exe")) { throw "No Mothball.exe in $Built" }
Copy-Item -Recurse "$Built\*" "$Stage\app"

# 3. Microsoft's C++ runtime, which Flutter apps need and a fresh Windows may
#    not have. Taken from this machine, so it matches the architecture.
# vcruntime140_1.dll exists only for x64; Arm64 does not use it.
$Runtime = @('msvcp140.dll', 'vcruntime140.dll')
if ($Arch -eq 'x64') { $Runtime += 'vcruntime140_1.dll' }
foreach ($dll in $Runtime) {
  $src = Join-Path $env:WINDIR "System32\$dll"
  if (-not (Test-Path $src)) { throw "$dll not found in System32" }
  Copy-Item $src "$Stage\app\"
}
Copy-Item app\windows\runner\resources\app_icon.ico $Stage

# 4. Portable zip (for Scoop) and the CLI on its own.
$Zip = Join-Path $Out "Mothball-$Version-windows-$Arch.zip"
if (Test-Path $Zip) { Remove-Item $Zip }
$Portable = Join-Path $Out "portable-$Arch"
if (Test-Path $Portable) { Remove-Item -Recurse -Force $Portable }
New-Item -ItemType Directory -Force "$Portable\bin" | Out-Null
Copy-Item -Recurse "$Stage\app\*" $Portable
Copy-Item "$Stage\bin\*" "$Portable\bin"
Compress-Archive -Path "$Portable\*" -DestinationPath $Zip
Copy-Item "$Stage\bin\mothball.exe" (Join-Path $Out "mothball-$Version-windows-$GoArch.exe")

# 5. The installer.
if (-not $SkipInstaller) {
  $iscc = @(
    (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $iscc) { throw 'Inno Setup 6 (ISCC.exe) not found' }
  & $iscc /Qp "/DAppVersion=$Version" "/DArch=$Arch" "/DSourceDir=$Stage" "/DOutputDir=$Out" installer\windows\mothball.iss
  if ($LASTEXITCODE) { throw 'Inno Setup failed' }
}

Get-ChildItem $Out -File | ForEach-Object {
  $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
  Write-Host ("{0}  {1}  ({2:N1} MB)" -f $h, $_.Name, ($_.Length / 1MB))
}
