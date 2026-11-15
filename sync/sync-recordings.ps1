# Sends Command Center's in-game recordings to the addon repository (collected/ folder).
# Only the CommandCenterCollect block is copied out of the SavedVariables file - never your
# settings, whispers or anything else. Each WoW account becomes one file named by a hash.
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
git pull --rebase --quiet 2>&1 | Out-Null

$outDir = Join-Path $RepoPath "collected"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$sha = [System.Security.Cryptography.SHA256]::Create()
$found = 0
Get-ChildItem -Path (Join-Path $WowPath "WTF\Account") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $sv = Join-Path $_.FullName "SavedVariables\CommandCenter.lua"
  if (-not (Test-Path $sv)) { return }
  $text = Get-Content -Raw -Encoding UTF8 $sv
  # WoW writes each top-level variable as "Name = {" ... and closes it with "}" at column 0
  $m = [regex]::Match($text, "(?ms)^CommandCenterCollect\s*=\s*\{.*?^\}\s*$")
  if (-not $m.Success) { return }
  $block = $m.Value -replace '(?m)^\t\["recent"\] = \{.*?^\t\},\r?\n', ''   # skip the corpse de-dup list
  $hash = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($_.Name)) | ForEach-Object { $_.ToString("x2") }) -join ""
  $dest = Join-Path $outDir ("rec-" + $hash.Substring(0, 12) + ".lua")
  Set-Content -Path $dest -Value $block -Encoding UTF8 -NoNewline
  $found++
}
if ($found -eq 0) { Log "No recordings found under $WowPath (play with Command Center first, then log out or /reload)."; exit 0 }

git add collected | Out-Null
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Log "No new recordings."; exit 0 }
git commit -m "Recordings $(Get-Date -Format yyyy-MM-dd)" --quiet
git push --quiet
if ($LASTEXITCODE -ne 0) { Log "Push failed - check your GitHub sign-in (Git Credential Manager)."; exit 1 }
Log "Pushed recordings from $found account(s)."
