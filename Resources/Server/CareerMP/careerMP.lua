--CareerMP (SERVER) by Dudekahedron, 2026
--Thanks to Bouboule, and Lion and Luuk from BeamPaint, for http request examples

local HARD_CLIENT_VERSION = {major = 0, minor = 0, revision = 33}
local HARD_SERVER_VERSION = {major = 0, minor = 0, revision = 33}

local RAW = "https://raw.githubusercontent.com/"
local GITHUB_REPO = "StanleyDudek/CareerMP/"
local BRANCH = "main/"
local CLIENT_PATH = "Resources/Client/"
local CLIENT_FILE = "CareerMP.zip"
local SERVER_PATH = "Resources/Server/CareerMP/"
local SERVER_FILE = "careerMP.lua"
local CLIENT_VERSION_FILE = "versions/client.json"
local SERVER_VERSION_FILE = "versions/server.json"
local CLIENT_URL = RAW .. GITHUB_REPO .. BRANCH .. CLIENT_PATH .. CLIENT_FILE
local SERVER_URL = RAW .. GITHUB_REPO .. BRANCH .. SERVER_PATH .. SERVER_FILE
local CLIENT_UPDATE_URL = RAW .. GITHUB_REPO .. BRANCH .. SERVER_PATH .. CLIENT_VERSION_FILE
local SERVER_UPDATE_URL = RAW .. GITHUB_REPO .. BRANCH .. SERVER_PATH .. SERVER_VERSION_FILE

local configPath = "Resources/Server/CareerMP/config/"

local defaultConfig = {
	server = {
		autoUpdate = true,
		autoRestart = true,
		longWindowMax = 10000,
		shortWindowMax = 1000,
		longWindowSeconds = 300,
		shortWindowSeconds = 30,
		allowTransactions = true,
		sessionSendingMax = 100000,
		sessionReceiveMax = 200000,
	},
	client = {
		localUnicycleGhost = false,
		remoteUnicycleGhost = true,
		remoteVehicleGhost = false,
		serverSaveName = "",
		serverSaveSuffix = "",
		serverSaveNameEnabled = false,
		roadTrafficAmount = 0,
		parkedTrafficAmount = 0,
		roadTrafficEnabled = false,
		parkedTrafficEnabled = false,
		worldEditorEnabled = false,
		consoleEnabled = false,
		simplifyRemoteVehicles = false,
		spawnVehicleIgnitionLevel = 0,
		skipOtherPlayersVehicles = false,
		trafficSmartSelections = true,
		trafficSimpleVehicles = true,
		trafficAllowMods = false
	}
}

local synced = false
local vehicleStates = {}
local loadedPrefabs = {}

local signalTimer = MP.CreateTimer()

local ledger = {
	send = {},
	receive = {}
}

local trapNames = {
	[1] = "Riverway Plaza",
	[2] = "Plaza Northbound",
	[3] = "Plaza Southbound",
	[4] = "Beach",
	[5] = "Lighthouse",
	[6] = "Island Port Northbound",
	[7] = "Island Port Southbound"
}

local function downloadVersionFile(url, path)
	local response
    if MP.GetOSName() == "Windows" then
        response = os.execute('powershell -Command "Invoke-WebRequest -Uri ' .. url .. ' -OutFile ' .. path .. '"')
    else
        response = os.execute("wget -q -O " .. path .. " " .. url)
    end
	if response then
		local file = io.open(path, "r")
		if file then
			local data = file:read("*all")
			file:close()
			return data
		end
	else
		return nil
	end
end

local function downloadFile(url, path)
	local response
    if MP.GetOSName() == "Windows" then
        response = os.execute('powershell -Command "Invoke-WebRequest -Uri ' .. url .. ' -OutFile ' .. path .. '"')
    else
        response = os.execute("wget -q -O " .. path .. " " .. url)
    end
	return response
end

local function needsUpdate(installedVersion, latest)
    local components = { "major", "minor", "revision" }
    for _, key in pairs(components) do
        local i, l = installedVersion[key] or 0, latest[key] or 0
        if l > i then
            return true
        end
        if l < i then
            return false
        end
    end
    return false
end

