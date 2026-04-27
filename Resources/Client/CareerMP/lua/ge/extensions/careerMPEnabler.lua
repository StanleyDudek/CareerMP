--CareerMP (CLIENT) by Dudekahedron, 2026

local M = {}

--Setup

local nickname = MPConfig.getNickname()

local blockedInputActions = {}

local clientConfig

local function getClientConfig()
	return clientConfig
end

local careerMPActive = false
local syncRequested = false

local originalMPOnUpdate
local originalGetDriverData

local inComputerMenus = false

--Settings

local userTrafficSettings = {}
local careerMPTrafficSettings = {}

local userGameplaySettings = {}
local careerMPGameplaySettings = {}

local function getUserTrafficSettings()
	userTrafficSettings.trafficSmartSelections = settings.getValue('trafficSmartSelections')
	userTrafficSettings.trafficSimpleVehicles = settings.getValue('trafficSimpleVehicles')
	userTrafficSettings.trafficAllowMods = settings.getValue('trafficAllowMods')
end

local function setTrafficSettings(trafficSettings)
	for setting, value in pairs(trafficSettings) do
		settings.setValue(setting, value)
	end
end

local function getUserGameplaySettings()
	userGameplaySettings.simplifyRemoteVehicles = settings.getValue("simplifyRemoteVehicles")
	userGameplaySettings.spawnVehicleIgnitionLevel = settings.getValue("spawnVehicleIgnitionLevel")
	userGameplaySettings.skipOtherPlayersVehicles = settings.getValue("skipOtherPlayersVehicles")
end

local function setGameplaySettings(gameplaySettings)
	for setting, value in pairs(gameplaySettings) do
		settings.setValue(setting, value)
	end
end

--Hidden Nametags by Vehicle Model

local hiddens = {
	anticut = "anticut",
	ball = "ball",
	barrels = "barrels",
	barrier = "barrier",
	barrier_plastic = "barrier_plastic",
	blockwall = "blockwall",
	bollard = "bollard",
	boxutility = "boxutility",
	boxutility_large = "boxutility_large",
	cannon = "cannon",
	caravan = "caravan",
	cardboard_box = "cardboard_box",
	cargotrailer = "cargotrailer",
	chair = "chair",
	christmas_tree = "christmas_tree",
	cones = "cones",
	containerTrailer = "containerTrailer",
	couch = "couch",
	crowdbarrier = "crowdbarrier",
	delineator = "delineator",
	dolly = "dolly",
	dryvan = "dryvan",
	engine_props = "engine_props",
	flail = "flail",
	flatbed = "flatbed",
	flipramp = "flipramp",
	frameless_dump = "frameless_dump",
	fridge = "fridge",
	gate = "gate",
	haybale = "haybale",
	inflated_mat = "inflated_mat",
	kickplate = "kickplate",
	large_angletester = "large_angletester",
	large_bridge = "large_bridge",
	large_cannon = "large_cannon",
	large_crusher = "large_crusher",
	large_hamster_wheel = "large_hamster_wheel",
	large_roller = "large_roller",
	large_spinner = "large_spinner",
	large_tilt = "large_tilt",
	large_tire = "large_tire",
	log_trailer = "log_trailer",
	logs = "logs",
	mattress = "mattress",
	metal_box = "metal_box",
	metal_ramp = "metal_ramp",
	piano = "piano",
	porta_potty = "porta_potty",
	pressure_ball = "pressure_ball",
	rallyflags = "rallyflags",
	rallysigns = "rallysigns",
	rallytape = "rallytape",
	roadsigns = "roadsigns",
	rocks = "rocks",
	rollover = "rollover",
	roof_crush_tester = "roof_crush_tester",
	sawhorse = "sawhorse",
	shipping_container = "shipping_container",
	simple_traffic = "simple_traffic",
	spikestrip = "spikestrip",
	steel_coil = "steel_coil",
	streetlight = "streetlight",
	suspensionbridge = "suspensionbridge",
	tanker = "tanker",
	testroller = "testroller",
	tiltdeck = "tiltdeck",
	tirestacks = "tirestacks",
	tirewall = "tirewall",
	trafficbarrel = "trafficbarrel",
	trampoline = "trampoline",
	trashbin = "trashbin",
	tsfb = "tsfb",
	tub = "tub",
	tube = "tube",
	tv = "tv",
	wall = "wall",
	weightpad = "weightpad",
	woodcrate = "woodcrate",
	woodplanks = "woodplanks",
}

--Vehicles and part paints

