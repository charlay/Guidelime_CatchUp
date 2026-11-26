local addonName, addon = ...

addon.Parser = addon.Parser or {}
local Parser = addon.Parser

local RACES = {
	HUMAN = "Human",
	NIGHTELF = "NightElf",
	DWARF = "Dwarf",
	GNOME = "Gnome",
	ORC = "Orc",
	TROLL = "Troll",
	TAUREN = "Tauren",
	UNDEAD = "Undead",
	SCOURGE = "Undead",
	DRAENEI = "Draenei",
	BLOODELF = "BloodElf",
	WORGEN = "Worgen",
	GOBLIN = "Goblin",
	PANDAREN = "Pandaren",
	SKYBORNE = "Skyborne",
}

local CLASSES = {
	WARRIOR = "Warrior",
	ROGUE = "Rogue",
	MAGE = "Mage",
	WARLOCK = "Warlock",
	HUNTER = "Hunter",
	PRIEST = "Priest",
	DRUID = "Druid",
	PALADIN = "Paladin",
	SHAMAN = "Shaman",
	DEATHKNIGHT = "DeathKnight",
	MONK = "Monk",
}

local FACTIONS = {
	ALLIANCE = "Alliance",
	HORDE = "Horde",
}

local FLAVORS = {
	CLASSIC = "CLASSIC",
	CLASSICERA = "CLASSIC",
	VANILLA = "CLASSIC",
	TBC = "TBC",
	WOTLK = "WOTLK",
	WRATH = "WOTLK",
	CATA = "CATA",
	CATACLYSM = "CATA",
	MOP = "MOP",
	MISTS = "MOP",
	FOREVER = "FOREVER",
}

local function normalizeToken(tok)
	return (tok or ""):upper():gsub("[%s%-_]", "")
end

function Parser.GetPlayerInfo()
	local _, classFile = UnitClass("player")
	local _, raceFile = UnitRace("player")
	local faction = UnitFactionGroup("player")
	local build = select(4, GetBuildInfo()) or 16001
	local flavor = "CLASSIC"
	if build < 16000 then
		flavor = "CLASSIC"
	elseif build < 20000 then
		flavor = "FOREVER"
	elseif build < 30000 then
		flavor = "TBC"
	elseif build < 40000 then
		flavor = "WOTLK"
	elseif build < 50000 then
		flavor = "CATA"
	else
		flavor = "MOP"
	end
	local hardcore = false
	if C_GameRules and C_GameRules.IsHardcoreActive then
		hardcore = C_GameRules.IsHardcoreActive() and true or false
	end
	return {
		class = CLASSES[normalizeToken(classFile)] or classFile,
		race = RACES[normalizeToken(raceFile)] or raceFile,
		faction = faction,
		level = UnitLevel("player") or 1,
		flavor = flavor,
		hardcore = hardcore,
	}
end

local function listContains(list, value)
	if not list then return false end
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

-- Check whether a guide or step applicability table matches the current player
function Parser.CheckApplies(rules, player)
	if not rules then return true end
	player = player or Parser.GetPlayerInfo()

	if rules.faction and player.faction and rules.faction ~= player.faction then
		return false
	end
	if rules.races and #rules.races > 0 and not listContains(rules.races, player.race) then
		return false
	end
	if rules.excludedRaces and #rules.excludedRaces > 0 and listContains(rules.excludedRaces, player.race) then
		return false
	end
	if rules.classes and #rules.classes > 0 and not listContains(rules.classes, player.class) then
		return false
	end
	if rules.excludedClasses and #rules.excludedClasses > 0 and listContains(rules.excludedClasses, player.class) then
		return false
	end
	if rules.flavors and #rules.flavors > 0 and not listContains(rules.flavors, player.flavor) then
		return false
	end
	if rules.excludedFlavors and #rules.excludedFlavors > 0 and listContains(rules.excludedFlavors, player.flavor) then
		return false
	end
	if rules.hardcore ~= nil then
		if rules.hardcore and not player.hardcore then return false end
		if not rules.hardcore and player.hardcore then return false end
	end
	return true
end

function Parser.GuideApplies(guide)
	return Parser.CheckApplies(guide)
end

local function parseAppliesTag(tag, target)
	if not tag or tag == "" then return end
	local cleaned = tag:upper():gsub("%s+", "")
	for item in cleaned:gmatch("[^,]+") do
		local excluded = false
		if item:sub(1, 1) == "!" then
			excluded = true
			item = item:sub(2)
		end
		-- Strip trailing numeric/comparison constraints for simple token check
		local tok = item:match("^([A-Z]+)")
		if tok then
			if CLASSES[tok] then
				local key = excluded and "excludedClasses" or "classes"
				target[key] = target[key] or {}
				table.insert(target[key], CLASSES[tok])
			elseif RACES[tok] then
				local key = excluded and "excludedRaces" or "races"
				target[key] = target[key] or {}
				table.insert(target[key], RACES[tok])
			elseif FACTIONS[tok] then
				if not excluded then
					target.faction = FACTIONS[tok]
				end
			elseif FLAVORS[tok] then
				local key = excluded and "excludedFlavors" or "flavors"
				target[key] = target[key] or {}
				table.insert(target[key], FLAVORS[tok])
			elseif tok == "HARDCORE" then
				target.hardcore = not excluded
			elseif tok == "SOFTCORE" then
				target.hardcore = excluded
			end
		end
	end
end

