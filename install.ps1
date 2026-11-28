# Install desertant, the Desert Ant Labs CLI, on Windows from the latest GitHub release.
#
#   powershell -c "irm https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.ps1 | iex"
#
# The release lands in DESERTANT_HOME (%LOCALAPPDATA%\Programs\desertant) with the DLLs
# the binary needs beside it, and `da.exe` as a second name for `desertant.exe`. That
# folder goes on the user's PATH. DESERTANT_VERSION=v0.9.0 pins a release, and
# DESERTANT_BASE_URL installs from another folder of release assets. `desertant update`
# runs this script again.

function Install-Desertant {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $repo = 'Desert-Ant-Labs/desert-ant-cli'
    $dest = if ($env:DESERTANT_HOME) { $env:DESERTANT_HOME } else { Join-Path $env:LOCALAPPDATA 'Programs\desertant' }
    $version = if ($env:DESERTANT_VERSION) { $env:DESERTANT_VERSION } else { 'latest' }

    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ("$arch" -ne 'X64') {
        Write-Host "desertant has a Windows build for x64 only, and this PC is $arch."
        return $false
    }

    $asset = 'desertant-windows-x86_64.zip'
    if ($env:DESERTANT_BASE_URL) {
        $base = $env:DESERTANT_BASE_URL
    } elseif ($version -eq 'latest') {
        $base = "https://github.com/$repo/releases/latest/download"
    } else {
        $base = "https://github.com/$repo/releases/download/$version"
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "desertant-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        Write-Host "Downloading $asset."
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$base/$asset" -OutFile "$tmp\$asset"
            Invoke-WebRequest -UseBasicParsing -Uri "$base/checksums.txt" -OutFile "$tmp\checksums.txt"
        } catch {
            Write-Host "Could not download $base/$asset."
            return $false
        }

        # sha256sum marks a file it read in binary mode with a star before the name.
        $line = Get-Content "$tmp\checksums.txt" | Where-Object { $_ -match "^[0-9a-fA-F]{64} [ *]$([regex]::Escape($asset))$" } | Select-Object -First 1
        $expected = if ($line) { $line.Substring(0, 64).ToLower() } else { '' }
        $actual = (Get-FileHash -Algorithm SHA256 "$tmp\$asset").Hash.ToLower()
        if (-not $expected -or $expected -ne $actual) {
            Write-Host "The checksum of $asset does not match checksums.txt. Not installing."
            return $false
        }

        # Run the new binary before it replaces anything, so a missing DLL leaves the
        # installed copy as it was.
        Expand-Archive -Path "$tmp\$asset" -DestinationPath "$tmp\new"
        $ErrorActionPreference = 'Continue'
        $installed = "$(& "$tmp\new\desertant.exe" --version 2>&1)"
        $started = $LASTEXITCODE -eq 0
        $ErrorActionPreference = 'Stop'
        if (-not $started) {
            Write-Host 'The downloaded desertant did not start:'
            Write-Host "  $installed"
            return $false
        }

        # A running desertant.exe and the DLLs it loaded cannot be overwritten, but they
        # can be renamed, and the next install removes the renamed copy.
        function Clear-Target($path) {
            if (-not (Test-Path $path)) { return }
            try { Remove-Item -Recurse -Force $path }
            catch { Move-Item -Force $path "$path.$([guid]::NewGuid()).old" }
        }
        New-Item -ItemType Directory -Force $dest | Out-Null
        Get-ChildItem $dest -Filter '*.old' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem $dest -Directory -Filter '*.bundle' | ForEach-Object { Clear-Target $_.FullName }
        foreach ($item in Get-ChildItem "$tmp\new") {
            $target = Join-Path $dest $item.Name
            Clear-Target $target
            Copy-Item -Recurse $item.FullName $target
        }
        $da = Join-Path $dest 'da.exe'
        Clear-Target $da
        try { New-Item -ItemType HardLink -Path $da -Value (Join-Path $dest 'desertant.exe') | Out-Null }
        catch { Copy-Item (Join-Path $dest 'desertant.exe') $da }
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    Write-Host "Installed desertant $installed into $dest."
    $entries = @(([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object { $_ })
    if ($entries -notcontains $dest) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $dest) -join ';'), 'User')
        $env:Path = "$env:Path;$dest"
        Write-Host 'Added it to your PATH. Open a new terminal to run desertant or da.'
    }
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Host 'Install ffmpeg to read audio other than WAV, video, and images: winget install Gyan.FFmpeg'
    }
    return $true
}

# Run as a file, as `desertant update` does, a failure sets the exit code. Piped into
# iex, exit would close the window, so the message is all that is left.
if (-not (Install-Desertant) -and $PSCommandPath) { exit 1 }
