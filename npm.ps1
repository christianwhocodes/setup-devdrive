<#
.SYNOPSIS
  Configure npm prefix/cache on a Dev Drive.

.DESCRIPTION
  This script sets npm global prefix, cache and updates user environment variables.
  It creates required directories, safely updates ~/.npmrc (with a backup), updates the
  user PATH and also updates the current session PATH so global binaries are usable
  immediately.

USAGE
  Run in PowerShell (no elevation required for user-scope changes):
    .\setup-devdrive-npm.ps1
#>

# ---- Helper output functions (colored) ----
function Write-Info($msg) { Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Step($msg) { Write-Host "`n--- $msg ---" -ForegroundColor Magenta }

# ---- Config (adjust if you want) ----
$npmGlobal = "G:\.packages\npm"
$npmCache = Join-Path $npmGlobal "cache"
$npmBin = Join-Path $npmGlobal "bin"
$npmrcPath = Join-Path $env:USERPROFILE ".npmrc"

Write-Step "Starting npm Dev Drive setup"
Write-Info "Target prefix: $npmGlobal"
Write-Info "Target cache : $npmCache"

# ---- Create directories ----
foreach ($dir in @($npmGlobal, $npmCache, $npmBin)) {
    if (-not (Test-Path $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Ok "Created directory: $dir"
        }
        catch {
            Write-Err "Failed to create $dir : $_"
        }
    }
    else {
        Write-Info "Already exists: $dir"
    }
}

# ---- Configure npm (use npm if available) ----
Write-Step "Configuring npm (npm config set ...)"
if (Get-Command npm -ErrorAction SilentlyContinue) {
    try {
        npm config set prefix $npmGlobal 2>$null
        npm config set cache $npmCache 2>$null
        Write-Ok "npm config updated (prefix & cache)"
    }
    catch {
        Write-Warn "npm command failed to set config: $_"
    }
}
else {
    Write-Warn "npm not found in PATH. Skipping 'npm config set' commands."
}

# ---- Set user environment variables (both lowercase & uppercase variants) ----
Write-Step "Setting user environment variables"
try {
    [System.Environment]::SetEnvironmentVariable("NPM_CONFIG_PREFIX", $npmGlobal, "User")
    [System.Environment]::SetEnvironmentVariable("npm_config_prefix", $npmGlobal, "User")
    [System.Environment]::SetEnvironmentVariable("NPM_CONFIG_CACHE", $npmCache, "User")
    [System.Environment]::SetEnvironmentVariable("npm_config_cache", $npmCache, "User")
    Write-Ok "Set npm_config_* (user scope)"
}
catch {
    Write-Err "Failed to write npm env vars: $_"
}

# ---- Update user PATH and current session PATH ----
Write-Step "Updating user PATH to include npm bin"
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User") -or ""

# Normalize: remove trailing semicolons for concatenation safety
$userPathTrim = $userPath.TrimEnd(';')
$escapedBin = [regex]::Escape($npmBin)

if ($userPathTrim -notmatch "(^|;)$escapedBin($|;)") {
    $newUserPath = if ($userPathTrim) { "$userPathTrim;$npmBin" } else { $npmBin }
    try {
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Ok "User PATH updated to include: $npmBin"
    }
    catch {
        Write-Err "Failed to update user PATH: $_"
    }
}
else {
    Write-Info "npm bin already present in user PATH."
}

# Also update current session PATH so changes are available immediately
if ($env:Path -notmatch "(^|;)$escapedBin($|;)") {
    $env:Path = $env:Path.TrimEnd(';') + ";" + $npmBin
    Write-Ok "Current session PATH updated to include: $npmBin"
}
else {
    Write-Info "Current session PATH already contains npm bin."
}

# ---- Create or update .npmrc (backup existing) ----
Write-Step "Creating/updating $npmrcPath"
$desiredLines = @(
    "prefix=$npmGlobal"
    "cache=$npmCache"
)

try {
    if (-not (Test-Path $npmrcPath)) {
        $desiredLines | Set-Content -Path $npmrcPath -Encoding UTF8
        Write-Ok ".npmrc created at $npmrcPath"
    }
    else {
        $timestamp = (Get-Date).ToString('yyyyMMddHHmmss')
        $backup = "${npmrcPath}.bak.$timestamp"
        Copy-Item -Path $npmrcPath -Destination $backup -Force
        Write-Info "Existing .npmrc backed up to $backup"

        $existing = Get-Content -Path $npmrcPath -ErrorAction SilentlyContinue
        $updated = $existing | ForEach-Object {
            if ($_ -match '^prefix=') { "prefix=$npmGlobal" }
            elseif ($_ -match '^cache=') { "cache=$npmCache" }
            else { $_ }
        }

        if (-not ($updated -match '^prefix=')) { $updated += "prefix=$npmGlobal" }
        if (-not ($updated -match '^cache=')) { $updated += "cache=$npmCache" }

        $updated | Set-Content -Path $npmrcPath -Encoding UTF8
        Write-Ok ".npmrc updated (backup saved)"
    }
}
catch {
    Write-Err "Failed to create/update .npmrc: $_"
}

# ---- Verification checks (colored) ----
Write-Step "Verifying configuration"

# Helper to print a check with color (uses approved verb 'Write')
function Write-Check($label, $value, [switch]$isOk) {
    if ($isOk) { Write-Host "✅ ${label}: ${value}" -ForegroundColor Green }
    else { Write-Host "❌ ${label}: ${value}" -ForegroundColor Red }
}

# npm prefix/cache via npm (if available)
if (Get-Command npm -ErrorAction SilentlyContinue) {
    try {
        $npmPrefix = (npm config get prefix) -replace "`r|`n", ""
        $npmCacheGet = (npm config get cache) -replace "`r|`n", ""
    }
    catch {
        $npmPrefix = ""
        $npmCacheGet = ""
    }
}
else {
    $npmPrefix = ""
    $npmCacheGet = ""
}

Write-Check "npm config get prefix" $npmPrefix ($npmPrefix -and ($npmPrefix -ieq $npmGlobal))
Write-Check "npm config get cache"  $npmCacheGet ($npmCacheGet -and ($npmCacheGet -ieq $npmCache))

# npm bin -g (current session)
try {
    $npmBinCurrent = (npm bin -g) -replace "`r|`n", ""
    Write-Check "npm bin -g" $npmBinCurrent ($npmBinCurrent -and ($npmBinCurrent -ieq $npmBin))
}
catch {
    Write-Warn "npm bin -g unavailable or npm not found"
}

# Check directories
foreach ($d in @($npmGlobal, $npmCache, $npmBin)) {
    if (Test-Path $d) { Write-Host "📂 Exists: $d" -ForegroundColor Green }
    else { Write-Host "📂 Missing: $d" -ForegroundColor Red }
}

# Quick user guidance
Write-Step "Done"
Write-Info "New environment variable values are written to the user registry."
Write-Info "To pick them up in new shells, start a new PowerShell / CMD session or sign out and back in."
Write-Info "If you use 'refreshenv' (Chocolatey) or a similar tool, you can reload without restarting."

# Optionally show a helpful quick test command (colored)
Write-Host "`nTry installing a global package and running it:" -ForegroundColor Cyan
Write-Host "  npm i -g npm@latest" -ForegroundColor White
Write-Host "  npm list -g --depth=0" -ForegroundColor White
Write-Host "  where.exe npm" -ForegroundColor White

# End
Write-Ok "Setup script finished."