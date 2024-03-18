--CareerMP (CLIENT) by Dudekahedron, 2024

mpCareer = false

local M = {}

local CareerMP_VERSION = "0.0.1"
local logTag = "MPCareer"

local syncRequested = false

local paintTimer = 0
local paintInterval = 5

local payTimer = 0
local payInterval = 300
local payRate = 100

local gui_module = require("ge/extensions/editor/api/gui")
local gui = {setupEditorGuiTheme = nop}
local im = ui_imgui
local windowOpen = im.BoolPtr(true)
local ffi = require('ffi')

local newChatEnabled = settings.getValue('enableNewChatMenu')
local originalNewChatEnabled = newChatEnabled

local userTrafficSettings = {}
local mpCareerTrafficSettings = {
	trafficAmount = 1,
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
local mpGameplaySettings = {
	startThermalsPreHeated = true,
	startBrakeThermalsPreHeated = true,
	spawnVehicleIgnitionLevel = 1,
	--simplifyRemoteVehicles = true
}

local renderDistance = 5000

local function rxMPCareerSync(data)
	if data ~= "null" then
		local vehicleStates = jsonDecode(data)
		for serverVid, state in pairs(vehicleStates) do
			local gameVid = MPVehicleGE.getGameVehicleID(serverVid)
			if gameVid ~= -1 then
				if not MPVehicleGE.isOwn(gameVid) then
					if not state.active then
						be:getObjectByID(gameVid):setActive(0)
					else
						be:getObjectByID(gameVid):setActive(1)
					end
				end
			end
		end
	end
end

local function rxMPCareerUnicycleSpawn(data)
	core_vehicles.spawnNewVehicle("unicycle", {config = "vehicles/unicycle/beammp_default.pc"})
end

local function rxPrefab(data)
	if data ~= "null" or data ~= nil then
		local prefab = jsonDecode(data)
		if prefab.pLoad == true then
			local filename = prefab.pPath
			local f = io.open(filename, "r")
			if f == nil then
				return
			end
			local content = f:read("*all")
			f:close()
			content = content:gsub("new BeamNGVehicle(.-)};", "")
			local tempPath = "settings/BeamMP/tempPrefab.prefab"
			local tempFile = io.open(tempPath, "w")
			if tempFile then
				tempFile:write(content)
				tempFile:close()
			end
			spawnPrefab(prefab.pName, tempPath, "0 0 0", "0 0 1", "1 1 1")
			be:reloadCollision()
		elseif prefab.pLoad == false then
			removePrefab(prefab.pName)
			be:reloadCollision()
		end
	end
end

local function rxPayment(data)
	if mpCareer then
		local payment = jsonDecode(data)
		local money = payment.money or 0
		local bonusStars = payment.bonusStars or 0
		local reason = payment.reason or "Server Payment"
		guihooks.trigger('toastrMsg', {type="success", title = reason, msg = "$" .. money .. " & " .. bonusStars  .. " Bonus Star(s), ", config = {timeOut = 10000 }})
		career_modules_playerAttributes.addAttribute("money", money, reason)
		career_modules_playerAttributes.addAttribute("bonusStars", bonusStars, reason)
	end
end

local function rxPaint(data)
	local tempData = jsonDecode(data)
	local server_vehicle_id = tostring(tempData[1])
	local paints = tempData[2]
	local gameVehicleID = MPVehicleGE.getGameVehicleID(server_vehicle_id)
	local veh = be:getObjectByID(gameVehicleID)
	if veh then
		if paints and type(paints) == 'table' then
			local paint = paints[1]
			if paint then
				veh.color = ColorF(paint.baseColor[1], paint.baseColor[2], paint.baseColor[3], paint.baseColor[4]):asLinear4F()
			end
			paint = paints[2]
			if paint then
				veh.colorPalette0 = ColorF(paint.baseColor[1], paint.baseColor[2], paint.baseColor[3], paint.baseColor[4]):asLinear4F()
			end
			paint = paints[3]
			if paint then
				veh.colorPalette1 = ColorF(paint.baseColor[1], paint.baseColor[2], paint.baseColor[3], paint.baseColor[4]):asLinear4F()
			end
			veh:setMetallicPaintData(paints)
		end
	end
end

local function drawMPCareer()
	gui.setupWindow("MPCareer")
	im.SetNextWindowBgAlpha(0.666)
	im.Begin("CareerMP v" .. CareerMP_VERSION)
		im.PushStyleColor2(im.Col_Button, im.ImVec4(0.15, 0.55, 0.05, 0.333))
		im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(0.1, 0.55, 0.09, 0.5))
		im.PushStyleColor2(im.Col_ButtonActive, im.ImVec4(0.05, 0.55, 0.05, 0.999))
		if im.Button("Save Career") then
			career_saveSystem.saveCurrent()
		end
		im.PopStyleColor(3)
		im.PushStyleColor2(im.Col_Button, im.ImVec4(1.0, 0.55, 0.05, 0.333))
		im.PushStyleColor2(im.Col_ButtonHovered, im.ImVec4(1.0, 0.55, 0.09, 0.5))
		im.PushStyleColor2(im.Col_ButtonActive, im.ImVec4(1.0, 0.55, 0.05, 0.999))
		im.SameLine()
		if im.Button("Exit Server") then
			MPCoreNetwork.leaveServer(true)
		end
		im.PopStyleColor(3)
		im.Separator()
		if im.Button("Clear Mission Black Screen") then
			ui_fadeScreen.stop()
		end
		im.Separator()
		if im.Button("Clear Stuck Garage Menu") then
			career_career.closeAllMenus()
		end
	im.End()
