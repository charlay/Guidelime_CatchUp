local addonName, addon = ...

addon.UI = addon.UI or {}
local UI = addon.UI

-- Guidelime-inspired palette
local COLOR_LIME = "|cFF82E600"
local COLOR_QUEST = "|cFF59C4F1"
local COLOR_GOLD = "|cFFFFD100"
local COLOR_MUTED = "|cFF99A39E"

local ICON_LIME = "Interface\\AddOns\\Guidelime\\Icons\\lime"
local ICON_UNAVAILABLE = "Interface\\AddOns\\Guidelime\\Icons\\questunavailable"

local BACKDROP_MAIN = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true,
	tileSize = 32,
	edgeSize = 24,
	insets = { left = 6, right = 6, top = 6, bottom = 6 },
}

local BACKDROP_SUB = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = false,
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local STATUS_INFO = {
	READY = {
		label = "READY",
		color = COLOR_LIME,
		icon = "Interface\\GossipFrame\\AvailableQuestIcon",
		desc = "Available to pick up now",
	},
	IN_LOG_COMPLETE = {
		label = "TURN IN",
		color = COLOR_GOLD,
		icon = "Interface\\GossipFrame\\ActiveQuestIcon",
		desc = "In your quest log and ready to turn in",
	},
	IN_LOG = {
		label = "IN LOG",
		color = COLOR_QUEST,
		icon = "Interface\\GossipFrame\\IncompleteQuestIcon",
		desc = "In your quest log — finish objectives",
	},
	BLOCKED = {
		label = "CHAIN",
		color = "|cFFFFA500",
		icon = ICON_UNAVAILABLE,
		desc = "Unlocked after an earlier quest in this list",
	},
	LEVEL_LOW = {
		label = "LOW LVL",
		color = "|cFFFF3B30",
		icon = ICON_UNAVAILABLE,
		desc = "Your character level is below the minimum required level",
	},
}

local ACTION_INFO = {
	ACCEPT = {
		label = "ACCEPT",
		color = COLOR_LIME,
		icon = "Interface\\GossipFrame\\AvailableQuestIcon",
	},
	COMPLETE = {
		label = "DO",
		color = COLOR_QUEST,
		icon = "Interface\\GossipFrame\\WorkOrderGossipIcon",
	},
	TURNIN = {
		label = "TURN IN",
		color = COLOR_GOLD,
		icon = "Interface\\GossipFrame\\ActiveQuestIcon",
	},
}

-- Match Guidelime's WoW quest-difficulty level colors
local function getLevelColor(level)
	if not level or level <= 0 then return "|cFF808080" end
	local pLevel = UnitLevel("player") or 1
	if level > pLevel + 4 then
		return "|cFFFF2A1A" -- Red
	elseif level > pLevel + 2 then
		return "|cFFFFA500" -- Orange
	elseif level >= pLevel - 2 then
		return "|cFFFFFF00" -- Yellow
	elseif level >= pLevel - 4 - math.min(4, math.floor(pLevel / 10)) then
		return "|cFF40C040" -- Green
	else
		return "|cFF808080" -- Gray
	end
end

local function getWowheadQuestUrl(questId)
	local build = select(4, GetBuildInfo()) or 16001
	local sub = "classic"
	if build >= 50000 then
		sub = "mop-classic"
	elseif build >= 40000 then
		sub = "cata"
	elseif build >= 30000 then
		sub = "wotlk"
	elseif build >= 20000 then
		sub = "tbc"
	end
	return "https://www.wowhead.com/" .. sub .. "/quest=" .. tostring(questId)
end

local function formatCoords(loc)
	if not loc then return "Unknown location" end
	local parts = {}
	if loc.zoneName then table.insert(parts, loc.zoneName) end
	if loc.x and loc.y and (loc.x > 0 or loc.y > 0) then
		table.insert(parts, string.format("(%.1f, %.1f)", loc.x, loc.y))
	end
	if loc.name then table.insert(parts, "- " .. loc.name) end
	return table.concat(parts, " ")
end

local function setWaypointForNode(node, forcedLoc, forcedActionLabel)
	if not node then return end
	local loc = forcedLoc
	local actionLabel = forcedActionLabel
	if not loc then
		loc = node.starter
		actionLabel = "Accept"
		if node.inLogComplete and node.finisher then
			loc = node.finisher
			actionLabel = "Turn In"
		elseif node.inLog and node.finisher and not node.hasObjectives then
			loc = node.finisher
			actionLabel = "Turn In"
		end
	end

	if not loc or not loc.uiMapId then
		addon.Print("No coordinates found in QuestieDB for " .. node.name .. " (#" .. node.questId .. ").")
		return
	end

	local title = string.format("%s: %s", actionLabel, node.name)
	local setAny = false

	-- 1. TomTom if installed
	if TomTom and TomTom.AddWaypoint and loc.x and loc.y then
		pcall(function()
			TomTom:AddWaypoint(loc.uiMapId, loc.x / 100, loc.y / 100, {
				title = title,
				crazy = true,
				from = "Guidelime: CatchUp",
			})
		end)
		setAny = true
	end

	-- 2. Native Blizzard Map Pin if supported
	if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and loc.x and loc.y then
		if C_Map.CanSetUserWaypointOnMap(loc.uiMapId) then
			pcall(function()
				local point = UiMapPoint.CreateFromCoordinates(loc.uiMapId, loc.x / 100, loc.y / 100)
				C_Map.SetUserWaypoint(point)
				if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
					C_SuperTrack.SetSuperTrackedUserWaypoint(true)
				end
			end)
			setAny = true
		end
	end

	-- 3. Open World Map cleanly via QuestieCompat (taint-safe on WoW: Forever & Classic)
	local QuestieCompat = QuestieLoader and QuestieLoader:ImportModule("QuestieCompat")
	if QuestieCompat and QuestieCompat.OpenWorldMap then
		QuestieCompat.OpenWorldMap(loc.uiMapId)
	elseif C_Map and C_Map.OpenWorldMap and not InCombatLockdown() then
		C_Map.OpenWorldMap(loc.uiMapId)
	end

	if setAny then
		addon.Print(string.format("Waypoint set: %s — %s", title, formatCoords(loc)))
	else
		addon.Print(string.format("Showing map: %s — %s", title, formatCoords(loc)))
	end
