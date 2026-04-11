--CareerMP (CLIENT) by Dudekahedron, 2026

local M = {}

--Setup
local nickname = MPConfig.getNickname()

local clientConfig

local function getClientConfig()
	return clientConfig
end

local careerMPActive = false --one-way switch, set true when we patch the topBar items after everything is loaded
local syncRequested = false --one-way switch, set true when we have sent the sync request to the server

local originalMPOnUpdate --a variable that will eventually hold the original copy of BeamMP's multiplayer_multiplayer.onUpdate() 
local originalGetDriverData --a variable that will eventually hold the original copy of BeamMP's modified core_camera.getDriverData()

--Default Settings Values
local userTrafficSettings = {}
local careerMPTrafficSettings = {
	trafficSmartSelections = false,
	trafficSimpleVehicles = true,
	trafficAllowMods = true
}

local userGameplaySettings = {}
local careerMPGameplaySettings = {
	simplifyRemoteVehicles = false,
	spawnVehicleIgnitionLevel = 0,
	skipOtherPlayersVehicles = false
}

--Hidden Nametags by Vehicle Model
--Names of select spawnable objects that will be looked up to hide multiplayer nametags on, to reduce visual clutter i.e. nametags on traffic and trailers
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

local function rxCareerVehSync(data) --called when activate states of vehicles changed, or provided to a client when joining so the start with the correct active states
	if data ~= "null" then
		local vehicleStates = jsonDecode(data) --decode list of states provided by server
		local vehicles = MPVehicleGE.getVehicles() --get table of vehicles from BeamMP
		for serverVehicleID, state in pairs(vehicleStates) do --look through table of vehicles
			if vehicles[serverVehicleID] then --if we find one
				local gameVehicleID = vehicles[serverVehicleID].gameVehicleID
				if gameVehicleID ~= -1 then --if it's ready, and has a gameVehicleID we can use, -1 means BeamMP can't find it
					if not MPVehicleGE.isOwn(gameVehicleID) then --if it is a remote vehicle
						if not state.active then --if it is not marked as active
							be:getObjectByID(gameVehicleID):setActive(0) --deactivate it
							vehicles[serverVehicleID].hideNametag = true --hide its nametag
						else --if it is marked as active
							be:getObjectByID(gameVehicleID):setActive(1) --set it active
							if hiddens[vehicles[serverVehicleID].jbeam] then --if it is an object that should have the nametag hidden
								vehicles[serverVehicleID].hideNametag = true --hide the nametag
							else
								vehicles[serverVehicleID].hideNametag = false --or don't
							end
						end
					end
				end
			end
		end
	end
end

local function onVehicleActiveChanged(gameVehicleID, active) --called by the base game when a vehicle's active state has changed, given an ID number and active state boolean
	if gameVehicleID then --check nil, you never know
		if MPVehicleGE.isOwn(gameVehicleID) then --if it is a local vehicle
			local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID) --get its server vehicle ID, ("0-0", "0-1", etc)
			if serverVehicleID then --check nil
				local data = {} --table to hold our data
				data.active = active --add active state
				data.serverVehicleID = serverVehicleID --add ID
				TriggerServerEvent("careerVehicleActiveHandler", jsonEncode(data)) --send it to server
			end
		else --if it is a remote vehicle
			TriggerServerEvent("careerVehSyncRequested", "") --tell the server we want an up to date list of active vehicle states
		end
	end
end

local function onVehicleSpawned(gameVehicleID) --called by the base game when a vehicle is spawned
	if gameVehicleID then --check nil, you never know
		local veh = be:getObjectByID(gameVehicleID) --get the vehicle object
		if veh then --check nil
			veh:setField('renderDistance', '', 6969) --set the render distance sufficiently high that you can see players and traffic on the map surface from the bigmap view
			veh:queueLuaCommand('careerMPEnabler.onVehicleReady()') --trigger a vehicle lua event that will call back when the vehicle is ready, AKA you can get the data you might need from it
		end
		if not MPVehicleGE.isOwn(gameVehicleID) then --if it is a remote vehicle
			TriggerServerEvent("careerVehSyncRequested", "") --tell the server we want an up to date list of active vehicle states
		end
	end