end

local function getUserTrafficSettings()
	userTrafficSettings = {
		trafficAmount = settings.getValue('trafficAmount'),
		trafficExtraAmount = settings.getValue('trafficExtraAmount'),
		trafficExtraVehicles = settings.getValue('trafficExtraVehicles'),
		trafficParkedAmount = settings.getValue('trafficParkedAmount'),
		trafficParkedVehicles = settings.getValue('trafficParkedVehicles'),
		trafficLoadForFreeroam = settings.getValue('trafficLoadForFreeroam'),
		trafficSmartSelections = settings.getValue('trafficSmartSelections'),
		trafficSimpleVehicles = settings.getValue('trafficSimpleVehicles'),
		trafficAllowMods = settings.getValue('trafficAllowMods'),
		trafficEnableSwitching = settings.getValue('trafficEnableSwitching'),
		trafficMinimap = settings.getValue('trafficMinimap')
	}
end

local function setTrafficSettings(trafficSettings)
	for setting, value in pairs(trafficSettings) do
		settings.setValue(setting, value)
	end
end

local function getUserGameplaySettings()
	userGameplaySettings = {
		spawnVehicleIgnitionLevel = settings.getValue("spawnVehicleIgnitionLevel"),
		startThermalsPreHeated = settings.getValue("startThermalsPreHeated"),
		startBrakeThermalsPreHeated = settings.getValue("startBrakeThermalsPreHeated"),
		simplifyRemoteVehicles = settings.getValue("simplifyRemoteVehicles")
	}
end

local function setGameplaySettings(gameplaySettings)
	for setting, value in pairs(gameplaySettings) do
		settings.setValue(setting, value)
	end
end

local function onUpdate(dt)
	if worldReadyState == 2 then
		if windowOpen[0] == true then
			drawMPCareer()
		end
		if not syncRequested then
			TriggerServerEvent("MPCareerSyncRequested", "")
			syncRequested = true
			mpCareer = true
			local data = jsonEncode( { mpCareer } )
			TriggerServerEvent("MPCareerActiveHandler", data)
			core_gamestate.setGameState('career', 'career', 'career')
			if career_saveSystem.setSaveSlot(MPConfig.getNickname(), nil) then
				career_career = extensions.career_mpCareer
				log('W', logTag, "--------------------------------------ACTIVATING CAREER--v")
				career_career.activateCareer(false)
				log('W', logTag, "--------------------------------------ACTIVATED CAREER--^")
			end
			if not newChatEnabled then
				settings.setValue('enableNewChatMenu', true)
			end
		end
		if mpCareer then
			paintTimer = paintTimer + dt
			if paintTimer >= paintInterval then
				paintTimer = 0
				local veh = be:getPlayerVehicle(0)
				if veh then
					local gameVehID = be:getPlayerVehicleID(0)
					if MPVehicleGE.isOwn(gameVehID) then
						local serverVehID = MPVehicleGE.getServerVehicleID(gameVehID)
						local invID = career_modules_inventory.getInventoryIdFromVehicleId(gameVehID)
						if invID then
							local autosavePath = career_saveSystem.getSaveRootDirectory() .. MPConfig.getNickname() .. "/autosave1"
							local inventoryData = jsonReadFile(autosavePath .. "/career/inventory.json")
							local vehicleData = jsonReadFile(autosavePath .. "/career/vehicles/" .. invID .. ".json")
							local vehPaints = vehicleData.config.paints
							TriggerServerEvent("paintUpdate", jsonEncode( { serverVehID, vehPaints }))
						else
							TriggerServerEvent("paintUpdate", jsonEncode( { serverVehID, veh.paints }))
						end
					end
				end
			end
			payTimer = payTimer + dt
			if payTimer >= payInterval then
				payTimer = 0
				career_modules_playerAttributes.addAttribute("money", payRate, {label="CareerMP Incentive"})
				guihooks.trigger('toastrMsg', {type="success", title = "CareerMP", msg = "Incentive Payout: $" .. payRate, config = {timeOut = 5000 }})
			end
		end
	end
