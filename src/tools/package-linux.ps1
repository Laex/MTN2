# Pack the terminal program and, when it was built (build-linux.ps1 -Sdl), the
# window program (after src\build-linux.ps1) into
#   dist\MTN2-<Version>-linux-x64.tar.gz, plus a .deb and, when rpmbuild is found in WSL, an .rpm
# The archive holds a folder mtn2\ with the program, the language packs (strings and F1 help), the plugins
# built by build-linux.ps1 (native .so libraries, manifests, WASM modules) and
# libwasmtime.so, a version file, the license texts and the Linux notes. tar runs in WSL so that the program keeps its execute bit.
param(
    [Parameter(Mandatory)]
    [string]$Version,
    [string]$Distro = 'Ubuntu-24.04'
)
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Bin = Join-Path $Root 'bin'
$Program = Join-Path $Bin 'linux64\mtn2-tui'
if (-not (Test-Path $Program)) { throw 'bin\linux64\mtn2-tui not found; run src\build-linux.ps1 first' }

$Dist = Join-Path $Root 'dist'
$Stage = Join-Path $Dist 'linux-stage\mtn2'
if (Test-Path (Join-Path $Dist 'linux-stage')) { Remove-Item (Join-Path $Dist 'linux-stage') -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'plugins') | Out-Null

Copy-Item $Program $Stage
$Window = Join-Path $Bin 'linux64\mtn2-sdl'
$HasWindow = Test-Path $Window
if ($HasWindow) { Copy-Item $Window $Stage }
$ModeList = if ($HasWindow) { 'mtn2/mtn2-tui mtn2/mtn2-sdl' } else { 'mtn2/mtn2-tui' }
$PluginsBuilt = Join-Path $Bin 'linux64\plugins'
if (Test-Path $PluginsBuilt) { Copy-Item (Join-Path $PluginsBuilt '*') (Join-Path $Stage 'plugins') -Recurse -Force }
$Wasmtime = Join-Path $Bin 'linux64\libwasmtime.so'
if (Test-Path $Wasmtime) { Copy-Item $Wasmtime $Stage }
$Packs = Join-Path $Bin 'linux64\resource'
if (Test-Path $Packs) { Copy-Item $Packs (Join-Path $Stage 'resource') -Recurse }
Copy-Item (Join-Path $Root 'LICENSE') $Stage
Copy-Item (Join-Path $Root 'THIRD-PARTY.md') $Stage
Copy-Item (Join-Path $Root 'CHANGELOG.md') $Stage
Copy-Item (Join-Path $Root 'docs\LINUX.md') $Stage
# A shell script must keep LF endings whatever the checkout did to them.
$Install = (Get-Content (Join-Path $PSScriptRoot 'install-linux.sh') -Raw).Replace("`r`n", "`n")
[IO.File]::WriteAllText((Join-Path $Stage 'install.sh'), $Install, (New-Object Text.UTF8Encoding $false))
# The program has no version resource on Linux; it reads this file (uPlatformUpdate).
[IO.File]::WriteAllText((Join-Path $Stage 'version'), ($Version -replace '^v', '') + "`n", (New-Object Text.UTF8Encoding $false))

$Safe = $Version -replace '[^\w.\-]', '_'
$Archive = Join-Path $Dist "MTN2-$Safe-linux-x64.tar.gz"
if (Test-Path $Archive) { Remove-Item $Archive -Force }

