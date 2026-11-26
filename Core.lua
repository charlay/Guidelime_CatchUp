local addonName, addon = ...

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local COLOR_LIME = "|cFF82E600"
local COLOR_QUEST = "|cFF59C4F1"

addon.selectedGuideName = nil
addon.lastObservedGuide = nil
addon.lastScanResult = nil
addon.lastGeneratedGuide = nil
addon.debugging = false

local DEFAULT_DB = {
	includeOptional = false,
	includeDungeonElite = false,
	autoNotify = true,
	mergeWithTarget = true,
	viewMode = "ROUTE",
	minimap = { hide = false },
}

function addon.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(COLOR_LIME .. "[Guidelime: CatchUp]|r " .. tostring(msg))
end

local function debugPrint(...)
	if addon.debugging then
		print("|cFF88CCFF[Guidelime: CatchUp Debug]|r", ...)
	end
end

local function ensureDefaults()
	GuidelimeCatchUpDB = GuidelimeCatchUpDB or {}
	for k, v in pairs(DEFAULT_DB) do
		if GuidelimeCatchUpDB[k] == nil then
			if type(v) == "table" then
				GuidelimeCatchUpDB[k] = {}
				for tk, tv in pairs(v) do GuidelimeCatchUpDB[k][tk] = tv end
			else
				GuidelimeCatchUpDB[k] = v
			end
		end
	end
	GuidelimeCatchUpCharDB = GuidelimeCatchUpCharDB or {}
end

function addon.GetTargetGuideName()
	if addon.selectedGuideName then
		return addon.selectedGuideName
	end
	local current = GuidelimeDataChar and GuidelimeDataChar.currentGuide
	if current then
		local g = addon.Capture.GetGuide(current)
		if g and g.isCatchUp then
			if GuidelimeCatchUpCharDB and GuidelimeCatchUpCharDB.savedCatchUpGuides and GuidelimeCatchUpCharDB.savedCatchUpGuides[current] and GuidelimeCatchUpCharDB.savedCatchUpGuides[current].targetGuideName then
				return GuidelimeCatchUpCharDB.savedCatchUpGuides[current].targetGuideName
			end
			if GuidelimeCatchUpCharDB and GuidelimeCatchUpCharDB.savedCatchUpGuide and GuidelimeCatchUpCharDB.savedCatchUpGuide.targetGuideName then
				return GuidelimeCatchUpCharDB.savedCatchUpGuide.targetGuideName
			end
			if GuidelimeCatchUpCharDB and GuidelimeCatchUpCharDB.lastTargetGuide then
				return GuidelimeCatchUpCharDB.lastTargetGuide
			end
		end
	end
	return current
end

function addon.RunScan(notifyUser)
	ensureDefaults()
	addon.Capture.ImportLateGuides()

	if not addon.Scanner.IsQuestieReady() then
		addon.lastScanResult = { ready = false, error = "Waiting for Questie database to finish loading..." }
		if addon.UI.frame and addon.UI.frame:IsShown() then
			addon.UI.Refresh()
		end
		return
	end

	local targetName = addon.GetTargetGuideName()
	if not targetName then
		addon.lastScanResult = { ready = true, error = "No Guidelime guide selected. Pick a guide in Guidelime or use the Target Guide dropdown above." }
		if addon.UI.frame and addon.UI.frame:IsShown() then
			addon.UI.Refresh()
		end
		return
	end

	local guideEntry = addon.Capture.GetGuide(targetName)
	if not guideEntry then
		addon.lastScanResult = {
			ready = true,
			error = "Could not inspect guide \"" .. targetName .. "\". Make sure it was registered after Guidelime_CatchUp loaded.",
		}
		if addon.UI.frame and addon.UI.frame:IsShown() then
			addon.UI.Refresh()
		end
		return
	end

	if not guideEntry.isCatchUp then
		GuidelimeCatchUpCharDB.lastTargetGuide = guideEntry.name
	end

	local scan = addon.Scanner.ScanGuide(guideEntry, {
		includeOptional = GuidelimeCatchUpDB.includeOptional == true,
		includeDungeonElite = GuidelimeCatchUpDB.includeDungeonElite == true,
	})
	addon.lastScanResult = scan

	if addon.UI.frame and addon.UI.frame:IsShown() then
		addon.UI.Refresh()
	end

	if notifyUser and GuidelimeCatchUpDB.autoNotify ~= false and scan and scan.ready and not scan.error and scan.stats and scan.stats.total > 0 then
		local title = guideEntry.title or guideEntry.name
		addon.Print(string.format(
			"Found |cFFFFD100%d|r catch-up quest%s (%d prereq, %d carried-over) across %d zone%s for " .. COLOR_QUEST .. "%s|r. Type " .. COLOR_LIME .. "/catchup|r or click the minimap icon.",
			scan.stats.total, scan.stats.total == 1 and "" or "s",
			scan.stats.prereqs, scan.stats.carriedOver,
			scan.stats.zoneCount, scan.stats.zoneCount == 1 and "" or "s",
			title
		))
		if not (addon.UI.frame and addon.UI.frame:IsShown()) then
			addon.UI.ShowNotifyBanner(title, scan.stats)
		end
	end