end

-- Reusable copyable text popup (for generated guide text or Wowhead URL)
function UI.ShowCopyPopup(titleText, bodyText)
	if not UI.copyFrame then
		local f = CreateFrame("Frame", "GuidelimeCatchUpCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		f:SetSize(560, 420)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		if f.SetBackdrop then
			f:SetBackdrop(BACKDROP_MAIN)
			f:SetBackdropColor(0.05, 0.07, 0.06, 0.96)
		end

		f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		f.title:SetPoint("TOPLEFT", 18, -16)

		f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
		f.hint:SetText("Press Ctrl+C to copy. Press Esc or Close when done.")

		local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		closeBtn:SetPoint("TOPRIGHT", -6, -6)

		local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 16, -54)
		sf:SetPoint("BOTTOMRIGHT", -34, 44)

		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetFontObject("ChatFontNormal")
		eb:SetWidth(500)
		eb:SetAutoFocus(true)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		sf:SetScrollChild(eb)
		f.editBox = eb

		local okBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		okBtn:SetSize(100, 24)
		okBtn:SetPoint("BOTTOMRIGHT", -16, 12)
		okBtn:SetText(CLOSE or "Close")
		okBtn:SetScript("OnClick", function() f:Hide() end)

		table.insert(UISpecialFrames, "GuidelimeCatchUpCopyFrame")
		UI.copyFrame = f
	end

	UI.copyFrame.title:SetText(titleText or "Guidelime: CatchUp")
	UI.copyFrame.editBox:SetText(bodyText or "")
	UI.copyFrame.editBox:HighlightText()
	UI.copyFrame:Show()
	UI.copyFrame.editBox:SetFocus()
end

local function showNodeTooltip(row, node, scanResult)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT", 6, 0)
	local lvlStr = (node.level and node.level > 0) and (getLevelColor(node.level) .. "[" .. node.level .. "]|r ") or ""
	GameTooltip:AddLine(lvlStr .. COLOR_QUEST .. node.name .. "|r |cFF888888(#" .. node.questId .. ")|r", 1, 1, 1)

	local st = STATUS_INFO[node.status] or STATUS_INFO.READY
	GameTooltip:AddLine("Status: " .. st.color .. st.desc .. "|r", 0.9, 0.9, 0.9)

	if node.requiredLevel and node.requiredLevel > 0 then
		local playerLvl = UnitLevel("player") or 1
		local c = (playerLvl < node.requiredLevel) and "|cFFFF3B30" or "|cFFCCCCCC"
		GameTooltip:AddLine("Minimum Level: " .. c .. node.requiredLevel .. "|r", 0.8, 0.8, 0.8)
	end

	GameTooltip:AddLine(" ")
	if node.reason == "CARRIED_OVER" then
		GameTooltip:AddLine("Why needed: |cFFFFFFFFGuide references this quest ([QC]/[QT]) without accepting it first.|r", 0.75, 0.95, 0.65, true)
	elseif node.reason == "CARRIED_OVER_INCOMPLETE" then
		GameTooltip:AddLine("Why needed: |cFFFFFFFFGuide expects you to turn this quest in, so finish its objectives first.|r", 0.75, 0.95, 0.65, true)
	else
		local targetNames = {}
		for _, tid in ipairs(node.forTargetQuests or {}) do
			local tm = scanResult.targetQuestMeta and scanResult.targetQuestMeta[tid]
			table.insert(targetNames, tm and tm.name or ("Quest #" .. tid))
		end
		if #targetNames > 0 then
			GameTooltip:AddLine("Unlocks in guide: |cFFFFFFFF" .. table.concat(targetNames, ", ") .. "|r", 0.75, 0.95, 0.65, true)
		end
	end

	if node.prereqs and #node.prereqs > 0 then
		local preNames = {}
		for _, pid in ipairs(node.prereqs) do
			local pn = scanResult.nodes and scanResult.nodes[pid]
			table.insert(preNames, pn and pn.name or ("Quest #" .. pid))
		end
		GameTooltip:AddLine("Requires first: |cFFFFA500" .. table.concat(preNames, ", ") .. "|r", 0.9, 0.7, 0.5, true)
	end

	local todo = {}
	if node.needsAccept then table.insert(todo, "Accept") end
	if node.needsComplete and node.hasObjectives then table.insert(todo, "Complete") end
	if node.needsTurnIn then table.insert(todo, "Turn In") end
	if #todo > 0 then
		GameTooltip:AddLine("Catch-up steps: |cFFFFFFFF" .. table.concat(todo, " -> ") .. "|r", 0.8, 0.8, 0.8)
	end

	GameTooltip:AddLine(" ")
	if node.starter then
		GameTooltip:AddLine("Start: |cFFFFFFFF" .. formatCoords(node.starter) .. "|r", 0.55, 0.92, 0.25, true)
	end
	if node.finisher then
		GameTooltip:AddLine("Turn-in: |cFFFFFFFF" .. formatCoords(node.finisher) .. "|r", 1, 0.85, 0.35, true)
	end

	if node.sourceGuide then
		GameTooltip:AddLine("Earlier Guidelime guide: " .. COLOR_QUEST .. node.sourceGuide .. "|r", 0.7, 0.85, 1, true)
	end

	if node.alternatives and #node.alternatives > 0 then
		local QuestieDB = QuestieLoader and QuestieLoader:ImportModule("QuestieDB")
		local altNames = {}
		for _, altId in ipairs(node.alternatives) do
			local aq = QuestieDB and QuestieDB.GetQuest(altId)
			table.insert(altNames, aq and aq.name or ("#" .. altId))
		end
		GameTooltip:AddLine("Alternative option(s): |cFFAAAAAA" .. table.concat(altNames, ", ") .. "|r", 0.7, 0.7, 0.7, true)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(COLOR_LIME .. "Left-Click:|r Set Waypoint & Open Map", 0.85, 0.85, 0.85)
	GameTooltip:AddLine(COLOR_LIME .. "Right-Click:|r " .. (node.inLog and "Open in Quest Log" or "Copy Wowhead Link"), 0.85, 0.85, 0.85)
	GameTooltip:Show()