local function updateClient()
    local installedVersion = ReadJson(SERVER_PATH .. CLIENT_VERSION_FILE)
	local installed = FS.Exists(CLIENT_PATH .. CLIENT_FILE)
	if not installed then
		print("[CareerMP] ---------- CareerMP Update Client not installed, downloading...")
		downloadFile(CLIENT_URL, CLIENT_PATH .. CLIENT_FILE)
	end
	if not installedVersion then
        print("[CareerMP] ---------- CareerMP Update Applying self version!")
		installedVersion = HARD_CLIENT_VERSION
		WriteJson(SERVER_PATH .. CLIENT_VERSION_FILE, HARD_CLIENT_VERSION)
	end
    local latestVersionFile = downloadVersionFile(CLIENT_UPDATE_URL, SERVER_PATH .. CLIENT_VERSION_FILE)
	local latest = Util.JsonDecode(latestVersionFile)
    if not latest then
        print("[CareerMP] ---------- CareerMP Update Failed to fetch latest client version!")
        return
    end
	local update = needsUpdate(installedVersion, latest)
    if installedVersion then
        print("[CareerMP] ---------- CareerMP Update Client installed: " .. installedVersion.major .. "." .. installedVersion.minor .. "." .. installedVersion.revision)
        print("[CareerMP] ---------- CareerMP Update Client latest: " .. latest.major .. "." .. latest.minor .. "." .. latest.revision)
        if update then
			print("[CareerMP] ---------- CareerMP Update Updating client...")
			downloadFile(CLIENT_URL, CLIENT_PATH .. CLIENT_FILE)
			print("[CareerMP] ---------- CareerMP Update Client updated to " ..  latest.major .. "." .. latest.minor .. "." .. latest.revision .. "! Restart the server to apply the update!")
		else
			print("[CareerMP] ---------- CareerMP Update Client up to date!")
			return
		end
	else
		print("[CareerMP] ---------- CareerMP Update Client version not found.")
        downloadFile(CLIENT_URL, CLIENT_PATH .. CLIENT_FILE)
        print("[CareerMP] ---------- CareerMP Update Client version updated to " ..  latest.major .. "." .. latest.minor .. "." .. latest.revision .. "! Restart the server to apply the update!")
    end
	return update
end

local function updateServer()
    local installedVersion = ReadJson(SERVER_PATH .. SERVER_VERSION_FILE)
	local installed = FS.Exists(SERVER_PATH .. SERVER_FILE)
	if not installed then
		print("[CareerMP] ---------- CareerMP Update Server not installed, downloading...")
		downloadFile(SERVER_URL, SERVER_PATH .. SERVER_FILE)
	end
	if not installedVersion then
        print("[CareerMP] ---------- CareerMP Update Applying self version!")
		installedVersion = HARD_SERVER_VERSION
		WriteJson(SERVER_PATH .. SERVER_VERSION_FILE, HARD_SERVER_VERSION)
	end
    local latestVersionFile = downloadVersionFile(SERVER_UPDATE_URL, SERVER_PATH .. SERVER_VERSION_FILE)
    local latest = Util.JsonDecode(latestVersionFile)
    if not latest then
        print("[CareerMP] ---------- CareerMP Update Failed to fetch latest server version")
        return
    end
	local update = needsUpdate(installedVersion, latest)
    if installedVersion then
        print("[CareerMP] ---------- CareerMP Update Server installed: " .. installedVersion.major .. "." .. installedVersion.minor .. "." .. installedVersion.revision)
        print("[CareerMP] ---------- CareerMP Update Server latest: " .. latest.major .. "." .. latest.minor .. "." .. latest.revision)
        if update then
			print("[CareerMP] ---------- CareerMP Update Updating server...")
			downloadFile(SERVER_URL, SERVER_PATH .. SERVER_FILE)
			print("[CareerMP] ---------- CareerMP Update Server updated to " ..  latest.major .. "." .. latest.minor .. "." .. latest.revision .. "! Restart the server to apply the update!")
		else
			print("[CareerMP] ---------- CareerMP Update Server up to date!")
			return
		end
	else
		print("[CareerMP] ---------- CareerMP Update Server version not found.")
        downloadFile(SERVER_URL, SERVER_PATH .. SERVER_FILE)
        print("[CareerMP] ---------- CareerMP Update Server version updated to " ..  latest.major .. "." .. latest.minor .. "." .. latest.revision .. "! Restart the server to apply the update!")
    end
	return update
end

local function parseQuotedString(input, startIndex)
	local closingQuoteIndex = input:find('"', startIndex + 1)
	if closingQuoteIndex then
		local value = input:sub(startIndex + 1, closingQuoteIndex - 1)
		return value, closingQuoteIndex + 2
	else
		local value = input:sub(startIndex + 1)
		return value, nil
	end
end

local function parseWord(input, startIndex)
	local nextSpaceIndex = input:find(' ', startIndex)
	if nextSpaceIndex then
		local value = input:sub(startIndex, nextSpaceIndex - 1)
		return value, nextSpaceIndex + 1
	else
		return input:sub(startIndex), nil
	end
end

