# Command Center

## [v3.0.2](https://github.com/foreverfraddons/CommandCenter/tree/v3.0.2) (2026-11-16)
[Full Changelog](https://github.com/foreverfraddons/CommandCenter/compare/v3.0.1...v3.0.2) [Previous Releases](https://github.com/foreverfraddons/CommandCenter/releases)

- Release v3.0.2  
- Tools: S:RegisterTool so other addons (Questicus) appear as Command Center tools  
    Registered tools get a home tile, a Tools window row, a dock / Button Box icon; the  
    dock opens their window (t.window) out of the icon.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01GT6f3pdLBbtoQK4dfuHd3Z  
- Recordings sync: also send Questicus recordings (QuesticusCollect -> collected/qrec-<hash>.lua)  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01GT6f3pdLBbtoQK4dfuHd3Z  
- Show drops without a known rate as plain sources (ForeverDB chance 0)  
    ForeverDB now also merges QuestieDB, which lists where items drop but not  
    how often; those come through as chance 0 and are shown without a percent.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01GT6f3o68wGRs1Fj4Jogbye  
- Make ForeverDB (CurseForge: forever-db) a required dependency  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01GT6f3mdWksB39ToTkxtfgi  
- Use the separate ForeverDB addon instead of bundling the data  
    ItemDB loads ForeverDB (falls back to the old CommandCenter\_ForeverDB folder).  
    Removed CommandCenter\_ForeverDB/ and the update-db workflow; daily release only  
    watches the addon now.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01GT6f3mdWksB39ToTkxtfgi  
