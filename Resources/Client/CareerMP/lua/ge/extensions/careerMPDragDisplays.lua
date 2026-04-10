--CareerMP Drag Displays (CLIENT) by Dudekahedron, 2026

local M = {}

--Drag Race Displays, most of the folllowing is ripped from the base game to duplicate the behavior in MP
local dragData

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
			prestageLight  = {obj = findLightObject("Prestagelight_" .. lane, prefabId),        anim = "prestage",  isOn = false},
			stageLight     = {obj = findLightObject("Stagelight_" .. lane, prefabId),           anim = "prestage",  isOn = false},
			winnerLight    = {obj = findLightObject("WinLight_Timeboard_" .. lane, prefabId),   anim = "prestage",  isOn = false},
			driverLight    = {obj = findLightObject("WinLight_Driver_" .. lane, prefabId),      anim = "prestage",  isOn = false},
		},
		countDownLights = {
			amberLight1    = {obj = findLightObject("Amberlight1_" .. lane, prefabId),          anim = "tree",      isOn = false},
			amberLight2    = {obj = findLightObject("Amberlight2_" .. lane, prefabId),          anim = "tree",      isOn = false},
			amberLight3    = {obj = findLightObject("Amberlight3_" .. lane, prefabId),          anim = "tree",      isOn = false},
			greenLight     = {obj = findLightObject("Greenlight_" .. lane, prefabId),           anim = "tree",      isOn = false},
			redLight       = {obj = findLightObject("Redlight_" .. lane, prefabId),             anim = "tree",      isOn = false},
		},
		globalLights = {
			blueLight      = {obj = findLightObject("BlueLight", prefabId),                     anim = "prestage",  isOn = false},
		},
		timers = {
			dialOffset = 0,
			laneTimer = 0,
			laneTimerFlag = false
		}
	}
end

local function initTree()
	if not dragData then
		return {}
	end
	if not dragData.strip then
		return {}
	end
	if not dragData.strip.lanes or #dragData.strip.lanes == 0 then
		return {}
	end
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

local function hasTreeLights()
    if not dragData or not dragData.strip or not dragData.strip.treeLights then
        return false
    end
    for _, laneTree in ipairs(dragData.strip.treeLights) do
        if laneTree and laneTree.stageLights then
        for _, light in pairs(laneTree.stageLights) do
            if light and light.obj then
                return true
            end
        end
        for _, light in pairs(laneTree.countDownLights) do
            if light and light.obj then
                return true
            end
        end
        end
    end
    return false
end

local function updateTreeLightsUI(vehId, changes)
	if not changes then
        return
    end
	if not vehId or vehId == be:getPlayerVehicleID(0) then
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
	for i = 1, 5 do
		local timeDigit = scenetree.findObject("display_time_" .. i .. "_r")
		table.insert(time, timeDigit)
		local speedDigit = scenetree.findObject("display_speed_" .. i .. "_r")
		table.insert(speed, speedDigit)
	end
	table.insert(displayDigits.timeDigits, time)
	table.insert(displayDigits.speedDigits, speed)
	time = {}
	speed = {}
	for i = 1, 5 do
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
		for _, group in pairs(laneTree) do
            if type(group) == "table" then
                for _, light in pairs(group) do
                    if type(light) == "table" and light.obj and simObjectExists(light.obj) then
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
			stageLight = false,
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
		for _, laneTypeData in ipairs(digitTypeData) do
            for _, digit in ipairs(laneTypeData) do
                if digit and simObjectExists(digit) then
                    digit:setHidden(true)
                end
            end
		end
	end
end

local function manageWinnerLights(dtSim)
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

local function rxUpdateWinnerLight(data)
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
    if lane then
        local stageLights = dragData.strip.treeLights[lane].stageLights
        if stageLights then
            local winnerLight = stageLights.winnerLight
            local driverLight = stageLights.driverLight
            if winnerLight and winnerLight.obj then
                winnerLight.obj = findLightObject("WinLight_Timeboard_" .. lane, prefabId)
                winnerLight.isOn = true
                winnerLight.obj:setHidden(false)
            end
            if driverLight and driverLight.obj and not driverLightBlinkState.isBlinking then
                driverLight.obj = findLightObject("WinLight_Driver_" .. lane, prefabId)
                driverLight.isOn = true
                driverLightBlinkState.lane = lane
                driverLightBlinkState.isBlinking = true
                driverLightBlinkState.timer = 0
            end
        end
    end
