# scoop-setup.ps1
# Bootstraps Scoop and installs a set of common packages for a fresh Windows install.
# Usage (from an *unelevated* PowerShell prompt):
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#   .\scoop-setup.ps1

# --- Install Scoop (if not already present) ---------------------------------
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop..." -ForegroundColor Cyan
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
} else {
    Write-Host "Scoop already installed." -ForegroundColor Green
}

# --- Install git first (required for adding buckets) -------------------------
scoop install git

# --- Add useful buckets -----------------------------------------------------
$buckets = @(
    'extras',
    'versions',
    'nerd-fonts',
    'java',
    'games'
)
foreach ($b in $buckets) {
    scoop bucket add $b
}

# --- Packages to install ----------------------------------------------------
# Edit this list to taste.
$packages = @(
    # Core CLI tools
    '7zip',
    'curl',
    'wget',
    'aria2',          # parallel downloader; speeds up scoop itself
    'sudo',
    'which',
    'grep',
    'sed',
    'jq',
    'ripgrep',
    'fd',
    'fzf',
    'bat',
    'eza',
    'starship',

    # Dev tools
    'gh',             # GitHub CLI
    'python',
    'nvm',
    'go',
    'vscode',
    'windows-terminal',
    'msys2',
    'ruby',
    'yt-dlp',
    'bun',
    'deno',
    'ffmpeg',


    # Apps (from extras bucket)
    'helium',
    'googlechrome'
    'vlc',
    'obsidian',
    'everything',
    'ytmdesktop',
    'obs-studio',
    'obsidian',
    'prismlauncher',
    'steam',
    'tabby',

    # Fonts
    'FiraCode-NF',

    # Java versions
    'graalvm',
    'graalvm20-jdk8',
    'graalvm21-jdk11',
    'graalvm21-jdk17',
    'graalvm21-jdk21',
    'temurin-lts-jdk',
    'temurin8-jdk',
    'temurin11-jdk',
    'temurin16-jdk',
    'temurin17-jdk',
    'temurin21-jdk',
    'temurin25-jdk',

    # .NET bullshit
    'vcredist2022',
    'windowsdesktop-runtime',
    'windowsdesktop-runtime-6.0',
    'windowsdesktop-runtime-7.0',
    'windowsdesktop-runtime-8.0',
    'windowsdesktop-runtime-9.0',
)

Write-Host "Installing $($packages.Count) packages..." -ForegroundColor Cyan
foreach ($p in $packages) {
    Write-Host "  -> $p" -ForegroundColor Yellow
    scoop install $p
}

# --- Enable aria2 multi-connection downloads --------------------------------
scoop config aria2-enabled true
scoop config aria2-warning-enabled false

# --- Install PowerShell 7 and set as Windows Terminal default ----------------
Write-Host "Installing PowerShell 7 (pwsh)..." -ForegroundColor Cyan
scoop install pwsh

Write-Host "Applying ChrisTitusTech PowerShell profile..." -ForegroundColor Cyan
pwsh -NoProfile -Command "irm https://github.com/ChrisTitusTech/powershell-profile/raw/main/setup.ps1 | iex"

# Point Windows Terminal's default profile at PowerShell 7.
# This is a per-user, fully reversible change (just edits Terminal's settings.json).
# It does NOT replace the OS-wide default shell (that needs registry edits + admin
# and isn't officially supported, so it's deliberately left out).
$wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wtSettings) {
    try {
        $json = Get-Content $wtSettings -Raw | ConvertFrom-Json
        $pwshProfile = $json.profiles.list | Where-Object { $_.commandline -match 'pwsh' -or $_.name -match 'PowerShell' -and $_.source -match 'Windows.Terminal.PowershellCore' } | Select-Object -First 1
        if ($pwshProfile) {
            $json.defaultProfile = $pwshProfile.guid
            $json | ConvertTo-Json -Depth 32 | Set-Content $wtSettings -Encoding utf8
            Write-Host "Set PowerShell 7 as the default Windows Terminal profile." -ForegroundColor Green
        } else {
            Write-Host "Could not find a PowerShell 7 profile in Windows Terminal yet." -ForegroundColor Yellow
            Write-Host "Open Windows Terminal once so it registers the pwsh profile, then re-run this section." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to update Windows Terminal settings: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "Windows Terminal settings.json not found." -ForegroundColor Yellow
    Write-Host "Launch Windows Terminal once to generate it, then set the default profile manually" -ForegroundColor Yellow
    Write-Host "(Settings -> Startup -> Default profile -> PowerShell)." -ForegroundColor Yellow
}

Write-Host "`nDone. Run 'scoop list' to see installed packages." -ForegroundColor Green
Write-Host "Run 'scoop update *' periodically to update everything." -ForegroundColor Green