end

function addon.GenerateAndRegisterGuide()
	if not addon.lastScanResult or not addon.lastScanResult.ordered or #addon.lastScanResult.ordered == 0 then
		addon.Print("No missing quests found to build a catch-up guide.")
		return
	end

	local result, err = addon.Generator.RegisterCatchUpGuide(addon.lastScanResult)
	if not result then
		addon.Print("|cFFFF4444Error:|r " .. tostring(err))
		return
	end

	addon.lastGeneratedGuide = result
	if addon.UI.frame and addon.UI.frame:IsShown() then
		addon.UI.Refresh()
	end

	local kindLabel = result.merged and "merged guide" or "catch-up guide"
	if result.loadedDirectly then
		addon.Print("Generated and loaded " .. kindLabel .. ": " .. COLOR_LIME .. result.name .. "|r")
	else
		addon.Print("Generated " .. kindLabel .. " " .. COLOR_LIME .. result.name .. "|r in Guidelime (original guide untouched)!")
		addon.Print("Click |cFFFFD100Load Guide (Reload UI)|r to activate it immediately, OR open Guidelime's Available Guides list (it's at the top of " .. COLOR_QUEST .. (result.group or "CatchUp") .. "|r).")
	end
end

-- Minimap Button via LibDataBroker + LibDBIcon (already loaded by Guidelime)
local function setupMinimapButton()
	if not LDB or not LDBIcon then return end
	if addon._minimapRegistered then return end
	addon._minimapRegistered = true

	local dataObj = LDB:NewDataObject(addonName, {
		type = "data source",
		text = "Guidelime: CatchUp",
		icon = "Interface\\AddOns\\Guidelime\\Icons\\lime",
		OnClick = function(_, button)
			if button == "LeftButton" then
				addon.UI.Toggle()
			elseif button == "RightButton" then
				addon.RunScan(true)
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("Guide" .. COLOR_LIME .. "lime|r: CatchUp", 1, 1, 1)
			local scan = addon.lastScanResult
			if scan and scan.ready and not scan.error and scan.guide and scan.stats then
				tooltip:AddLine("Guide: |cFFFFFFFF" .. (scan.guide.title or scan.guide.name) .. "|r")
				if scan.stats.total == 0 then
					tooltip:AddLine(COLOR_LIME .. "All caught up! (0 missing quests)|r")
				else
					tooltip:AddLine(string.format("|cFFFFD100%d missing quests|r (%d ready, %d in log)",
						scan.stats.total, scan.stats.ready, scan.stats.inLog))
				end
			else
				tooltip:AddLine("|cFFAAAAAANo guide scanned yet.|r")
			end
			tooltip:AddLine(" ")
			tooltip:AddLine(COLOR_LIME .. "Left-Click:|r Open / Close CatchUp Window", 0.85, 0.85, 0.85)
			tooltip:AddLine(COLOR_LIME .. "Right-Click:|r Rescan Active Guide", 0.85, 0.85, 0.85)
		end,
	})

	LDBIcon:Register(addonName, dataObj, GuidelimeCatchUpDB.minimap)
end

-- Slash commands
SLASH_GUIDELIMECATCHUP1 = "/limecatchup"
SLASH_GUIDELIMECATCHUP2 = "/catchup"
SLASH_GUIDELIMECATCHUP3 = "/glcu"
SlashCmdList["GUIDELIMECATCHUP"] = function(msg)
	local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if cmd == "" or cmd == "show" or cmd == "toggle" then
		addon.UI.Toggle()
	elseif cmd == "scan" or cmd == "check" then
		addon.RunScan(true)
		if addon.lastScanResult and addon.lastScanResult.stats and addon.lastScanResult.stats.total == 0 then
			addon.Print(COLOR_LIME .. "All caught up!|r 0 missing quests for " .. (addon.lastScanResult.guide.title or "this guide") .. ".")
		end
	elseif cmd == "generate" or cmd == "gen" then
		addon.RunScan(false)
		addon.GenerateAndRegisterGuide()
	elseif cmd == "clear" or cmd == "delete" then
		local count = 0
		if GuidelimeCatchUpCharDB then
			if type(GuidelimeCatchUpCharDB.savedCatchUpGuides) == "table" then
				for k in pairs(GuidelimeCatchUpCharDB.savedCatchUpGuides) do
					count = count + 1
					if GuidelimeDataChar and GuidelimeDataChar.progress then
						GuidelimeDataChar.progress[k] = nil
					end
					if GuidelimeDataChar and GuidelimeDataChar.guideSize then
						GuidelimeDataChar.guideSize[k] = nil
					end
				end
			end
			if GuidelimeCatchUpCharDB.savedCatchUpGuide and count == 0 then
				count = 1
			end
			if GuidelimeDataChar and GuidelimeDataChar.currentGuide then
				local cur = GuidelimeDataChar.currentGuide
				local g = addon.Capture.GetGuide(cur)
				if g and g.isCatchUp then
					local orig = (GuidelimeCatchUpCharDB.savedCatchUpGuides and GuidelimeCatchUpCharDB.savedCatchUpGuides[cur] and GuidelimeCatchUpCharDB.savedCatchUpGuides[cur].targetGuideName)
						or (GuidelimeCatchUpCharDB.savedCatchUpGuide and GuidelimeCatchUpCharDB.savedCatchUpGuide.targetGuideName)
						or GuidelimeCatchUpCharDB.lastTargetGuide
					if orig then GuidelimeDataChar.currentGuide = orig end
				end
			end
			GuidelimeCatchUpCharDB.savedCatchUpGuides = {}
			GuidelimeCatchUpCharDB.savedCatchUpGuide = nil
		end
		addon.lastGeneratedGuide = nil
		if addon.UI.frame and addon.UI.frame:IsShown() then addon.UI.Refresh() end
		addon.Print(string.format("Cleared %d generated catch-up guide%s. Run " .. COLOR_LIME .. "/reload|r to remove them from Guidelime's list.", count, count == 1 and "" or "s"))
	elseif cmd == "minimap" then
		GuidelimeCatchUpDB.minimap.hide = not GuidelimeCatchUpDB.minimap.hide
		if LDBIcon then
			if GuidelimeCatchUpDB.minimap.hide then
				LDBIcon:Hide(addonName)
				addon.Print("Minimap button hidden. Type /catchup minimap to show it again.")
			else
				LDBIcon:Show(addonName)
				addon.Print("Minimap button shown.")
			end
		end
	elseif cmd == "debug" then
		addon.debugging = not addon.debugging
		addon.Print("Debug logging: " .. (addon.debugging and "ON" or "OFF"))
	else
		addon.Print("Commands: " .. COLOR_LIME .. "/catchup|r (toggle window), " .. COLOR_LIME .. "/catchup scan|r, " .. COLOR_LIME .. "/catchup generate|r, " .. COLOR_LIME .. "/catchup clear|r, " .. COLOR_LIME .. "/catchup minimap|r")
	end
