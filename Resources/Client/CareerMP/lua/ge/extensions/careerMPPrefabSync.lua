--CareerMP prefabSync (CLIENT) by Dudekahedron, 2026

local M = {}

local prefabsTable = {}

local iterT = {}
local iterC = 0

local prefabNames = {
	"arrive",
	"closedGates",
	"deco",
	"forwardPrefab",
	"logs",
	"loopPrefab",
	"mainPrefab",
	"obstacles",
	"obstacles2",
	"obstacles-fromFile",
	"openGates",
	"parkingLotClutter",
	"prefab",
	"ramp",
	"reversePrefab",
	"road",
	"rockslide",
	"targets",
	"vehicles"
}

local function addPrefabEntry(name, path, outdated)
	prefabsTable[name] = {
		path = path,
		outdated = outdated
	}
end

local function checkPrefab(prefabData, baseName, userSettings)
	local fullJson = string.format("%s/%s.prefab.json", prefabData.pPath, baseName)
	local fullLegacy = string.format("%s/%s.prefab", prefabData.pPath, baseName)
	local prefabKey = prefabData.pName .. baseName:gsub("Prefab", ""):gsub("%-", "")
	local outdated, exists = false, FS:fileExists(fullJson)
	if not exists then
		outdated = true
		exists = FS:fileExists(fullLegacy)
		if not exists then
			return
		end
	end
	if baseName == "forwardPrefab" and userSettings.reverse then
		return
	end
	if baseName == "reversePrefab" and not userSettings.reverse then
		return
	end
	addPrefabEntry(prefabKey, exists and (outdated and fullLegacy or fullJson), outdated)
end

local function removeAllPrefabs(pName)
	for _, base in pairs(prefabNames) do
		local key = pName .. base:gsub("Prefab", ""):gsub("%-", "")
		if scenetree.findObject(key) then
			removePrefab(key)
		end
	end
	be:reloadCollision()
end

local function rxPrefabSync(data)
	if not data or data == "null" then
		return
	end
	local prefabData = jsonDecode(data)
	local userSettings = prefabData.pSettings
	if prefabData.pLoad then
		for _, base in ipairs(prefabNames) do
			checkPrefab(prefabData, base, userSettings)
		end
	else
		removePrefab(prefabData.pName)
		removeAllPrefabs(prefabData.pName)
	end
end

local function readPrefab(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*all")
	f:close()
	return content
end

local function writePrefab(path, content)
	local f = io.open(path, "w+")
	if not f then
		return
	end
	f:write(content)
	f:close()
end

local function cleanPrefab(content)
	local result = ""
	local inSep = 1
	for _ = 1, #content do
		local outSep = content:find("}\n", inSep)
		if not outSep then
			break
		end
		local block = content:sub(inSep, outSep)
		inSep = content:find("{", outSep)
		if not block:find("BeamNGVehicle", 1) then
			result = result .. block .. "\n"
		end
		if not inSep then
			break
		end
	end
	return result
end

local function cleanPrefabOutdated(content)
	local result = ""
	local inSep = 1
	for _ = 1, #content do
		local start = content:find("   new BeamNGVehicle%(", inSep)
		if not start then
			result = result .. content:sub(inSep)
			break
		end
		result = result .. content:sub(inSep, start - 1)
		local outSep = content:find("};", start)
		if not outSep then
			break
		end
		inSep = outSep + 2
		if inSep > #content then
			break
		end
	end
	return result
end

local function processPrefab(path, name, outdated)
	local content = readPrefab(path)
	if not content then
		return
	end
	local cleanedPrefab = not outdated and cleanPrefab(content) or cleanPrefabOutdated(content)
	if cleanedPrefab then
		local ext = not outdated and ".prefab.json" or ".prefab"
		local tempPath = "settings/BeamMP/tempPrefab" .. name .. ext
		writePrefab(tempPath, cleanedPrefab)
		spawnPrefab(name, tempPath, "0 0 0", "0 0 1", "1 1 1")
	end
end

local function onAnyMissionChanged(state, mission)
	if state == "stopped" then
		local prefab = {}
		prefab.pName = mission.missionType .. "-" .. tostring(iterT[mission.missionType])
		prefab.pLoad = false
		local data = jsonEncode(prefab)
		TriggerServerEvent("careerPrefabSync", data)
	end
end

local function onMissionStartWithFade(mission, userSettings)
	local prefab = {}
	iterT[mission.missionType] = iterC
	prefab.pName = mission.missionType .. "-" .. tostring(iterT[mission.missionType])
	prefab.pPath = mission.missionFolder
	prefab.pSettings = userSettings
	prefab.pLoad = true
	local data = jsonEncode(prefab)
	TriggerServerEvent("careerPrefabSync", data)
	iterC = iterC + 1
end

local function onUpdate(dtReal, dtSim, dtRaw)
	if worldReadyState == 2 then
		for name, data in pairs(prefabsTable) do
			processPrefab(data.path, name, data.outdated)
			prefabsTable[name] = nil
			be:reloadCollision()
			break
		end
	end
end

local function onExtensionLoaded()
	AddEventHandler("rxPrefabSync", rxPrefabSync)
	log('W', 'careerMP', 'CareerMP prefabSync LOADED!')
end

local function onExtensionUnloaded()
	log('W', 'careerMP', 'CareerMP prefabSync UNLOADED!')
end

M.onAnyMissionChanged = onAnyMissionChanged
M.onMissionStartWithFade = onMissionStartWithFade

M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