local function parseCommand(message, separator)
	local arguments = {}
	local command = nil
	if separator then
		command = message:sub(1, separator - 1)
		local argumentsString = message:sub(separator + 1)
		local currentIndex = 1
		while currentIndex <= #argumentsString do
			local currentChar = argumentsString:sub(currentIndex, currentIndex)
			if currentChar == '"' then
				local value, nextIndex = parseQuotedString(argumentsString, currentIndex)
				table.insert(arguments, value)
				if not nextIndex then
					break
				end
				currentIndex = nextIndex
			elseif currentChar ~= ' ' then
				local value, nextIndex = parseWord(argumentsString, currentIndex)
				table.insert(arguments, value)
				if not nextIndex then
					break
				end
				currentIndex = nextIndex
			else
				currentIndex = currentIndex + 1
			end
		end
	end
	return command, arguments
end

local function prepareConfig()
	print("[CareerMP] ---------- CareerMP Config Loading...")
	Config = ReadJson(configPath .. "config.json")
	if not Config then
		print("[CareerMP] ---------- CareerMP Config Initializing...")
		Config = defaultConfig
		for section, fields in pairs(defaultConfig) do
			for field, value in pairs(fields) do
				print("[CareerMP] ---------- CareerMP Config " .. section .. " " .. field .. " set to " .. tostring(value))
			end
		end
		WriteJson(configPath .. "config.json", Config)
	else
		local updateFound
		for section, fields in pairs(defaultConfig) do
			print("[CareerMP] ---------- CareerMP Config Checking " .. section)
			if Config[section] == nil then
				updateFound = true
				print("[CareerMP] ---------- CareerMP Config Adding: " .. section)
				Config[section] = {}
				for field, value in pairs(fields) do
					print("[CareerMP] ---------- CareerMP Config " .. section .. " " .. field .. " set to " .. tostring(value))
					Config[section][field] = value
				end
			else
				for field, value in pairs(fields) do
					if Config[section][field] == nil then
						print("[CareerMP] ---------- CareerMP Config " .. section .. " " .. field .. " not found")
						print("[CareerMP] ---------- CareerMP Config " .. section .. " " .. field .. " set to " .. tostring(value))
						updateFound = true
						Config[section][field] = value
					end
				end
			end
		end
		if updateFound then
			print("[CareerMP] ---------- CareerMP Config Updated!")
			WriteJson(configPath .. "config.json", Config)
		end
	end
	print("[CareerMP] ---------- CareerMP Config Loaded!")
end

function onInit()

	print("[CareerMP] ---------- CareerMP Loading...")

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
	MP.RegisterEvent("txUpdateBlueLight", "txUpdateBlueLight")
	MP.RegisterEvent("txUpdatePreStageLight", "txUpdatePreStageLight")
	MP.RegisterEvent("txUpdateStageLight", "txUpdateStageLight")
	MP.RegisterEvent("txUpdateDisqualifiedLight", "txUpdateDisqualifiedLight")
	MP.RegisterEvent("txUpdateTreeLights", "txUpdateTreeLights")
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

	MP.RegisterEvent("onConsoleInput","onConsoleInputHandler")

	MP.RegisterEvent("GetConfig","GetConfig")
	MP.RegisterEvent("SetConfig","SetConfig")
	MP.RegisterEvent("Update","Update")
	MP.RegisterEvent("Help","Help")

	prepareConfig()

	if not FS.IsDirectory(SERVER_PATH .. "/versions") then
		FS.CreateDirectory(SERVER_PATH .. "/versions")
	end

	if Config.server.autoUpdate then
		local update
		update = updateClient()
		update = updateServer()
		if update and Config.server.autoRestart then
			exit()
		end
	end

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
	local sender = getOrCreate(ledger.send, sender_id)
	local receiver = getOrCreate(ledger.receive, receiver_id)
	local short_total = getWindowTotal(sender.short_transactions, now, Config.server.shortWindowSeconds)
	local long_total = getWindowTotal(sender.long_transactions, now, Config.server.longWindowSeconds)
	if sender.session_total + amount > Config.server.sessionSendingMax then
		return false
	end
	if short_total > 0 and short_total + amount > Config.server.shortWindowMax then
		return false
	end
	if long_total > 0 and long_total + amount > Config.server.longWindowMax then
		return false
	end
	if receiver.session_total + amount > Config.server.sessionReceiveMax then
		return false
	end
	sender.session_total = sender.session_total + amount
	receiver.session_total = receiver.session_total + amount
	if amount <= Config.server.shortWindowMax then
		table.insert(sender.short_transactions, { amount = amount, timestamp = now })
	end
	if amount <= Config.server.longWindowMax then
		table.insert(sender.long_transactions, { amount = amount, timestamp = now })
	end
	return true
end

function payPlayer(player_id, data)
	local paymentData = Util.JsonDecode(data)
	paymentData.sender = MP.GetPlayerName(player_id)
	if Config.server.allowTransactions then
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

function txUpdateBlueLight(player_id, data)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxUpdateBlueLight", data)
		end
	end
end

function txUpdatePreStageLight(player_id, data)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxUpdatePreStageLight", data)
		end
	end
end