end

local function onVehicleReady(gameVehicleID) --called from vehicle lua when the vehicle is ready to be manipulated
	local serverVehicleID = MPVehicleGE.getServerVehicleID(gameVehicleID) --get its server vehicle ID, ("0-0", "0-1", etc)
	if serverVehicleID then --check nil
		if not MPVehicleGE.isOwn(gameVehicleID) then --if it is a remote vehicle
			local vehicles = MPVehicleGE.getVehicles() --get the list of vehicles from BeamMP
			local veh = be:getObjectByID(gameVehicleID) --get the ready vehicle as an object using its gameVehicleID
			if veh.JBeam == "unicycle" then
				if clientConfig then
					if not clientConfig.unicycleCollisionEnabled then
						veh:queueLuaCommand('careerMPEnabler.setUnicycleGhost(' .. tostring(clientConfig.unicycleCollisionEnabled) .. ')')
					end
				end
			end
			if hiddens[veh.JBeam] then --if it is an object that should have the nametag hidden
				vehicles[serverVehicleID].hideNametag = true --hide the nametag
			else
				vehicles[serverVehicleID].hideNametag = false --or don't
			end
		end
	end
end

local function onVehicleSwitched(oldGameVehicleID, newGameVehicleID) --called by the base game when the camera switches from one vehicle to another
	local veh = be:getObjectByID(newGameVehicleID) --get the new vehicle as an object
	if veh then --check nil
		if hiddens[veh.JBeam] then --if it is an object that should have the nametag hidden
			if not MPVehicleGE.isOwn(newGameVehicleID) then --if it is a remote vehicle
				be:enterNextVehicle(0, 1) --switch to the next vehicle, which might call this function again until arriving at a local vehicle
			end
		end
	end
end

--Traffic

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

local function onSpeedTrapTriggered(speedTrapData, playerSpeed, overSpeed) --called by base game when a player drives through a speed trap at sufficiently high speed, we collect the data and sent it to the server, which will broadcast the event to remote clients as a notification
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

local function onRedLightCamTriggered(redLightData, playerSpeed) --called by base game when a player drives through a red light at an intersection with a red light camera, we collect the data and sent it to the server, which will broadcast the event to remote clients as a notification
	if MPVehicleGE.isOwn(redLightData.subjectID) then
		local veh = be:getObjectByID(redLightData.subjectID)
		redLightData.licensePlate = veh:getDynDataFieldbyName("licenseText", 0) or "Illegible"
		redLightData.vehicleModel = core_vehicles.getModel(veh.JBeam).model.Name
		redLightData.playerSpeed = playerSpeed
		TriggerServerEvent("redLight", jsonEncode( redLightData ) )
	end
end

local function rxTrafficSignalTimer(data) --called by the server on an interval, data is a server based time value, this keeps traffic signals for all clients in sync
	core_trafficSignals.setTimer(tonumber(data))
end

local function onCareerActive(active) --when a player loads a save file manually while in a server
	if active and careerMPActive then --if their call of this event happens while CareerMP has been
		local vehicles = MPVehicleGE.getVehicles() --get the vehicles spawned
		for _, vehicle in pairs(vehicles) do
			if vehicle.isLocal then --if it's local, owned by the player
				if vehicle.jbeam ~= "unicycle" then --ignore unicycles so players don't get placed in someone else's car
					be:getObjectByID(vehicle.gameVehicleID):delete() --delete what's leftover
				end
			end
		end
	end
end

--Garage / Office Computer Handling

