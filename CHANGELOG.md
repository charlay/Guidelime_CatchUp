# Changelog

All notable changes to **Guidelime: CatchUp** will be documented in this file.

## [1.0.1] - 2026-11-26

### Changed
- Added `X-Curse-Project-ID: 1833513` TOC metadata for CurseForge and WowUp-CF automatic addon matching.

## [1.0.0] - 2026-11-26

### Added
- **Automatic Prerequisite & Carried-Over Quest Detection:**
  - Scans any active or selected Guidelime guide for `[QC]`/`[QT]` steps missing an earlier `[QA]` in the same guide (carried-over quests).
  - Recursively resolves `QuestieDB` prerequisite chains (`preQuestSingle`, `preQuestGroup`, `availableStartingWith`) all the way back to the earliest uncompleted quest in every chain, skipping quests already completed earlier inside the same guide and respecting race/class/faction/exclusive rules.
- **Hub-Batched Spatial Route Optimizer:**
  - Splits catch-up quests into atomic `Accept`, `Do`, and `Turn In` actions using `QuestieDB` coordinates and `HereBeDragons-2.0` real-world distances.
  - Batches nearby turn-ins (unlocking follow-ups immediately at the same NPC) and accepts within quest hubs before heading out, sweeps field objectives in nearest-coordinate order, respects a 19-quest log cap, and finishes near the target guide's starting zone.
- **Non-Destructive Merged & Standalone Guide Generation:**
  - Generates a brand-new playable Guidelime guide (`0-0 CatchUp + <Target Guide>`) combining the optimized catch-up route with the full target guide and its `[NX...]` links, leaving original guides completely untouched.
  - Includes a toggle to generate a standalone catch-up-only guide instead.
- **Guidelime-Themed UI & Waypoints:**
  - Three views: **Route Order** (batched steps), **By Zone**, and **By Target Quest**, plus a dropdown to preview any installed guide.
  - Filter toggles for **Optional `[O]`**, **Dungeon / Elite**, **Auto-Notify**, and **Merge w/ Target**.
  - Left-click any row to set a waypoint (TomTom + native Blizzard Map Pin) and open the World Map; right-click to open the Quest Log or copy a flavor-matched Wowhead link.
  - Minimap button, auto-notification toast on guide switch, and slash commands (`/limecatchup`, `/catchup`, `/glcu`, including `/catchup clear`).
- **Multi-Flavor Support:** Compatible with WoW: Forever, Classic Era, TBC, Wrath, Cataclysm, and Mists of Pandaria Classic.