local function rxCareerVehSync(data)
	if data ~= "null" then
		local vehicleStates = jsonDecode(data)
		local vehicles = MPVehicleGE.getVehicles()
		for serverVehicleID, state in pairs(vehicleStates) do
			if vehicles[serverVehicleID] then
				local gameVehicleID = vehicles[serverVehicleID].gameVehicleID
				if gameVehicleID ~= -1 then
					if not MPVehicleGE.isOwn(gameVehicleID) then
						if not state.active then
							be:getObjectByID(gameVehicleID):setActive(0)
							vehicles[serverVehicleID].hideNametag = true
						else
							be:getObjectByID(gameVehicleID):setActive(1)
							if hiddens[vehicles[serverVehicleID].jbeam] then
								vehicles[serverVehicleID].hideNametag = true
							else
								vehicles[serverVehicleID].hideNametag = false
							end
						end
					end
				end
			end
		end
	end
end

local function onVehicleActiveChanged(gameVehicleID, active)
	if gameVehicleID then
		if MPVehicleGE.isOwn(gameVehicleID) then
			local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID)
			if serverVehicleID then
				local data = {}
				data.active = active
				data.serverVehicleID = serverVehicleID
				TriggerServerEvent("careerVehicleActiveHandler", jsonEncode(data))
			end
		else
			TriggerServerEvent("careerVehSyncRequested", "")
		end
	end
end

local function onVehicleSpawned(gameVehicleID)
	if gameVehicleID then
		local veh = be:getObjectByID(gameVehicleID)
		if veh then
			veh:queueLuaCommand('careerMPEnabler.onVehicleReady()')
		end
		if not MPVehicleGE.isOwn(gameVehicleID) then
			TriggerServerEvent("careerVehSyncRequested", "")
		end
	end
end

local function onVehicleReady(gameVehicleID)
	local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID)
	if serverVehicleID then
		local veh = be:getObjectByID(gameVehicleID)
		if veh then
			if not MPVehicleGE.isOwn(gameVehicleID) then
				local vehicles = MPVehicleGE.getVehicles()
				if clientConfig then
					if veh.JBeam == "unicycle" then
						veh:queueLuaCommand('careerMPEnabler.setUnicycleGhost(' .. tostring(clientConfig.unicycleGhost) .. ')')
					end
					veh:queueLuaCommand('careerMPEnabler.setAllGhost(' .. tostring(clientConfig.allGhost) .. ')')
				end
				if hiddens[veh.JBeam] then
					vehicles[serverVehicleID].hideNametag = true
				else
					vehicles[serverVehicleID].hideNametag = false
				end
			end
			veh:setField('renderDistance', '', 1610)
		end
	end
end

local function onVehicleSwitched(oldGameVehicleID, newGameVehicleID)
	local newVeh = be:getObjectByID(newGameVehicleID)
	local oldVeh = be:getObjectByID(oldGameVehicleID)
	if newVeh then
		if hiddens[newVeh.JBeam] then
			if not MPVehicleGE.isOwn(newGameVehicleID) then
				be:enterNextVehicle(0, 1)
			end
		end
		if newVeh.JBeam == "unicycle" then
			if inComputerMenus then
				gameplay_walk.setWalkingMode(false)
				be:enterVehicle(0, oldVeh)
			end
		end
	end
end

--Traffic Signals and Cameras

local function onSpeedTrapTriggered(speedTrapData, playerSpeed, overSpeed)
	if MPVehicleGE.isOwn(speedTrapData.subjectID) then
		local veh = be:getObjectByID(speedTrapData.subjectID)
		local highscore, leaderboard = gameplay_speedTrapLeaderboards.addRecord(speedTrapData, playerSpeed, overSpeed, veh)
		speedTrapData.licensePlate = veh:getDynDataFieldbyName("licenseText", 0) or "Illegible"
		speedTrapData.vehicleModel = core_vehicles.getModel(veh.JBeam).model.Name
		speedTrapData.playerSpeed = playerSpeed
		speedTrapData.overSpeed = overSpeed
		speedTrapData.highscore = highscore
		speedTrapData.leaderboard = leaderboard
		TriggerServerEvent("speedTrap", jsonEncode( speedTrapData ) )
	end
end

local function onRedLightCamTriggered(redLightData, playerSpeed)
	if MPVehicleGE.isOwn(redLightData.subjectID) then
		local veh = be:getObjectByID(redLightData.subjectID)
		redLightData.licensePlate = veh:getDynDataFieldbyName("licenseText", 0) or "Illegible"
		redLightData.vehicleModel = core_vehicles.getModel(veh.JBeam).model.Name
		redLightData.playerSpeed = playerSpeed
		TriggerServerEvent("redLight", jsonEncode( redLightData ) )
	end