local function computerMenuHandler(targetVehicleID) --called after a vehicle has been selected in the garage / office computer menu, and then one of the menu items is selected, i.e. picking your vehicle and picking part shopping
	if targetVehicleID then --check nil
		local veh = be:getObjectByID(targetVehicleID) --get vehicle object
		if veh then --check nil, you never know
			if gameplay_walk.isWalking() then --if they're walking
				gameplay_walk.getInVehicle(veh) --enter the vehicle
			else --if they're in a vehicle
				be:enterVehicle(0, veh) --switch to the target vehicle
			end
		end
	end
end

local function onPartShoppingStarted(targetVehicleID)
	computerMenuHandler(targetVehicleID)
end

local function onRepairInGarage(invVehId, targetVehicleID)
	--computerMenuHandler(targetVehicleID)
end

local function onVehicleRepairDelayed(targetVehicleID)
	--computerMenuHandler(targetVehicleID)
end

local function onVehicleRepairInstant(targetVehicleID)
	--computerMenuHandler(targetVehicleID)
end

local function onAfterVehicleRepaired(targetVehicleID)
	--computerMenuHandler(targetVehicleID)
end

local function onCareerTuningStarted(targetVehicleID)
	computerMenuHandler(targetVehicleID)
end

local function onVehiclePaintingUiOpened(targetVehicleID)
	computerMenuHandler(targetVehicleID)
end

local function onPerformanceTestStarted(targetVehicleID)
	computerMenuHandler(targetVehicleID)
end

--Patch BeamMP behavior and topBar

local function patchTopBar() --function to remove entries in the top menu bar because other methods of limiting these items fail
	local entries = ui_topBar.getEntries() --get the topBar entries, remove the ones we know we don't want
	ui_topBar.removeEntry("environment")
	ui_topBar.removeEntry("mods")
	ui_topBar.removeEntry("vehicleconfig")
	ui_topBar.removeEntry("vehicles")
	entries = ui_topBar.getEntries() --making sure this reflects our removals
	ui_topBar.updateEntries(entries) --update the entries
	ui_topBar.updateVisibleItems() --update the topBar items' visibilities
end

local function modifiedGetDriverData(veh) --copy of MP's modified getDriverData function, we need this unchanged when patching MP's multiplayer_multiplayer.onUpdate
	if not veh then return nil end
	local caller = debug.getinfo(2).name
	if caller and caller == "getDoorsidePosRot" and veh.mpVehicleType and veh.mpVehicleType == 'R' then
		local id, right = core_camera.getDriverDataById(veh and veh:getID())
		return id, not right
	end
	return core_camera.getDriverDataById(veh and veh:getID())
end

local function modifiedOnUpdate(dt) --a modified version of MP's multiplayer_multiplayer.onUpdate() function to comment out unicycle deletion
	if MPCoreNetwork and MPCoreNetwork.isMPSession() then
		if core_camera.getDriverData ~= modifiedGetDriverData then
			log('W', 'onUpdate', 'Setting modifiedGetDriverData')
			originalGetDriverData = core_camera.getDriverData
			core_camera.getDriverData = modifiedGetDriverData
		end
		--if gameplay_walk and gameplay_walk.toggleWalkingMode ~= modifiedToggleWalkingMode then
			--log('W', 'onUpdate', 'Setting modifiedToggleWalkingMode')
			--originalToggleWalkingMode = gameplay_walk.toggleWalkingMode
			--gameplay_walk.toggleWalkingMode = modifiedToggleWalkingMode
		--end
		if worldReadyState == 0 then
			serverConnection.onCameraHandlerSetInitial()
			extensions.hook('onCameraHandlerSet')
		end
	end
end

local function patchBeamMP() --replace MP's multiplayer_multiplayer.onUpdate() with one that does not delete unicycles
	if multiplayer_multiplayer then
		if multiplayer_multiplayer.onUpdate ~= modifiedOnUpdate then
			originalMPOnUpdate = multiplayer_multiplayer.onUpdate
			multiplayer_multiplayer.onUpdate = modifiedOnUpdate
		end
	end
