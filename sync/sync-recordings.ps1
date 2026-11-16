# Sends the in-game recordings of Command Center (CommandCenterCollect) and Questicus
# (QuesticusCollect) to the addon repository (collected/ folder), where ForeverDB picks them up.
# Only those recording blocks are copied out of the SavedVariables files - never your settings,
# whispers or anything else. Each WoW account becomes one file per addon, named by a hash.
# Run by the scheduled task that install-sync.ps1 sets up (daily and at logon).
param(
  [string]$WowPath  = "D:\Blizzard\World of Warcraft\_forever_",
  [string]$RepoPath = "$env:USERPROFILE\CommandCenter-repo"
)
$ErrorActionPreference = "Stop"
$log = Join-Path $RepoPath "sync\last-sync.log"
function Log($m) { $line = "$(Get-Date -Format s)  $m"; Write-Host $line; Add-Content -Path $log -Value $line -ErrorAction SilentlyContinue }

if (-not (Test-Path (Join-Path $RepoPath ".git"))) { throw "Repository not found at $RepoPath - run install-sync.ps1 first." }
Set-Location $RepoPath
# this folder is only a sync copy: always start from what's on GitHub (your recordings are written
# again from the SavedVariables below, so nothing is lost)
git fetch --quiet origin 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Log "Could not reach GitHub (fetch failed) - check your internet / GitHub sign-in."; exit 1 }
git reset --hard --quiet origin/main 2>&1 | Out-Null
# git refuses to commit without a name and e-mail: give this sync copy its own
if (-not (git config user.email)) {
  git config user.name "Recordings sync"
  git config user.email "recordings-sync@users.noreply.github.com"
}

$outDir = Join-Path $RepoPath "collected"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$sha = [System.Security.Cryptography.SHA256]::Create()
$found = 0
$sources = @(
  @{ File = "CommandCenter.lua"; Var = "CommandCenterCollect"; Prefix = "rec-" },
  @{ File = "Questicus.lua";     Var = "QuesticusCollect";     Prefix = "qrec-" }
)
Get-ChildItem -Path (Join-Path $WowPath "WTF\Account") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $account = $_
  $hash = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($account.Name)) | ForEach-Object { $_.ToString("x2") }) -join ""
  foreach ($src in $sources) {
    $sv = Join-Path $account.FullName ("SavedVariables\" + $src.File)
    if (-not (Test-Path $sv)) { continue }
    $text = Get-Content -Raw -Encoding UTF8 $sv
    # WoW writes each top-level variable as "Name = {" ... and closes it with "}" at column 0
    $m = [regex]::Match($text, "(?ms)^" + $src.Var + "\s*=\s*\{.*?^\}\s*$")
    if (-not $m.Success) { continue }
    $block = $m.Value -replace '(?m)^\t\["recent"\] = \{.*?^\t\},\r?\n', ''   # skip the corpse de-dup list
    $dest = Join-Path $outDir ($src.Prefix + $hash.Substring(0, 12) + ".lua")
    Set-Content -Path $dest -Value $block -Encoding UTF8 -NoNewline
    $found++
  }
}
if ($found -eq 0) { Log "No recordings found under $WowPath (play with Command Center or Questicus first, then log out or /reload)."; exit 0 }

git add collected | Out-Null
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Log "No new recordings."; exit 0 }
git commit -m "Recordings $(Get-Date -Format yyyy-MM-dd)" --quiet
if ($LASTEXITCODE -ne 0) { Log "Commit failed (git said no) - nothing was sent."; exit 1 }
git push --quiet origin HEAD:main
if ($LASTEXITCODE -ne 0) { Log "Push failed - check your GitHub sign-in (Git Credential Manager)."; exit 1 }
Log "Pushed $found recording file(s)."
