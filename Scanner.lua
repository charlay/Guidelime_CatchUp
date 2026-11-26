local addonName, addon = ...

addon.Scanner = addon.Scanner or {}
local Scanner = addon.Scanner

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)

local QuestieDB
local ZoneDB
local QuestiePlayer
local QuestieCorrections
local QuestieQuestBlacklist

local function bindQuestieModules()
	if not QuestieLoader then return false end
	QuestieDB = QuestieDB or QuestieLoader:ImportModule("QuestieDB")
	ZoneDB = ZoneDB or QuestieLoader:ImportModule("ZoneDB")
	QuestiePlayer = QuestiePlayer or QuestieLoader:ImportModule("QuestiePlayer")
	QuestieCorrections = QuestieCorrections or QuestieLoader:ImportModule("QuestieCorrections")
	QuestieQuestBlacklist = QuestieQuestBlacklist or QuestieLoader:ImportModule("QuestieQuestBlacklist")
	return QuestieDB ~= nil and ZoneDB ~= nil
end

function Scanner.IsQuestieReady()
	if not bindQuestieModules() then return false end
	if type(QuestieDB.QueryQuest) ~= "function" then return false end
	if QuestieDB.QuestPointers == nil then return false end
	if Questie and Questie.API and Questie.API.isReady == false then return false end
	return true
end

-- Snapshot completed quests from both WoW API and Questie's saved table
local function getCompletedQuests()
	local completed = {}
	if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		local ids = C_QuestLog.GetAllCompletedQuestIDs()
		if ids then
			for _, id in ipairs(ids) do
				completed[id] = true
			end
		end
	elseif GetQuestsCompleted then
		local t = GetQuestsCompleted()
		if t then
			for id, v in pairs(t) do
				if v then completed[id] = true end
			end
		end
	end
	if Questie and Questie.db and Questie.db.char and Questie.db.char.complete then
		for id, v in pairs(Questie.db.char.complete) do
			if v then completed[id] = true end
		end
	end
	return completed
end

local function isQuestCompleted(questId, completed)
	if completed[questId] then return true end
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		if C_QuestLog.IsQuestFlaggedCompleted(questId) then
			completed[questId] = true
			return true
		end
	end
	return false
end

-- Snapshot active quests in the player's quest log
local function getActiveQuests()
	local active = {}
	if C_QuestLog and C_QuestLog.GetInfo then
		local numEntries = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
		for i = 1, numEntries do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID and info.questID > 0 then
				active[info.questID] = {
					index = i,
					title = info.title,
					isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false,
					isFailed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(info.questID) or false,
				}
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		local numEntries = GetNumQuestLogEntries()
		for i = 1, numEntries do
			local title, _, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
			if title and not isHeader and qid and qid > 0 then
				active[qid] = {
					index = i,
					title = title,
					isComplete = (isComplete == 1),
					isFailed = (isComplete == -1),
				}
			end
		end
	end
	return active
end

local function getZoneNameFromAreaId(areaId)
	if not areaId or areaId <= 0 then return nil, nil end
	if ZoneDB.IsDungeonZone and ZoneDB.IsDungeonZone(areaId) then
		local dName = ZoneDB:GetLocalizedDungeonName(areaId)
		local loc = ZoneDB:GetDungeonLocation(areaId)
		local uiMapId = loc and loc[1] and ZoneDB:GetUiMapIdByAreaId(loc[1]) or nil
		return dName or (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaId)) or ("Zone " .. areaId), uiMapId
	end
	local parentId = ZoneDB:GetParentZoneId(areaId) or areaId
	local uiMapId = ZoneDB:GetUiMapIdByAreaId(parentId)
	local name
	if uiMapId and C_Map and C_Map.GetMapInfo then
		local mapInfo = C_Map.GetMapInfo(uiMapId)
		if mapInfo and mapInfo.name then name = mapInfo.name end
	end
	if not name and C_Map and C_Map.GetAreaInfo then
		name = C_Map.GetAreaInfo(parentId) or C_Map.GetAreaInfo(areaId)
	end
	return name or ("Zone " .. tostring(parentId)), uiMapId
end

local function attachWorldCoords(loc)
	if not loc then return nil end
	if HBD and loc.uiMapId and loc.x and loc.y and (loc.x > 0 or loc.y > 0) then
		local wx, wy, instance = HBD:GetWorldCoordinatesFromZone(loc.x / 100, loc.y / 100, loc.uiMapId)
		if wx and wy and instance then
			loc.wx = wx
			loc.wy = wy
			loc.instance = instance
		end
	end
	return loc
end

local function worldDist(a, b)
	if not a or not b then return nil end
	if a.wx and a.wy and a.instance and b.wx and b.wy and b.instance then
		if a.instance ~= b.instance then return nil end
		local dx = b.wx - a.wx
		local dy = b.wy - a.wy
		return (dx * dx + dy * dy) ^ 0.5
	end
	return nil
end

-- Pick the best coordinate from a Questie spawns table (preferring refLoc if given)
local function pickBestSpawn(spawns, refLoc)
	if not spawns then return nil, nil, nil end
	local bestArea, bestX, bestY, bestDist
	for zId, coords in pairs(spawns) do
		if coords then
			local _, uiMapId = getZoneNameFromAreaId(zId)
			for _, pair in ipairs(coords) do
				local x, y = pair[1], pair[2]
				if x and y and (x > 0 or y > 0) then
					if refLoc and refLoc.wx and uiMapId and HBD then
						local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, uiMapId)
						if wx and wy and inst == refLoc.instance then
							local dx, dy = wx - refLoc.wx, wy - refLoc.wy
							local d = (dx * dx + dy * dy) ^ 0.5
							if not bestDist or d < bestDist then
								bestDist = d
								bestArea, bestX, bestY = zId, x, y
							end
						elseif not bestArea then
							bestArea, bestX, bestY = zId, x, y
						end
					else
						return zId, x, y
					end
				end
			end
		end
	end
	return bestArea, bestX, bestY
end