end

-- Guidelime-themed notification banner when switching to a guide with missing prereqs
function UI.ShowNotifyBanner(guideTitle, stats)
	if not UI.banner then
		local b = CreateFrame("Frame", "GuidelimeCatchUpBanner", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		b:SetSize(430, 58)
		b:SetPoint("TOP", UIParent, "TOP", 0, -110)
		b:SetFrameStrata("DIALOG")
		b:EnableMouse(true)
		if b.SetBackdrop then
			b:SetBackdrop(BACKDROP_SUB)
			b:SetBackdropColor(0.05, 0.08, 0.06, 0.95)
			b:SetBackdropBorderColor(0.51, 0.90, 0.0, 0.95)
		end

		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(24, 24)
		b.icon:SetPoint("LEFT", 12, 0)
		b.icon:SetTexture(ICON_LIME)

		b.title = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, 6)
		b.title:SetPoint("RIGHT", -96, 0)
		b.title:SetJustifyH("LEFT")

		b.sub = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		b.sub:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -3)
		b.sub:SetPoint("RIGHT", -96, 0)
		b.sub:SetJustifyH("LEFT")

		b.openBtn = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
		b.openBtn:SetSize(64, 24)
		b.openBtn:SetPoint("RIGHT", -26, 0)
		b.openBtn:SetText("View")
		b.openBtn:SetScript("OnClick", function()
			b:Hide()
			UI.Show()
		end)

		b.closeBtn = CreateFrame("Button", nil, b, "UIPanelCloseButton")
		b.closeBtn:SetSize(20, 20)
		b.closeBtn:SetPoint("TOPRIGHT", -3, -3)
		b.closeBtn:SetScript("OnClick", function() b:Hide() end)

		UI.banner = b
	end

	UI.banner.title:SetText(string.format(COLOR_LIME .. "Guidelime CatchUp:|r %d missing quest%s for %s", stats.total, stats.total == 1 and "" or "s", guideTitle or "guide"))
	UI.banner.sub:SetText(string.format("%d ready now  •  %d in log  •  %d zone%s", stats.ready, stats.inLog, stats.zoneCount, stats.zoneCount == 1 and "" or "s"))
	UI.banner:Show()

	if UI.bannerTimer then UI.bannerTimer:Cancel() end
	UI.bannerTimer = C_Timer.NewTimer(10, function()
		if UI.banner and UI.banner:IsShown() then
			UI.banner:Hide()
		end
	end)
end

