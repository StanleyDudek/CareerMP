--CareerMP (CLIENT) by Dudekahedron, 2026

local M = {}

--Setup
local nickname = MPConfig.getNickname()

local careerMPActive = false --one-way switch, set true when we patch the topBar items after everything is loaded
local syncRequested = false --one-way switch, set true when we have sent the sync request to the server

local prefabsTable = {} --this will hold data about prefabs that have been synced 

local iterT = {} --a table to iterate
local iterC = 0 --a counter to increment, used to iterate the iterT table

local originalMPOnUpdate --a variable that will eventually hold the original copy of BeamMP's multiplayer_multiplayer.onUpdate() 
local originalGetDriverData --a variable that will eventually hold the original copy of BeamMP's modified core_camera.getDriverData()

local vehicleTooClose = false
local physicsActive = false
local physicsComplete = false
local physicsTimeout = 0
local physicsTimeoutThreshold = 1
local firstPhysicsTimeout = 0
local firstPhysicsTimeoutThreshold = 5

local missionUIToResolve = false

--Manually setup names of prefabs, from ...\BeamNG.drive\gameplay\
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

--Paths
local defaultAppLayoutDirectory = "settings/ui_apps/originalLayouts/default/"
local missionAppLayoutDirectory = "settings/ui_apps/originalLayouts/mission/"
local userDefaultAppLayoutDirectory = "settings/ui_apps/layouts/default/"
local userMissionAppLayoutDirectory = "settings/ui_apps/layouts/mission/"

--Default Settings Values
local userTrafficSettings = {}
local freeRoamMPTrafficSettings = {
	trafficAmount = 2,
	trafficExtraAmount = 0,
	trafficExtraVehicles = false,
	trafficParkedAmount = 0,
	trafficParkedVehicles = false,
	trafficLoadForFreeroam = false,
	trafficSmartSelections = false,
	trafficSimpleVehicles = true,
	trafficAllowMods = true,
	trafficEnableSwitching = false,
	trafficMinimap = true
}

local userGameplaySettings = {}
local freeRoamMPGameplaySettings = {
	simplifyRemoteVehicles = false
}

--UI Layouts
local stateToUpdate --a variable to hold a state name to look up which UI app layout to inject MP UI apps into

--Manually setup names of default UI app layouts, from ...\BeamNG.drive\settings\ui_apps\originalLayouts\default\
local defaultLayouts = {
	busRouteScenario = { filename = "busRouteScenario" },
	busStuntMinSpeed = { filename = "busStuntMinSpeed" },
	career = { filename = "career" },
	careerBigMap = { filename = "careerBigMap" },
	careerMission = { filename = "careerMission" },
	careerMissionEnd = { filename = "careerMissionEnd" },
	careerPause = { filename = "careerPause" },
	careerRefuel = { filename = "careerRefuel" },
	collectionEvent = { filename = "collectionEvent" },
	crawl = { filename = "crawl" },
	damageScenario = { filename = "damageScenario" },
	dderbyScenario = { filename = "dderbyScenario" },
	discover = { filename = "discover" },
	driftScenario = { filename = "driftScenario" },
	exploration = { filename = "exploration" },
	externalui = { filename = "externalUI" },
	freeroam = { filename = "freeroam" },
	garage = { filename = "garage" },
	garage_v2 = { filename = "garage_v2" },
	multiseatscenario = { filename = "multiseatscenario" },
	noncompeteScenario = { filename = "noncompeteScenario" },
	offroadScenario = { filename = "offroadScenario" },
	proceduralScenario = { filename = "proceduralScenario" },
	quickraceScenario = { filename = "quickraceScenario" },
	radial = { filename = "radial" },
	scenario = { filename = "scenario" },
	scenario_cinematic_start = { filename = "scenario_cinematic_start" },
	singleCheckpointScenario = { filename = "singleCheckpointScenario" },
	tasklist = { filename = "tasklist" },
	tasklistTall = { filename = "tasklistTall" },
	unicycle = { filename = "unicycle" }
}

