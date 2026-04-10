--CareerMP perPartPaint (CLIENT) by Dudekahedron, 2026

local M = {}

local pendingPaints = {}
local pendingRemotePaints = {}
local ensuredPartConditionsByVeh = {}

local function clampHelper(value)
	return clamp(tonumber(value) or 0, 0, 1)
end

local function copyPaint(paint)
	local base = paint.baseColor or {}
	return {
		baseColor = { base[1] or 1, base[2] or 1, base[3] or 1, base[4] or 1 },
		metallic = paint.metallic or 0,
		roughness = paint.roughness or 0.5,
		clearcoat = paint.clearcoat or 0,
		clearcoatRoughness = paint.clearcoatRoughness or 0
	}
end

local function sanitizePaint(paint)
	local sanitized = copyPaint(paint) or {}
	validateVehiclePaint(sanitized)
	local base = sanitized.baseColor or {}
	sanitized.baseColor = {
		clampHelper(base[1]),
		clampHelper(base[2]),
		clampHelper(base[3]),
		clampHelper(base[4] or 1)
	}
	sanitized.metallic = clampHelper(sanitized.metallic)
	sanitized.roughness = clampHelper(sanitized.roughness)
	sanitized.clearcoat = clampHelper(sanitized.clearcoat)
	sanitized.clearcoatRoughness = clampHelper(sanitized.clearcoatRoughness)
	return sanitized
end

local function sanitizePaints(paints)
	local sanitized = {}
	local lastPaint = nil
	for i = 1, 3 do
		local paint = paints[i] or lastPaint or paints[1]
		if not paint then
			break
		end
		local sanitizedPaint = sanitizePaint(paint)
		if not sanitizedPaint then
			break
		end
		sanitized[i] = sanitizedPaint
		lastPaint = paint
	end
	if tableIsEmpty(sanitized) then
		return nil
	end
	if not sanitized[2] then
		sanitized[2] = copyPaint(sanitized[1])
	end
	if not sanitized[3] then
		sanitized[3] = copyPaint(sanitized[2] or sanitized[1])
	end
	return sanitized
end

local function paintsToLuaLiteral(paints)
	if tableIsEmpty(paints) then
		return '{ {baseColor={1, 1, 1, 1}, metallic = 0, roughness = 0.5 , clearcoat = 0, clearcoatRoughness = 0 } }'
	end
	local segments = {}
	for i = 1, #paints do
		local paint = paints[i] or {}
		local base = paint.baseColor or {}
		segments[#segments + 1] = string.format(
		'{baseColor = {%s, %s, %s, %s}, metallic = %s, roughness = %s, clearcoat = %s, clearcoatRoughness = %s}',
		string.format('%.6f', base[1] or 0),
		string.format('%.6f', base[2] or 0),
		string.format('%.6f', base[3] or 0),
		string.format('%.6f', base[4] or 1),
		string.format('%.6f', paint.metallic or 0),
		string.format('%.6f', paint.roughness or 0),
		string.format('%.6f', paint.clearcoat or 0),
		string.format('%.6f', paint.clearcoatRoughness or 0)
		)
	end
	return '{' .. table.concat(segments, ',') .. '}'
end

