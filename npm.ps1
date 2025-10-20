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
    .\npm.ps1
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

# ---- Update user PATH and current session PATH (safe, append-only) ----
Write-Step "Updating user PATH to include npm bin"

# Read user PATH robustly
$userPathRaw = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($null -eq $userPathRaw) { $userPath = "" }
elseif ($userPathRaw -is [string]) { $userPath = $userPathRaw }
else { $userPath = [string]$userPathRaw }

# Helper: normalize entries for reliable comparison
function ConvertTo-NormalizedEntry($e) {
    if (-not $e) { return "" }
    # Expand environment variables
    $expanded = [Environment]::ExpandEnvironmentVariables($e)
    $normalized = $expanded.Trim()
    # Replace forward slashes with backslashes and collapse duplicate backslashes
    $normalized = $normalized -replace '/', '\'
    # Remove trailing backslashes (but keep root like C:\)
    if ($normalized -ne '' -and $normalized -ne '\' -and $normalized.Length -gt 1) {
        $normalized = $normalized.TrimEnd('\')
    }
    return $normalized.ToLowerInvariant()
}

# Fix malformed PATH: detect missing semicolons between paths by looking for drive letter patterns
Write-Step "Checking PATH format integrity"
if ($userPath -match '[A-Za-z]:\\[^;]*[A-Za-z]:\\') {
    Write-Warn "Detected malformed PATH with missing semicolons!"
    $fixedPath = $userPath -replace '([A-Za-z]:\\[^;]*?)([A-Za-z]:\\)', '$1;$2'
    $userPath = $fixedPath
    Write-Ok "Path separator issues fixed"
}

# Split the user PATH into distinct entries
$userEntries = @()
if ($userPath) {
    $userEntries = $userPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

# Additional safety check - look for suspicious entries that might be merged paths
$cleanedEntries = @()
foreach ($entry in $userEntries) {
    # Check if entry contains multiple drive letters (e.g., "C:\pathD:\path")
    if ($entry -match '^[A-Za-z]:\\.*[A-Za-z]:\\') {
        $splitPaths = $entry -split '(?<=\\)(?=[A-Za-z]:\\)'
        Write-Warn "Split suspicious PATH entry: $entry"
        $cleanedEntries += $splitPaths | Where-Object { $_ -ne "" }
    }
    else {
        $cleanedEntries += $entry
    }
}
$userEntries = $cleanedEntries

# Display current PATH for verification
Write-Info "Current PATH entries:"
foreach ($entry in $userEntries) {
    Write-Host "  - $entry" -ForegroundColor DarkGray
}

# Remove default npm path if present
$defaultNpmPath = Join-Path $env:APPDATA "npm"
$defaultNpmPathNormalized = ConvertTo-NormalizedEntry $defaultNpmPath
$hasDefaultNpmPath = $false

# Filter out the default npm path if it exists
$filteredEntries = @()
foreach ($entry in $userEntries) {
    $entryNormalized = ConvertTo-NormalizedEntry $entry
    if ($entryNormalized -eq $defaultNpmPathNormalized) {
        Write-Warn "Removing default npm path from PATH: $entry"
        $hasDefaultNpmPath = $true
    }
    else {
        $filteredEntries += $entry
    }
}

if ($hasDefaultNpmPath) {
    $userEntries = $filteredEntries
    $changed = $true
    Write-Info "Default npm PATH entry has been removed."
}

# Ensure typical default user entries exist (WindowsApps) — safe to add if missing
$defaultUserEntries = @("$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps")

# Build a hashset of normalized existing entries to avoid duplicates
$existingNormalized = @{}
foreach ($e in $userEntries) {
    $key = ConvertTo-NormalizedEntry $e
    if ($key -ne "") { $existingNormalized[$key] = $true }
}

$changed = $false

# Add default user entries if missing
foreach ($def in $defaultUserEntries) {
    $k = ConvertTo-NormalizedEntry $def
    if (-not $existingNormalized.ContainsKey($k)) {
        $userEntries += $def
        $existingNormalized[$k] = $true
        $changed = $true
        Write-Info "Adding default user PATH entry: $def"
    }
}

# Add npm bin if missing
$npmBinNormalized = ConvertTo-NormalizedEntry $npmBin
if ($npmBinNormalized -ne "" -and -not $existingNormalized.ContainsKey($npmBinNormalized)) {
    $userEntries += $npmBin
    $existingNormalized[$npmBinNormalized] = $true
    $changed = $true
    Write-Ok "Will add npm bin to user PATH: $npmBin"
}
else {
    Write-Info "npm bin already present in user PATH."
}

# Only write when there's a change to avoid accidental overwrites
if ($changed) {
    # Re-join entries preserving order and removing exact duplicates (case-insensitive normalized)
    $finalEntries = @()
    $seen = @{}
    foreach ($e in $userEntries) {
        $k = ConvertTo-NormalizedEntry $e
        if ($k -and -not $seen.ContainsKey($k)) {
            $finalEntries += $e
            $seen[$k] = $true
        }
    }
    $newUserPath = ($finalEntries -join ';')
    try {
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Ok "User PATH updated (preserved existing entries and appended missing ones)."
    }
    catch {
        Write-Err "Failed to update user PATH: $_"
    }
}
else {
    Write-Info "No changes needed to user PATH."
}

# Update current session PATH similarly (do not destroy existing session entries)
$currentEnvPath = if ($env:Path -is [string]) { $env:Path } elseif ($null -eq $env:Path) { "" } else { [string]$env:Path }
$currentEntries = @()
if ($currentEnvPath) {
    $currentEntries = $currentEnvPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}
$currentNormalized = @{}
foreach ($e in $currentEntries) {
    $key = ConvertTo-NormalizedEntry $e
    if ($key -ne "") { $currentNormalized[$key] = $true }
}

if (-not $currentNormalized.ContainsKey($npmBinNormalized)) {
    # Append npm bin to current session PATH (preserve order)
    $updatedCurrent = @()
    $updatedCurrent += $currentEntries
    $updatedCurrent += $npmBin
    # Remove duplicates preserving first occurrence
    $finalCurrent = @()
    $seenC = @{}
    foreach ($e in $updatedCurrent) {
        $k = ConvertTo-NormalizedEntry $e
        if ($k -and -not $seenC.ContainsKey($k)) {
            $finalCurrent += $e
            $seenC[$k] = $true
        }
    }
    $env:Path = ($finalCurrent -join ';')
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

        # Use a joined string when checking for presence to avoid array -match ambiguity
        if (-not ($updated -join "`n" -match '^prefix=')) { $updated += "prefix=$npmGlobal" }
        if (-not ($updated -join "`n" -match '^cache=')) { $updated += "cache=$npmCache" }

        $updated | Set-Content -Path $npmrcPath -Encoding UTF8
        Write-Ok ".npmrc updated (backup saved)"
    }
}
catch {
    Write-Err "Failed to create/update .npmrc: $_"
}

# ---- Verification checks (colored) ----
Write-Step "Verifying configuration"

function Write-Check($label, $value, [switch]$isOk) {
    if ($isOk) { Write-Host "✅ ${label}: ${value}" -ForegroundColor Green }
    else { Write-Host "❌ ${label}: ${value}" -ForegroundColor Red }
}

# Add path format verification
if ($env:Path -match '[A-Za-z]:\\[^;]*[A-Za-z]:\\') {
    Write-Check "PATH format" "Missing semicolons detected" $false
}
else {
    Write-Check "PATH format" "Proper semicolon separators" -isOk
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    try {
        $npmPrefix = (npm config get prefix) -replace "`r|`n", ""
        $npmCacheGet = (npm config get cache) -replace "`r|`n", ""
        
        # Check if the values match the expected values
        $prefixMatch = $npmPrefix -ieq $npmGlobal
        $cacheMatch = $npmCacheGet -ieq $npmCache
        
        Write-Check "npm config get prefix" $npmPrefix -isOk:$prefixMatch
        Write-Check "npm config get cache"  $npmCacheGet -isOk:$cacheMatch
    }
    catch {
        Write-Check "npm config get prefix" "Error retrieving" $false
        Write-Check "npm config get cache"  "Error retrieving" $false
    }
}
else {
    Write-Check "npm" "Not found in PATH" $false
}

foreach ($d in @($npmGlobal, $npmCache, $npmBin)) {
    if (Test-Path $d) { Write-Host "📂 Exists: $d" -ForegroundColor Green }
    else { Write-Host "📂 Missing: $d" -ForegroundColor Red }
}

Write-Step "Done"
Write-Info "New environment variable values are written to the user registry."
Write-Info "To pick them up in new shells, start a new PowerShell / CMD session or sign out and back in."
Write-Info "If you use 'refreshenv' (Chocolatey) or a similar tool, you can reload without restarting."

Write-Host "`nTry installing a global package and running it:" -ForegroundColor Cyan
Write-Host "  npm i -g npm@latest" -ForegroundColor White
Write-Host "  npm list -g --depth=0" -ForegroundColor White
Write-Host "  where.exe npm" -ForegroundColor White

Write-Ok "Setup script finished."