--Manually setup names of mission UI app layouts, from ...\BeamNG.drive\settings\ui_apps\originalLayouts\mission\
local missionLayouts = {
	aRunForLifeMission = { filename = "aRunForLife" },
	basicMissionLayout = { filename = "basicMission" },
	crashTestMission = { filename = "crashTestMission" },
	crawlMission = { filename = "crawlMission" },
	dragMission = { filename = "dragMission" },
	driftMission = { filename = "driftMission" },
	driftNavigationMission = { filename = "driftNavigationMission" },
	evadeMission = { filename = "evadeMission" },
	garageToGarageMission = { filename = "garageToGarage" },
	rallyModeLoop = { filename = "rallyModeLoop" },
	rallyModeLoopStage = { filename = "rallyModeLoopStage" },
	rallyModeRecce = { filename = "rallyModeRecce" },
	rallyModeStage = { filename = "rallyModeStage" },
	scenarioMission = { filename = "scenarioMission" },
	timeTrialMission = { filename = "timeTrialMission" }
}

--a copy of the multiplayer UI apps data, to inject into a UI app layout, if they are not found
local multiplayerApps = {
	multiplayerchat = {
		appName = "multiplayerchat",
		placement = {
			width = "550px",
			bottom = "0px",
			height = "170px",
			left = "180px"
		}
	},
	multiplayersession = {
		appName = "multiplayersession",
		placement = {
			bottom = "",
			height = "40px",
			left = 0,
			margin = "auto",
			position = "absolute",
			right = 0,
			top = "0px",
			width = "700px"
		}
	},
	multiplayerplayerlist = {
		appName = "multiplayerplayerlist",
		placement = {
			bottom = "",
			height = "560px",
			left = "",
			position = "absolute",
			right = "0px",
			top = "30px",
			width = "300px"
		}
	}
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

--Drag Race Displays, most of the folllowing is ripped from the base game to duplicate the behavior in MP
local dragData --variable to hold collected drag data to apply to the local client when a remote client does drag races

local driverLightBlinkState = {
	lane = nil,
	isBlinking = false,
	timer = 0,
	frequency = 1/6,
	isOn = false
}

local function findLightObject(name, prefabId)
	if prefabId then
		local prefabInstance = scenetree.findObjectById(prefabId)
		if prefabInstance then
			local obj = prefabInstance:findObject(name)
			if obj then
				return obj
			end
		end
	end
	return scenetree.findObject(name)
end

local function createTreeLights(lane, prefabId)
	return {
		stageLights = {
			prestageLight  = {obj = findLightObject("Prestagelight_" .. lane, prefabId),       anim = "prestage", isOn = false},
			stageLight     = {obj = findLightObject("Stagelight_" .. lane, prefabId),          anim = "prestage", isOn = false},
			winnerLight    = {obj = findLightObject("WinLight_Timeboard_" .. lane, prefabId),  anim = "prestage", isOn = false},
			driverLight    = {obj = findLightObject("WinLight_Driver_" .. lane, prefabId),     anim = "prestage", isOn = false},
		},
		countDownLights = {
			amberLight1    = {obj = findLightObject("Amberlight1_" .. lane, prefabId), anim = "tree", isOn = false},
			amberLight2    = {obj = findLightObject("Amberlight2_" .. lane, prefabId), anim = "tree", isOn = false},
			amberLight3    = {obj = findLightObject("Amberlight3_" .. lane, prefabId), anim = "tree", isOn = false},
			greenLight     = {obj = findLightObject("Greenlight_" .. lane, prefabId),  anim = "tree", isOn = false},
			redLight       = {obj = findLightObject("Redlight_" .. lane, prefabId),    anim = "tree", isOn = false},
		},
		globalLights = {
			blueLight = {obj = findLightObject("BlueLight", prefabId), anim = "prestage", isOn = false},
		},
		timers = {
			dialOffset = 0,
			laneTimer = 0,
			laneTimerFlag = false
		}
	}
end

local function initTree()
	local prefabId = nil
	if dragData and dragData.prefabs and dragData.prefabs.christmasTree then
		prefabId = dragData.prefabs.christmasTree.prefabId
	end

	local treeLights = {}
	for laneIndex = 1, #dragData.strip.lanes do
		treeLights[laneIndex] = createTreeLights(laneIndex, prefabId)
	end
	return treeLights
end

local function updateTreeLightsUI(vehId, changes)
	if not changes then
		return
	end
	if not vehId then
		guihooks.trigger("updateTreeLightApp", changes)
	end
end

local function initDisplay()
	local displayDigits = {
		timeDigits = {},
		speedDigits = {}
	}
	local time = {}
	local speed = {}
	for i=1, 5 do
		local timeDigit = scenetree.findObject("display_time_" .. i .. "_r")
		table.insert(time, timeDigit)

		local speedDigit = scenetree.findObject("display_speed_" .. i .. "_r")
		table.insert(speed, speedDigit)
	end
	table.insert(displayDigits.timeDigits, time)
	table.insert(displayDigits.speedDigits, speed)

	time = {}
	speed = {}

	for i=1, 5 do
		local timeDigit = scenetree.findObject("display_time_" .. i .. "_l")
		table.insert(time, timeDigit)

		local speedDigit = scenetree.findObject("display_speed_" .. i .. "_l")
		table.insert(speed, speedDigit)
	end
	table.insert(displayDigits.timeDigits, time)
	table.insert(displayDigits.speedDigits, speed)

	if not displayDigits then
		return
	end
	return displayDigits
end

local function clearLights()
	if not dragData then
		return
	end
	for _, laneTree in ipairs(dragData.strip.treeLights) do
		for _,group in pairs(laneTree) do
			if type(group) == "table" then
				for _,light in pairs(group) do
					if type(light) == "table" and light.obj then
						light.obj:setHidden(true)
						light.isOn = false
					end
				end
			end
		end
		laneTree.timers.laneTimer = 0
		laneTree.timers.laneTimerFlag = false
		laneTree.timers.dialOffset = 0
	end
	updateTreeLightsUI(nil, {
		stageLights = {
			prestageLight = false,
			stageLight = false
		},
		countDownLights = {
			amberLight1 = false,
			amberLight2 = false,
			amberLight3 = false,
			greenLight = false,
			redLight = false
		},
		globalLights = {
			blueLight = false
		}
	})
	driverLightBlinkState = {
		lane = nil,
		isBlinking = false,
		timer = 0,
		frequency = 1/6,
		isOn = false
	}
end

local function clearDisplay()
	if not dragData then
		return
	end
	for _, digitTypeData in pairs(dragData.strip.displayDigits) do
		for _,laneTypeData in ipairs(digitTypeData) do
			for _,digit in ipairs(laneTypeData) do
				digit:setHidden(true)
			end
		end
	end
end

local function manageDragLights(dtSim)
	if driverLightBlinkState.isBlinking then
		if dragData then
			local driverLight = dragData.strip.treeLights[driverLightBlinkState.lane].stageLights.driverLight
			driverLight.obj = findLightObject("WinLight_Driver_" .. driverLightBlinkState.lane, dragData.prefabs.christmasTree.prefabId)
			if driverLight and driverLight.obj then
				local newTimer = driverLightBlinkState.timer + dtSim
				if newTimer >= driverLightBlinkState.frequency then
					driverLightBlinkState.timer = newTimer % driverLightBlinkState.frequency
					driverLightBlinkState.isOn = not driverLightBlinkState.isOn
					driverLight.obj:setHidden(not driverLightBlinkState.isOn)
				else
					driverLightBlinkState.timer = newTimer
				end
			else
				driverLightBlinkState.isBlinking = false
				driverLightBlinkState.isOn = false
			end
		end
	end
end

--Drag data receive functions

local function rxUpdateDisplay(data) --called when a drag display has changed on a remote client, this sets the drag displays of local clients 
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	if dragData then
		dragData.strip.displayDigits = initDisplay()
		dragData.strip.treeLights = initTree()
		guihooks.trigger('updateTreeLightStaging', true)
	end
	local timeDisplayValue = decodedData.timeDisplayValue
	local speedDisplayValue = decodedData.speedDisplayValue
	local timeDigits
	local speedDigits
	local lane = decodedData.lane
	timeDigits = dragData.strip.displayDigits.timeDigits[lane]
	speedDigits = dragData.strip.displayDigits.speedDigits[lane]
	if #timeDisplayValue > 0 and #timeDisplayValue < 6 then
		for i,v in ipairs(timeDisplayValue) do
			timeDigits[i]:preApply()
			timeDigits[i]:setField('shapeName', 0, "art/shapes/quarter_mile_display/display_".. v ..".dae")
			timeDigits[i]:setHidden(false)
			timeDigits[i]:postApply()
		end
	end
	for i,v in ipairs(speedDisplayValue) do
		if speedDigits and speedDigits[i] then
			speedDigits[i]:preApply()
			speedDigits[i]:setField('shapeName', 0, "art/shapes/quarter_mile_display/display_".. v ..".dae")
			speedDigits[i]:setHidden(false)
			speedDigits[i]:postApply()
		end
	end
end

local function rxUpdateWinnerLight(data) --similar to the above, for when the winner light flashes
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	driverLightBlinkState = decodedData.driverLightBlinkState
	local lane = driverLightBlinkState.lane
	local prefabId = dragData.prefabs.christmasTree.prefabId
	dragData.strip.treeLights[lane].stageLights.winnerLight.obj = findLightObject("WinLight_Timeboard_" .. lane, prefabId)
	dragData.strip.treeLights[lane].stageLights.driverLight.obj = findLightObject("WinLight_Driver_" .. lane, prefabId)
	if lane then
		if dragData.strip.treeLights[lane].stageLights.winnerLight and dragData.strip.treeLights[lane].stageLights.winnerLight.obj then
			dragData.strip.treeLights[lane].stageLights.winnerLight.isOn = true
			dragData.strip.treeLights[lane].stageLights.winnerLight.obj:setHidden(false)
		end
		if dragData.strip.treeLights[lane].stageLights.driverLight and dragData.strip.treeLights[lane].stageLights.driverLight.obj and not driverLightBlinkState.isBlinking then
			dragData.strip.treeLights[lane].stageLights.driverLight.isOn = true
			driverLightBlinkState.lane = lane
			driverLightBlinkState.isBlinking = true
			driverLightBlinkState.timer = 0
		end
	end
end

local function rxClearAll() --received when a remote client's drag data have been cleared, so the local drag data clear
	if not dragData then
		dragData = gameplay_drag_general.getData()
		return
	end
	local prefabId = dragData.prefabs.christmasTree.prefabId
	for i = 1, 2 do
		local winnerLightObj = findLightObject("WinLight_Timeboard_" .. i, prefabId)
		local driverLightObj = findLightObject("WinLight_Driver_" .. i, prefabId)
		winnerLightObj:setHidden(true)
		driverLightObj:setHidden(true)
	end
	clearLights()
  	clearDisplay()
	gameplay_drag_general.unloadRace()
end

--Vehicles

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

local function getUserGameplaySettings()
	userGameplaySettings.simplifyRemoteVehicles = settings.getValue("simplifyRemoteVehicles")
end

local function setGameplaySettings(gameplaySettings)
	for setting, value in pairs(gameplaySettings) do
		settings.setValue(setting, value)
	end
end

local function getUserTrafficSettings()
	userTrafficSettings.trafficAmount = settings.getValue('trafficAmount')
	userTrafficSettings.trafficExtraAmount = settings.getValue('trafficExtraAmount')
	userTrafficSettings.trafficExtraVehicles = settings.getValue('trafficExtraVehicles')
	userTrafficSettings.trafficParkedAmount = settings.getValue('trafficParkedAmount')
	userTrafficSettings.trafficParkedVehicles = settings.getValue('trafficParkedVehicles')
	userTrafficSettings.trafficLoadForFreeroam = settings.getValue('trafficLoadForFreeroam')
	userTrafficSettings.trafficSmartSelections = settings.getValue('trafficSmartSelections')
	userTrafficSettings.trafficSimpleVehicles = settings.getValue('trafficSimpleVehicles')
	userTrafficSettings.trafficAllowMods = settings.getValue('trafficAllowMods')
	userTrafficSettings.trafficEnableSwitching = settings.getValue('trafficEnableSwitching')
	userTrafficSettings.trafficMinimap = settings.getValue('trafficMinimap')
end

local function setTrafficSettings(trafficSettings)
	for setting, value in pairs(trafficSettings) do
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

--Prefabs

local function addPrefabEntry(name, path, outdated) --insert lookup data about a prefab into prefabsTable
	prefabsTable[name] = {
		path = path,
		outdated = outdated
	}
end

local function checkPrefab(prefabData, baseName, userSettings) --figure out if the prefab is outdated
	local fullJson = string.format("%s/%s.prefab.json", prefabData.pPath, baseName) --matching modern *.prefab.json format
	local fullLegacy = string.format("%s/%s.prefab", prefabData.pPath, baseName) --matching outdated *.prefab format
	local prefabKey = prefabData.pName .. baseName:gsub("Prefab", ""):gsub("%-", "") --prefab name that will become a key for this prefab in the prefabsTable
	local outdated, exists = false, FS:fileExists(fullJson)
	if not exists then --if the file does not exist by looking for the *.prefab.json format
		outdated = true --it might exist but be outdate
		exists = FS:fileExists(fullLegacy) --check if the outdated format exists by this name
		if not exists then --still found nothing so just give up
			return
		end
	end
	--some prefabs have forward and reverse layouts, since both are present and we only want to load one at a time, we will return from this function early on a mismatch
	if baseName == "forwardPrefab" and userSettings.reverse then
		return
	end
	if baseName == "reversePrefab" and not userSettings.reverse then
		return
	end
	addPrefabEntry(prefabKey, exists and (outdated and fullLegacy or fullJson), outdated) --send this prefab data to be entered in the prefabsTable
end

local function removeAllPrefabs(pName) --unloads all loaded prefabs
	for _, base in pairs(prefabNames) do --look through all prefab names
		local key = pName .. base:gsub("Prefab", ""):gsub("%-", "") --build a key from the prefab's name
		if scenetree.findObject(key) then --if we find that object by name in the scene tree
			removePrefab(key) --remove it
		end
	end
	be:reloadCollision() --reload collision
end

local function rxPrefabSync(data) --called by server for a local client when they fisrt join the server or a remote client loads a prefab
	if not data or data == "null" then --if we get no data here, just return
		return
	end
	local prefabData = jsonDecode(data) --decode the prefabData
	local userSettings = prefabData.pSettings
	if prefabData.pLoad then --if this prefab is marked to be loaded
		for _, base in ipairs(prefabNames) do --look through the prefab names for a match
			checkPrefab(prefabData, base, userSettings) --check if the prefab is outdated
		end
	else --if this prefab is not marked to be loaded, remove it
		removePrefab(prefabData.pName)
		removeAllPrefabs(prefabData.pName)
	end
end

local function readPrefab(path) --file system read
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*all")
	f:close()
	return content
end

local function writePrefab(path, content) --file system write
	local f = io.open(path, "w+")
	if not f then
		return
	end
	f:write(content)
	f:close()
end

local function cleanPrefab(content) --remove physics objects from the prefab to be spawned on the remote client
	local result = "" --empty string where result will be built
	local inSep = 1 --input separator begins at index 1
	for _ = 1, #content do --iterate through the prefab's content
		local outSep = content:find("}\n", inSep) --locate the output separator
		if not outSep then --if we don't find one, break out of this loop
			break
		end
		local block = content:sub(inSep, outSep) --the block will be the content between the two separators that we want
		inSep = content:find("{", outSep) --the input separator is move to the start of the next block to find
		if not block:find("BeamNGVehicle", 1) then --if we do not find the string "BeamNGVehicle" in this block
			result = result .. block .. "\n" --enter this block into the result, inserting a newline character
		end
		if not inSep then --if no input separator because we have reached the end of content, then break out of the loop
			break
		end
	end
	return result --after cleaning the prefab return it
end

local function cleanPrefabOutdated(content) --remove physics objects from the outdate prefab to be spawned on the remote client, primary difference is the pattern matching
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

local function processPrefab(path, name, outdated) --called whenever there are entries in the prefabsTable
	local content = readPrefab(path) --get the content given the path
	if not content then --check nil
		return
	end
	local cleanedPrefab = not outdated and cleanPrefab(content) or cleanPrefabOutdated(content) --clean it with the appropriate cleaning function
	if cleanedPrefab then --check nil
		local ext = not outdated and ".prefab.json" or ".prefab" --choose the correct file extension
		local tempPath = "settings/BeamMP/tempPrefab" .. name .. ext --this beammp path was chosen because I don't want to put prefabs in a location in the user folder that might inadvertently get loaded or used somehow
		writePrefab(tempPath, cleanedPrefab) --write cleaned prefab into the above path
		spawnPrefab(name, tempPath, "0 0 0", "0 0 1", "1 1 1") --spawn that cleaned prefab
	end
end

local function onAnyMissionChanged(state, mission) --called by base game, we use this to determine when to unload a prefab, and then tell the server
	if state == "stopped" then --if the mission state is stopped
		local prefab = {} --collect some prefab data
		prefab.pName = mission.missionType .. "-" .. tostring(iterT[mission.missionType]) --build the prefab name to use
		prefab.pLoad = false --mark it to be unloaded
		local data = jsonEncode(prefab) --encode the data
		TriggerServerEvent("careerPrefabSync", data) --send it to server
	end
end

local function onMissionStartWithFade(mission, userSettings) --called by base game, we use this to determine when to load a prefab, and then tell the server
	local prefab = {} --collect some prefab data
	iterT[mission.missionType] = iterC --keeping track of loaded prefabs in our iterT
	prefab.pName = mission.missionType .. "-" .. tostring(iterT[mission.missionType]) --build the prefab name to use
	prefab.pPath = mission.missionFolder --grab the path
	prefab.pSettings = userSettings --grab the settings
	prefab.pLoad = true --mark it to be loaded
	local data = jsonEncode(prefab) --encode the data
	TriggerServerEvent("careerPrefabSync", data) --send it to server
	iterC = iterC + 1 --increase our counter
end

--State and UI Apps

local function checkUIApps(state) --this extremely verbose and probably redundant, etc, but it works, whenever a state changes, we get the current ui apps layout and make sure the multiplayer ui apps are present.
	local originalMpLayout = jsonReadFile(userDefaultAppLayoutDirectory .. "multiplayer.uilayout.json")
	local currentMpLayout = deepcopy(originalMpLayout)
	if currentMpLayout then
		for _, app in pairs(currentMpLayout.apps) do
			if app.appName == "multiplayerchat" then
				multiplayerApps.multiplayerchat = app
			end
			if app.appName == "multiplayersession" then
				multiplayerApps.multiplayersession = app
			end
			if app.appName == "multiplayerplayerlist" then
				multiplayerApps.multiplayerplayerlist = app
			end
		end
	end
	local found
	if defaultLayouts[state.appLayout] then
		local customLayout = jsonReadFile(userDefaultAppLayoutDirectory .. defaultLayouts[state.appLayout].filename .. ".uilayout.json")
		local defaultLayout
		local currentLayout
		if customLayout then
			currentLayout = deepcopy(customLayout)
		else
			defaultLayout = jsonReadFile(defaultAppLayoutDirectory .. defaultLayouts[state.appLayout].filename .. ".uilayout.json")
			currentLayout = deepcopy(defaultLayout)
		end
		if currentLayout then
			for _, app in pairs(currentLayout.apps) do
				if app.appName == "multiplayerchat" then
					found = true
				end
			end
			if not found then
				table.insert(currentLayout.apps, multiplayerApps.multiplayerchat)
				stateToUpdate = true
			end
			for _, app in pairs(currentLayout.apps) do
				if app.appName == "multiplayersession" then
					found = true
				end
			end
			if not found then
				table.insert(currentLayout.apps, multiplayerApps.multiplayersession)
				stateToUpdate = true
			end
			for _, app in pairs(currentLayout.apps) do
				if app.appName == "multiplayerplayerlist" then
					found = true
				end
			end
			if not found then
				table.insert(currentLayout.apps, multiplayerApps.multiplayerplayerlist)
				stateToUpdate = true
			end
		end
		if stateToUpdate then
			jsonWriteFile(userDefaultAppLayoutDirectory .. defaultLayouts[state.appLayout].filename .. ".uilayout.json", currentLayout, 1)
		end
	elseif missionLayouts[state.appLayout] then
		local customLayout = jsonReadFile(userMissionAppLayoutDirectory .. missionLayouts[state.appLayout].filename .. ".uilayout.json")
		local missionLayout
		local currentLayout
		if customLayout then
			currentLayout = deepcopy(customLayout)
		else
			missionLayout = jsonReadFile(missionAppLayoutDirectory .. missionLayouts[state.appLayout].filename .. ".uilayout.json")
			currentLayout = deepcopy(missionLayout)
		end
		if currentLayout then
			for _, app in pairs(currentLayout.apps) do
				if app.appName == "multiplayerchat" then
					found = true
				end
			end
			if not found then
				table.insert(currentLayout.apps, multiplayerApps.multiplayerchat)
				stateToUpdate = true
			end
			for _, app in pairs(currentLayout.apps) do
				if app.appName == "multiplayersession" then
					found = true
				end
			end
			if not found then
				table.insert(currentLayout.apps, multiplayerApps.multiplayersession)
				stateToUpdate = true
			end
			for _, app in pairs(currentLayout.apps) do
				if app.appName == "multiplayerplayerlist" then
					found = true
				end
			end
			if not found then
				table.insert(currentLayout.apps, multiplayerApps.multiplayerplayerlist)
				stateToUpdate = true
			end
		end
		if stateToUpdate then
			jsonWriteFile(userMissionAppLayoutDirectory .. missionLayouts[state.appLayout].filename .. ".uilayout.json", currentLayout, 1)
		end
	end
end

local function onGameStateUpdate(state) --called by the base game any time the gamestate changes
	if missionUIToResolve and state.appLayout == "freeroam" then
		core_gamestate.setGameState("career", "career", nil)
		missionUIToResolve = false
	end
	if not state.appLayout:find("career") then
		missionUIToResolve = true
	end
	checkUIApps(state) --whenever a state changes, make sure multiplayer UI apps are present in the UI app layout
	if state.state == "career" then --if the state is changed to career
		
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
	be:setDynamicCollisionEnabled(false)
	physicsActive = false
	physicsComplete = false
end

local function onWorldReadyState(state) --called by the base game when the level has finished loading, at the moment that objects are spawning, before the loading screen has faded out
	if state == 2 then --final state
		nickname = MPConfig.getNickname()
		if not syncRequested then --if the client has not requested a sync
			if not careerMPActive then --if we havn't activated career yet and so we haven't marked careerMPActive true
				career_career.createOrLoadCareerAndStart(nickname, false, false) --trigger career to start
				careerMPActive = true --mark careerMPActive true
			end
			TriggerServerEvent("prefabSyncRequested", "") --request a prefab sync from the server
			TriggerServerEvent("careerSyncRequested", "") --request a career sync from the server
			syncRequested = true --mark syncRequested true
		end
	end
end

local function onClientPostStartMission(levelPath) --called by base game once the loading screen has begun to fade and control has been given to the player
	patchTopBar() --patch the top bar to remove freeroam menu items
end

local function getObjectRadius(id)
    local x, y, z = be:getObjectOOBBHalfExtentsXYZ(id)
    return math.sqrt(x * x + y * y + z * z)
end

local function callback(id, distance)
    local playerID = be:getPlayerVehicleID(0)
    if id ~= playerID then
        local safetyMargin = 1
        local playerRadius = getObjectRadius(playerID)
        local otherRadius = getObjectRadius(id)
        vehicleTooClose = distance < (playerRadius + otherRadius + safetyMargin)
    end
end

local function onUpdate(dtReal, dtSim, dtRaw) --called by base game every update
	patchBeamMP() --patch BeamMP's unicycle deletion
	if worldReadyState == 2 then --if the level is loaded
		manageDragLights(dtSim) --handle drag lights
		for name, data in pairs(prefabsTable) do --check if there are any prefabs to handle
			processPrefab(data.path, name, data.outdated)
			prefabsTable[name] = nil
			be:reloadCollision()
			break
		end
		if stateToUpdate then --if we need to handle a new ui app layout
			ui_apps.requestUIAppsData() --refresh the ui apps
			stateToUpdate = false --set to false until next change
		end
		local playerID = be:getPlayerVehicleID(0)
		local vehicles = MPVehicleGE.getVehicles()
		local playerVehicle = be:getObjectByID(playerID)
		local playerPos = playerVehicle and vec3(playerVehicle:getPosition()) or vec3()
		if vehicleTooClose and not physicsComplete then
			physicsTimeout = 0
			local cameraPos = commands.isFreeCamera() and vec3(core_camera.getPosition()) or playerPos
			for _, vehicle in pairs(vehicles) do
				if vehicle.isLocal or not vehicle:getOwner() then
					goto continue
				end
				local obj = be:getObjectByID(vehicle.gameVehicleID)
				if obj then
					local fadeDist = cameraPos:distance(vec3(be:getObjectOOBBCenterXYZ(vehicle.gameVehicleID)))
					local fadeRadius = getObjectRadius(playerID) + getObjectRadius(vehicle.gameVehicleID) + 1
					obj:setMeshAlpha(playerID == vehicle.gameVehicleID and 1 or 1 - clamp(linearScale(fadeDist, fadeRadius, 0, 0, 1), 0, 1), "", false)
				end
				::continue::
			end
		end
		firstPhysicsTimeout = firstPhysicsTimeout + dtReal
		if firstPhysicsTimeout < firstPhysicsTimeoutThreshold then
			be:setDynamicCollisionEnabled(false)
			physicsActive = false
			physicsComplete = false
		end
		if physicsActive then
			physicsTimeout = physicsTimeout + dtReal
			if physicsTimeout >= physicsTimeoutThreshold and not physicsComplete and not vehicleTooClose then
				be:setDynamicCollisionEnabled(true)
				physicsComplete = true
				vehicleTooClose = false
				for _, vehicle in pairs(vehicles) do
					if not vehicle.isLocal and vehicle:getOwner() then
						local obj = be:getObjectByID(vehicle.gameVehicleID)
						if obj then obj:setMeshAlpha(1, "", false) end
					end
				end
			end
		end
		getClosestVehicle(playerID, "careerMPEnabler.callback")
	end
end

local function onBeamNGTrigger(data)
	if MPVehicleGE.isOwn(data.subjectID) then
		if data.triggerName:find("Phys") then
			if data.event == "enter" then
				be:setDynamicCollisionEnabled(false)
				physicsActive = false
				physicsComplete = false
			elseif  data.event == "tick" then
				local veh = be:getObjectByID(data.subjectID)
				if veh.JBeam ~= "unicycle" then
					be:setDynamicCollisionEnabled(false)
					physicsActive = false
					physicsComplete = false
				end
			elseif data.event == "exit" then
				if not physicsActive then
					physicsActive = true
					physicsComplete = false
					physicsTimeout = 0
				end
			end
		end
	end
end

--Loading / Unloading

local function onExtensionLoaded() --called by the base game when the extension loads, good place to setup MP event handlers
	getUserTrafficSettings()
	setTrafficSettings(freeRoamMPTrafficSettings)
	getUserGameplaySettings()
	setGameplaySettings(freeRoamMPGameplaySettings)
	AddEventHandler("rxUpdateDisplay", rxUpdateDisplay)
	AddEventHandler("rxUpdateWinnerLight", rxUpdateWinnerLight)
	AddEventHandler("rxClearAll", rxClearAll)
	AddEventHandler("rxPrefabSync", rxPrefabSync)
	AddEventHandler("rxCareerSync", rxCareerSync)
	AddEventHandler("rxCareerVehSync", rxCareerVehSync)
	AddEventHandler("rxTrafficSignalTimer", rxTrafficSignalTimer)
	career_career = extensions.career_careerMP --replace stock career lua with my modified careerMP lua
	log('W', 'careerMP', 'CareerMP Enabler LOADED!')
end

local function onExtensionUnloaded()
	unPatchBeamMP() --better than nothing
	setTrafficSettings(userTrafficSettings)
	setGameplaySettings(userGameplaySettings)
	log('W', 'careerMP', 'CareerMP Enabler UNLOADED!')
end

--Access

M.callback = callback

M.onVehicleActiveChanged = onVehicleActiveChanged
M.onVehicleSpawned = onVehicleSpawned
M.onVehicleReady = onVehicleReady
M.onVehicleSwitched = onVehicleSwitched

M.onSpeedTrapTriggered = onSpeedTrapTriggered
M.onRedLightCamTriggered = onRedLightCamTriggered
M.onAnyMissionChanged = onAnyMissionChanged
M.onMissionStartWithFade = onMissionStartWithFade
M.onGameStateUpdate = onGameStateUpdate

M.onCareerTuningStarted = onCareerTuningStarted
M.onPartShoppingStarted = onPartShoppingStarted
M.onPerformanceTestStarted = onPerformanceTestStarted
M.onRepairInGarage = onRepairInGarage
M.onVehicleRepairDelayed = onVehicleRepairDelayed
M.onVehicleRepairInstant = onVehicleRepairInstant
M.onAfterVehicleRepaired = onAfterVehicleRepaired
M.onVehiclePaintingUiOpened = onVehiclePaintingUiOpened

M.onClientPostStartMission = onClientPostStartMission

M.onBeamNGTrigger = onBeamNGTrigger

M.onWorldReadyState = onWorldReadyState
M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