end

local function rxUpdateBlueLight(data)
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	if not dragData or not dragData.strip.treeLights or not dragData.strip.treeLights[1] then
		return
	end
	local hasTree = hasTreeLights()
	local blueLight = dragData.strip.treeLights[1].globalLights.blueLight
	if hasTree and blueLight.obj and simObjectExists(blueLight.obj) and decodedData.blueLight then
		blueLight.obj:setHidden(not decodedData.blueLight.isOn)
	end
end

local function rxUpdatePreStageLight(data)
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	local gameVehicleID = MPVehicleGE.getGameVehicleID(decodedData.serverVehicleID)
	if not gameVehicleID or not dragData then
        return
    end
	local laneTree = dragData.strip.treeLights[decodedData.lane]
	if not laneTree or not laneTree.stageLights then
        return
    end
	local hasTree = hasTreeLights()
	if hasTree and laneTree.stageLights.prestageLight.obj and simObjectExists(laneTree.stageLights.prestageLight.obj) then
		laneTree.stageLights.prestageLight.obj:setHidden(not decodedData.isOn)
	end
end

local function rxUpdateStageLight(data)
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	local gameVehicleID = MPVehicleGE.getGameVehicleID(decodedData.serverVehicleID)
	if not gameVehicleID or not dragData then
        return
    end
	local laneTree = dragData.strip.treeLights[decodedData.lane]
	if laneTree.stageLights.stageLight.obj and simObjectExists(laneTree.stageLights.stageLight.obj) then
		dragData.strip.treeLights[decodedData.lane].stageLights.stageLight.obj:setHidden(not decodedData.isOn)
	end
end

local function rxUpdateDisqualifiedLight(data)
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	local gameVehicleID = MPVehicleGE.getGameVehicleID(decodedData.serverVehicleID)
	if not dragData or not gameVehicleID then
        return
    end
	local treeLights = dragData.strip.treeLights[decodedData.lane]
	local countDownLights = treeLights.countDownLights
	if countDownLights.amberLight1.obj and simObjectExists(countDownLights.amberLight1.obj) then
        countDownLights.amberLight1.obj:setHidden(not decodedData.countDownLights.amberLight1.isOn)
    end
	if countDownLights.amberLight2.obj and simObjectExists(countDownLights.amberLight2.obj) then
        countDownLights.amberLight2.obj:setHidden(not decodedData.countDownLights.amberLight2.isOn)
    end
	if countDownLights.amberLight3.obj and simObjectExists(countDownLights.amberLight3.obj) then
        countDownLights.amberLight3.obj:setHidden(not decodedData.countDownLights.amberLight3.isOn)
    end
	if countDownLights.greenLight.obj and simObjectExists(countDownLights.greenLight.obj) then
        countDownLights.greenLight.obj:setHidden(not decodedData.countDownLights.greenLight.isOn)
    end
	if countDownLights.redLight.obj and simObjectExists(countDownLights.redLight.obj) then
        countDownLights.redLight.obj:setHidden(not decodedData.countDownLights.redLight.isOn)
    end
end

local function rxUpdateTreeLights(data)
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	local gameVehicleID = MPVehicleGE.getGameVehicleID(decodedData.serverVehicleID)
	if not dragData or not gameVehicleID then
        return
    end
	local treeLights = dragData.strip.treeLights[decodedData.lane]
	local countDownLights = treeLights.countDownLights
	if countDownLights.amberLight1.obj and simObjectExists(countDownLights.amberLight1.obj) then
        countDownLights.amberLight1.obj:setHidden(not decodedData.countDownLights.amberLight1.isOn)
    end
	if countDownLights.amberLight2.obj and simObjectExists(countDownLights.amberLight2.obj) then
        countDownLights.amberLight2.obj:setHidden(not decodedData.countDownLights.amberLight2.isOn)
    end
	if countDownLights.amberLight3.obj and simObjectExists(countDownLights.amberLight3.obj) then
        countDownLights.amberLight3.obj:setHidden(not decodedData.countDownLights.amberLight3.isOn)
    end
	if countDownLights.greenLight.obj and simObjectExists(countDownLights.greenLight.obj) then
        countDownLights.greenLight.obj:setHidden(not decodedData.countDownLights.greenLight.isOn)
    end
	if countDownLights.redLight.obj and simObjectExists(countDownLights.redLight.obj) then
        countDownLights.redLight.obj:setHidden(not decodedData.countDownLights.redLight.isOn)
    end