local function identifiersToLuaLiteral(identifiers)
	if type(identifiers) ~= "table" or tableIsEmpty(identifiers) then
		return "{}"
	end
	local segments = {}
	for i = 1, #identifiers do
		local identifier = identifiers[i]
		if identifier and identifier ~= '' then
		segments[#segments + 1] = string.format('%q', identifier)
		end
	end
	if tableIsEmpty(segments) then
		return '{}'
	end
	return '{' .. table.concat(segments, ',') .. '}'
end

local function buildIdentifiers(partPath, partName, slotPath)
	local ids = {}
	if partPath and partPath ~= "" then
		ids[#ids + 1] = partPath
	end
	if partName and partName ~= "" and partName ~= partPath then
		ids[#ids + 1] = partName
	end
	if slotPath and slotPath ~= "" then
		ids[#ids + 1] = slotPath
	end
	return ids
end

local function ensureVehiclePartConditionInitialized(vehObj, gameVehicleID)
	if not vehObj or not vehObj.queueLuaCommand then
		return
	end
	local id = gameVehicleID or (vehObj.getID and vehObj:getID())
	if not id or id == -1 then
		return
	end
	if ensuredPartConditionsByVeh[id] then
		return
	end
	local command = [=[if partCondition and partCondition.ensureConditionsInit then
		partCondition.ensureConditionsInit(0, 1, 1)
	end]=]
	vehObj:queueLuaCommand(command)
	ensuredPartConditionsByVeh[id] = true
end

local function queuePartPaintCommands(vehObj, identifiers, paints)
	if not vehObj or not paints or not identifiers or #identifiers == 0 then
		return
	end
	local command = string.format([[
		local identifiers = %s
		local paints = %s
		if partCondition then
			if partCondition.ensureConditionsInit then
				partCondition.ensureConditionsInit(0, 1, 1)
			end
			if partCondition.setPartPaints then
				for _, identifier in ipairs(identifiers) do
					partCondition.setPartPaints(identifier, paints, 0)
				end
			end
		end
		]],
		identifiersToLuaLiteral(identifiers),
		paintsToLuaLiteral(paints)
	)
	vehObj:queueLuaCommand(command)
end

local function setPartPaintRemote(gameVehicleID, partPath, paints, partName, slotPath)
	if not gameVehicleID or not paints then
		return
	end
	local vehObj = be:getObjectByID(gameVehicleID)
	if not vehObj then
		return
	end
	paints = sanitizePaints(paints)
	if not paints then
		return
	end
	local identifiers = buildIdentifiers(partPath, partName, slotPath)
	if #identifiers == 0 then
		return
	end
	ensureVehiclePartConditionInitialized(vehObj, gameVehicleID)
	queuePartPaintCommands(vehObj, identifiers, paints)
end

local function applyPartPaintRemote(data)
	setPartPaintRemote(
		data.gameVehicleID,
		data.partPath,
		data.paints,
		data.partName,
		data.slotPath
	)
end

local function sendPartPaints(inventoryId, serverVehicleID, originID)
	local partConditions = career_modules_inventory.getVehicles()[inventoryId].partConditions
	for part, partData in pairs(partConditions) do
		if partData.visualState then
			local data = {}
			data.partPath = part
			data.slotPath, data.partName = string.match(data.partPath, "(.*/)([^/]+)$")
			data.paints = partData.visualState.paint.originalPaints
			data.serverVehicleID = serverVehicleID
			if originID	then
				data.originID = originID
			end
			TriggerServerEvent("perPartPainting", jsonEncode(data))
		end
	end
end

local function onInventorySpawnVehicle(inventoryId, gameVehicleID)
	if gameVehicleID then
		local vehicles = MPVehicleGE.getVehicles()
		for serverVehicleID, vehicleData in pairs(vehicles) do
			if vehicleData.gameVehicleID and vehicleData.gameVehicleID == gameVehicleID then
				sendPartPaints(inventoryId, serverVehicleID)
			else
				table.insert(pendingPaints, inventoryId)
			end
		end
	else
		table.insert(pendingPaints, inventoryId)
	end
end

local function rxRemotePartPaint(data)
	local paintData = jsonDecode(data)
	if paintData.serverVehicleID then
		if MPVehicleGE.getVehicles()[paintData.serverVehicleID] then
			paintData.gameVehicleID = MPVehicleGE.getGameVehicleID(paintData.serverVehicleID)
			applyPartPaintRemote(paintData)
		else
			pendingRemotePaints[paintData.gameVehicleID] = paintData
		end
	end
end

local function rxRequestPartPaints(data)
	local requestData = jsonDecode(data)
	local gameVehicleID = MPVehicleGE.getGameVehicleID(requestData.serverVehicleID)
	local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId(gameVehicleID)
	if not inventoryId then
		return
	end
	sendPartPaints(inventoryId, requestData.serverVehicleID, requestData.originID)
end

local function onVehicleReady(gameVehicleID)
	local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID)
	if serverVehicleID then
		if not MPVehicleGE.isOwn(gameVehicleID) then
			TriggerServerEvent("requestPartPaints", jsonEncode({serverVehicleID = serverVehicleID}))
		else
			local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId(gameVehicleID)
			if inventoryId then
				sendPartPaints(inventoryId, serverVehicleID)
			end
		end
	end
end


local function onVehicleDestroyed(vehId)
	ensuredPartConditionsByVeh[vehId] = nil
end


local function onPartShoppingStarted(targetVehicleID, inventoryId)
	if inventoryId then
		local gameVehicleID = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
		if gameVehicleID then
			local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID)
			if serverVehicleID then
				sendPartPaints(inventoryId, serverVehicleID)
			end
		end
	end
end

local function onPartShoppingPartInstalled(partData)
	if partData.inventoryId then
		local gameVehicleID = career_modules_inventory.getVehicleIdFromInventoryId(partData.inventoryId)
		if gameVehicleID then
			local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID)
			if serverVehicleID then
				sendPartPaints(partData.inventoryId, serverVehicleID)
			end
		end
	end
end

local function onPartShoppingTransactionComplete(inventoryId)
	if inventoryId then
		local gameVehicleID = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
		if gameVehicleID then
			local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID)
			if serverVehicleID then
				sendPartPaints(inventoryId, serverVehicleID)
			end
		end
	end