-- Main Guidelime: CatchUp window
function UI.CreateMainFrame()
	if UI.frame then return UI.frame end

	local f = CreateFrame("Frame", "GuidelimeCatchUpFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	local db = GuidelimeCatchUpDB or {}
	f:SetSize(db.width or 700, db.height or 520)
	if db.point and db.x and db.y then
		f:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	else
		f:SetPoint("CENTER")
	end
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(560, 380, 980, 760)
	elseif f.SetMinResize then
		f:SetMinResize(560, 380)
	end
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		GuidelimeCatchUpDB.point = point
		GuidelimeCatchUpDB.x = math.floor(x)
		GuidelimeCatchUpDB.y = math.floor(y)
	end)
	if f.SetBackdrop then
		f:SetBackdrop(BACKDROP_MAIN)
		f:SetBackdropColor(0.05, 0.07, 0.06, 0.96)
	end
	f:Hide()
	table.insert(UISpecialFrames, "GuidelimeCatchUpFrame")

	-- Resize grip
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		GuidelimeCatchUpDB.width = math.floor(f:GetWidth())
		GuidelimeCatchUpDB.height = math.floor(f:GetHeight())
		UI.Refresh()
	end)

	-- Guidelime-themed Title & Close button
	local titleIcon = f:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(20, 20)
	titleIcon:SetPoint("TOPLEFT", 16, -14)
	titleIcon:SetTexture(ICON_LIME)

	f.titleText = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	f.titleText:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
	f.titleText:SetText("Guide" .. COLOR_LIME .. "lime|r: CatchUp")

	local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -6, -6)

	-- Guide Picker Row
	local guideLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	guideLabel:SetPoint("TOPLEFT", 18, -44)
	guideLabel:SetText(COLOR_LIME .. "Target Guide:|r")

	f.guideBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.guideBtn:SetHeight(22)
	f.guideBtn:SetPoint("LEFT", guideLabel, "RIGHT", 8, 0)
	f.guideBtn:SetPoint("RIGHT", f, "RIGHT", -118, 0)
	f.guideBtn:SetText("Select a Guide...")
	f.guideBtn:SetScript("OnClick", function(self)
		UI.OpenGuideDropdown(self)
	end)

	f.useCurrentBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.useCurrentBtn:SetSize(96, 22)
	f.useCurrentBtn:SetPoint("LEFT", f.guideBtn, "RIGHT", 6, 0)
	f.useCurrentBtn:SetText("Use Active")
	f.useCurrentBtn:SetScript("OnClick", function()
		addon.selectedGuideName = nil
		addon.RunScan(false)
	end)

	-- Filter & View Toolbar (lime-accented border)
	local toolbar = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
	toolbar:SetPoint("TOPLEFT", 14, -72)
	toolbar:SetPoint("TOPRIGHT", -14, -72)
	toolbar:SetHeight(56)
	if toolbar.SetBackdrop then
		toolbar:SetBackdrop(BACKDROP_SUB)
		toolbar:SetBackdropColor(0.07, 0.10, 0.08, 0.90)
		toolbar:SetBackdropBorderColor(0.40, 0.65, 0.15, 0.80)
	end

	local function makeCheckbox(parent, label, tooltip, key)
		local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
		cb:SetSize(22, 22)
		local lbl = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		lbl:SetText(label)
		cb.label = lbl
		cb:SetChecked(GuidelimeCatchUpDB[key] == true)
		cb:SetScript("OnClick", function(self)
			GuidelimeCatchUpDB[key] = self:GetChecked() and true or false
			addon.RunScan(false)
		end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(label, 0.51, 0.90, 0.0)
			GameTooltip:AddLine(tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return cb
	end

	f.cbOptional = makeCheckbox(toolbar, "Optional [O]", "Include quests marked as optional ([O]) in the guide.", "includeOptional")
	f.cbOptional:SetPoint("TOPLEFT", 8, -4)

	f.cbDungeon = makeCheckbox(toolbar, "Dungeon / Elite", "Include Dungeon, Raid, and Elite quests in catch-up scanning.", "includeDungeonElite")
	f.cbDungeon:SetPoint("LEFT", f.cbOptional.label, "RIGHT", 14, 0)

	f.cbAutoNotify = makeCheckbox(toolbar, "Auto-Notify", "Automatically notify you when selecting a Guidelime guide with missing prerequisites.", "autoNotify")
	f.cbAutoNotify:SetPoint("LEFT", f.cbDungeon.label, "RIGHT", 14, 0)

	f.cbMergeGuide = makeCheckbox(toolbar, "Merge w/ Target", "Combine the catch-up steps and the full target guide into one seamless new guide (original guide is untouched).", "mergeWithTarget")
	f.cbMergeGuide:SetPoint("LEFT", f.cbAutoNotify.label, "RIGHT", 14, 0)

	-- View Mode Buttons
	local viewLabel = toolbar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	viewLabel:SetPoint("BOTTOMLEFT", 12, 8)
	viewLabel:SetText(COLOR_LIME .. "View:|r")

	f.viewButtons = {}
	local viewModes = {
		{ id = "ROUTE", label = "Route Order" },
		{ id = "ZONE", label = "By Zone" },
		{ id = "TARGET", label = "By Target Quest" },
	}
	local prevBtn = viewLabel
	for i, vm in ipairs(viewModes) do
		local btn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
		btn:SetSize(vm.id == "TARGET" and 112 or 88, 20)
		btn:SetPoint("LEFT", prevBtn, "RIGHT", i == 1 and 8 or 4, 0)
		btn:SetText(vm.label)
		btn.viewId = vm.id
		btn:SetScript("OnClick", function()
			GuidelimeCatchUpDB.viewMode = vm.id
			UI.Refresh()
		end)
		f.viewButtons[vm.id] = btn
		prevBtn = btn
	end

	-- Summary Bar
	f.summaryText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.summaryText:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 6, -8)
	f.summaryText:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -6, -8)
	f.summaryText:SetJustifyH("LEFT")

	-- Scroll List Container
	local listBox = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
	listBox:SetPoint("TOPLEFT", f.summaryText, "BOTTOMLEFT", -6, -6)
	listBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 54)
	if listBox.SetBackdrop then
		listBox:SetBackdrop(BACKDROP_SUB)
		listBox:SetBackdropColor(0.03, 0.04, 0.04, 0.94)
		listBox:SetBackdropBorderColor(0.32, 0.48, 0.16, 0.75)
	end

	local scrollFrame = CreateFrame("ScrollFrame", "GuidelimeCatchUpScrollFrame", listBox, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 6, -6)
	scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
	f.scrollFrame = scrollFrame

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(1, 1)
	scrollFrame:SetScrollChild(scrollChild)
	f.scrollChild = scrollChild

	f.rowPool = {}
	f.headerPool = {}

	-- Footer Action Bar
	f.refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.refreshBtn:SetSize(80, 26)
	f.refreshBtn:SetPoint("BOTTOMLEFT", 16, 16)
	f.refreshBtn:SetText("Refresh")
	f.refreshBtn:SetScript("OnClick", function()
		addon.RunScan(false)
	end)

	f.generateBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.generateBtn:SetSize(180, 26)
	f.generateBtn:SetPoint("LEFT", f.refreshBtn, "RIGHT", 8, 0)
	f.generateBtn:SetText("Generate Merged Guide")
	f.generateBtn:SetScript("OnClick", function()
		addon.GenerateAndRegisterGuide()
	end)

	f.loadReloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.loadReloadBtn:SetSize(156, 26)
	f.loadReloadBtn:SetPoint("LEFT", f.generateBtn, "RIGHT", 8, 0)
	f.loadReloadBtn:SetText("Load Guide (Reload UI)")
	f.loadReloadBtn:Disable()
	f.loadReloadBtn:SetScript("OnClick", function()
		if addon.lastGeneratedGuide and addon.lastGeneratedGuide.name then
			addon.Generator.ActivateViaReload(addon.lastGeneratedGuide.name)
		end
	end)

	f.copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.copyBtn:SetSize(88, 26)
	f.copyBtn:SetPoint("LEFT", f.loadReloadBtn, "RIGHT", 8, 0)
	f.copyBtn:SetText("Copy Text")
	f.copyBtn:Disable()
	f.copyBtn:SetScript("OnClick", function()
		if addon.lastScanResult and addon.lastScanResult.ordered and #addon.lastScanResult.ordered > 0 then
			local text = addon.Generator.BuildGuideText(addon.lastScanResult)
			if text then
				UI.ShowCopyPopup("Guidelime: CatchUp — Generated Guide", text)
			end
		end
	end)

	f.emptyLabel = listBox:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	f.emptyLabel:SetPoint("CENTER", listBox, "CENTER", 0, 8)
	f.emptyLabel:SetWidth(460)
	f.emptyLabel:Hide()

	UI.frame = f
	return f