end

local function onCareerActive(active)
	log('W', "onCareerActive", "--------------------------------------onCareerActive--v")
	log('W', "onCareerActive", "--------------------------------------active: " .. tostring(active))
	log('W', "onCareerActive", "--------------------------------------onCareerActive--^")

	if active and not mpCareer then
		mpCareer = active
		local data = jsonEncode( { mpCareer } )
		TriggerServerEvent("MPCareerActiveHandler", data)
	elseif not active and mpCareer then
		mpCareer = active
		local data = jsonEncode( { mpCareer } )
		TriggerServerEvent("MPCareerActiveHandler", data)
	end

end

local function onAnyMissionChanged(state, mission)
	if state == "started" then
		local prefab = {}
		local prefab_files = FS:findFiles(mission.missionFolder, '*.prefab', 0, false, true)
		if #prefab_files ~= 0 then
			for index, value in pairs(prefab_files) do
				prefab.pName = mission.missionType .. "-" .. tostring(index)
				prefab.pPath = value
				prefab.pLoad = true
				local data = jsonEncode(prefab)
				TriggerServerEvent("txPrefab", data)
			end
		end
	elseif state == "stopped" then
		local prefab = {}
		local prefab_files = FS:findFiles(mission.missionFolder, '*.prefab', 0, false, true)
		if #prefab_files ~= 0 then
			for index, value in pairs(prefab_files) do
				prefab.pName = mission.missionType .. "-" .. tostring(index)
				prefab.pPath = value
				prefab.pLoad = false
				local data = jsonEncode(prefab)
				TriggerServerEvent("txPrefab", data)
			end
		end
	end
end

local function onVehicleActiveChanged(gameVid, active)
	log('W', "onVehicleActiveChanged", "--------------------------------------onVehicleActiveChanged--v")
	log('W', "onVehicleActiveChanged", "-------------------------------------- active: " .. tostring(active))
	log('W', "onVehicleActiveChanged", "-------------------------------------- gameVid: " .. gameVid)
	if MPVehicleGE.isOwn(gameVid) then
		local serverVid = MPVehicleGE.getServerVehicleID(gameVid)
		if serverVid then
			local data = jsonEncode( { active, serverVid } )
			TriggerServerEvent("MPCareerVehicleActiveHandler", data)
			log('W', "onVehicleActiveChanged", "-------------------------------------- serverVid: " .. serverVid)
		end
	end
	log('W', "onVehicleActiveChanged", "--------------------------------------onVehicleActiveChanged--^")
end

local function onVehicleSpawned(gameVehicleID)
	log('W', "onVehicleSpawned", "--------------------------------------onVehicleSpawned--v")
	log('W', "onVehicleSpawned", "--------------------------------------gameVehicleID: " .. gameVehicleID)
	local veh = be:getObjectByID(gameVehicleID)
	if veh then
		log('W', "onVehicleSpawned", "--------------------------------------setting renderDistance: " .. renderDistance)
		veh:setField('renderDistance', '', renderDistance)
	end
	log('W', "onVehicleSpawned", "--------------------------------------onVehicleSpawned--^")
end

