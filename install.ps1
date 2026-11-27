# Install dotfiles + Claude Code setup on native Windows.
# Usage (PowerShell): powershell -ExecutionPolicy Bypass -File .\install.ps1 [-NoDeps]
# Claude Code on Windows runs hooks through Git Bash, so the bash hooks and
# scripts work as-is. Files are copied, not symlinked (symlinks need Developer Mode).
param([switch]$NoDeps)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path

function Install-Deps {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found. Install "App Installer" from the Microsoft Store, then rerun.'
    }
    $pkgs = @(
        'Git.Git', 'GitHub.cli', 'jqlang.jq', 'OpenJS.NodeJS.LTS',
        'astral-sh.uv', 'Gitleaks.Gitleaks', 'JanDeDobbeleer.OhMyPosh', 'Gyan.FFmpeg'
    )
    foreach ($p in $pkgs) {
        Write-Host "==> winget $p"
        winget install --id $p -e --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {  # -1978335189 = already installed
            Write-Warning "winget $p exited $LASTEXITCODE (continuing)"
        }
    }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Find-GitBash {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw 'Git Bash not found. Install Git for Windows (winget install Git.Git) and rerun.'
}

function Install-PowerShellPrompt {
    $theme = Join-Path $HOME '.config\ohmyposh\theme.json'
    $line = "if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) { oh-my-posh init pwsh --config '$theme' | Invoke-Expression }"
    if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
    if (-not (Select-String -Path $PROFILE -SimpleMatch $line -Quiet)) {
        Add-Content -Path $PROFILE -Value "`n$line"
        Write-Host "==> added oh-my-posh to $PROFILE"
    }
}

if (-not $NoDeps) { Install-Deps }
$bash = Find-GitBash
$unixRepo = (& $bash -lc "cygpath -u '$Repo'").Trim()
& $bash -lc "cd '$unixRepo' && ./install.sh --copy --no-deps"
if ($LASTEXITCODE -ne 0) { throw "install.sh failed ($LASTEXITCODE)" }
Install-PowerShellPrompt
Write-Host '==> done. Restart your terminal.'