-- Parse just the header metadata ([N], [GA], [NX]) from raw guide text
function Parser.ParseHeader(rawText, group)
	if type(rawText) ~= "string" then return nil end
	local meta = {
		group = group,
		text = rawText,
		next = {},
	}
	if meta.group and meta.group:sub(1, 10) == "Guidelime_" then
		meta.group = meta.group:sub(11)
	end
	for line in rawText:gmatch("[^\r\n]+") do
		local stripped = line:gsub("%-%-.*$", "")
		for code in stripped:gmatch("%[(.-)%]") do
			local c2 = code:sub(1, 2)
			local c1 = code:sub(1, 1)
			if c2 == "GA" then
				parseAppliesTag(code:sub(3), meta)
			elseif c2 == "NX" then
				local tag = code:sub(3):gsub("^%s*", "")
				table.insert(meta.next, tag)
			elseif c1 == "N" and c2 ~= "NX" then
				local tag = code:sub(2):gsub("^%s*", "")
				local minL, maxL, title = tag:match("^%s*(%d*%.?%d*)%s*%-?%s*(%d*%.?%d*)%s*(.*)$")
				if title then
					meta.minLevel = tonumber(minL)
					meta.maxLevel = tonumber(maxL)
					meta.title = title
				end
			end
		end
	end
	meta.name = meta.title or ""
	if meta.minLevel ~= nil or meta.maxLevel ~= nil then
		meta.name = " " .. meta.name
		if meta.maxLevel ~= nil then meta.name = meta.maxLevel .. meta.name end
		meta.name = "-" .. meta.name
		if meta.minLevel ~= nil then meta.name = meta.minLevel .. meta.name end
	end
	if meta.group and meta.group ~= "" then
		meta.name = meta.group .. " " .. meta.name
	end
	return meta
end

-- Parse all applicable quest references from a captured guide entry.
-- Returns:
--   parsed = {
--     guide = guideEntry,
--     quests = { [questId] = { questId, firstLine, firstAcceptLine, firstCompleteLine, firstTurnInLine,
--                              hasAccept, hasComplete, hasTurnIn, hasSkip, allOptional, steps = {...} } },
--     questOrder = { questId1, questId2, ... }
--   }
function Parser.ParseGuideQuests(guideEntry)
	if not guideEntry or type(guideEntry.text) ~= "string" then return nil end

	local player = Parser.GetPlayerInfo()
	local parsed = {
		guide = guideEntry,
		quests = {},
		questOrder = {},
	}

	local lineNum = 0
	for rawLine in (guideEntry.text .. "\n"):gmatch("(.-)\r?\n") do
		lineNum = lineNum + 1
		local line = rawLine:gsub("%-%-.*$", "")
		if line ~= "" then
			local stepRules = {}
			local isOptional = false
			local stepQuestOps = {}

			-- Check if line text itself explicitly labels it as an optional quest (common in TUGs guides)
			local lowerLine = line:lower()
			local textSaysOptional = lowerLine:find("optional", 1, true) ~= nil

			for code in line:gmatch("%[(.-)%]") do
				local c2 = code:sub(1, 2):upper()
				local c1 = code:sub(1, 1):upper()

				if c2 == "OC" or (c1 == "O" and #code == 1) then
					isOptional = true
				elseif c1 == "A" and c2 ~= "AU" then
					-- [A Race,Class,...]
					parseAppliesTag(code:sub(2), stepRules)
				elseif c2 == "QA" or c2 == "QP" or c2 == "QC" or c2 == "QT" or c2 == "QS" or c2 == "QW" or (c1 == "Q" and code:sub(2, 2):match("[%s%d]")) then
					local opType
					local rest
					if c2 == "QA" or c2 == "QP" then
						opType = "ACCEPT"
						rest = code:sub(3)
					elseif c2 == "QC" then
						opType = "COMPLETE"
						rest = code:sub(3)
					elseif c2 == "QW" then
						opType = "COMPLETE"
						isOptional = true
						rest = code:sub(3)
					elseif c2 == "QT" then
						opType = "TURNIN"
						rest = code:sub(3)
					elseif c2 == "QS" then
						opType = "SKIP"
						rest = code:sub(3)
					else
						opType = "COMPLETE"
						rest = code:sub(2)
					end

					local qidStr, objStr = rest:match("^%s*(%d+),?(%d*)")
					local qid = tonumber(qidStr)
					if qid then
						table.insert(stepQuestOps, {
							questId = qid,
							op = opType,
							objective = tonumber(objStr),
							line = lineNum,
						})
					end
				end
			end

			if #stepQuestOps > 0 and Parser.CheckApplies(stepRules, player) then
				local stepOptional = isOptional or textSaysOptional
				for _, opInfo in ipairs(stepQuestOps) do
					local qid = opInfo.questId
					local q = parsed.quests[qid]
					if not q then
						q = {
							questId = qid,
							firstLine = lineNum,
							firstAcceptLine = nil,
							firstCompleteLine = nil,
							firstTurnInLine = nil,
							hasAccept = false,
							hasComplete = false,
							hasTurnIn = false,
							hasSkip = false,
							allOptional = true,
							steps = {},
						}
						parsed.quests[qid] = q
						table.insert(parsed.questOrder, qid)
					end

					if not stepOptional then
						q.allOptional = false
					end

					if opInfo.op == "ACCEPT" then
						q.hasAccept = true
						if not q.firstAcceptLine then q.firstAcceptLine = lineNum end
					elseif opInfo.op == "COMPLETE" then
						q.hasComplete = true
						if not q.firstCompleteLine then q.firstCompleteLine = lineNum end
					elseif opInfo.op == "TURNIN" then
						q.hasTurnIn = true
						if not q.firstTurnInLine then q.firstTurnInLine = lineNum end
					elseif opInfo.op == "SKIP" then
						q.hasSkip = true
					end

					table.insert(q.steps, {
						op = opInfo.op,
						line = lineNum,
						objective = opInfo.objective,
						optional = stepOptional,
					})
				end
			end
		end
	end

	return parsed
end