local function MPCareerVehicleActive(data)
	local tempData = jsonDecode(data)
	local active = tempData[1]
	local serverVid = tempData[2]
	log('W', "MPCareerVehicleActive", "--------------------------------------MPCareerVehicleActive--v")
	log('W', "MPCareerVehicleActive", "--------------------------------------active: " .. tostring(active))
	if serverVid then
		log('W', "MPCareerVehicleActive", "--------------------------------------serverVid: " .. serverVid)
		local gameVid = MPVehicleGE.getGameVehicleID(serverVid)
		if gameVid ~= -1 then
			if not MPVehicleGE.isOwn(gameVid) then
				if not active then
					be:getObjectByID(gameVid):setActive(0)
				else
					be:getObjectByID(gameVid):setActive(1)
				end
			end
		end
	end
	log('W', "MPCareerVehicleActive", "--------------------------------------MPCareerVehicleActive--^")
end

local function onPartShoppingStarted()
	local veh = be:getPlayerVehicle(0)
	local lastVehicleId = career_modules_inventory.getLastVehicle()
	local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(lastVehicleId)
	if vehObjId then
		if be:getObjectByID(vehObjId).JBeam ~= "boxutility"
		or be:getObjectByID(vehObjId).JBeam ~= "boxutility_large"
		or be:getObjectByID(vehObjId).JBeam ~= "caravan"
		or be:getObjectByID(vehObjId).JBeam ~= "cargotrailer"
		or be:getObjectByID(vehObjId).JBeam ~= "containerTrailer"
		or be:getObjectByID(vehObjId).JBeam ~= "dolly"
		or be:getObjectByID(vehObjId).JBeam ~= "dryvan"
		or be:getObjectByID(vehObjId).JBeam ~= "flatbed"
		or be:getObjectByID(vehObjId).JBeam ~= "frameless_dump"
		or be:getObjectByID(vehObjId).JBeam ~= "tanker"
		or be:getObjectByID(vehObjId).JBeam ~= "tiltdeck"
		or be:getObjectByID(vehObjId).JBeam ~= "tsfb" then
			gameplay_walk.getInVehicle(be:getObjectByID(vehObjId))
		end
	end
	if veh.JBeam == "unicycle" then
		veh:delete()
		MPVehicleGE.focusCameraOnPlayer(MPConfig.getNickname())
	end
end

local function onCareerTuningStarted()
	local veh = be:getPlayerVehicle(0)
	local lastVehicleId = career_modules_inventory.getLastVehicle()
	local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(lastVehicleId)
	if vehObjId then
		if be:getObjectByID(vehObjId).JBeam ~= "boxutility"
		or be:getObjectByID(vehObjId).JBeam ~= "boxutility_large"
		or be:getObjectByID(vehObjId).JBeam ~= "caravan"
		or be:getObjectByID(vehObjId).JBeam ~= "cargotrailer"
		or be:getObjectByID(vehObjId).JBeam ~= "containerTrailer"
		or be:getObjectByID(vehObjId).JBeam ~= "dolly"
		or be:getObjectByID(vehObjId).JBeam ~= "dryvan"
		or be:getObjectByID(vehObjId).JBeam ~= "flatbed"
		or be:getObjectByID(vehObjId).JBeam ~= "frameless_dump"
		or be:getObjectByID(vehObjId).JBeam ~= "tanker"
		or be:getObjectByID(vehObjId).JBeam ~= "tiltdeck"
		or be:getObjectByID(vehObjId).JBeam ~= "tsfb" then
			gameplay_walk.getInVehicle(be:getObjectByID(vehObjId))
		end
	end
	if veh.JBeam == "unicycle" then
		veh:delete()
		MPVehicleGE.focusCameraOnPlayer(MPConfig.getNickname())
	end
end

local function onCareerPaintingStarted()
	local veh = be:getPlayerVehicle(0)
	local lastVehicleId = career_modules_inventory.getLastVehicle()
	local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(lastVehicleId)
	if vehObjId then
		gameplay_walk.getInVehicle(be:getObjectByID(vehObjId))
	end
	if veh.JBeam == "unicycle" then
		veh:delete()
		MPVehicleGE.focusCameraOnPlayer(MPConfig.getNickname())
	end
end

local function onCareerVehicleInventoryMenu()
	gameplay_walk.setWalkingMode(true)
