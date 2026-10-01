# Smoke-test the packages package-release.ps1 left in dist\: unzip each into a
# clean temp folder and run `MTN2.exe --self-check` there (uSelfCheck.pas), so
# a file the program needs at run time but the package forgot fails the
# release instead of reaching users. Also checks what each package must and
# must not contain.
#
#   ./src/tools/check-release.ps1 -Version v0.3.6
param(
    [Parameter(Mandatory)]
    [string]$Version,
    [int]$TimeoutSec = 120
)
$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Dist = Join-Path $Root 'dist'
$Safe = $Version -replace '[^\w.\-]', '_'
$Regular = Join-Path $Dist "MTN2-$Safe-win64.zip"
$Portable = Join-Path $Dist "MTN2-$Safe-win64-portable.zip"

# Settings and history the app writes (uConfigLocation) -- a package carrying
# one would overwrite the user's copy on every update. Plus build by-products.
$Forbidden = @(
    'keymap.json', 'session.json', 'history.json', 'dialoghistory.json',
    'dirsync-state.json', 'fileposition.json', 'filehistory.json',
    'folderhistory.json', 'folderhotlist.json', 'sshconnections.json',
    'workspaces.json', 'usermenu.json', 'update.json',
    '*.map', '*.rsm', '*.drc', '*.dcu'
)

function Get-RelativeFiles([string]$Dir) {
    $Base = (Resolve-Path $Dir).Path.TrimEnd('\') + '\'
    Get-ChildItem $Dir -Recurse -File | ForEach-Object { $_.FullName.Substring($Base.Length) } | Sort-Object
}

function Test-Package([string]$Zip, [bool]$ExpectPortable) {
    if (-not (Test-Path $Zip)) { throw "missing package: $Zip" }
    $Name = Split-Path $Zip -Leaf
    $Dir = Join-Path ([IO.Path]::GetTempPath()) ("mtn2-check-" + [guid]::NewGuid())
    Expand-Archive -Path $Zip -DestinationPath $Dir
    try {
        $Files = @(Get-RelativeFiles $Dir)
        foreach ($Pattern in $Forbidden) {
            $Hit = $Files | Where-Object { (Split-Path $_ -Leaf) -like $Pattern }
            if ($Hit) { throw "${Name}: must not contain $($Hit -join ', ')" }
        }
        # 7z.dll goes with its license text (the license requires it).
        foreach ($Needed in 'plugins\mtn.7z\7z.dll', 'plugins\mtn.7z\license.txt', 'THIRD-PARTY.md') {
            if ($Files -notcontains $Needed) { throw "${Name}: must contain $Needed" }
        }
        $HasPortable = $Files -contains 'portable.dat'
        if ($HasPortable -ne $ExpectPortable) {
            throw "${Name}: portable.dat present=$HasPortable, expected $ExpectPortable"
        }

        $Out = Join-Path $Dir 'self-check.txt'
        $Proc = Start-Process -FilePath (Join-Path $Dir 'MTN2.exe') -ArgumentList '--self-check' `
            -WorkingDirectory $Dir -RedirectStandardOutput $Out -NoNewWindow -PassThru
        if (-not $Proc.WaitForExit($TimeoutSec * 1000)) {
            $Proc.Kill()
            throw "${Name}: MTN2.exe --self-check did not exit within $TimeoutSec s"
        }
        Get-Content $Out | ForEach-Object { Write-Host "  $_" }
        if ($Proc.ExitCode -ne 0) { throw "${Name}: self-check failed (exit $($Proc.ExitCode))" }
        Write-Host "OK: $Name"
        return , ($Files | Where-Object { $_ -ne 'portable.dat' })
    }
    finally {
        Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$RegularFiles = Test-Package $Regular $false
$PortableFiles = Test-Package $Portable $true
$Diff = Compare-Object $RegularFiles $PortableFiles
if ($Diff) {
    throw "packages differ beyond portable.dat: $($Diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })"
}
Write-Host 'OK: both packages carry the same program files'
