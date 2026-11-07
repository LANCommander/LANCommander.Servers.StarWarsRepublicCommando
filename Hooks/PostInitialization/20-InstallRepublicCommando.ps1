#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# Star Wars: Republic Commando is retail software with no public download. Use an existing install
# (the GameData folder) in /config/Server, or set RC_ARCHIVE_URL to a zip of one, e.g. a
# LANCommander archive; file:// URLs are read in place. The folder holding System/MPGame.u and
# System/UCC.exe is used, so the game may sit in a subfolder of the zip. Movies/, Help/ and
# Manual.pdf aren't needed by the server and are left out.

Invoke-Hook "PreInstallRepublicCommando"

$ucc = Join-Path $Env:SERVER_DIR 'System/UCC.exe'

if (Test-Path -Path $ucc) {
    Write-Log "Republic Commando found in $Env:SERVER_DIR"
} elseif ($Env:RC_ARCHIVE_URL) {
    $extract = '/tmp/republiccommando'
    $download = $null

    if ($Env:RC_ARCHIVE_URL.StartsWith('file://')) {
        $zip = [System.Uri]::UnescapeDataString($Env:RC_ARCHIVE_URL.Substring(7))
        if (-not (Test-Path -Path $zip)) { throw "Archive not found: $zip" }
        Write-Log "Extracting Republic Commando from $zip"
    } else {
        $zip = $download = '/tmp/republiccommando.zip'
        Write-Log "Downloading Republic Commando from $Env:RC_ARCHIVE_URL"

        curl -fL --retry 3 --output $zip "$Env:RC_ARCHIVE_URL"
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:RC_ARCHIVE_URL" }
    }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue
    unzip -q -o $zip -d $extract -x 'Movies/*' '*/Movies/*' 'Help/*' '*/Help/*' 'Manual.pdf' '*/Manual.pdf'
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $zip" }

    $root = Get-ChildItem -Path $extract -Filter 'MPGame.u' -Recurse -File -Depth 3 |
        Where-Object { $_.Directory.Name -eq 'System' -and (Test-Path (Join-Path $_.DirectoryName 'UCC.exe')) } |
        Select-Object -First 1 -ExpandProperty Directory
    if (-not $root) {
        throw "System/MPGame.u and System/UCC.exe not found in $Env:RC_ARCHIVE_URL. The game shipped without UCC.exe; install SWRCFix into System/ first."
    }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    Move-Item -Force -Path (Join-Path $root.Parent.FullName '*') -Destination $Env:SERVER_DIR
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    Remove-Item -Recurse -Force -Path $extract
    if ($download) { Remove-Item -Force -Path $download }

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "Republic Commando installed"
} else {
    Write-Log -Level Error "System/UCC.exe not found in $Env:SERVER_DIR. Copy a Republic Commando install (GameData folder with SWRCFix) there or set RC_ARCHIVE_URL."
}

Invoke-Hook "PostInstallRepublicCommando"

Set-Location $Env:SERVER_ROOT