end

local function rxTrafficSignalTimer(data)
	core_trafficSignals.setTimer(tonumber(data))
end

--Garage / Office Computer Handling

local function computerMenuHandler(targetVehicleID)
	if targetVehicleID then
		local veh = be:getObjectByID(targetVehicleID)
		if veh then
			if veh.JBeam ~= "unicycle" then
				if gameplay_walk.isWalking() then
					gameplay_walk.getInVehicle(veh)
				else
					be:enterVehicle(0, veh)
				end
				inComputerMenus = true
			end
		end
	end
end

local function onComputerOpened()
	if inComputerMenus then
		inComputerMenus = false
	end
end

--Patch BeamMP behavior and topBar

local function patchTopBar()
	local entries = ui_topBar.getEntries()
	ui_topBar.removeEntry("environment")
	ui_topBar.removeEntry("mods")
	ui_topBar.removeEntry("vehicleconfig")
	ui_topBar.removeEntry("vehicles")
	entries = ui_topBar.getEntries()
	ui_topBar.updateEntries(entries)
	ui_topBar.updateVisibleItems()
end

local function modifiedGetDriverData(veh)
	if not veh then return nil end
	local caller = debug.getinfo(2).name
	if caller and caller == "getDoorsidePosRot" and veh.mpVehicleType and veh.mpVehicleType == 'R' then
		local id, right = core_camera.getDriverDataById(veh and veh:getID())
		return id, not right
	end
	return core_camera.getDriverDataById(veh and veh:getID())
end

local function modifiedOnUpdate(dt)
	if MPCoreNetwork and MPCoreNetwork.isMPSession() then
		if core_camera.getDriverData ~= modifiedGetDriverData then
			log('W', 'onUpdate', 'Setting modifiedGetDriverData')
			originalGetDriverData = core_camera.getDriverData
			core_camera.getDriverData = modifiedGetDriverData
		end
		if worldReadyState == 0 then
			serverConnection.onCameraHandlerSetInitial()
			extensions.hook('onCameraHandlerSet')
		end
	end
end

local function patchBeamMP()
	if multiplayer_multiplayer then
		if multiplayer_multiplayer.onUpdate ~= modifiedOnUpdate then
			originalMPOnUpdate = multiplayer_multiplayer.onUpdate
			multiplayer_multiplayer.onUpdate = modifiedOnUpdate
		end
	end
end

local function unPatchBeamMP()
	multiplayer_multiplayer.onUpdate = originalMPOnUpdate
	core_camera.getDriverData = originalGetDriverData
end

--Initial Syncs and Updates

local function actionsCheck()
	if not clientConfig.consoleEnabled then
		table.insert(blockedInputActions, "toggleConsoleNG")
		extensions.core_input_actionFilter.setGroup('careerMP', blockedInputActions)
		extensions.core_input_actionFilter.addAction(0, 'careerMP', true)
	elseif clientConfig.consoleEnabled then
		extensions.core_input_actionFilter.setGroup('careerMP', blockedInputActions)
		extensions.core_input_actionFilter.addAction(0, 'careerMP', false)
	end
	if not clientConfig.worldEditorEnabled then
		table.insert(blockedInputActions, "editorToggle")
		table.insert(blockedInputActions, "editorSafeModeToggle")
		table.insert(blockedInputActions, "objectEditorToggle")
		extensions.core_input_actionFilter.setGroup('careerMP', blockedInputActions)
		extensions.core_input_actionFilter.addAction(0, 'careerMP', true)
	elseif clientConfig.worldEditorEnabled then
		extensions.core_input_actionFilter.setGroup('careerMP', blockedInputActions)
		extensions.core_input_actionFilter.addAction(0, 'careerMP', false)
	end
end

local function settingsCheck()
	careerMPTrafficSettings.trafficAllowMods = clientConfig.trafficAllowMods
	careerMPTrafficSettings.trafficSimpleVehicles = clientConfig.trafficSimpleVehicles
	careerMPTrafficSettings.trafficSmartSelections = clientConfig.trafficSmartSelections
	setTrafficSettings(careerMPTrafficSettings)
	careerMPGameplaySettings.simplifyRemoteVehicles = clientConfig.simplifyRemoteVehicles
	careerMPGameplaySettings.spawnVehicleIgnitionLevel = clientConfig.spawnVehicleIgnitionLevel
	careerMPGameplaySettings.skipOtherPlayersVehicles = clientConfig.skipOtherPlayersVehicles
	setGameplaySettings(careerMPGameplaySettings)