end

local function rxUpdateDisplay(data)
	local decodedData = jsonDecode(data)
	if gameplay_drag_general then
		if not dragData then
			gameplay_drag_general.setDragRaceData(decodedData.dragData)
			dragData = gameplay_drag_general.getData()
		end
	end
	if dragData then
		dragData.strip.treeLights = initTree() or {}
		dragData.strip.displayDigits = initDisplay() or {}
		guihooks.trigger('updateTreeLightStaging', true)
	end
	local displayVal = decodedData.velVal
	if settings.getValue('uiUnitLength') == "metric" then
		displayVal = displayVal * 3.6
	elseif settings.getValue('uiUnitLength') == "imperial" then
		displayVal = displayVal * 2.23694
	end
	local lane = decodedData.lane
	local timeDisplayValue = decodedData.timeDisplayValue
	local speedDisplayValue = {}
	local timeDigits = {}
	local speedDigits = {}
	timeDigits = dragData.strip.displayDigits.timeDigits[lane]
	speedDigits = dragData.strip.displayDigits.speedDigits[lane]
	if displayVal < 100 then
		table.insert(speedDisplayValue, "empty")
	end
	for num in string.gmatch(string.format("%.2f", displayVal), "%d") do
		table.insert(speedDisplayValue, num)
	end
	if #timeDisplayValue > 0 and #timeDisplayValue < 6 then
		for i,v in ipairs(timeDisplayValue) do
			if timeDigits[i] and simObjectExists(timeDigits[i]) then
				timeDigits[i]:preApply()
				timeDigits[i]:setField('shapeName', 0, "art/shapes/quarter_mile_display/display_".. v ..".dae")
				timeDigits[i]:setHidden(false)
				timeDigits[i]:postApply()
			end
		end
	end
	for i,v in ipairs(speedDisplayValue) do
		if speedDigits and speedDigits[i] and simObjectExists(speedDigits[i]) then
			speedDigits[i]:preApply()
			speedDigits[i]:setField('shapeName', 0, "art/shapes/quarter_mile_display/display_".. v ..".dae")
			speedDigits[i]:setHidden(false)
			speedDigits[i]:postApply()
		end
	end
end

local function rxClearAll()
	if not dragData then
		dragData = gameplay_drag_general.getData()
		return
	end
	local prefabId = dragData.prefabs.christmasTree.prefabId
	for i = 1, 2 do
		local winnerLightObj = findLightObject("WinLight_Timeboard_" .. i, prefabId)
		local driverLightObj = findLightObject("WinLight_Driver_" .. i, prefabId)
		if winnerLightObj then
			winnerLightObj:setHidden(true)
		end
		if driverLightObj then
			driverLightObj:setHidden(true)
		end
	end
	clearLights()
	clearDisplay()
	gameplay_drag_general._clear()
end

local function onUpdate(dtReal, dtSim, dtRaw)
	if worldReadyState == 2 then
		manageWinnerLights(dtSim)
	end
end

local function onExtensionLoaded()
	AddEventHandler("rxUpdateDisplay", rxUpdateDisplay)
	AddEventHandler("rxUpdateWinnerLight", rxUpdateWinnerLight)
	AddEventHandler("rxUpdateBlueLight", rxUpdateBlueLight)
	AddEventHandler("rxUpdatePreStageLight", rxUpdatePreStageLight)
	AddEventHandler("rxUpdateStageLight", rxUpdateStageLight)
	AddEventHandler("rxUpdateDisqualifiedLight", rxUpdateDisqualifiedLight)
	AddEventHandler("rxUpdateTreeLights", rxUpdateTreeLights)
	AddEventHandler("rxClearAll", rxClearAll)
	log('W', 'careerMP', 'CareerMP Drag Light Sync LOADED!')
end

local function onExtensionUnloaded()
	log('W', 'careerMP', 'CareerMP Drag Light Sync UNLOADED!')
end

M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