end

-- Dropdown menu to select any applicable Guidelime guide
function UI.OpenGuideDropdown(anchor)
	if not UI.guideDropDown then
		UI.guideDropDown = CreateFrame("Frame", "GuidelimeCatchUpGuideDropDown", UIParent, "UIDropDownMenuTemplate")
	end

	local guides = addon.Capture.GetApplicableGuides()
	local groups = {}
	local groupOrder = {}
	for _, g in ipairs(guides) do
		local grp = (g.group and g.group ~= "") and g.group or "Other Guides"
		if not groups[grp] then
			groups[grp] = {}
			table.insert(groupOrder, grp)
		end
		table.insert(groups[grp], g)
	end

	UIDropDownMenu_Initialize(UI.guideDropDown, function(self, level, menuList)
		local info = UIDropDownMenu_CreateInfo()
		if level == 1 then
			info.text = COLOR_LIME .. "(Active Guidelime Guide)|r"
			info.notCheckable = true
			info.func = function()
				addon.selectedGuideName = nil
				addon.RunScan(false)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info, level)

			if #groupOrder == 1 then
				local grp = groupOrder[1]
				info = UIDropDownMenu_CreateInfo()
				info.text = grp
				info.isTitle = true
				info.notCheckable = true
				UIDropDownMenu_AddButton(info, level)
				for _, g in ipairs(groups[grp]) do
					local item = UIDropDownMenu_CreateInfo()
					local prefix = (g.minLevel and g.maxLevel) and (g.minLevel .. "-" .. g.maxLevel .. " ") or (g.minLevel and (g.minLevel .. " ") or "")
					item.text = prefix .. (g.title or g.name)
					item.checked = (addon.GetTargetGuideName() == g.name)
					item.func = function()
						addon.selectedGuideName = g.name
						addon.RunScan(false)
						CloseDropDownMenus()
					end
					UIDropDownMenu_AddButton(item, level)
				end
			else
				for _, grp in ipairs(groupOrder) do
					local sub = UIDropDownMenu_CreateInfo()
					sub.text = grp .. " (" .. #groups[grp] .. ")"
					sub.hasArrow = true
					sub.notCheckable = true
					sub.menuList = groups[grp]
					UIDropDownMenu_AddButton(sub, level)
				end
			end
		elseif level == 2 and menuList then
			for _, g in ipairs(menuList) do
				local item = UIDropDownMenu_CreateInfo()
				local prefix = (g.minLevel and g.maxLevel) and (g.minLevel .. "-" .. g.maxLevel .. " ") or (g.minLevel and (g.minLevel .. " ") or "")
				item.text = prefix .. (g.title or g.name)
				item.checked = (addon.GetTargetGuideName() == g.name)
				item.func = function()
					addon.selectedGuideName = g.name
					addon.RunScan(false)
					CloseDropDownMenus()
				end
				UIDropDownMenu_AddButton(item, level)
			end
		end
	end, "MENU")

	ToggleDropDownMenu(1, nil, UI.guideDropDown, anchor, 0, 0)
end

local function acquireHeader(f, idx)
	local h = f.headerPool[idx]
	if not h then
		h = CreateFrame("Frame", nil, f.scrollChild)
		h:SetHeight(24)
		h.bg = h:CreateTexture(nil, "BACKGROUND")
		h.bg:SetAllPoints()
		h.bg:SetColorTexture(0.11, 0.17, 0.08, 0.90)

		h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		h.text:SetPoint("LEFT", 8, 0)
		h.text:SetPoint("RIGHT", -8, 0)
		h.text:SetJustifyH("LEFT")
		f.headerPool[idx] = h
	end
	h:Show()
	return h
end