end

-- Debounced quest-log refresh
local pendingRefreshTimer = nil
local function scheduleLiveRefresh()
	if pendingRefreshTimer then pendingRefreshTimer:Cancel() end
	pendingRefreshTimer = C_Timer.NewTimer(0.4, function()
		pendingRefreshTimer = nil
		if addon.Scanner.IsQuestieReady() then
			if addon.UI.frame and addon.UI.frame:IsShown() then
				addon.RunScan(false)
			end
		end
	end)
end

-- Lightweight watcher for Guidelime guide selection changes
local function startGuideWatcher()
	if addon._watcherTicker then return end
	addon._watcherTicker = C_Timer.NewTicker(0.6, function()
		if not addon.Scanner.IsQuestieReady() then return end
		local current = GuidelimeDataChar and GuidelimeDataChar.currentGuide
		if current and current ~= addon.lastObservedGuide then
			addon.lastObservedGuide = current
			debugPrint("Detected guide change ->", current)
			local g = addon.Capture.GetGuide(current)
			if g and g.isCatchUp then
				if addon.UI.frame and addon.UI.frame:IsShown() then
					addon.RunScan(false)
				end
			else
				addon.selectedGuideName = nil
				addon.RunScan(true)
			end
		end
	end)
end

-- Wait for QuestieDB to finish its async startup, then run initial scan
local function waitForQuestieAndStart(attempts)
	attempts = attempts or 0
	if addon.Scanner.IsQuestieReady() then
		debugPrint("QuestieDB ready after", attempts, "checks. Captured guides:", #addon.Capture.guideOrder)
		addon.Capture.ImportLateGuides()
		local current = GuidelimeDataChar and GuidelimeDataChar.currentGuide
		addon.lastObservedGuide = current
		if current then
			local g = addon.Capture.GetGuide(current)
			if g and not g.isCatchUp then
				addon.RunScan(true)
			end
		end
		startGuideWatcher()
		return
	end
	if attempts < 60 then
		C_Timer.After(1.0, function() waitForQuestieAndStart(attempts + 1) end)
	else
		debugPrint("Timed out waiting for QuestieDB; starting watcher anyway.")
		startGuideWatcher()
	end
end

-- Event driver
local eventFrame = CreateFrame("Frame")
local function safeRegisterEvent(ev)
	if not C_EventUtils or C_EventUtils.IsEventValid(ev) then
		eventFrame:RegisterEvent(ev)
	end
end

safeRegisterEvent("ADDON_LOADED")
safeRegisterEvent("PLAYER_LOGIN")
safeRegisterEvent("QUEST_LOG_UPDATE")
safeRegisterEvent("QUEST_TURNED_IN")
safeRegisterEvent("QUEST_ACCEPTED")
safeRegisterEvent("QUEST_REMOVED")
safeRegisterEvent("PLAYER_LEVEL_UP")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		ensureDefaults()
		addon.Capture.ImportLateGuides()
	elseif event == "PLAYER_LOGIN" then
		ensureDefaults()
		addon.Capture.ImportLateGuides()
		setupMinimapButton()
		C_Timer.After(2.5, function() waitForQuestieAndStart(0) end)
	elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "PLAYER_LEVEL_UP" then
		scheduleLiveRefresh()
	end
end)
