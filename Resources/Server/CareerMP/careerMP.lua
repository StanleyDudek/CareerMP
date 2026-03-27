--CareerMP (SERVER) by Dudekahedron, 2026

local vehicleStates = {}
local loadedPrefabs = {}

local signalTimer = MP.CreateTimer()

local sessionTransactionMax = 100000
local sessionReceiveMax = 200000
local shortWindowMax = 1000
local shortWindowSeconds = 30
local longWindowMax = 10000
local longWindowSeconds = 300
local sendLedger = {}
local receiveLedger = {}

local allowTransactions = true

local trapNames = {
    [1] = "Riverway Plaza",
    [2] = "Plaza Northbound",
    [3] = "Plaza Southbound",
    [4] = "Beach",
    [5] = "Lighthouse",
    [6] = "Island Port Northbound",
    [7] = "Island Port Southbound"
}

function onInit()
	MP.RegisterEvent("perPartPainting","perPartPaintingHandler")
	MP.RegisterEvent("requestPartPaints","requestPartPaintsHandler")

	MP.RegisterEvent("payPlayer","payPlayer")

	MP.RegisterEvent("careerPrefabSync","careerPrefabSync")
	MP.RegisterEvent("careerSyncRequested","careerSyncRequested")
	MP.RegisterEvent("prefabSyncRequested","prefabSyncRequested")
	MP.RegisterEvent("careerVehSyncRequested","careerVehSyncRequested")
	MP.RegisterEvent("careerVehicleActiveHandler","careerVehicleActiveHandler")

	MP.RegisterEvent("txUpdateDisplay", "txUpdateDisplay")
	MP.RegisterEvent("txUpdateWinnerLight", "txUpdateWinnerLight")
	MP.RegisterEvent("txClearDisplay", "txClearDisplay")
	MP.RegisterEvent("txClearAll", "txClearAll")

	MP.RegisterEvent("speedTrap", "speedTrap")
    MP.RegisterEvent("redLight", "redLight")
    MP.RegisterEvent("trafficLightTimer","trafficLightTimer")
	MP.CreateEventTimer("trafficLightTimer", 10000)

	MP.RegisterEvent("onPlayerJoin","onPlayerJoinHandler")
	MP.RegisterEvent("onVehicleSpawn","onVehicleSpawnHandler")
	MP.RegisterEvent("onVehicleEdited","onVehicleEditedHandler")
	MP.RegisterEvent("onVehicleDeleted","onVehicleDeletedHandler")
	MP.RegisterEvent("onPlayerDisconnect","onPlayerDisconnectHandler")

	print("[CareerMP] ---------- CareerMP Loaded!")
end

function perPartPaintingHandler(player_id, data)
    local paintData = Util.JsonDecode(data)
	if not paintData.originID then
		for id in pairs(MP.GetPlayers()) do
			if player_id ~= id then
				MP.TriggerClientEvent(id, "rxRemotePartPaint", data)
			end
		end
	else
		MP.TriggerClientEvent(paintData.originID, "rxRemotePartPaint", data)
	end
end

function requestPartPaintsHandler(player_id, data)
    local requestData = Util.JsonDecode(data)
	local targetID = tonumber(requestData.serverVehicleID:sub(1,1))
	requestData.originID = player_id
	MP.TriggerClientEventJson(targetID, "rxRequestPartPaints", requestData)
end

local function getOrCreate(ledger, player_id)
    if not ledger[player_id] then
        ledger[player_id] = {
            session_total = 0,
            short_transactions = {},
            long_transactions = {}
        }
    end
    return ledger[player_id]
end

local function getWindowTotal(transactions, now, windowSeconds)
    local window_total = 0
    local cutoff = now - windowSeconds
    local kept = {}
    for _, transaction in ipairs(transactions) do
        if transaction.timestamp > cutoff then
            table.insert(kept, transaction)
            window_total = window_total + transaction.amount
        end
    end
    for i = #transactions, 1, -1 do
		transactions[i] = nil
		end
    for _, t in ipairs(kept) do
		table.insert(transactions, t)
	end
    return window_total
end

local function attemptTransaction(sender_id, receiver_id, amount, now)
    local sender = getOrCreate(sendLedger, sender_id)
    local receiver = getOrCreate(receiveLedger, receiver_id)
    local short_total = getWindowTotal(sender.short_transactions, now, shortWindowSeconds)
    local long_total = getWindowTotal(sender.long_transactions, now, longWindowSeconds)
    if sender.session_total + amount > sessionTransactionMax then
        return false
    end
    if short_total > 0 and short_total + amount > shortWindowMax then
        return false
    end
    if long_total > 0 and long_total + amount > longWindowMax then
        return false
    end
    if receiver.session_total + amount > sessionReceiveMax then
        return false
    end
    sender.session_total = sender.session_total + amount
    receiver.session_total = receiver.session_total + amount
	if amount <= shortWindowMax then
		table.insert(sender.short_transactions, { amount = amount, timestamp = now })
	end
	if amount <= longWindowMax then
		table.insert(sender.long_transactions, { amount = amount, timestamp = now })
	end
    return true
end

function payPlayer(player_id, data)
	local paymentData = Util.JsonDecode(data)
	paymentData.sender = MP.GetPlayerName(player_id)
	if allowTransactions then
		if MP.IsPlayerConnected(paymentData.target_player_id) then
			if attemptTransaction(player_id, paymentData.target_player_id, paymentData.money, signalTimer:GetCurrent()) then
				MP.TriggerClientEventJson(paymentData.target_player_id, "rxPayment", paymentData)
				MP.TriggerClientEventJson(player_id, "rxConfirmation", paymentData)
			else
				MP.TriggerClientEventJson(player_id, "rxBounce", paymentData)
			end
		else
			MP.TriggerClientEventJson(player_id, "rxBounce", paymentData)
		end
	else
		MP.TriggerClientEventJson(player_id, "rxDeny", paymentData)
	end