local function acquireRow(f, idx)
	local r = f.rowPool[idx]
	if not r then
		r = CreateFrame("Button", nil, f.scrollChild)
		r:SetHeight(34)
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()

		r.hl = r:CreateTexture(nil, "HIGHLIGHT")
		r.hl:SetAllPoints()
		r.hl:SetColorTexture(0.45, 0.78, 0.12, 0.22)

		r.stepNum = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		r.stepNum:SetPoint("LEFT", 6, 6)
		r.stepNum:SetWidth(24)
		r.stepNum:SetJustifyH("RIGHT")

		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", r.stepNum, "RIGHT", 4, 0)

		r.badge = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		r.badge:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
		r.badge:SetWidth(58)
		r.badge:SetJustifyH("LEFT")

		r.questText = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		r.questText:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 4, 2)
		r.questText:SetPoint("RIGHT", r, "RIGHT", -195, 0)
		r.questText:SetJustifyH("LEFT")
		r.questText:SetWordWrap(false)

		r.subText = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		r.subText:SetPoint("TOPLEFT", r.questText, "BOTTOMLEFT", 0, -2)
		r.subText:SetPoint("RIGHT", r, "RIGHT", -12, 0)
		r.subText:SetJustifyH("LEFT")
		r.subText:SetWordWrap(false)

		r.locText = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		r.locText:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -4)
		r.locText:SetWidth(185)
		r.locText:SetJustifyH("RIGHT")
		r.locText:SetWordWrap(false)

		f.rowPool[idx] = r
	end
	r:Show()
	return r
end

local function populateRow(row, node, stepIndex, scanResult, width, zebra)
	row:SetWidth(width)
	row.bg:SetColorTexture(zebra and 0.07 or 0.05, zebra and 0.09 or 0.06, zebra and 0.07 or 0.05, 0.80)

	local st = STATUS_INFO[node.status] or STATUS_INFO.READY
	row.stepNum:SetText(stepIndex and (stepIndex .. ".") or "•")
	row.icon:SetTexture(st.icon)
	row.icon:SetDesaturated(false)
	row.badge:SetText(st.color .. st.label .. "|r")

	local tags = ""
	if node.tagLabel then tags = tags .. " |cFFFF8844[" .. node.tagLabel .. "]|r" end
	if node.isOptional then tags = tags .. " |cFFAAAAAA[Opt]|r" end
	if node.reason == "CARRIED_OVER" or node.reason == "CARRIED_OVER_INCOMPLETE" then
		tags = tags .. " " .. COLOR_QUEST .. "[Carry-Over]|r"
	end

	local lvlStr = (node.level and node.level > 0) and (getLevelColor(node.level) .. "[" .. node.level .. "]|r ") or ""
	row.questText:SetText(lvlStr .. node.name .. tags)

	local subParts = {}
	if node.starter and node.starter.name then
		table.insert(subParts, "Start: " .. node.starter.name)
	end
	if node.sourceGuide then
		table.insert(subParts, COLOR_QUEST .. "Guide: " .. node.sourceGuide .. "|r")
	elseif node.reason == "PREREQ" and node.forTargetQuests and node.forTargetQuests[1] then
		local tm = scanResult.targetQuestMeta and scanResult.targetQuestMeta[node.forTargetQuests[1]]
		if tm and tm.name then
			table.insert(subParts, "Unlocks: " .. tm.name)
		end
	end
	row.subText:SetText(table.concat(subParts, "  •  "))

	local loc = (node.inLogComplete and node.finisher) or node.starter
	if loc and loc.x and loc.y and (loc.x > 0 or loc.y > 0) then
		row.locText:SetText(string.format("|cFFCCCCCC%s|r " .. COLOR_LIME .. "(%.1f, %.1f)|r", node.zoneName or "", loc.x, loc.y))
	else
		row.locText:SetText("|cFFCCCCCC" .. (node.zoneName or "Unknown") .. "|r")
	end

	row:SetScript("OnEnter", function(self)
		showNodeTooltip(self, node, scanResult)
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(_, button)
		if button == "LeftButton" then
			setWaypointForNode(node)
		elseif button == "RightButton" then
			if node.inLog then
				local TrackerUtils = QuestieLoader and QuestieLoader:ImportModule("TrackerUtils")
				if TrackerUtils and TrackerUtils.ShowQuestLog then
					TrackerUtils:ShowQuestLog({ Id = node.questId })
					return
				end
			end
			UI.ShowCopyPopup("Wowhead Link: " .. node.name, getWowheadQuestUrl(node.questId))
		end
	end)
end