function txUpdateStageLight(player_id, data)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxUpdateStageLight", data)
		end
	end
end

function txUpdateDisqualifiedLight(player_id, data)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxUpdateDisqualifiedLight", data)
		end
	end
end

function txUpdateTreeLights(player_id, data)
	for id in pairs(MP.GetPlayers()) do
		if player_id ~= id then
			MP.TriggerClientEvent(id, "rxUpdateTreeLights", data)
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
	MP.TriggerClientEventJson(player_id, "rxCareerSync", Config.client)
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
	ledger.send[player_id] = nil
	ledger.receive[player_id] = nil
end

function onConsoleInputHandler(message)
	local space = message:find(" ")
	if not space then
		return ""
	end
	local commandPrefix = message:sub(1, space)
	if commandPrefix == "CareerMP " or "CMP " then
		local prefixLen = commandPrefix:len()
		message = message:sub(prefixLen + 1)
		local command = message
		local arguments = {}
		local separator = message:find(' ')
		if separator then
			command, arguments = parseCommand(message, separator)
		end
		MP.TriggerLocalEvent(command, arguments)
	end
	return ""
end

local function checkValue(value)
	if tonumber(value) then
		return tonumber(value)
	elseif value == "true" then
		return true
	elseif value == "false" then
		return false
	end
	return value
end

function GetConfig(arguments)
	Config = ReadJson(configPath .. "config.json")
	if #arguments == 0 then
		print(Config)
	elseif #arguments == 1 then
		print(Config[arguments[1]])
	else
		print(Config[arguments[1]][arguments[2]])
	end
end

function SetConfig(arguments)
	if #arguments < 3 then
		print("Usage: CareerMP SetConfig <section> <key> <value>")
		return
	end
	Config = ReadJson(configPath .. "config.json")
	local section = arguments[1]
	local key = arguments[2]
	local value = arguments[3]
	if not Config[section] then
		print("[CareerMP] ---------- Unknown section: " .. section)
		return
	end
	if Config[section][key] == nil then
		print("[CareerMP] ---------- Unknown key: " .. section .. " " .. key)
		return
	end
	Config[section][key] = checkValue(value)
	print("[CareerMP] ---------- Config:    " .. section .. " " .. tostring(key) .. " set to " .. tostring(Config[section][key]))
	WriteJson(configPath .. "config.json", Config)
	MP.TriggerClientEventJson(-1, "rxClientConfigUpdate", Config.client)
end

function Update(arguments)
	local update
	update = updateClient()
	update = updateServer()
	if update and Config.server.autoRestart then
		exit()
	end
end

function Help(arguments)
	print("CareerMP GetConfig <section> <key>            - Displays Config, or section, or key")
	print("CareerMP SetConfig <section*> <key*> <value*> - Sets Config section key to value, * = REQUIRED")
	print("CareerMP Update                               - Checks for CareerMP update")
	print("CareerMP Help                                 - Displays Commands Usage")
end

function ReadJson(path)
	if not path then
		print("[CareerMP] ---------- ReadJson:  path is nil!")
		return
	end
	if not FS.Exists(path) then
		print("[CareerMP] ---------- ReadJson:  " .. path .. " does not exist!")
		return
	end
	local jsonFile, err = io.open(path, "r")
	if not jsonFile then
		print("[CareerMP] ---------- ReadJson:  failed to open " .. path .. ": " .. tostring(err))
		return
	end
	local jsonText = jsonFile:read("*a")
	jsonFile:close()
	if not jsonText or jsonText == "" then
		print("[CareerMP] ---------- ReadJson:  " .. path .. " is empty!")
		return
	end
	local data = Util.JsonDecode(jsonText)
	if data == nil then
		print("[CareerMP] ---------- ReadJson:  failed to decode " .. path)
		return
	end
	return data
end

function WriteJson(path, data)
	if not path then
		print("[CareerMP] ---------- WriteJson: path is nil!")
		return
	end
	if data == nil then
		print("[CareerMP] ---------- WriteJson: data is nil, aborting!")
		return
	end
	local checkDirectory = path:match("(.+)/[^/]+$")
	if checkDirectory and not FS.Exists(checkDirectory) then
		FS.CreateDirectory(checkDirectory)
		print("[CareerMP] ---------- WriteJson: created directory " .. checkDirectory)
	end
	local encoded = Util.JsonEncode(data)
	if not encoded then
		print("[CareerMP] ---------- WriteJson: failed to encode data!")
		return
	end
	local jsonFile, err = io.open(path, "w")
	if not jsonFile then
		print("[CareerMP] ---------- WriteJson: failed to open " .. path .. ": " .. tostring(err))
		return
	end
	print("[CareerMP] ---------- WriteJson: writing " .. path)
	jsonFile:write(Util.JsonPrettify(encoded))
	jsonFile:close()
	return true
end