end

local function onCareerPartsInventoryMenu()
	local veh = be:getPlayerVehicle(0)
	local lastVehicleId = career_modules_inventory.getLastVehicle()
	local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(lastVehicleId)
	if vehObjId then
		if be:getObjectByID(vehObjId).JBeam ~= "boxutility"
		or be:getObjectByID(vehObjId).JBeam ~= "boxutility_large"
		or be:getObjectByID(vehObjId).JBeam ~= "caravan"
		or be:getObjectByID(vehObjId).JBeam ~= "cargotrailer"
		or be:getObjectByID(vehObjId).JBeam ~= "containerTrailer"
		or be:getObjectByID(vehObjId).JBeam ~= "bdolly"
		or be:getObjectByID(vehObjId).JBeam ~= "dryvan"
		or be:getObjectByID(vehObjId).JBeam ~= "flatbed"
		or be:getObjectByID(vehObjId).JBeam ~= "frameless_dump"
		or be:getObjectByID(vehObjId).JBeam ~= "tanker"
		or be:getObjectByID(vehObjId).JBeam ~= "tiltdeck"
		or be:getObjectByID(vehObjId).JBeam ~= "tsfb" then
			gameplay_walk.getInVehicle(be:getObjectByID(vehObjId))
		end
	end
	if veh.JBeam == "unicycle" then
		veh:delete()
		MPVehicleGE.focusCameraOnPlayer(MPConfig.getNickname())
	end
end

local function onExtensionLoaded()

	AddEventHandler("MPCareerVehicleActive", MPCareerVehicleActive)
	AddEventHandler("rxMPCareerSync", rxMPCareerSync)
	AddEventHandler("rxMPCareerUnicycleSpawn", rxMPCareerUnicycleSpawn)
	AddEventHandler("rxPayment", rxPayment)
	AddEventHandler("rxPaint", rxPaint)
	AddEventHandler("rxPrefab", rxPrefab)

	log('W', logTag, "--------------------------------------REPLACING CAREER--v")
	career_career = extensions.career_mpCareer
	log('W', logTag, "--------------------------------------REPLACED CAREER--^")

	log('W', logTag, "--------------------------------------REPLACING BIG MAP MODE--v")
	freeroam_bigMapMode = extensions.freeroam_mpBigMapMode
	log('W', logTag, "--------------------------------------REPLACED BIG MAP MODE--^")

	log('W', logTag, "--------------------------------------REPLACING USER SETTINGS--v")
	getUserTrafficSettings()
	setTrafficSettings(mpCareerTrafficSettings)
	getUserGameplaySettings()
	setGameplaySettings(mpGameplaySettings)
	log('W', logTag, "--------------------------------------REPLACED USER SETTINGS--^")

	log('W', logTag, "--------------------------------------SETTING UP IMGUI--v")
	gui_module.initialize(gui)
	gui.registerWindow("MPCareer", im.ImVec2(227, 113))
	gui.showWindow("MPCareer")
	log('W', logTag, "--------------------------------------SET UP IMGUI--^")

	log('W', logTag, "-=$=- MPCareer LOADED -=$=-")

end

local function onExtensionUnloaded()
	log('W', logTag, "--------------------------------------RESTORING USER SETTINGS--v")
	settings.setValue('enableNewChatMenu', originalNewChatEnabled)
	setTrafficSettings(userTrafficSettings)
	setGameplaySettings(userGameplaySettings)
	log('W', logTag, "--------------------------------------RESTORED USER SETTINGS--^")
	log('W', logTag, "-=$=- MPCareer UNLOADED -=$=-")
end

M.onUpdate = onUpdate

M.onCareerTuningStarted = onCareerTuningStarted

M.onCareerPaintingStarted = onCareerPaintingStarted

M.onCareerVehicleInventoryMenu = onCareerVehicleInventoryMenu

M.onCareerPartsInventoryMenu = onCareerPartsInventoryMenu

M.onPartShoppingStarted = onPartShoppingStarted

M.onCareerActive = onCareerActive

M.onAnyMissionChanged = onAnyMissionChanged

M.onVehicleSpawned = onVehicleSpawned

M.onVehicleActiveChanged = onVehicleActiveChanged

M.onInit = function() setExtensionUnloadMode(M, "manual") end

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

return M