end

local function unPatchBeamMP() --probably does nothing! but if the extension truly does unload correctly, this should make sure there are no issues if the player continues using beammp on other servers
	multiplayer_multiplayer.onUpdate = originalMPOnUpdate
	core_camera.getDriverData = originalGetDriverData
end

--Initial Syncs and Updates

local function rxCareerSync(data) --the client has told the server it is ready, and the server has acknowledged by triggering this event
	clientConfig = jsonDecode(data)
	nickname = MPConfig.getNickname()
	if not careerMPActive then --if we havn't activated career yet and so we haven't marked careerMPActive true
		career_career.createOrLoadCareerAndStart(nickname .. clientConfig.serverSaveSuffix, false, false) --trigger career to start
		careerMPActive = true --mark careerMPActive true
	end
end

local function onWorldReadyState(state) --called by the base game when the level has finished loading, at the moment that objects are spawning, before the loading screen has faded out
	if state == 2 then --final state
		if not syncRequested then --if the client has not requested a sync
			TriggerServerEvent("prefabSyncRequested", "") --request a prefab sync from the server
			TriggerServerEvent("careerSyncRequested", "") --request a career sync from the server
			syncRequested = true --mark syncRequested true
		end
	end
end

local function onClientPostStartMission(levelPath) --called by base game once the loading screen has begun to fade and control has been given to the player
	patchTopBar() --patch the top bar to remove freeroam menu items
end

local function onUpdate(dtReal, dtSim, dtRaw) --called by base game every update
	if worldReadyState == 2 then --if the level is loaded
		patchBeamMP() --patch BeamMP's unicycle deletion
		if clientConfig then
			local vehicles = MPVehicleGE.getVehicles()
			for serverVehicleID in pairs(vehicles) do
				local veh = be:getObjectByID(vehicles[serverVehicleID].gameVehicleID)
				if veh then
					if veh.JBeam == "unicycle" then
						veh:queueLuaCommand('careerMPEnabler.setUnicycleGhost(' .. tostring(clientConfig.unicycleCollisionEnabled) .. ')')
					end
				end
			end
		end
	end
end

--Loading / Unloading

local function onExtensionLoaded() --called by the base game when the extension loads, good place to setup MP event handlers
	getUserTrafficSettings()
	setTrafficSettings(careerMPTrafficSettings)
	getUserGameplaySettings()
	setGameplaySettings(careerMPGameplaySettings)
	AddEventHandler("rxCareerSync", rxCareerSync)
	AddEventHandler("rxCareerVehSync", rxCareerVehSync)
	AddEventHandler("rxTrafficSignalTimer", rxTrafficSignalTimer)
	career_career = extensions.career_careerMP --replace stock career lua with my modified careerMP lua
	log('W', 'careerMP', 'CareerMP Enabler LOADED!')
end

local function onExtensionUnloaded()
	setTrafficSettings(userTrafficSettings)
	setGameplaySettings(userGameplaySettings)
	log('W', 'careerMP', 'CareerMP Enabler UNLOADED!')
end

local function onServerLeave()
	unPatchBeamMP()
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

M.onCareerTuningStarted = onCareerTuningStarted
M.onPartShoppingStarted = onPartShoppingStarted
M.onPerformanceTestStarted = onPerformanceTestStarted
M.onRepairInGarage = onRepairInGarage
M.onVehicleRepairDelayed = onVehicleRepairDelayed
M.onVehicleRepairInstant = onVehicleRepairInstant
M.onAfterVehicleRepaired = onAfterVehicleRepaired
M.onVehiclePaintingUiOpened = onVehiclePaintingUiOpened

M.onClientPostStartMission = onClientPostStartMission

M.onWorldReadyState = onWorldReadyState
M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onServerLeave = onServerLeave

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