end

local function onConditionCheckCallback(gameVehicleID)
	if pendingRemotePaints[gameVehicleID] then
		applyPartPaintRemote(pendingRemotePaints[gameVehicleID].paintData)
		table.remove(pendingRemotePaints, gameVehicleID)
	end
end

local function onUpdate()
	if worldReadyState == 2 then
		local vehicles
		for i = #pendingPaints, 1, -1 do
			local entry = pendingPaints[i]
			local gameVehicleID = career_modules_inventory.getVehicleIdFromInventoryId(entry)
			if gameVehicleID then
				vehicles = MPVehicleGE.getVehicles()
				for serverVehicleID, vehicleData in pairs(vehicles) do
					if vehicleData.gameVehicleID == gameVehicleID then
						sendPartPaints(entry, serverVehicleID)
						table.remove(pendingPaints, i)
					end
				end
			end
		end
		for gameVehicleID, paintData in pairs(pendingRemotePaints) do
			if paintData.serverVehicleID then
				local veh = be:getObjectByID(gameVehicleID)
				if veh then
					veh:queueLuaCommand('careerMPEnabler.onConditionCheck()')
				end
			else
				vehicles = MPVehicleGE.getVehicles()
				for serverVehicleID, vehicleData in pairs(vehicles) do
					if vehicleData.gameVehicleID == gameVehicleID then
						paintData.serverVehicleID = serverVehicleID
					end
					if paintData.serverVehicleID then
						local veh = be:getObjectByID(gameVehicleID)
						if veh then
							veh:queueLuaCommand('careerMPEnabler.onConditionCheck()')
						end
					end
				end
			end
		end
	end
end

local function onExtensionLoaded()
	AddEventHandler("rxRequestPartPaints", rxRequestPartPaints)
	AddEventHandler("rxRemotePartPaint", rxRemotePartPaint)
	log('W', 'careerMP', 'CareerMP perPartPaint LOADED!')
end

local function onExtensionUnloaded()
	log('W', 'careerMP', 'CareerMP perPartPaint UNLOADED!')
end

M.onConditionCheckCallback = onConditionCheckCallback

M.onInventorySpawnVehicle = onInventorySpawnVehicle

M.onVehicleReady = onVehicleReady
M.onVehicleDestroyed = onVehicleDestroyed

M.onPartShoppingStarted = onPartShoppingStarted
M.onPartShoppingPartInstalled = onPartShoppingPartInstalled
M.onPartShoppingTransactionComplete = onPartShoppingTransactionComplete

M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