-- Resolve an NPC, GameObject, or Item starter/finisher to { name, kind, id, areaId, uiMapId, zoneName, x, y, wx, wy, instance }
local function resolveEntityLocation(entityGroup, isStarter, refLoc)
	if not entityGroup then return nil end

	-- 1. NPCs
	if entityGroup.NPC and #entityGroup.NPC > 0 then
		for _, npcId in ipairs(entityGroup.NPC) do
			local npc = QuestieDB:GetNPC(npcId)
			if npc then
				local areaId, x, y = pickBestSpawn(npc.spawns, refLoc)
				if (not areaId) and npc.waypoints then
					for zId, paths in pairs(npc.waypoints) do
						if paths and paths[1] and paths[1][1] then
							areaId = zId
							x, y = paths[1][1][1], paths[1][1][2]
							break
						end
					end
				end
				local zoneName, uiMapId = getZoneNameFromAreaId(areaId)
				return attachWorldCoords({
					name = npc.name or ("NPC #" .. npcId),
					kind = "NPC",
					id = npcId,
					areaId = areaId,
					uiMapId = uiMapId,
					zoneName = zoneName,
					x = x,
					y = y,
				})
			end
		end
	end

	-- 2. GameObjects
	if entityGroup.GameObject and #entityGroup.GameObject > 0 then
		for _, objId in ipairs(entityGroup.GameObject) do
			local obj = QuestieDB:GetObject(objId)
			if obj then
				local areaId, x, y = pickBestSpawn(obj.spawns, refLoc)
				local zoneName, uiMapId = getZoneNameFromAreaId(areaId)
				return attachWorldCoords({
					name = obj.name or ("Object #" .. objId),
					kind = "Object",
					id = objId,
					areaId = areaId,
					uiMapId = uiMapId,
					zoneName = zoneName,
					x = x,
					y = y,
				})
			end
		end
	end

	-- 3. Items (starters only)
	if isStarter and entityGroup.Item and #entityGroup.Item > 0 then
		for _, itemId in ipairs(entityGroup.Item) do
			local item = QuestieDB:GetItem(itemId)
			local itemName = (item and item.name) or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemId)) or ("Item #" .. itemId)
			local areaId, x, y
			if item and item.npcDrops and item.npcDrops[1] then
				local dropNpc = QuestieDB:GetNPC(item.npcDrops[1])
				if dropNpc then
					areaId, x, y = pickBestSpawn(dropNpc.spawns, refLoc)
				end
			elseif item and item.objectDrops and item.objectDrops[1] then
				local dropObj = QuestieDB:GetObject(item.objectDrops[1])
				if dropObj then
					areaId, x, y = pickBestSpawn(dropObj.spawns, refLoc)
				end
			end
			local zoneName, uiMapId = getZoneNameFromAreaId(areaId)
			return attachWorldCoords({
				name = itemName .. " (Drop/Item)",
				kind = "Item",
				id = itemId,
				areaId = areaId,
				uiMapId = uiMapId,
				zoneName = zoneName,
				x = x,
				y = y,
			})
		end
	end

	return nil
end

