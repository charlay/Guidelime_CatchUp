# Store Listing Copy (CurseForge / Wago / WowUpHub)

> This file is excluded from packaged addon zips via `.pkgmeta`. Copy-paste the sections below when creating listings on CurseForge, Wago Addons, or submitting to WowUpHub.

---

## Project Title
`Guidelime: CatchUp`

## Short Summary (1-liner)
Automatically finds missing prerequisite chains and carried-over quests for your Guidelime guide using QuestieDB, and generates hub-batched, spatially optimized catch-up & merged guides.

## Categories
- Primary: `Quests & Leveling`
- Secondary: `Map & Minimap`

## Full Description (Markdown)

Jumping into a mid-level **Guidelime** guide after running dungeons or leveling in another zone? **Guidelime: CatchUp** scans your selected guide against your character's quest history and **QuestieDB** to find every missing quest you need — then builds an optimized, playable catch-up route right inside Guidelime.

### What It Finds
- **Carried-Over Quests:** Detects `[QC]` and `[QT]` steps in your guide that assume you already accepted the quest in an earlier guide (including quests in your log that still need objectives completed before turning in).
- **Full Prerequisite Chains:** Recursively walks `QuestieDB` (`preQuestSingle`, `preQuestGroup`, `availableStartingWith`) back to the earliest quest you can actually pick up today, respecting race/class/faction rules and skipping chains already completed earlier inside the same guide.

### Hub-Batched Spatial Route Optimizer
Instead of running back and forth one quest at a time, **Guidelime: CatchUp** uses `QuestieDB` coordinates and `HereBeDragons-2.0` yard distances to:
- Batch all ready **Turn-Ins** (unlocking follow-ups at the same NPC) and nearby **Accepts** at each town hub before heading out.
- Sweep nearby **Objectives** in nearest-coordinate order before returning to town.
- Respect a safe 19-quest log cap and finish near your target guide's starting zone.

### Non-Destructive Merged Guides
- One click generates a brand-new guide (`0-0 CatchUp + <Target Guide>`) combining your optimized catch-up steps seamlessly with the full target guide and its `[NX...]` links.
- Never modifies or overwrites your original guides, Guidelime, or Questie.
- Prefer a standalone catch-up guide? Just uncheck **Merge w/ Target**.

### Interactive Window & Waypoints
- Switch between **Route Order**, **By Zone**, and **By Target Quest** views, or preview any installed guide from the dropdown.
- Toggle **Optional `[O]`** and **Dungeon / Elite** quests anytime.
- **Left-Click** any step to set a waypoint (TomTom + native map pin) and open the World Map; **Right-Click** to open the Quest Log or copy a Wowhead link.
- Commands: `/limecatchup`, `/catchup`, `/glcu`, `/catchup clear`.

### Requirements
- **Guidelime**
- **Questie**