local function populateActionRow(row, act, stepIndex, scanResult, width, zebra)
	local node = act.node
	row:SetWidth(width)
	row.bg:SetColorTexture(zebra and 0.07 or 0.05, zebra and 0.09 or 0.06, zebra and 0.07 or 0.05, 0.80)

	local ai = ACTION_INFO[act.action] or ACTION_INFO.ACCEPT
	row.stepNum:SetText(stepIndex .. ".")
	row.icon:SetTexture(ai.icon)
	row.icon:SetDesaturated(false)
	row.badge:SetText(ai.color .. ai.label .. "|r")

	local tags = ""
	if node.tagLabel then tags = tags .. " |cFFFF8844[" .. node.tagLabel .. "]|r" end
	if node.reason == "CARRIED_OVER" or node.reason == "CARRIED_OVER_INCOMPLETE" then
		tags = tags .. " " .. COLOR_QUEST .. "[Carry-Over]|r"
	end

	local lvlStr = (node.level and node.level > 0) and (getLevelColor(node.level) .. "[" .. node.level .. "]|r ") or ""
	row.questText:SetText(lvlStr .. node.name .. tags)

	local subParts = {}
	if act.pos and act.pos.name then
		local prefix = (act.action == "ACCEPT" and "NPC: ") or (act.action == "TURNIN" and "Turn-in: ") or "Area: "
		table.insert(subParts, prefix .. act.pos.name)
	end
	if act.batchedAtHub then
		table.insert(subParts, COLOR_LIME .. "[Hub Batch]|r")
	elseif act.distFromPrev and act.distFromPrev > 0 then
		table.insert(subParts, string.format("~%d yds", math.floor(act.distFromPrev + 0.5)))
	end
	if node.sourceGuide then
		table.insert(subParts, COLOR_QUEST .. "Guide: " .. node.sourceGuide .. "|r")
	end
	row.subText:SetText(table.concat(subParts, "  •  "))

	local loc = act.pos or node.starter
	if loc and loc.x and loc.y and (loc.x > 0 or loc.y > 0) then
		row.locText:SetText(string.format("|cFFCCCCCC%s|r " .. COLOR_LIME .. "(%.1f, %.1f)|r", act.zoneName or node.zoneName or "", loc.x, loc.y))
	else
		row.locText:SetText("|cFFCCCCCC" .. (act.zoneName or node.zoneName or "Unknown") .. "|r")
	end

	row:SetScript("OnEnter", function(self)
		showNodeTooltip(self, node, scanResult)
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(_, button)
		if button == "LeftButton" then
			local label = (act.action == "ACCEPT" and "Accept") or (act.action == "TURNIN" and "Turn In") or "Complete"
			setWaypointForNode(node, act.pos, label)
		elseif button == "RightButton" then
			if node.inLog then
				local TrackerUtils = QuestieLoader and QuestieLoader:ImportModule("TrackerUtils")
				if TrackerUtils and TrackerUtils.ShowQuestLog then
					TrackerUtils:ShowQuestLog({ Id = node.questId })
					return
				end
			end
			UI.ShowCopyPopup("Wowhead Link: " .. node.name, getWowheadQuestUrl(node.questId))
		end
	end)
end