end

function txUpdateDisplay(player_id, data)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxUpdateDisplay", data)
		end
	end
end

function txUpdateWinnerLight(player_id, data)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxUpdateWinnerLight", data)
		end
	end
end

function txClearDisplay(player_id)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxClearDisplay", "")
		end
	end
end

function txClearAll(player_id)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxClearAll", "")
		end
	end
end

function speedTrap(player_id, data)
    local speedTrapData = Util.JsonDecode(data)
    local triggerName = speedTrapData.triggerName
    local triggerNumber = tonumber(string.match(triggerName, "%d+"))
    local triggerPlace = trapNames[triggerNumber] or "Unknown"
    local player_name = MP.GetPlayerName(player_id)
	MP.SendNotification(-1, "Speed Violation by " .. player_name .. "!", "survellianceCamera", "survellianceCamera")
	MP.SendNotification(-1, "Speed: " .. string.format( "%.1f", speedTrapData.playerSpeed * 2.23694 ) .. " in " .. string.format( "%.0f", speedTrapData.speedLimit * 2.23694 ) .. " MPH Zone", "powerGauge05", "powerGauge05")
	MP.SendNotification(-1, "Location: " .. triggerPlace, "location1", "location1")
	MP.SendNotification(-1, "Vehicle: " .. speedTrapData.vehicleModel, "car", "car")
	MP.SendNotification(-1, "Plate: " .. speedTrapData.licensePlate, "code", "code")
end

function redLight(player_id, data)
    local redLightData = Util.JsonDecode(data)
    local triggerName = redLightData.triggerName
    local triggerNumber = tonumber(string.match(triggerName, "%d+"))
    local triggerPlace = trapNames[triggerNumber] or "Unknown"
    local player_name = MP.GetPlayerName(player_id)
	MP.SendNotification(-1, "Failure to stop at Red Light by " .. player_name .. "!", "trafficLight", "trafficLight")
	MP.SendNotification(-1, "Speed: " .. string.format( "%.1f", redLightData.playerSpeed * 2.23694 ) .. " MPH", "powerGauge05", "powerGauge05")
	MP.SendNotification(-1, "Location: " .. triggerPlace, "location1", "location1")
	MP.SendNotification(-1, "Vehicle: " .. redLightData.vehicleModel, "car", "car")
	MP.SendNotification(-1, "Plate: " .. redLightData.licensePlate, "code", "code")
end

local synced = false

function trafficLightTimer()
	if synced then
		MP.TriggerClientEvent(-1, "rxTrafficSignalTimer", tostring(signalTimer:GetCurrent()))
	end
end

function careerVehSyncRequested(player_id)
	synced = true
	MP.TriggerClientEventJson(player_id, "rxCareerVehSync", vehicleStates)
end

function careerPrefabSync(player_id, data)
    local prefab = Util.JsonDecode(data)
    if prefab.pLoad == true then
        loadedPrefabs[player_id][prefab.pName] = prefab
    elseif prefab.pLoad == false then
        loadedPrefabs[player_id][prefab.pName] = nil
    end
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxPrefabSync", data)
		end
	end
end

function careerSyncRequested(player_id)
	MP.TriggerClientEvent(player_id, "rxCareerSync", "")
end

function prefabSyncRequested(player_id)
    for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			if loadedPrefabs[id] then
				for k,v in pairs(loadedPrefabs[id]) do
					MP.TriggerClientEventJson(player_id, "rxPrefabSync", loadedPrefabs[id][k])
				end
			end
        end
    end
end

function careerVehicleActiveHandler(player_id, data)
	local vehicleData = Util.JsonDecode(data)
	if vehicleStates[vehicleData.serverVehicleID] then
		vehicleStates[vehicleData.serverVehicleID].active = vehicleData.active
	else
		vehicleStates[vehicleData.serverVehicleID] = {}
		vehicleStates[vehicleData.serverVehicleID].active = vehicleData.active
	end
	MP.TriggerClientEventJson(-1, "rxCareerVehSync", vehicleStates)
end

function onPlayerJoinHandler(player_id)
    loadedPrefabs[player_id] = {}
end

function onVehicleSpawnHandler(player_id, vehicle_id,  data)
	vehicleStates[player_id .. "-" .. vehicle_id] = {}
	vehicleStates[player_id .. "-" .. vehicle_id].active = true
	MP.TriggerClientEventJson(-1, "rxCareerVehSync", vehicleStates)
end

function onVehicleEditedHandler(player_id, vehicle_id,  data)
	if vehicleStates[player_id .. "-" .. vehicle_id] then
		vehicleStates[player_id .. "-" .. vehicle_id].active = true
	else
		vehicleStates[player_id .. "-" .. vehicle_id] = {}
		vehicleStates[player_id .. "-" .. vehicle_id].active = true
	end
end

function onVehicleDeletedHandler(player_id, vehicle_id)
	if vehicleStates[player_id .. "-" .. vehicle_id] then
		vehicleStates[player_id .. "-" .. vehicle_id] = nil
	end
end

function onPlayerDisconnectHandler(player_id)
	loadedPrefabs[player_id] = nil
	sendLedger[player_id] = nil
	receiveLedger[player_id] = nil
end
