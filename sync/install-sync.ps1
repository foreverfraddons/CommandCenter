# One-time setup on your PC: clones the addon repository and schedules the recordings sync
# (every day and whenever you log in to Windows). Needs Git for Windows (signed in to GitHub).
#   powershell -ExecutionPolicy Bypass -File install-sync.ps1 -Repo yourname/CommandCenter
param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [string]$WowPath  = "D:\Blizzard\World of Warcraft\_forever_",
  [string]$RepoPath = "$env:USERPROFILE\CommandCenter-repo",
  [string]$Time     = "6:41PM"
)
$ErrorActionPreference = "Stop"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git isn't installed - get Git for Windows from https://git-scm.com/download/win and run this again." }
if (-not (Test-Path (Join-Path $RepoPath ".git"))) { git clone "https://github.com/$Repo.git" $RepoPath }
$script = Join-Path $RepoPath "sync\sync-recordings.ps1"
$argLine = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -WowPath `"$WowPath`" -RepoPath `"$RepoPath`""
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argLine
$triggers = @((New-ScheduledTaskTrigger -Daily -At $Time), (New-ScheduledTaskTrigger -AtLogOn))
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName "Command Center recordings sync" -Action $action -Trigger $triggers -Settings $settings -Description "Pushes WoW Forever recordings to $Repo" -Force | Out-Null
Write-Host "Done. Recordings will be pushed daily at $Time and at logon. Running it once now..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $script -WowPath $WowPath -RepoPath $RepoPath