end

local function rxCareerSync(data)
	clientConfig = jsonDecode(data)
	nickname = MPConfig.getNickname()
	blockedInputActions = {}
	settingsCheck()
	actionsCheck()
	if not careerMPActive then
		if clientConfig.serverSaveNameEnabled then
			nickname = clientConfig.serverSaveName
		end
		career_career.createOrLoadCareerAndStart(nickname .. clientConfig.serverSaveSuffix, false, false)
		careerMPActive = true
	end
end

local function rxClientConfigUpdate(data)
	clientConfig = jsonDecode(data)
	blockedInputActions = {}
	settingsCheck()
	actionsCheck()
end

local function onCareerActive(active)
	if active and careerMPActive then
		local vehicles = MPVehicleGE.getVehicles()
		for _, vehicle in pairs(vehicles) do
			if vehicle.isLocal then
				if vehicle.jbeam ~= "unicycle" then
					be:getObjectByID(vehicle.gameVehicleID):delete()
				end
			end
		end
	end
end

local function onWorldReadyState(state)
	if state == 2 then
		if not syncRequested then
			TriggerServerEvent("prefabSyncRequested", "")
			TriggerServerEvent("careerSyncRequested", "")
			syncRequested = true
		end
	end
end

local function onClientPostStartMission(levelPath)
	patchTopBar()
end

local function onUpdate(dtReal, dtSim, dtRaw)
	patchBeamMP()
	if worldReadyState == 2 then
		if clientConfig then
			local vehicles = MPVehicleGE.getVehicles()
			for serverVehicleID in pairs(vehicles) do
				local veh = be:getObjectByID(vehicles[serverVehicleID].gameVehicleID)
				if veh then
					if not MPVehicleGE.isOwn(vehicles[serverVehicleID].gameVehicleID) then
						if veh.JBeam == "unicycle" then
							veh:queueLuaCommand(string.format('careerMPEnabler.setGhost(%s)', tostring(clientConfig.remoteUnicycleGhost)))
						else
							veh:queueLuaCommand(string.format('careerMPEnabler.setGhost(%s)', tostring(clientConfig.remoteVehicleGhost)))
						end
					elseif veh.JBeam == "unicycle" then
						veh:queueLuaCommand(string.format('careerMPEnabler.setGhost(%s)', tostring(clientConfig.localUnicycleGhost)))
					end
				end
			end
		end
	end
end

--Loading / Unloading

local function onExtensionLoaded()
	getUserTrafficSettings()
	getUserGameplaySettings()
	AddEventHandler("rxCareerSync", rxCareerSync)
	AddEventHandler("rxClientConfigUpdate", rxClientConfigUpdate)
	AddEventHandler("rxCareerVehSync", rxCareerVehSync)
	AddEventHandler("rxTrafficSignalTimer", rxTrafficSignalTimer)
	career_career = extensions.career_careerMP
	log('W', 'careerMP', 'CareerMP Enabler LOADED!')
end

local function onExtensionUnloaded()
	log('W', 'careerMP', 'CareerMP Enabler UNLOADED!')
end

local function onServerLeave()
	unPatchBeamMP()
	blockedInputActions = {}
	extensions.core_input_actionFilter.setGroup('careerMP', blockedInputActions)
	extensions.core_input_actionFilter.addAction(0, 'careerMP', false)
	setTrafficSettings(userTrafficSettings)
	setGameplaySettings(userGameplaySettings)
end

--Access

M.getClientConfig = getClientConfig

M.onCareerActive = onCareerActive

M.onVehicleActiveChanged = onVehicleActiveChanged
M.onVehicleSpawned = onVehicleSpawned
M.onVehicleReady = onVehicleReady
M.onVehicleSwitched = onVehicleSwitched

M.onSpeedTrapTriggered = onSpeedTrapTriggered
M.onRedLightCamTriggered = onRedLightCamTriggered

M.onComputerOpened = onComputerOpened

M.onCareerTuningStarted = computerMenuHandler
M.onPartShoppingStarted = computerMenuHandler
M.onPerformanceTestStarted = computerMenuHandler
M.onVehiclePaintingUiOpened = computerMenuHandler

M.onClientPostStartMission = onClientPostStartMission

M.onWorldReadyState = onWorldReadyState
M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onServerLeave = onServerLeave

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