function UI.Refresh()
	if not UI.frame then return end
	local f = UI.frame
	local scan = addon.lastScanResult
	local viewMode = (GuidelimeCatchUpDB and GuidelimeCatchUpDB.viewMode) or "ROUTE"

	f.cbOptional:SetChecked(GuidelimeCatchUpDB.includeOptional == true)
	f.cbDungeon:SetChecked(GuidelimeCatchUpDB.includeDungeonElite == true)
	f.cbAutoNotify:SetChecked(GuidelimeCatchUpDB.autoNotify ~= false)
	f.cbMergeGuide:SetChecked(GuidelimeCatchUpDB.mergeWithTarget ~= false)
	f.generateBtn:SetText(GuidelimeCatchUpDB.mergeWithTarget ~= false and "Generate Merged Guide" or "Generate CatchUp Guide")

	for id, btn in pairs(f.viewButtons) do
		if id == viewMode then
			btn:Disable()
		else
			btn:Enable()
		end
	end

	for _, h in ipairs(f.headerPool) do h:Hide() end
	for _, r in ipairs(f.rowPool) do r:Hide() end
	f.emptyLabel:Hide()

	local targetName = addon.GetTargetGuideName()
	local guideObj = targetName and addon.Capture.GetGuide(targetName)
	if guideObj then
		local prefix = (guideObj.minLevel and guideObj.maxLevel) and (guideObj.minLevel .. "-" .. guideObj.maxLevel .. " ") or ""
		f.guideBtn:SetText(prefix .. (guideObj.title or guideObj.name))
	elseif targetName then
		f.guideBtn:SetText(targetName)
	else
		f.guideBtn:SetText("No Guidelime Guide Selected")
	end

	if not scan then
		f.summaryText:SetText(COLOR_GOLD .. "Scanning...|r")
		f.generateBtn:Disable()
		f.loadReloadBtn:Disable()
		f.copyBtn:Disable()
		return
	end

	if scan.error then
		f.summaryText:SetText("|cFFFF8844" .. scan.error .. "|r")
		f.emptyLabel:SetText(scan.error)
		f.emptyLabel:Show()
		f.generateBtn:Disable()
		f.loadReloadBtn:Disable()
		f.copyBtn:Disable()
		return
	end

	local stats = scan.stats
	local filterNote = ""
	if stats.filteredOptional > 0 or stats.filteredDungeonElite > 0 then
		local hidden = {}
		if stats.filteredOptional > 0 then table.insert(hidden, stats.filteredOptional .. " optional") end
		if stats.filteredDungeonElite > 0 then table.insert(hidden, stats.filteredDungeonElite .. " dungeon/elite") end
		filterNote = "  |cFF888888(Hidden: " .. table.concat(hidden, ", ") .. ")|r"
	end

	if stats.total == 0 then
		f.summaryText:SetText(COLOR_LIME .. "All caught up!|r 0 missing prerequisites or carried-over quests." .. filterNote)
		f.emptyLabel:SetText(COLOR_LIME .. "All caught up!|r\n\nYou have no missing prerequisite chains or carried-over quests for this guide.")
		f.emptyLabel:Show()
		f.generateBtn:Disable()
		f.loadReloadBtn:Disable()
		f.copyBtn:Disable()
		return
	end

	local stepInfo = ""
	if scan.routeStats and scan.routeStats.totalActions and scan.routeStats.totalActions > 0 then
		stepInfo = string.format("  •  " .. COLOR_LIME .. "%d Batched Steps|r", scan.routeStats.totalActions)
	end

	f.summaryText:SetText(string.format(
		COLOR_GOLD .. "%d quest%s needed|r (%d prereq%s, %d carried-over)  •  " .. COLOR_LIME .. "%d Ready|r  •  " .. COLOR_QUEST .. "%d In Log|r  •  %d Zone%s%s%s",
		stats.total, stats.total == 1 and "" or "s",
		stats.prereqs, stats.prereqs == 1 and "" or "s",
		stats.carriedOver,
		stats.ready, stats.inLog,
		stats.zoneCount, stats.zoneCount == 1 and "" or "s",
		stepInfo,
		filterNote
	))

	f.generateBtn:Enable()
	f.copyBtn:Enable()
	if addon.lastGeneratedGuide and addon.lastGeneratedGuide.targetGuideName == scan.guide.name then
		f.loadReloadBtn:Enable()
	else
		f.loadReloadBtn:Disable()
	end

	local contentWidth = math.max(460, (f.scrollFrame:GetWidth() or (f:GetWidth() - 62)) - 4)
	local y = 0
	local headerIdx = 0
	local rowIdx = 0

	if viewMode == "ROUTE" then
		local actionSteps = scan.optimizedActions
		if actionSteps and #actionSteps > 0 then
			local lastZone = nil
			for i, act in ipairs(actionSteps) do
				local z = act.zoneName or (act.node and act.node.zoneName) or "Unknown Zone"
				if z ~= lastZone then
					headerIdx = headerIdx + 1
					local h = acquireHeader(f, headerIdx)
					h:SetWidth(contentWidth)
					h:SetPoint("TOPLEFT", 0, -y)
					h.text:SetText(COLOR_LIME .. z .. "|r  " .. COLOR_MUTED .. "(Hub-Batched Spatial Route)|r")
					y = y + 26
					lastZone = z
				end
				rowIdx = rowIdx + 1
				local r = acquireRow(f, rowIdx)
				r:SetPoint("TOPLEFT", 0, -y)
				populateActionRow(r, act, i, scan, contentWidth, (rowIdx % 2 == 0))
				y = y + 35
			end
		else
			local lastZone = nil
			for i, node in ipairs(scan.ordered) do
				if node.zoneName ~= lastZone then
					headerIdx = headerIdx + 1
					local h = acquireHeader(f, headerIdx)
					h:SetWidth(contentWidth)
					h:SetPoint("TOPLEFT", 0, -y)
					h.text:SetText(COLOR_LIME .. (node.zoneName or "Unknown Zone") .. "|r")
					y = y + 26
					lastZone = node.zoneName
				end
				rowIdx = rowIdx + 1
				local r = acquireRow(f, rowIdx)
				r:SetPoint("TOPLEFT", 0, -y)
				populateRow(r, node, i, scan, contentWidth, (rowIdx % 2 == 0))
				y = y + 35
			end
		end
	elseif viewMode == "ZONE" then
		for _, zoneName in ipairs(scan.zoneOrder) do
			local list = scan.byZone[zoneName]
			if list and #list > 0 then
				headerIdx = headerIdx + 1
				local h = acquireHeader(f, headerIdx)
				h:SetWidth(contentWidth)
				h:SetPoint("TOPLEFT", 0, -y)
				h.text:SetText(string.format(COLOR_LIME .. "%s|r  |cFFAAAAAA(%d quest%s)|r", zoneName, #list, #list == 1 and "" or "s"))
				y = y + 26

				for i, node in ipairs(list) do
					rowIdx = rowIdx + 1
					local r = acquireRow(f, rowIdx)
					r:SetPoint("TOPLEFT", 0, -y)
					populateRow(r, node, i, scan, contentWidth, (rowIdx % 2 == 0))
					y = y + 35
				end
				y = y + 4
			end
		end
	elseif viewMode == "TARGET" then
		for _, tId in ipairs(scan.targetOrder) do
			local group = scan.byTarget[tId]
			if group and #group.nodes > 0 then
				headerIdx = headerIdx + 1
				local h = acquireHeader(f, headerIdx)
				h:SetWidth(contentWidth)
				h:SetPoint("TOPLEFT", 0, -y)
				local lvlStr = (group.target.level and group.target.level > 0) and (getLevelColor(group.target.level) .. "[" .. group.target.level .. "]|r ") or ""
				h.text:SetText(string.format(COLOR_QUEST .. "Target:|r %s|cFFFFFFFF%s|r  |cFFAAAAAA(%d step%s)|r",
					lvlStr, group.target.name, #group.nodes, #group.nodes == 1 and "" or "s"))
				y = y + 26

				for i, node in ipairs(group.nodes) do
					rowIdx = rowIdx + 1
					local r = acquireRow(f, rowIdx)
					r:SetPoint("TOPLEFT", 0, -y)
					populateRow(r, node, i, scan, contentWidth, (rowIdx % 2 == 0))
					y = y + 35
				end
				y = y + 4
			end
		end
	end

	f.scrollChild:SetSize(contentWidth, math.max(1, y + 6))
end

function UI.Show()
	local f = UI.CreateMainFrame()
	f:Show()
	addon.RunScan(false)
end

function UI.Hide()
	if UI.frame then UI.frame:Hide() end
end

function UI.Toggle()
	local f = UI.CreateMainFrame()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		addon.RunScan(false)
	end
end