function ConvertTo-WslPath([string]$Path) {
    '/mnt/' + $Path.Substring(0, 1).ToLower() + $Path.Substring(2).Replace('\', '/')
}
$WslStage = ConvertTo-WslPath (Split-Path $Stage -Parent)
$WslArchive = ConvertTo-WslPath $Archive
wsl -d $Distro -- bash -c "cd '$WslStage' && chmod 755 $ModeList mtn2/install.sh && tar czf '$WslArchive' --owner=0 --group=0 mtn2"
if ($LASTEXITCODE -ne 0) { throw "tar failed with $LASTEXITCODE" }
Write-Host "OK: $Archive"

# A Debian package: the same folder under /opt/mtn2 and the command /usr/bin/mtn2.
$Deb = Join-Path $Dist "MTN2-$Safe-linux-x64.deb"
if (Test-Path $Deb) { Remove-Item $Deb -Force }
$DebRoot = Join-Path $Dist 'linux-stage\deb'
New-Item -ItemType Directory -Force -Path (Join-Path $DebRoot 'DEBIAN'), (Join-Path $DebRoot 'opt'), (Join-Path $DebRoot 'usr\bin') | Out-Null
Copy-Item $Stage (Join-Path $DebRoot 'opt\mtn2') -Recurse
# The package manager updates the program: this file turns the self-updater off.
New-Item -ItemType File -Path (Join-Path $DebRoot 'opt\mtn2\no-self-update') | Out-Null
$Recommends = 'Recommends: 7zip | p7zip-full, chafa, libcurl4t64 | libcurl4'
if ($HasWindow) { $Recommends += ', libsdl2-2.0-0, libfreetype6, libsdl2-image-2.0-0' }
$WindowLink = if ($HasWindow) { ' && ln -s /opt/mtn2/mtn2-sdl usr/bin/mtn2-sdl' } else { '' }
$DebModes = $ModeList -replace 'mtn2/', 'opt/mtn2/'
$Control = @(
    'Package: mtn2',
    "Version: $($Version -replace '^v', '')",
    'Section: utils',
    'Priority: optional',
    'Architecture: amd64',
    'Maintainer: MTN2 <noreply@users.noreply.github.com>',
    'Homepage: https://github.com/Laex/MTN2',
    $Recommends,
    'Description: Dual-panel file manager for the terminal',
    ' Modern Terminal Navigator 2: two panels with tabs, viewer, editor,',
    ' terminals, SFTP and archives, drawn inside an ordinary terminal.') -join "`n"
[IO.File]::WriteAllText((Join-Path $DebRoot 'DEBIAN\control'), $Control + "`n", (New-Object Text.UTF8Encoding $false))
$WslDeb = ConvertTo-WslPath $Deb
$WslDebRoot = ConvertTo-WslPath $DebRoot
# Permissions are only honored on the WSL file system, so the tree is built there.
wsl -d $Distro -- bash -c "rm -rf /tmp/mtn2-deb && cp -r '$WslDebRoot' /tmp/mtn2-deb && cd /tmp/mtn2-deb && chmod 755 DEBIAN $DebModes opt/mtn2/install.sh && ln -s /opt/mtn2/mtn2-tui usr/bin/mtn2$WindowLink && dpkg-deb --root-owner-group --build . /tmp/mtn2.deb > /dev/null && cp /tmp/mtn2.deb '$WslDeb'; rc=`$?; rm -rf /tmp/mtn2-deb /tmp/mtn2.deb; exit `$rc"
if ($LASTEXITCODE -ne 0) { throw "dpkg-deb failed with $LASTEXITCODE" }
Write-Host "OK: $Deb"

# An RPM package: the same folder under /opt/mtn2 and the commands in /usr/bin. It needs
# rpmbuild in the WSL distribution and is left out (with a note) when that is missing.
wsl -d $Distro -- bash -c 'command -v rpmbuild > /dev/null'
if ($LASTEXITCODE -ne 0) {
    Write-Host "skip rpm : rpmbuild not found in $Distro (sudo apt install rpm)"
} else {
    $Rpm = Join-Path $Dist "MTN2-$Safe-linux-x64.rpm"
    if (Test-Path $Rpm) { Remove-Item $Rpm -Force }
    # An RPM version may not hold a dash.
    $RpmVersion = ($Version -replace '^v', '') -replace '-', '.'
    $RpmRecommends = @('p7zip', 'chafa', 'libcurl')
    if ($HasWindow) { $RpmRecommends += @('SDL2', 'freetype', 'SDL2_image') }
    $WindowFiles = if ($HasWindow) { '/usr/bin/mtn2-sdl' } else { '' }
    $WindowLinkRpm = if ($HasWindow) { 'ln -s /opt/mtn2/mtn2-sdl %{buildroot}/usr/bin/mtn2-sdl' } else { '' }
    $Spec = @"
Name: mtn2
Version: $RpmVersion
Release: 1
Summary: Dual-panel file manager for the terminal
License: MPL-2.0
URL: https://github.com/Laex/MTN2
BuildArch: x86_64
AutoReqProv: no
$((($RpmRecommends | ForEach-Object { "Recommends: $_" }) -join "`n"))

%description
Modern Terminal Navigator 2: two panels with tabs, viewer, editor,
terminals, SFTP and archives, drawn inside an ordinary terminal.

%global debug_package %{nil}
%global __os_install_post %{nil}
%define _build_id_links none

%install
mkdir -p %{buildroot}/opt %{buildroot}/usr/bin
cp -r $WslStage/mtn2 %{buildroot}/opt/mtn2
touch %{buildroot}/opt/mtn2/no-self-update
ln -s /opt/mtn2/mtn2-tui %{buildroot}/usr/bin/mtn2
$WindowLinkRpm

%files
%defattr(-,root,root,-)
/opt/mtn2
/usr/bin/mtn2
$WindowFiles
"@
    $SpecFile = Join-Path $Dist 'linux-stage\mtn2.spec'
    [IO.File]::WriteAllText($SpecFile, $Spec.Replace("`r`n", "`n") + "`n", (New-Object Text.UTF8Encoding $false))
    $WslSpec = ConvertTo-WslPath $SpecFile
    $WslRpm = ConvertTo-WslPath $Rpm
    # A script file keeps the shell of WSL from expanding the variables of the commands.
    # The tree is copied inside WSL so that the programs keep their execute bits.
    $RpmScript = @'
#!/bin/bash
# usage: rpm-build.sh <staging folder with mtn2/> <spec file> <output rpm>
stage="$1"; spec="$2"; out="$3"
work=/tmp/mtn2-rpm
rm -rf "$work"
mkdir -p "$work/stage"
cp -r "$stage/mtn2" "$work/stage/"
chmod -R u=rwX,go=rX "$work/stage/mtn2"
chmod 755 "$work/stage/mtn2/mtn2-tui" "$work/stage/mtn2/install.sh"
if [ -f "$work/stage/mtn2/mtn2-sdl" ]; then chmod 755 "$work/stage/mtn2/mtn2-sdl"; fi
sed "s#$stage#$work/stage#" "$spec" > "$work/mtn2.spec"
rc=0
rpmbuild -bb --define "_topdir $work/top" "$work/mtn2.spec" > "$work/log.txt" 2>&1 || rc=$?
if [ $rc -eq 0 ]; then
    built=$(find "$work/top/RPMS" -name '*.rpm' | head -1)
    cp "$built" "$out" || rc=1
else
    tail -20 "$work/log.txt"
fi
rm -rf "$work"
exit $rc
'@
    $RpmScriptFile = Join-Path $Dist 'linux-stage\rpm-build.sh'
    [IO.File]::WriteAllText($RpmScriptFile, $RpmScript.Replace("`r`n", "`n") + "`n", (New-Object Text.UTF8Encoding $false))
    wsl -d $Distro -- bash (ConvertTo-WslPath $RpmScriptFile) $WslStage $WslSpec $WslRpm
    if ($LASTEXITCODE -ne 0) { throw "rpmbuild failed with $LASTEXITCODE" }
    Write-Host "OK: $Rpm"
}
Remove-Item (Join-Path $Dist 'linux-stage') -Recurse -Force
