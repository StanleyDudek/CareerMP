--CareerMP UI Apps (CLIENT) by Dudekahedron, 2026

local M = {}

local missionUIToResolve = false

local stateToUpdate

local defaultAppLayoutDirectory = "settings/ui_apps/originalLayouts/default/"
local missionAppLayoutDirectory = "settings/ui_apps/originalLayouts/mission/"
local userDefaultAppLayoutDirectory = "settings/ui_apps/layouts/default/"
local userMissionAppLayoutDirectory = "settings/ui_apps/layouts/mission/"

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

local multiplayerApps = {
	multiplayerchat = {
		appName = "multiplayerchat",
		placement = {
			width = "550px",
			bottom = "0px",
			height = "170px",
			left = "305px"
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
	careermpplayerlist = {
		appName = "careermpplayerlist",
		placement = {
			bottom = "",
			height = "560px",
			left = "",
			position = "absolute",
			right = "0px",
			top = "240px",
			width = "300px"
		}
	}
}

local function findApp(layout, name)
	for i, app in ipairs(layout.apps) do
		if app.appName == name then
			return i, app
		end
	end
end

local function checkApp(layout, appData)
	local firstIndex = nil
	local removed = false
	for i = #layout.apps, 1, -1 do
		local app = layout.apps[i]
		if app.appName == appData.appName then
			if not firstIndex then
				firstIndex = i
			else
				table.remove(layout.apps, i)
				removed = true
			end
		end
	end
	if not firstIndex then
		table.insert(layout.apps, deepcopy(appData))
		return true
	end
	return removed
end

local function replaceApp(layout, oldName, newApp)
	local i = findApp(layout, oldName)
	if i then
		layout.apps[i] = deepcopy(newApp)
		return true
	end
end

local function loadLayout(customDir, defaultDir, filename)
	local custom = jsonReadFile(customDir .. filename .. ".uilayout.json")
	if custom then
		return deepcopy(custom), customDir
	end
	local default = jsonReadFile(defaultDir .. filename .. ".uilayout.json")
	if default then
		return deepcopy(default), customDir
	end
end

local function checkUIApps(state)
	local mpLayout = jsonReadFile(userDefaultAppLayoutDirectory .. "careermp.uilayout.json")
	if mpLayout then
		for _, app in pairs(mpLayout.apps) do
			multiplayerApps[app.appName] = app
		end
	end
	local layoutInfo = defaultLayouts[state.appLayout] or missionLayouts[state.appLayout]
	if not layoutInfo then
		return
	end
	local customDir = defaultLayouts[state.appLayout] and userDefaultAppLayoutDirectory or userMissionAppLayoutDirectory    local defaultDir = defaultLayouts[state.appLayout] and defaultAppLayoutDirectory or missionAppLayoutDirectory
	local layout, saveDir = loadLayout(customDir, defaultDir, layoutInfo.filename)
	if not layout then
		return
	end
	local updated = false
	updated = checkApp(layout, multiplayerApps.multiplayerchat) or updated
	updated = checkApp(layout, multiplayerApps.multiplayersession) or updated
	updated = replaceApp(layout, "multiplayerplayerlist", multiplayerApps.careermpplayerlist) or updated
	updated = checkApp(layout, multiplayerApps.careermpplayerlist) or updated
	if updated then
		jsonWriteFile(saveDir .. layoutInfo.filename .. ".uilayout.json", layout, 1)
		stateToUpdate = true
	end
end

local function onGameStateUpdate(state)
	if missionUIToResolve and state.appLayout == "freeroam" then
		core_gamestate.setGameState("career", "career", nil)
		missionUIToResolve = false
	end
	if not state.appLayout:find("career") then
		missionUIToResolve = true
	end
	checkUIApps(state)
end

local function onUpdate(dtReal, dtSim, dtRaw)
	if worldReadyState == 2 then
		if stateToUpdate then
			ui_apps.requestUIAppsData()
			stateToUpdate = false
		end
	end
end

local function onExtensionLoaded()
	log('W', 'careerMP', 'CareerMP UI Apps LOADED!')
end

local function onExtensionUnloaded()
	log('W', 'careerMP', 'CareerMP UI Apps UNLOADED!')
end

M.onGameStateUpdate = onGameStateUpdate

M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
