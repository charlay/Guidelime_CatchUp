local addonName, addon = ...

addon.Generator = addon.Generator or {}
local Generator = addon.Generator

local function sanitizeBracketText(str)
	if not str then return "" end
	return str:gsub("%[", "("):gsub("%]", ")"):gsub("[\r\n]", " ")
end

-- Extract the target guide suffix for [NX...] relative to targetGuide.group
local function getNextTagSuffix(guideEntry)
	if not guideEntry then return nil end
	local name = guideEntry.name or ""
	local group = guideEntry.group or ""
	if group ~= "" and name:sub(1, #group + 1) == (group .. " ") then
		return name:sub(#group + 2)
	end
	if guideEntry.minLevel or guideEntry.maxLevel then
		local prefix = (guideEntry.minLevel or "") .. "-" .. (guideEntry.maxLevel or "") .. " "
		return prefix .. (guideEntry.title or "")
	end
	return guideEntry.title or name
end

-- Extract header metadata ([GA], [NX]) and strip header-only tags ([GA], [N], [NX], [D], [DL])
-- from the target guide so its body can be merged cleanly into a brand-new guide without
-- overwriting the original guide's name/registration.
local function extractTargetGuideParts(rawText)
	local gaTags = {}
	local nxTags = {}
	local bodyLines = {}

	if type(rawText) ~= "string" then
		return gaTags, nxTags, bodyLines
	end

	for rawLine in (rawText .. "\n"):gmatch("(.-)\r?\n") do
		local cleaned = rawLine:gsub("%[(.-)%]", function(code)
			local c2 = code:sub(1, 2)
			local c1 = code:sub(1, 1)
			if c2 == "GA" then
				table.insert(gaTags, "[" .. code .. "]")
				return ""
			elseif c2 == "NX" then
				table.insert(nxTags, "[" .. code .. "]")
				return ""
			elseif c2 == "DL" then
				return ""
			elseif c1 == "N" then
				return ""
			elseif c1 == "D" then
				return ""
			end
			return "[" .. code .. "]"
		end)

		if cleaned:match("%S") then
			table.insert(bodyLines, cleaned)
		end
	end

	return gaTags, nxTags, bodyLines
end

-- Build a playable Guidelime guide string from a ScanGuide result.
-- options: { mergeWithTarget = bool (default true) }
-- Returns guideText, groupName, guideTitle
function Generator.BuildGuideText(scanResult, options)
	if not scanResult or not scanResult.guide or not scanResult.ordered or #scanResult.ordered == 0 then
		return nil
	end

	options = options or {}
	local mergeWithTarget = options.mergeWithTarget
	if mergeWithTarget == nil then
		mergeWithTarget = (GuidelimeCatchUpDB == nil or GuidelimeCatchUpDB.mergeWithTarget ~= false)
	end

	local guide = scanResult.guide
	local faction = UnitFactionGroup("player") or guide.faction or "Alliance"
	local group = (guide.group and guide.group ~= "") and guide.group or "CatchUp"
	local targetSuffix = getNextTagSuffix(guide)
	local cleanTarget = sanitizeBracketText(targetSuffix or guide.title or guide.name)

	local gaTags, nxTags, bodyLines = extractTargetGuideParts(guide.text)

	-- Use 0-0 level range so it always sorts cleanly at the top of the guide group
	-- and has a distinct name from the original guide (never overwrites it).
	local guideTitle = mergeWithTarget and ("CatchUp + " .. cleanTarget) or ("CatchUp: " .. cleanTarget)
	local lines = {}

	if #gaTags > 0 then
		for _, ga in ipairs(gaTags) do
			table.insert(lines, ga)
		end
	else
		table.insert(lines, "[GA " .. faction .. "]")
	end

	table.insert(lines, "[N0-0 " .. guideTitle .. "]")

	if mergeWithTarget then
		for _, nx in ipairs(nxTags) do
			table.insert(lines, nx)
		end
		table.insert(lines, "[D " .. addon.CATCHUP_MARKER .. " — Merged guide: " .. #scanResult.ordered .. " catch-up quests + " .. cleanTarget .. ".]")
	else
		if targetSuffix and targetSuffix ~= "" and not targetSuffix:find("[%[%]]") then
			table.insert(lines, "[NX" .. targetSuffix .. "]")
		end
		table.insert(lines, "[D " .. addon.CATCHUP_MARKER .. " — Auto-generated catch-up route (" .. #scanResult.ordered .. " quests) for " .. cleanTarget .. ".]")
	end

	local actionSteps = scanResult.optimizedActions
	local lastZone = nil
	local notedQuest = {}

	if actionSteps and #actionSteps > 0 then
		for _, act in ipairs(actionSteps) do
			local node = act.node
			local zoneTag = sanitizeBracketText(act.zoneName or node.zoneName or "")
			local zonePrefix = ""
			if zoneTag ~= "" and zoneTag ~= lastZone then
				zonePrefix = "*(" .. zoneTag .. ")* "
				lastZone = zoneTag
			end

			local unlockNote = ""
			if not notedQuest[node.questId] then
				notedQuest[node.questId] = true
				if node.reason == "CARRIED_OVER" or node.reason == "CARRIED_OVER_INCOMPLETE" then
					unlockNote = " *(carried over)*"
				elseif node.forTargetQuests and #node.forTargetQuests > 0 then
					local tMeta = scanResult.targetQuestMeta and scanResult.targetQuestMeta[node.forTargetQuests[1]]
					if tMeta and tMeta.name then
						unlockNote = " *(for " .. sanitizeBracketText(tMeta.name) .. ")*"
					end
				end
			end

			if act.action == "ACCEPT" then
				table.insert(lines, zonePrefix .. "Accept: [QA" .. node.questId .. "]" .. unlockNote)
			elseif act.action == "COMPLETE" then
				table.insert(lines, zonePrefix .. "Do: [QC" .. node.questId .. "]" .. unlockNote)
			elseif act.action == "TURNIN" then
				table.insert(lines, zonePrefix .. "TurnIn: [QT" .. node.questId .. "]" .. unlockNote)
			end
		end
	else
		for _, node in ipairs(scanResult.ordered) do
			local zoneTag = sanitizeBracketText(node.zoneName or "")
			local zonePrefix = ""
			if zoneTag ~= "" and zoneTag ~= lastZone then
				zonePrefix = "*(" .. zoneTag .. ")* "
				lastZone = zoneTag
			end
			if node.needsAccept then
				table.insert(lines, zonePrefix .. "Accept: [QA" .. node.questId .. "]")
				zonePrefix = ""
			end
			if node.needsComplete and node.hasObjectives then
				table.insert(lines, zonePrefix .. "Do: [QC" .. node.questId .. "]")
				zonePrefix = ""
			end
			if node.needsTurnIn then
				table.insert(lines, zonePrefix .. "TurnIn: [QT" .. node.questId .. "]")
			end
		end
	end

	-- Append the original guide's body seamlessly after the catch-up steps
	if mergeWithTarget and #bodyLines > 0 then
		table.insert(lines, "*=== CatchUp Complete — Continuing with " .. cleanTarget .. " ===*[OC]")
		for _, bodyLine in ipairs(bodyLines) do
			table.insert(lines, bodyLine)
		end
	end

	local guideText = table.concat(lines, "\n") .. "\n"
	return guideText, group, guideTitle
end

-- Register the generated catch-up guide with Guidelime (and persist it for reload-to-load)
function Generator.RegisterCatchUpGuide(scanResult, options)
	local mergeWithTarget = options and options.mergeWithTarget
	if mergeWithTarget == nil then
		mergeWithTarget = (GuidelimeCatchUpDB == nil or GuidelimeCatchUpDB.mergeWithTarget ~= false)
	end

	local guideText, group = Generator.BuildGuideText(scanResult, { mergeWithTarget = mergeWithTarget })
	if not guideText then
		return nil, "No missing catch-up quests to generate a guide for."
	end

	if not Guidelime or type(Guidelime.registerGuide) ~= "function" then
		return nil, "Guidelime.registerGuide is not available."
	end

	local ok, registered = pcall(Guidelime.registerGuide, guideText, group)
	if not ok or not registered then
		return nil, "Guidelime failed to parse generated guide: " .. tostring(registered)
	end

	GuidelimeCatchUpCharDB = GuidelimeCatchUpCharDB or {}
	local savedEntry = {
		name = registered.name,
		group = registered.group or group,
		text = guideText,
		targetGuideName = scanResult.guide.name,
		merged = mergeWithTarget,
		savedAt = time and time() or 0,
	}
	GuidelimeCatchUpCharDB.savedCatchUpGuide = savedEntry
	GuidelimeCatchUpCharDB.savedCatchUpGuides = GuidelimeCatchUpCharDB.savedCatchUpGuides or {}
	GuidelimeCatchUpCharDB.savedCatchUpGuides[registered.name] = savedEntry

	-- Keep savedCatchUpGuides bounded (up to 6 most recent)
	local keys = {}
	for k, v in pairs(GuidelimeCatchUpCharDB.savedCatchUpGuides) do
		table.insert(keys, { name = k, savedAt = v.savedAt or 0 })
	end
	if #keys > 6 then
		table.sort(keys, function(a, b) return a.savedAt > b.savedAt end)
		for i = 7, #keys do
			if keys[i].name ~= (GuidelimeDataChar and GuidelimeDataChar.currentGuide) then
				GuidelimeCatchUpCharDB.savedCatchUpGuides[keys[i].name] = nil
			end
		end
	end

	-- If Guidelime debug mode exposed Guidelime.addon.G.loadGuide, load immediately without reload
	local loadedDirectly = false
	if Guidelime.addon and Guidelime.addon.G and type(Guidelime.addon.G.loadGuide) == "function" then
		local okLoad = pcall(Guidelime.addon.G.loadGuide, registered.name)
		loadedDirectly = okLoad
	end

	return {
		name = registered.name,
		group = registered.group or group,
		title = registered.title,
		text = guideText,
		merged = mergeWithTarget,
		loadedDirectly = loadedDirectly,
		targetGuideName = scanResult.guide.name,
	}
end

-- Switch GuidelimeDataChar.currentGuide to a registered guide and reload UI
function Generator.ActivateViaReload(guideName)
	if not guideName or guideName == "" then return false end
	if not GuidelimeDataChar then return false end
	GuidelimeDataChar.currentGuide = guideName
	GuidelimeDataChar.mainFrameShowing = true
	if ReloadUI then
		ReloadUI()
		return true
	end
	return false
end
