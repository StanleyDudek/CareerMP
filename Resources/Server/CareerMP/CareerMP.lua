--CareerMP (SERVER) by Dudekahedron, 2024

local careerPlayers = {}

local vehicleStates = {}

function onInit()
	MP.RegisterEvent("txPrefab","txPrefabHandler")
	MP.RegisterEvent("MPCareerActiveHandler","MPCareerActiveHandler")
	MP.RegisterEvent("MPCareerVehicleActiveHandler","MPCareerVehicleActiveHandler")
	MP.RegisterEvent("MPCareerSyncRequested","MPCareerSyncRequestedHandler")
	MP.RegisterEvent("paintUpdate", "paintUpdateHandler")
	MP.RegisterEvent("onPlayerJoin", "onPlayerJoinHandler")
	MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnectHandler")
	MP.RegisterEvent("onVehicleSpawn", "onVehicleSpawnHandler")
	MP.RegisterEvent("onVehicleEdited", "onVehicleEditedHandler")
	print("CareerMP Loaded!")
end

function txPrefabHandler(player_id, data)
	for id, name in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxPrefab", data)
		end
	end
end

function MPCareerSyncRequestedHandler(player_id, data)
	MP.TriggerClientEventJson(player_id, "rxMPCareerSync", vehicleStates)
end

function MPCareerVehicleActiveHandler(player_id, data)
	local tempData = Util.JsonDecode(data)
	if string.find(tempData[2], "-") then
		if vehicleStates[tempData[2]] then
			vehicleStates[tempData[2]].active = tempData[1]
		else
			vehicleStates[tempData[2]] = {}
			vehicleStates[tempData[2]].active = tempData[1]
		end
		MP.TriggerClientEventJson(-1, "rxMPCareerSync", vehicleStates)
	end
end

function paintUpdateHandler(player_id, data)
	local tempData = Util.JsonDecode(data)
	MP.TriggerClientEventJson(-1, "rxPaint", {tempData[1], tempData[2]})
end

function MPCareerActiveHandler(player_id, data)
	local tempData = Util.JsonDecode(data)
	careerPlayers[player_id].careerActive = tempData[1]
end

function onVehicleSpawnHandler(player_id, vehicle_id,  data)
	vehicleStates[player_id .. "-" .. vehicle_id] = {}
	vehicleStates[player_id .. "-" .. vehicle_id].active = true
	if data.jbm ~= "unicycle" then
		if not careerPlayers[player_id].careerActive then
			MP.SendChatMessage(player_id, "You must enable CareerMP to play on this server!")
			return false
		end
	end
end

function onVehicleEditedHandler(player_id, vehicle_id,  data)
	if vehicleStates[player_id .. "-" .. vehicle_id] then
		vehicleStates[player_id .. "-" .. vehicle_id].active = true
	else
		vehicleStates[player_id .. "-" .. vehicle_id] = {}
		vehicleStates[player_id .. "-" .. vehicle_id].active = true
	end
	if data.jbm ~= "unicycle" then
		if not careerPlayers[player_id].careerActive then
			MP.TriggerClientEvent(player_id, "rxMPCareerUnicycleSpawn", "")
			MP.SendChatMessage(player_id, "You must enable CareerMP to play on this server!")
			return false
		end
	end
end

function onPlayerJoinHandler(player_id)
	careerPlayers[player_id] = {}
	careerPlayers[player_id].careerActive = false
end

function onPlayerDisconnectHandler(player_id)
	careerPlayers[player_id] = nil
	for k,v in pairs(vehicleStates) do
		if string.find(k, player_id .. "-") then
			vehicleStates[k] = nil
		end
	end
end