-- Resolve an approximate objective center location from QuestieDB ObjectiveData / triggerEnd
local function resolveObjectiveLocation(quest, starterLoc, finisherLoc)
	if not quest then return starterLoc or finisherLoc end
	local refLoc = starterLoc or finisherLoc
	local points = {}

	local function addFromNpcId(npcId, label)
		local npc = npcId and QuestieDB:GetNPC(npcId)
		if not npc or not npc.spawns then return end
		local areaId, x, y = pickBestSpawn(npc.spawns, refLoc)
		if areaId and x and y then
			local zoneName, uiMapId = getZoneNameFromAreaId(areaId)
			local pt = attachWorldCoords({
				name = label or npc.name,
				kind = "Objective",
				areaId = areaId,
				uiMapId = uiMapId,
				zoneName = zoneName,
				x = x,
				y = y,
			})
			table.insert(points, pt)
		end
	end

	local function addFromObjectId(objId, label)
		local obj = objId and QuestieDB:GetObject(objId)
		if not obj or not obj.spawns then return end
		local areaId, x, y = pickBestSpawn(obj.spawns, refLoc)
		if areaId and x and y then
			local zoneName, uiMapId = getZoneNameFromAreaId(areaId)
			local pt = attachWorldCoords({
				name = label or obj.name,
				kind = "Objective",
				areaId = areaId,
				uiMapId = uiMapId,
				zoneName = zoneName,
				x = x,
				y = y,
			})
			table.insert(points, pt)
		end
	end

	if quest.ObjectiveData then
		for _, obj in ipairs(quest.ObjectiveData) do
			if obj.Type == "monster" and obj.Id then
				addFromNpcId(obj.Id, obj.Text)
			elseif obj.Type == "object" and obj.Id then
				addFromObjectId(obj.Id, obj.Text)
			elseif obj.Type == "item" and obj.Id then
				local item = QuestieDB:GetItem(obj.Id)
				if item then
					if item.npcDrops and item.npcDrops[1] then
						-- Check up to first 4 dropping NPCs to find closest to hub
						local bestPt, bestD
						for i = 1, math.min(4, #item.npcDrops) do
							local npc = QuestieDB:GetNPC(item.npcDrops[i])
							if npc and npc.spawns then
								local areaId, x, y = pickBestSpawn(npc.spawns, refLoc)
								if areaId and x and y then
									local zName, uiMapId = getZoneNameFromAreaId(areaId)
									local pt = attachWorldCoords({
										name = obj.Text or item.name or npc.name,
										kind = "Objective",
										areaId = areaId,
										uiMapId = uiMapId,
										zoneName = zName,
										x = x,
										y = y,
									})
									local d = worldDist(refLoc, pt)
									if not bestPt or (d and (not bestD or d < bestD)) then
										bestPt, bestD = pt, d
									end
								end
							end
						end
						if bestPt then table.insert(points, bestPt) end
					elseif item.objectDrops and item.objectDrops[1] then
						addFromObjectId(item.objectDrops[1], obj.Text or item.name)
					end
				end
			elseif obj.Type == "killcredit" and obj.IdList and obj.IdList[1] then
				addFromNpcId(obj.IdList[1], obj.Text)
			end
		end
	end

	if #points == 0 and quest.triggerEnd and quest.triggerEnd[2] then
		local areaId, x, y = pickBestSpawn(quest.triggerEnd[2], refLoc)
		if areaId and x and y then
			local zoneName, uiMapId = getZoneNameFromAreaId(areaId)
			table.insert(points, attachWorldCoords({
				name = quest.triggerEnd[1] or "Quest Area",
				kind = "Objective",
				areaId = areaId,
				uiMapId = uiMapId,
				zoneName = zoneName,
				x = x,
				y = y,
			}))
		end
	end

	if #points == 0 then
		return starterLoc or finisherLoc
	end
	if #points == 1 then
		return points[1]
	end

	-- Compute centroid among points sharing the primary instance/zone
	local primary = points[1]
	local sumX, sumY, sumWx, sumWy, countZone, countWorld = 0, 0, 0, 0, 0, 0
	for _, pt in ipairs(points) do
		if pt.uiMapId == primary.uiMapId and pt.x and pt.y then
			sumX = sumX + pt.x
			sumY = sumY + pt.y
			countZone = countZone + 1
		end
		if pt.instance and pt.instance == primary.instance and pt.wx and pt.wy then
			sumWx = sumWx + pt.wx
			sumWy = sumWy + pt.wy
			countWorld = countWorld + 1
		end
	end

	local result = {
		name = primary.name or "Quest Objectives",
		kind = "Objective",
		areaId = primary.areaId,
		uiMapId = primary.uiMapId,
		zoneName = primary.zoneName,
		x = countZone > 0 and (sumX / countZone) or primary.x,
		y = countZone > 0 and (sumY / countZone) or primary.y,
		wx = countWorld > 0 and (sumWx / countWorld) or primary.wx,
		wy = countWorld > 0 and (sumWy / countWorld) or primary.wy,
		instance = primary.instance,
	}
	if not result.wx then attachWorldCoords(result) end
	return result
end

local function questHasObjectives(quest)
	if not quest then return true end
	if quest.ObjectiveData and #quest.ObjectiveData > 0 then return true end
	if quest.triggerEnd ~= nil then return true end
	if quest.objectives then
		for i = 1, 6 do
			if quest.objectives[i] and next(quest.objectives[i]) ~= nil then
				return true
			end
		end
	end
	if quest.extraObjectives and next(quest.extraObjectives) ~= nil then
		return true
	end
	return false
end

local function isQuestDungeonOrElite(questId, quest)
	if QuestieDB.IsDungeonQuest(questId) then return true, "Dungeon" end
	if QuestieDB.IsRaidQuest(questId) then return true, "Raid" end
	if quest and quest.zoneOrSort and quest.zoneOrSort > 0 and ZoneDB.IsDungeonZone and ZoneDB.IsDungeonZone(quest.zoneOrSort) then
		return true, "Dungeon"
	end
	local tagId = QuestieDB.GetQuestTagInfo(questId)
	if tagId == QuestieDB.questTagIds.DUNGEON then return true, "Dungeon" end
	if tagId == QuestieDB.questTagIds.RAID or tagId == QuestieDB.questTagIds.RAID_10 or tagId == QuestieDB.questTagIds.RAID_25 then
		return true, "Raid"
	end
	if tagId == QuestieDB.questTagIds.ELITE then return true, "Elite" end
	if tagId == QuestieDB.questTagIds.HEROIC then return true, "Heroic" end
	return false, nil
end

local function isQuestHidden(questId)
	if not QuestieCorrections or not QuestieCorrections.hiddenQuests then return false end
	local h = QuestieCorrections.hiddenQuests[questId]
	if not h then return false end
	local hideOnMap = QuestieQuestBlacklist and QuestieQuestBlacklist.HIDE_ON_MAP
	if hideOnMap and h == hideOnMap then return false end
	return true
end

local function isExclusiveCompletedOrActive(quest, completed, active)
	if not quest or not quest.exclusiveTo then return false end
	for _, exId in ipairs(quest.exclusiveTo) do
		if isQuestCompleted(exId, completed) or active[exId] then
			return true
		end
	end
	return false
end

local function isChainAlreadyPast(quest, completed, active)
	if not quest then return false end
	local nextId = quest.nextQuestInChain
	if nextId and nextId ~= 0 then
		if isQuestCompleted(nextId, completed) or active[nextId] then
			return true
		end
	end
	local untilId = quest.availableUntilCompleted
	if untilId and untilId ~= 0 and isQuestCompleted(untilId, completed) then
		return true
	end
	local bcTarget = quest.breadcrumbForQuestId
	if bcTarget and bcTarget ~= 0 and (isQuestCompleted(bcTarget, completed) or active[bcTarget]) then
		return true
	end
	return false
end

local function isQuestApplicableToPlayer(questId, quest)
	if not quest then return false end
	if isQuestHidden(questId) then return false end
	if QuestiePlayer then
		if quest.requiredRaces and quest.requiredRaces ~= 0 and not QuestiePlayer.HasRequiredRace(quest.requiredRaces) then
			return false
		end
		if quest.requiredClasses and quest.requiredClasses ~= 0 and not QuestiePlayer.HasRequiredClass(quest.requiredClasses) then
			return false
		end
	end
	return true
end

local function getQuestZoneInfo(quest, starter)
	if starter and starter.zoneName then
		return starter.zoneName, starter.areaId, starter.uiMapId
	end
	if quest and quest.zoneOrSort then
		if quest.zoneOrSort > 0 then
			local zName, uiMapId = getZoneNameFromAreaId(quest.zoneOrSort)
			return zName, quest.zoneOrSort, uiMapId
		elseif quest.zoneOrSort < 0 and QuestieDB.sortKeys then
			for key, val in pairs(QuestieDB.sortKeys) do
				if val == quest.zoneOrSort then
					local nice = key:lower():gsub("^%l", string.upper):gsub("_", " ")
					return nice, quest.zoneOrSort, nil
				end
			end
		end
	end
	return "Unknown Zone", 0, nil
end

local function getContinentId(uiMapId)
	if not uiMapId or not C_Map or not C_Map.GetMapInfo then return 0 end
	local cur = uiMapId
	for _ = 1, 6 do
		local info = C_Map.GetMapInfo(cur)
		if not info then break end
		if info.mapType == Enum.UIMapType.Continent then
			return info.mapID
		end
		if not info.parentMapID or info.parentMapID == 0 or info.parentMapID == cur then break end
		cur = info.parentMapID
	end
	return 0
end

local function addUnique(list, val)
	for _, v in ipairs(list) do
		if v == val then return end
	end
	table.insert(list, val)
end

-- Main scan entry point!
-- guideEntry: captured guide table from addon.Capture.GetGuide(name)
-- options: { includeOptional = bool, includeDungeonElite = bool }
function Scanner.ScanGuide(guideEntry, options)
	options = options or {}
	if not Scanner.IsQuestieReady() then
		return { ready = false, error = "Waiting for Questie database to finish loading..." }
	end
	if not guideEntry then
		return { ready = true, error = "No Guidelime guide is currently selected." }
	end

	local parsed = addon.Parser.ParseGuideQuests(guideEntry)
	if not parsed then
		return { ready = true, error = "Could not parse the selected guide." }
	end

	local completed = getCompletedQuests()
	local active = getActiveQuests()
	local playerLevel = UnitLevel("player") or 1
	local playerMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil

	-- Helper: is prequest P already accepted AND turned in earlier in this same target guide?
	local function handledEarlierInGuide(preId, beforeLine)
		local gq = parsed.quests[preId]
		if not gq then return false end
		if not gq.hasAccept then return false end
		if not gq.hasTurnIn then return false end
		if beforeLine and gq.firstTurnInLine and gq.firstTurnInLine > beforeLine then
			return false
		end
		return true
	end

	-- Nodes in our catch-up DAG: [questId] = node
	local nodes = {}
	-- Track filtered-out counts so the UI can show helpful hints
	local filteredOptional = 0
	local filteredDungeonElite = 0

	local function ensureNode(questId, reason, targetGuideQuestId)
		local existing = nodes[questId]
		if existing then
			if targetGuideQuestId then
				addUnique(existing.forTargetQuests, targetGuideQuestId)
			end
			-- Upgrade reason & completion requirements if another quest depends on turning this one in
			if reason == "PREREQ" then
				existing.needsTurnIn = true
				if not existing.inLogComplete and existing.hasObjectives then
					existing.needsComplete = true
				end
				if existing.reason == "CARRIED_OVER_INCOMPLETE" then
					existing.reason = "PREREQ"
				end
			end
			return existing
		end

		local quest = QuestieDB.GetQuest(questId)
		if not quest then return nil end

		local starter = resolveEntityLocation(quest.Starts, true)
		local finisher = resolveEntityLocation(quest.Finisher, false, starter)
		local objectiveLoc = resolveObjectiveLocation(quest, starter, finisher)
		local zoneName, areaId, uiMapId = getQuestZoneInfo(quest, starter)
		local isDE, deTag = isQuestDungeonOrElite(questId, quest)
		local activeInfo = active[questId]

		local node = {
			questId = questId,
			quest = quest,
			name = quest.name or ("Quest #" .. questId),
			level = (quest.level and quest.level > 0) and quest.level or (quest.questLevel or 0),
			requiredLevel = quest.requiredLevel or 0,
			zoneName = zoneName or "Unknown Zone",
			areaId = areaId or 0,
			uiMapId = uiMapId,
			continentId = getContinentId(uiMapId),
			starter = starter,
			objectiveLoc = objectiveLoc,
			finisher = finisher,
			hasObjectives = questHasObjectives(quest),
			isDungeonElite = isDE,
			tagLabel = deTag,
			isOptional = false,
			reason = reason, -- "PREREQ", "CARRIED_OVER", "CARRIED_OVER_INCOMPLETE"
			inLog = activeInfo ~= nil,
			inLogComplete = activeInfo and activeInfo.isComplete or false,
			needsAccept = activeInfo == nil,
			needsComplete = not (activeInfo and activeInfo.isComplete),
			needsTurnIn = (reason == "PREREQ"),
			prereqs = {},        -- questIds in `nodes` that must be finished before this node
			dependents = {},     -- questIds in `nodes` that depend on this node
			forTargetQuests = {},-- questIds in target guide that directly/indirectly need this node
			alternatives = nil,  -- optional list of alternative questIds from preQuestSingle
			sourceGuide = addon.Capture.FindSourceGuide(questId, guideEntry),
			status = "READY",
			depth = 0,
		}
		if targetGuideQuestId then
			table.insert(node.forTargetQuests, targetGuideQuestId)
		end
		nodes[questId] = node
		return node
	end

	local function linkEdge(prereqId, dependentId)
		local preNode = nodes[prereqId]
		local depNode = nodes[dependentId]
		if not preNode or not depNode or prereqId == dependentId then return end
		addUnique(depNode.prereqs, prereqId)
		addUnique(preNode.dependents, dependentId)
		-- Since dependentId needs prereqId turned in to unlock, prereqId definitely needs Complete + Turn-In
		preNode.needsTurnIn = true
		if not preNode.inLogComplete and preNode.hasObjectives then
			preNode.needsComplete = true
		end
	end

	-- Choose the best candidate from a preQuestSingle OR-list
	local function pickBestSinglePrequest(preQuestSingle, targetLine, parentQuest)
		local applicable = {}
		for _, candId in ipairs(preQuestSingle) do
			-- If any option is already completed -> fulfilled!
			if isQuestCompleted(candId, completed) then
				return nil, nil, true
			end
			-- If any option is handled earlier inside this same guide -> fulfilled by guide!
			if handledEarlierInGuide(candId, targetLine) then
				return nil, nil, true
			end
			local candQuest = QuestieDB.GetQuest(candId)
			if candQuest and isQuestApplicableToPlayer(candId, candQuest) then
				-- Check if locked out by an exclusive quest
				if not isExclusiveCompletedOrActive(candQuest, completed, active) then
					-- If a later quest in cand's chain is completed, check if it's already bypassed
					table.insert(applicable, { id = candId, quest = candQuest })
				end
			end
		end

		if #applicable == 0 then
			return nil, nil, false
		end

		-- Prefer one that is already in the player's quest log
		for _, entry in ipairs(applicable) do
			if active[entry.id] then
				local alts = {}
				for _, other in ipairs(applicable) do
					if other.id ~= entry.id then table.insert(alts, other.id) end
				end
				return entry.id, (#alts > 0 and alts or nil), false
			end
		end

		-- Score remaining candidates: prefer non-breadcrumb, non-dungeon, same zone as parent, reasonable level
		local parentZone = parentQuest and parentQuest.zoneOrSort or 0
		table.sort(applicable, function(a, b)
			local function score(e)
				local s = 0
				if e.quest.breadcrumbForQuestId and e.quest.breadcrumbForQuestId ~= 0 then s = s - 40 end
				local isDE = isQuestDungeonOrElite(e.id, e.quest)
				if isDE then s = s - 30 end
				if parentZone > 0 and e.quest.zoneOrSort == parentZone then s = s + 25 end
				local lvl = e.quest.level or e.quest.questLevel or 0
				if lvl > 0 and lvl <= playerLevel + 3 then s = s + 10 end
				return s
			end
			local sa, sb = score(a), score(b)
			if sa ~= sb then return sa > sb end
			return a.id < b.id
		end)

		local chosen = applicable[1].id
		local alts = {}
		for i = 2, #applicable do
			table.insert(alts, applicable[i].id)
		end
		return chosen, (#alts > 0 and alts or nil), false
	end

	-- Recursively walk prerequisites for `questId`
	local function walkPrequests(questId, targetGuideQuestId, targetLine, parentInNodes, stack, depth)
		if depth > 25 then return end -- safety guard
		if stack[questId] then return end -- cycle guard
		stack[questId] = true

		local quest = QuestieDB.GetQuest(questId)
		if not quest then
			stack[questId] = nil
			return
		end

		-- 1. preQuestSingle (OR — any one completed fulfills it)
		if quest.preQuestSingle and #quest.preQuestSingle > 0 then
			if not QuestieDB:IsPreQuestSingleFulfilled(quest.preQuestSingle) then
				local chosenId, alts, fulfilled = pickBestSinglePrequest(quest.preQuestSingle, targetLine, quest)
				if not fulfilled and chosenId then
					local preQuest = QuestieDB.GetQuest(chosenId)
					local isDE = isQuestDungeonOrElite(chosenId, preQuest)
					if options.includeDungeonElite or not isDE then
						local preNode = ensureNode(chosenId, "PREREQ", targetGuideQuestId)
						if preNode then
							preNode.needsTurnIn = true
							if alts and not preNode.alternatives then
								preNode.alternatives = alts
							end
							if parentInNodes then
								linkEdge(chosenId, questId)
							end
							if not active[chosenId] then
								walkPrequests(chosenId, targetGuideQuestId, targetLine, true, stack, depth + 1)
							end
						end
					else
						filteredDungeonElite = filteredDungeonElite + 1
					end
				end
			end
		end

		-- 2. preQuestGroup (AND — all entries must be completed)
		if quest.preQuestGroup and #quest.preQuestGroup > 0 then
			if not QuestieDB:IsPreQuestGroupFulfilled(quest.preQuestGroup) then
				for _, rawPreId in ipairs(quest.preQuestGroup) do
					local skipExclusive = rawPreId < 0
					local preId = math.abs(rawPreId)
					local satisfied = isQuestCompleted(preId, completed) or handledEarlierInGuide(preId, targetLine)

					if not satisfied and not skipExclusive then
						local ex = QuestieDB.QueryQuestSingle(preId, "exclusiveTo")
						if ex then
							for _, exId in ipairs(ex) do
								if isQuestCompleted(exId, completed) then
									satisfied = true
									break
								end
							end
						end
					end

					if not satisfied then
						local preQuest = QuestieDB.GetQuest(preId)
						if preQuest and isQuestApplicableToPlayer(preId, preQuest) and not isExclusiveCompletedOrActive(preQuest, completed, active) then
							local isDE = isQuestDungeonOrElite(preId, preQuest)
							if options.includeDungeonElite or not isDE then
								local preNode = ensureNode(preId, "PREREQ", targetGuideQuestId)
								if preNode then
									preNode.needsTurnIn = true
									if parentInNodes then
										linkEdge(preId, questId)
									end
									if not active[preId] then
										walkPrequests(preId, targetGuideQuestId, targetLine, true, stack, depth + 1)
									end
								end
							else
								filteredDungeonElite = filteredDungeonElite + 1
							end
						end
					end
				end
			end
		end

		-- 3. availableStartingWith (needs quest active OR completed)
		local startWith = quest.availableStartingWith
		if startWith and startWith ~= 0 then
			if not isQuestCompleted(startWith, completed) and not active[startWith] and not handledEarlierInGuide(startWith, targetLine) then
				local swQuest = QuestieDB.GetQuest(startWith)
				if swQuest and isQuestApplicableToPlayer(startWith, swQuest) and not isExclusiveCompletedOrActive(swQuest, completed, active) then
					local isDE = isQuestDungeonOrElite(startWith, swQuest)
					if options.includeDungeonElite or not isDE then
						local preNode = ensureNode(startWith, "PREREQ", targetGuideQuestId)
						if preNode then
							preNode.needsAccept = true
							preNode.needsComplete = false
							preNode.needsTurnIn = false
							if parentInNodes then
								linkEdge(startWith, questId)
							end
							walkPrequests(startWith, targetGuideQuestId, targetLine, true, stack, depth + 1)
						end
					else
						filteredDungeonElite = filteredDungeonElite + 1
					end
				end
			end
		end

		stack[questId] = nil
	end

	-- Pass 1: Examine every quest referenced in the target guide
	local targetQuestMeta = {}
	for _, qid in ipairs(parsed.questOrder) do
		local gq = parsed.quests[qid]
		if gq and not gq.hasSkip then
			local quest = QuestieDB.GetQuest(qid)
			if quest and isQuestApplicableToPlayer(qid, quest) then
				targetQuestMeta[qid] = {
					questId = qid,
					name = quest.name or ("Quest #" .. qid),
					level = (quest.level and quest.level > 0) and quest.level or (quest.questLevel or 0),
					firstLine = gq.firstLine,
					allOptional = gq.allOptional,
				}

				local isDE = isQuestDungeonOrElite(qid, quest)
				local skipOpt = gq.allOptional and not options.includeOptional
				local skipDE = isDE and not options.includeDungeonElite

				if skipOpt then
					filteredOptional = filteredOptional + 1
				elseif skipDE then
					filteredDungeonElite = filteredDungeonElite + 1
				elseif not isQuestCompleted(qid, completed)
					and not isExclusiveCompletedOrActive(quest, completed, active)
					and not (not active[qid] and isChainAlreadyPast(quest, completed, active))
				then
					local isCarriedOver = (not gq.hasAccept) and (gq.hasComplete or gq.hasTurnIn)

					if isCarriedOver then
						local activeInfo = active[qid]
						if activeInfo then
							-- Player already has it in quest log.
							-- Only flag if the guide expects a Turn-In ONLY (no [QC]) and it isn't finished yet!
							if gq.hasTurnIn and not gq.hasComplete and not activeInfo.isComplete then
								local node = ensureNode(qid, "CARRIED_OVER_INCOMPLETE", qid)
								if node then
									node.isOptional = gq.allOptional
									node.needsAccept = false
									node.needsComplete = true
									node.needsTurnIn = false -- Target guide has [QT]
								end
							end
						else
							-- Not in log and not completed -> must pick it up (and finish if guide has only [QT])!
							local node = ensureNode(qid, "CARRIED_OVER", qid)
							if node then
								node.isOptional = gq.allOptional
								node.needsAccept = true
								node.needsComplete = (not gq.hasComplete) and node.hasObjectives
								node.needsTurnIn = false -- Target guide will turn it in (unless upgraded by linkEdge)
								walkPrequests(qid, qid, gq.firstLine, true, {}, 1)
							end
						end
					elseif gq.hasAccept then
						-- Guide will accept this quest; check if its prerequisites are missing!
						if not active[qid] then
							walkPrequests(qid, qid, gq.firstAcceptLine or gq.firstLine, false, {}, 1)
						end
					end
				end
			end
		end
	end

	-- Pass 2: Compute status and chain depth for every catch-up node
	local inDegree = {}
	local totalNodes = 0
	for qid, node in pairs(nodes) do
		totalNodes = totalNodes + 1
		inDegree[qid] = #node.prereqs
		if node.inLog then
			if node.inLogComplete then
				node.status = "IN_LOG_COMPLETE"
			else
				node.status = "IN_LOG"
			end
		elseif #node.prereqs > 0 then
			node.status = "BLOCKED"
		elseif node.requiredLevel > playerLevel then
			node.status = "LEVEL_LOW"
		else
			node.status = "READY"
		end
	end

	-- Pass 3: Zone-clustered topological sort (Kahn's algorithm)
	-- Compute average level per zone for clean progression ordering
	local zoneStats = {}
	for _, node in pairs(nodes) do
		local z = node.zoneName
		local st = zoneStats[z]
		if not st then
			st = { sumLvl = 0, count = 0, minLvl = 999 }
			zoneStats[z] = st
		end
		local lvl = node.level > 0 and node.level or 60
		st.sumLvl = st.sumLvl + lvl
		st.count = st.count + 1
		if lvl < st.minLvl then st.minLvl = lvl end
	end

	local remainingInDegree = {}
	local readyPool = {}
	for qid, deg in pairs(inDegree) do
		remainingInDegree[qid] = deg
		if deg == 0 then
			table.insert(readyPool, qid)
		end
	end

	local ordered = {}
	local placed = {}
	local lastZone = nil
	local lastContinent = playerMapId and getContinentId(playerMapId) or 0

	local function statusPriority(status)
		if status == "IN_LOG_COMPLETE" then return 1 end
		if status == "IN_LOG" then return 2 end
		if status == "READY" then return 3 end
		if status == "BLOCKED" then return 4 end
		return 5 -- LEVEL_LOW
	end

	while #readyPool > 0 do
		table.sort(readyPool, function(aId, bId)
			local a, b = nodes[aId], nodes[bId]
			-- 1. Stay in the same zone to minimize travel
			if lastZone then
				local aSame = (a.zoneName == lastZone)
				local bSame = (b.zoneName == lastZone)
				if aSame ~= bSame then return aSame end
			end
			-- 2. Stay on the same continent
			if lastContinent and lastContinent ~= 0 then
				local aCont = (a.continentId == lastContinent)
				local bCont = (b.continentId == lastContinent)
				if aCont ~= bCont then return aCont end
			end
			-- 3. Prefer lower-level zone first
			local za, zb = zoneStats[a.zoneName], zoneStats[b.zoneName]
			if za and zb and za.minLvl ~= zb.minLvl then
				return za.minLvl < zb.minLvl
			end
			-- 4. Within zone, prefer already-in-log quests first, then lowest level
			local pa, pb = statusPriority(a.status), statusPriority(b.status)
			if pa ~= pb then return pa < pb end
			if a.level ~= b.level then return a.level < b.level end
			return aId < bId
		end)

		local nextId = table.remove(readyPool, 1)
		local node = nodes[nextId]
		placed[nextId] = true
		table.insert(ordered, node)
		lastZone = node.zoneName
		if node.continentId and node.continentId ~= 0 then
			lastContinent = node.continentId
		end

		for _, depId in ipairs(node.dependents) do
			remainingInDegree[depId] = (remainingInDegree[depId] or 1) - 1
			local depNode = nodes[depId]
			if depNode and node.depth + 1 > depNode.depth then
				depNode.depth = node.depth + 1
			end
			if remainingInDegree[depId] <= 0 and not placed[depId] then
				table.insert(readyPool, depId)
			end
		end
	end

	-- Fallback in case of any cyclic DB edge: append any unplaced nodes
	if #ordered < totalNodes then
		local leftover = {}
		for qid, node in pairs(nodes) do
			if not placed[qid] then table.insert(leftover, node) end
		end
		table.sort(leftover, function(a, b) return a.level < b.level end)
		for _, node in ipairs(leftover) do
			table.insert(ordered, node)
		end
	end

	-- Pass 4: Build summary counts & zone list
	local stats = {
		total = #ordered,
		prereqs = 0,
		carriedOver = 0,
		ready = 0,
		inLog = 0,
		blocked = 0,
		levelLow = 0,
		zones = {},
		zoneCount = 0,
		filteredOptional = filteredOptional,
		filteredDungeonElite = filteredDungeonElite,
	}

	local zoneOrder = {}
	local byZone = {}
	for _, node in ipairs(ordered) do
		if node.reason == "PREREQ" then
			stats.prereqs = stats.prereqs + 1
		else
			stats.carriedOver = stats.carriedOver + 1
		end
		if node.status == "READY" then stats.ready = stats.ready + 1
		elseif node.status == "IN_LOG" or node.status == "IN_LOG_COMPLETE" then stats.inLog = stats.inLog + 1
		elseif node.status == "BLOCKED" then stats.blocked = stats.blocked + 1
		elseif node.status == "LEVEL_LOW" then stats.levelLow = stats.levelLow + 1 end

		if not byZone[node.zoneName] then
			byZone[node.zoneName] = {}
			table.insert(zoneOrder, node.zoneName)
			stats.zoneCount = stats.zoneCount + 1
		end
		table.insert(byZone[node.zoneName], node)
	end

	-- Pass 5: Build "By Target Quest" grouping
	local byTarget = {}
	local targetOrder = {}
	local targetSeen = {}
	for _, node in ipairs(ordered) do
		for _, tId in ipairs(node.forTargetQuests) do
			if not targetSeen[tId] then
				targetSeen[tId] = true
				table.insert(targetOrder, tId)
				byTarget[tId] = {
					target = targetQuestMeta[tId] or { questId = tId, name = "Quest #" .. tId, level = 0, firstLine = 0 },
					nodes = {},
				}
			end
			table.insert(byTarget[tId].nodes, node)
		end
	end
	table.sort(targetOrder, function(a, b)
		local ta = byTarget[a].target
		local tb = byTarget[b].target
		return (ta.firstLine or 0) < (tb.firstLine or 0)
	end)

	-- Determine where the target guide physically starts so the spatial router finishes near its doorstep
	local targetStartPos = nil
	for _, qid in ipairs(parsed.questOrder) do
		local gq = parsed.quests[qid]
		local quest = QuestieDB.GetQuest(qid)
		if gq and quest and isQuestApplicableToPlayer(qid, quest) then
			local loc
			if gq.hasAccept then
				loc = resolveEntityLocation(quest.Starts, true)
			elseif gq.hasTurnIn then
				loc = resolveEntityLocation(quest.Finisher, false)
			else
				loc = resolveObjectiveLocation(quest, resolveEntityLocation(quest.Starts, true), nil)
			end
			if loc and loc.wx and loc.wy then
				targetStartPos = loc
				break
			end
		end
	end

	-- Pass 6: Build Hub-Batched Spatial Action Route (Accept / Complete / TurnIn interleaved by proximity!)
	local optimizedActions, routeStats = Scanner.BuildOptimizedRoute(nodes, ordered, active, targetStartPos)

	-- Reorder `ordered` (quest list) by first appearance in the optimized route so zone/quest order matches
	if optimizedActions and #optimizedActions > 0 then
		local seenQ = {}
		local reordered = {}
		for _, act in ipairs(optimizedActions) do
			if not seenQ[act.questId] and nodes[act.questId] then
				seenQ[act.questId] = true
				table.insert(reordered, nodes[act.questId])
			end
		end
		for _, node in ipairs(ordered) do
			if not seenQ[node.questId] then
				table.insert(reordered, node)
			end
		end
		ordered = reordered
	end

	return {
		ready = true,
		guide = guideEntry,
		nodes = nodes,
		ordered = ordered,
		optimizedActions = optimizedActions,
		routeStats = routeStats,
		targetStartPos = targetStartPos,
		byZone = byZone,
		zoneOrder = zoneOrder,
		byTarget = byTarget,
		targetOrder = targetOrder,
		targetQuestMeta = targetQuestMeta,
		stats = stats,
	}
end

-- Action-Level Hub-Batching & Spatial Coordinate Route Optimizer
-- Splits each catch-up quest into atomic ACCEPT / COMPLETE / TURNIN actions with real
-- HereBeDragons world coordinates, then schedules them to:
--   1) Batch all nearby Turn-Ins (unlocking follow-ups right away!) & Accepts at each town hub
--   2) Sweep field objectives in nearest-neighbor spatial order before returning to town
--   3) Respect a safe quest log cap (<= 19 active quests)
--   4) Defer the target guide's starting zone until last when traveling between zones
function Scanner.BuildOptimizedRoute(nodes, fallbackOrdered, activeQuests, targetStartPos)
	local actions = {}      -- [actionId] = action
	local actionList = {}
	local questActions = {} -- [questId] = { ACCEPT = act, COMPLETE = act, TURNIN = act }

	-- Count currently active quests in player's quest log
	local curLogCount = 0
	if activeQuests then
		for _ in pairs(activeQuests) do curLogCount = curLogCount + 1 end
	end
	local MAX_QUEST_LOG = 19

	local function createAction(node, kind, pos, logDelta)
		local id = kind:sub(1, 1) .. "_" .. node.questId
		local fallbackPos = pos or node.starter or node.finisher or { zoneName = node.zoneName, uiMapId = node.uiMapId }
		local act = {
			id = id,
			action = kind, -- "ACCEPT", "COMPLETE", "TURNIN"
			questId = node.questId,
			node = node,
			pos = fallbackPos,
			zoneName = (fallbackPos and fallbackPos.zoneName) or node.zoneName or "Unknown Zone",
			logDelta = logDelta or 0,
			prereqs = {},
			dependents = {},
			inDegree = 0,
			done = false,
		}
		actions[id] = act
		table.insert(actionList, act)
		questActions[node.questId] = questActions[node.questId] or {}
		questActions[node.questId][kind] = act
		return act
	end

	local function addDep(preAct, depAct)
		if not preAct or not depAct or preAct.id == depAct.id then return end
		for _, existing in ipairs(depAct.prereqs) do
			if existing == preAct.id then return end
		end
		table.insert(depAct.prereqs, preAct.id)
		table.insert(preAct.dependents, depAct.id)
		depAct.inDegree = depAct.inDegree + 1
	end

	-- 1. Create atomic actions per quest
	for _, node in ipairs(fallbackOrdered or {}) do
		local aAct, cAct, tAct
		if node.needsAccept then
			aAct = createAction(node, "ACCEPT", node.starter, 1)
		end
		if node.needsComplete and node.hasObjectives then
			cAct = createAction(node, "COMPLETE", node.objectiveLoc or node.starter or node.finisher, 0)
			if aAct then addDep(aAct, cAct) end
		end
		if node.needsTurnIn then
			tAct = createAction(node, "TURNIN", node.finisher or node.starter, -1)
			if cAct then
				addDep(cAct, tAct)
			elseif aAct then
				addDep(aAct, tAct)
			end
		end
	end

	-- 2. Wire cross-quest prerequisite dependencies (TurnIn(prereq) -> Accept(dependent))
	for _, node in ipairs(fallbackOrdered or {}) do
		local depQA = questActions[node.questId]
		if depQA then
			local entryAct = depQA.ACCEPT or depQA.COMPLETE or depQA.TURNIN
			if entryAct then
				for _, preId in ipairs(node.prereqs or {}) do
					local preQA = questActions[preId]
					if preQA then
						local exitAct = preQA.TURNIN or preQA.COMPLETE or preQA.ACCEPT
						if exitAct then
							addDep(exitAct, entryAct)
						end
					end
				end
			end
		end
	end

	if #actionList == 0 then
		return {}, { totalActions = 0, totalDistanceYards = 0, hubStops = 0 }
	end

	-- Determine initial player position via HereBeDragons
	local curPos = nil
	if HBD and HBD.GetPlayerWorldPosition then
		local pwx, pwy, pinst = HBD:GetPlayerWorldPosition()
		if pwx and pwy and pinst then
			local pMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
			local pZoneName = pMapId and C_Map.GetMapInfo and C_Map.GetMapInfo(pMapId) and C_Map.GetMapInfo(pMapId).name or nil
			curPos = { wx = pwx, wy = pwy, instance = pinst, zoneName = pZoneName }
		end
	end

	-- Track which quests unlock a follow-up in the same zone (useful for chain prioritization)
	local function unlocksSameZone(act)
		if act.action ~= "TURNIN" then return false end
		for _, depId in ipairs(act.dependents) do
			local dep = actions[depId]
			if dep and dep.zoneName == act.zoneName then
				return true
			end
		end
		return false
	end

	local HUB_RADIUS = 180 -- yards: covers a town / quest hub
	local CONTINENT_PENALTY = 25000
	local CROSS_ZONE_PENALTY = 900

	local remaining = #actionList
	local result = {}
	local totalDist = 0
	local lastActionType = nil

	-- Helper: check if any unlocked action exists in zones OTHER than zoneName (on same instance if known)
	local function hasOtherZoneUnlocked(unlockedList, excludedZone, sameInstance)
		for _, act in ipairs(unlockedList) do
			if act.zoneName ~= excludedZone then
				if not sameInstance or not act.pos.instance or act.pos.instance == sameInstance then
					return true
				end
			end
		end
		return false
	end

	-- Helper: distance between two positions
	local function estimateDistance(posA, posB)
		if not posA or not posB then return 500 end
		local d = worldDist(posA, posB)
		if d then return d end
		if posA.instance and posB.instance and posA.instance ~= posB.instance then
			return CONTINENT_PENALTY
		end
		if posA.zoneName and posB.zoneName and posA.zoneName == posB.zoneName then
			return 400
		end
		return 4000
	end

	while remaining > 0 do
		-- Collect all unlocked actions
		local unlocked = {}
		local hasNonAccept = false
		for _, act in ipairs(actionList) do
			if not act.done and act.inDegree <= 0 then
				table.insert(unlocked, act)
				if act.action ~= "ACCEPT" then hasNonAccept = true end
			end
		end

		-- Cycle fallback (if DB had any circular prereq)
		if #unlocked == 0 then
			for _, act in ipairs(actionList) do
				if not act.done then
					table.insert(unlocked, act)
					break
				end
			end
		end
		if #unlocked == 0 then break end

		local chosen = nil
		local chosenDist = nil
		local batchedAtHub = false

		-- Rule 1: Instant Hub Batching! If we're standing in a town/hub, batch TURNINs first (unlocking follow-ups!)
		-- and then ACCEPTs within HUB_RADIUS yards before ever walking out to the field.
		if curPos then
			local bestTurnIn, bestTurnInDist
			local bestAccept, bestAcceptDist

			for _, act in ipairs(unlocked) do
				if act.action == "TURNIN" or (act.action == "ACCEPT" and (curLogCount < MAX_QUEST_LOG or not hasNonAccept)) then
					local d = worldDist(curPos, act.pos)
					if d and d <= HUB_RADIUS then
						if act.action == "TURNIN" then
							if not bestTurnIn or d < bestTurnInDist then
								bestTurnIn, bestTurnInDist = act, d
							end
						elseif act.action == "ACCEPT" then
							if not bestAccept or d < bestAcceptDist then
								bestAccept, bestAcceptDist = act, d
							end
						end
					end
				end
			end

			if bestTurnIn then
				chosen = bestTurnIn
				chosenDist = bestTurnInDist
				batchedAtHub = true
			elseif bestAccept then
				chosen = bestAccept
				chosenDist = bestAcceptDist
				batchedAtHub = true
			end
		end

		-- Rule 2: Spatial Nearest-Neighbor with Hub-Prep, Field-Sweep, & Target-End-Zone Awareness
		if not chosen then
			local targetZone = targetStartPos and targetStartPos.zoneName
			local curInstance = curPos and curPos.instance
			local otherZonesExist = targetZone and hasOtherZoneUnlocked(unlocked, targetZone, curInstance) or false

			local bestScore = nil
			for _, act in ipairs(unlocked) do
				-- Respect quest log cap when possible
				local logPenalty = 0
				if act.action == "ACCEPT" and curLogCount >= MAX_QUEST_LOG and hasNonAccept then
					logPenalty = 50000
				end

				local rawDist = curPos and estimateDistance(curPos, act.pos) or ((act.node.level or 30) * 50)
				local score = rawDist + logPenalty

				-- Prefer staying in the current zone to avoid zone-hopping
				if curPos and curPos.zoneName and act.zoneName ~= curPos.zoneName then
					-- Only apply zone penalty if it's not right across the border
					if rawDist > 350 then
						score = score + CROSS_ZONE_PENALTY
					end
				end

				-- Town sweep bias: when we just accepted/turned in, prefer grabbing other nearby accepts in this zone before heading out
				if (lastActionType == "ACCEPT" or lastActionType == "TURNIN" or lastActionType == nil)
					and act.action == "ACCEPT" and rawDist <= 650 then
					score = score - 260
				end

				-- Field sweep bias: when we just completed an objective, prefer finishing other nearby objectives in the same zone before running back to town
				if lastActionType == "COMPLETE" and act.action == "COMPLETE"
					and curPos and act.zoneName == curPos.zoneName and rawDist <= 900 then
					score = score - 220
				end

				-- Chain unlock bias: turning in a quest that unlocks a follow-up in the same zone
				if unlocksSameZone(act) and rawDist <= 700 then
					score = score - 160
				end

				-- Save the target guide's starting zone for LAST when traveling to a new zone,
				-- so you finish catch-up right at the target guide's doorstep!
				if targetZone and otherZonesExist and act.zoneName == targetZone then
					if not curPos or curPos.zoneName ~= targetZone then
						score = score + 1800
					end
				end

				-- Slight tie-breaker toward lower quest level & deterministic ID
				score = score + (act.node.level or 0) * 0.5

				if not bestScore or score < bestScore then
					bestScore = score
					chosen = act
					chosenDist = worldDist(curPos, act.pos)
				end
			end
		end

		-- Commit chosen action
		chosen.done = true
		chosen.distFromPrev = chosenDist
		chosen.batchedAtHub = batchedAtHub
		table.insert(result, chosen)
		remaining = remaining - 1

		if chosenDist and chosenDist < CONTINENT_PENALTY then
			totalDist = totalDist + chosenDist
		end
		curLogCount = math.max(0, curLogCount + chosen.logDelta)
		lastActionType = chosen.action

		if chosen.pos and (chosen.pos.wx or chosen.pos.zoneName) then
			curPos = chosen.pos
		end

		-- Unlock dependents
		for _, depId in ipairs(chosen.dependents) do
			local dep = actions[depId]
			if dep then
				dep.inDegree = dep.inDegree - 1
			end
		end
	end

	return result, {
		totalActions = #result,
		totalDistanceYards = math.floor(totalDist + 0.5),
	}
end
