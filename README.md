# Command Center

Utility hub and interface upgrade for World of Warcraft: Forever.

```
CommandCenter/            the addon
collected/                in-game recordings pushed from your PC (read by forever-db)
sync/                     PC scripts that push the recordings
.github/workflows/        recordings -> rebuild, database -> update, daily CurseForge release
```

## Automation

| When | What |
|---|---|
| Daily at 18:41 and at logon (your PC) | `sync-recordings.ps1` pushes new recordings to `collected/` |
| A push to `collected/` | `forever-db` rebuilds the database straight away |
| The database changed | `forever-db` publishes a new **ForeverDB** version to CurseForge (separate project, a required dependency of Command Center) |
| Daily at 08:23 UTC | `Daily release`: if anything changed since the last release, it bumps the version, tags, and uploads to CurseForge |

## One-time setup

1. **GitHub:** create the two repos, `CommandCenter` (this one) and `forever-db`.
2. **CurseForge:** create two projects, Command Center and ForeverDB, and note their **Project IDs**. Then create an **API token** at https://legacy.curseforge.com/account/api-tokens.
3. **This repo → Settings → Secrets and variables → Actions:**
   - Variable: `CF_PROJECT_ID` = the Command Center CurseForge project ID
   - Secrets:
     - `CF_API_KEY` = the CurseForge token
     - `PIPELINE_TOKEN` = a fine-grained GitHub token with Contents and Actions read/write on both repos
4. **forever-db → the same page:**
   - Variable: `ADDON_REPO` = `owner/CommandCenter`
   - Secret: `PIPELINE_TOKEN` (the same token)
   - Secret: `CF_API_KEY` (the same CurseForge token; ForeverDB goes to project 1807282)
5. **Your PC:** install Git for Windows (sign in to GitHub when it asks), then run:
   ```
   powershell -ExecutionPolicy Bypass -File sync\install-sync.ps1 -Repo owner/CommandCenter
   ```
6. Run **Build database** once by hand with *force* ticked (forever-db → Actions), then **Daily release** here.
