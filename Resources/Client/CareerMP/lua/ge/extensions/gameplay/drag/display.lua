-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
local logTag = ""

local rand
local stagedAmount = 0
local dragData
local flashTime = 1.5

local driverLightBlinkState = {
  lane = nil,
  isBlinking = false,
  timer = 0,
  frequency = 1/6, -- 6Hz = 1/6 seconds per cycle
  isOn = false
}

local function flashMessage(msg, duration)
  duration = duration or flashTime

  local messageData = {{msg, duration, 0, false}}

  -- Original direct UI trigger for backward compatibility
  guihooks.trigger('DragRaceTreeFlashMessage', messageData)

  -- Also hook into gameplayAppContainers for intelligent routing
  extensions.hook('onGameplayFlashMessage', {
    source = 'drag',
    data = messageData
  })
end

local function findLightObject(name, prefabId)
  if prefabId then
    local prefabInstance = scenetree.findObjectById(prefabId)
    if prefabInstance then
      local obj = prefabInstance:findObject(name)
      if obj then return obj end
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
  if not dragData then
    log("W", logTag, "initTree called but dragData is nil")
    return {}
  end

  if not dragData.strip then
    log("W", logTag, "initTree called but dragData.strip is nil")
    return {}
  end

  if not dragData.strip.lanes or #dragData.strip.lanes == 0 then
    log("W", logTag, "initTree called but dragData.strip.lanes is empty or nil")
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

-- Check if display digits are available (not nil)
local function hasDisplayDigits()
  if not dragData or not dragData.strip or not dragData.strip.displayDigits then
    return false
  end
  local digits = dragData.strip.displayDigits
  if not digits.timeDigits or not digits.speedDigits then
    return false
  end
  -- Check if at least one digit exists
  for _, laneDigits in ipairs(digits.timeDigits) do
    if laneDigits and #laneDigits > 0 and laneDigits[1] then
      return true
    end
  end
  return false
end

-- Check if tree lights are available (at least one light object exists)
local function hasTreeLights()
  if not dragData or not dragData.strip or not dragData.strip.treeLights then
    return false
  end
  for _, laneTree in ipairs(dragData.strip.treeLights) do
    if laneTree and laneTree.stageLights then
      -- Check if at least one light object exists
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

-- Send times data to UI app when display signs are not available
local function sendTimesToUI(vehId)
  if not dragData or not dragData.racers or not dragData.racers[vehId] then
    return
  end

  local racer = dragData.racers[vehId]
  if not racer.isPlayable then
    return
  end

  local timers = racer.timers or {}
  local timesData = {
    time_1_4 = timers.time_1_4 and timers.time_1_4.value or 0,
    velAt_1_4 = timers.velAt_1_4 and timers.velAt_1_4.value or 0,
    reactionTime = timers.reactionTime and timers.reactionTime.value or 0,
    time_60 = timers.time_60 and timers.time_60.value or 0,
    time_330 = timers.time_330 and timers.time_330.value or 0,
    time_1_8 = timers.time_1_8 and timers.time_1_8.value or 0,
    time_1000 = timers.time_1000 and timers.time_1000.value or 0,
    velAt_1_8 = timers.velAt_1_8 and timers.velAt_1_8.value or 0,
    lane = racer.lane
  }

  guihooks.trigger("updateDragRaceTimes", timesData)
end

local function updateTreeLightsUI(vehId, changes)
  if not changes then return end

  -- Always send to UI, even if tree objects don't exist
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
    log("E", logTag, "Tried to get the display digits but there is none in the scene")
    return
  end
  return displayDigits
end

local function init()
  if dragData then
    dragData.strip.treeLights = initTree() or {}
    dragData.strip.displayDigits = initDisplay() or {}
    guihooks.trigger('updateTreeLightStaging', true)
  end
end

local function clearLights()
  rand = math.random() + 2
  stagedAmount = 0
  if not dragData then return end
  for _, laneTree in ipairs(dragData.strip.treeLights) do
    for _,group in pairs(laneTree) do
      if type(group) == "table" then
        for _,light in pairs(group) do
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
    frequency = 1/6, -- 6Hz = 1/6 seconds per cycle
    isOn = false
  }
  -- guihooks.trigger("updateStageApp", -100)
end


local function clearDisplay()
  if not dragData then return end
  for _, digitTypeData in pairs(dragData.strip.displayDigits) do
    for _,laneTypeData in ipairs(digitTypeData) do
      for _,digit in ipairs(laneTypeData) do
        if digit and simObjectExists(digit) then
          digit:setHidden(true)
        end
      end
    end
  end
  if MPVehicleGE.isOwn(be:getPlayerVehicleID(0)) then
    TriggerServerEvent("txClearDisplay", "")
  end
end

local function clearAll()
  clearLights()
  clearDisplay()
  math.randomseed(os.time())
  if MPVehicleGE.isOwn(be:getPlayerVehicleID(0)) then
    TriggerServerEvent("txClearAll", "")
  end
end

local function onExtensionLoaded()
  if gameplay_drag_general then
    dragData = gameplay_drag_general.getData()
  end
  init()
  clearAll()

end

local function updateDisplay(vehId)
  local lane = dragData.racers[vehId].lane
  local timeVal = dragData.racers[vehId].timers.time_1_4.value
  local velVal = dragData.racers[vehId].timers.velAt_1_4.value

  -- If display signs are not available, send times to UI app instead
  if not hasDisplayDigits() then
    sendTimesToUI(vehId)
    return
  end

  local timeDisplayValue = {}
  local speedDisplayValue = {}
  local timeDigits = {}
  local speedDigits = {}

  timeDigits = dragData.strip.displayDigits.timeDigits[lane]
  speedDigits = dragData.strip.displayDigits.speedDigits[lane]

  if timeVal < 10 then
    table.insert(timeDisplayValue, "empty")
  end

  if velVal < 100 then
    table.insert(speedDisplayValue, "empty")
  end

  -- Three decimal points for time
  for num in string.gmatch(string.format("%.3f", timeVal), "%d") do
    table.insert(timeDisplayValue, num)
  end

  -- Two decimal points for speed
  for num in string.gmatch(string.format("%.2f", velVal), "%d") do
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
  if MPVehicleGE.isOwn(be:getPlayerVehicleID(0)) then
    TriggerServerEvent("txUpdateDisplay", jsonEncode( { lane = lane, timeDisplayValue = timeDisplayValue, speedDisplayValue = speedDisplayValue, dragData = dragData } ))
  end
end

local function handle400TreeLogic(timers, countDownLights, racer, vehId)
  local hasTree = hasTreeLights()

  if timers.laneTimer > rand and not timers.laneTimerFlag then
    timers.laneTimer = 0
    timers.laneTimerFlag = true

    if hasTree then
      if countDownLights.amberLight1.obj and simObjectExists(countDownLights.amberLight1.obj) then countDownLights.amberLight1.obj:setHidden(false) end
      if countDownLights.amberLight2.obj and simObjectExists(countDownLights.amberLight2.obj) then countDownLights.amberLight2.obj:setHidden(false) end
      if countDownLights.amberLight3.obj and simObjectExists(countDownLights.amberLight3.obj) then countDownLights.amberLight3.obj:setHidden(false) end
    end
    countDownLights.amberLight1.isOn = true
    countDownLights.amberLight2.isOn = true
    countDownLights.amberLight3.isOn = true

    -- Always send to UI, even if tree objects don't exist
    if racer.isPlayable then
      updateTreeLightsUI(vehId, {
        countDownLights = {
          amberLight1 = true,
          amberLight2 = true,
          amberLight3 = true
        }
      })
    end
  end

  if timers.laneTimerFlag and timers.laneTimer >= 0.4 then
    if hasTree then
      if countDownLights.amberLight1.obj and simObjectExists(countDownLights.amberLight1.obj) then countDownLights.amberLight1.obj:setHidden(true) end
      if countDownLights.amberLight2.obj and simObjectExists(countDownLights.amberLight2.obj) then countDownLights.amberLight2.obj:setHidden(true) end
      if countDownLights.amberLight3.obj and simObjectExists(countDownLights.amberLight3.obj) then countDownLights.amberLight3.obj:setHidden(true) end
      if countDownLights.greenLight.obj and simObjectExists(countDownLights.greenLight.obj) then countDownLights.greenLight.obj:setHidden(racer.isDesqualified) end
      if countDownLights.redLight.obj and simObjectExists(countDownLights.redLight.obj) then countDownLights.redLight.obj:setHidden(not racer.isDesqualified) end
    end
    countDownLights.amberLight1.isOn = false
    countDownLights.amberLight2.isOn = false
    countDownLights.amberLight3.isOn = false
    countDownLights.greenLight.isOn = not racer.isDesqualified
    countDownLights.redLight.isOn = racer.isDesqualified

    -- Always send to UI, even if tree objects don't exist
    if racer.isPlayable then
      flashMessage("Go!", 5)
      updateTreeLightsUI(vehId, {
        countDownLights = {
          amberLight1 = false,
          amberLight2 = false,
          amberLight3 = false,
          greenLight = not racer.isDesqualified,
          redLight = racer.isDesqualified
        }
      })
    end
    extensions.hook("startRaceFromTree", vehId)
    racer.treeStarted = false
    timers.laneTimerFlag = false
  end
end

local function handle500TreeLogic(timers, countDownLights, racer, vehId)
  local t = timers.laneTimer
  local hasTree = hasTreeLights()

  local lightStages = {
    {1.0, 1.5, "amberLight1", false},
    {1.5, 2.0, "amberLight1", true, "amberLight2", false},
    {2.0, 2.5, "amberLight2", true, "amberLight3", false},
    {2.5, math.huge, "amberLight3", true, "greenLight", racer.isDesqualified}
  }

  for _, stage in ipairs(lightStages) do
    if t > stage[1] and t < stage[2] then
      if countDownLights[stage[3]].isOn == stage[4] then
        if hasTree and countDownLights[stage[3]].obj and simObjectExists(countDownLights[stage[3]].obj) then
          countDownLights[stage[3]].obj:setHidden(stage[4])
        end
        countDownLights[stage[3]].isOn = not stage[4]

        -- Always send to UI, even if tree objects don't exist
        if racer.isPlayable then
          updateTreeLightsUI(vehId, {
            countDownLights = {
              [stage[3]] = not stage[4]
            }
          })
        end
      end
      -- Update secondary light if present and state changed
      if stage[5] and countDownLights[stage[5]].isOn == stage[6] then
        if hasTree and countDownLights[stage[5]].obj and simObjectExists(countDownLights[stage[5]].obj) then
          countDownLights[stage[5]].obj:setHidden(stage[6])
        end
        countDownLights[stage[5]].isOn = not stage[6]

        -- Always send to UI, even if tree objects don't exist
        if racer.isPlayable then
          updateTreeLightsUI(vehId, {
            countDownLights = {
              [stage[5]] = not stage[6]
            }
          })
        end
      end
    end
  end

  if t > 2.5 then
    extensions.hook("startRaceFromTree", vehId)
    racer.treeStarted = false

    if countDownLights.greenLight.isOn == racer.isDesqualified then
      if hasTree and countDownLights.greenLight.obj and simObjectExists(countDownLights.greenLight.obj) then
        countDownLights.greenLight.obj:setHidden(racer.isDesqualified)
      end
      countDownLights.greenLight.isOn = not racer.isDesqualified

      -- Always send to UI, even if tree objects don't exist
      if racer.isPlayable then
        flashMessage("Go!", 5)
        updateTreeLightsUI(vehId, {
          countDownLights = {
            greenLight = not racer.isDesqualified,
            redLight = racer.isDesqualified
          }
        })
      end
    end
  end
end

-- minimum temporary fix
-- only for freeroam drag racing, hide the visual UI tree lights if the player is too far away from the start line
local function checkDisableTreeLightsUI()
  if not dragData or
  not dragData.racers or
  gameplay_drag_general.getGameplayContext() ~= "freeroam"
  or not ui_gameplayAppContainers.getAppVisibility('gameplayApps', 'drag')
  then return end

  for vehId, racer in pairs(dragData.racers) do
    if racer.isPlayable then
      -- Make sure updateRacer has run before checking distance, otherwise distance will be very high for one frame instead of correct
      if racer.currentDistanceFromOrigin == nil then
        return
      end

      gameplay_drag_utils.calculateDistanceOfAllWheelsFromStagePos(racer)
      local distance = gameplay_drag_utils.getFrontWheelDistanceFromStagePos(racer)
      if distance and math.abs(distance) > 10 then
        ui_gameplayAppContainers.hideApp('gameplayApps', 'drag')
        flashMessage("")
      end
      return
    end
  end
end

local function onUpdate(dtReal, dtSim, dtRaw)
  if not gameplay_drag_general then return end

  dragData = gameplay_drag_general.getData()
  if not dragData then return end

  -- Early return if drag system is not properly initialized (e.g., during crawl missions)
  if not dragData.strip or not dragData.strip.treeLights then
    return
  end

  if dragData.flashUpdate then
    local shouldContinue = dragData.flashUpdate(dtSim)
    if not shouldContinue then
      dragData.flashUpdate = nil
    end
    return -- Skip normal update during flash sequence
  end

  checkDisableTreeLightsUI()

  for vehId, racer in pairs(dragData.racers) do
    -- Send times to UI continuously if display signs are not available and racer is in race phase
    if racer.timersStarted and not hasDisplayDigits() and racer.isPlayable then
      sendTimesToUI(vehId)
    end

    if racer.treeStarted and not racer.isDesqualified then
      local treeLights = dragData.strip.treeLights[racer.lane]
      if not treeLights then
        return
      end
      local timers = treeLights.timers
      local countDownLights = treeLights.countDownLights

      timers.dialOffset = timers.dialOffset - dtSim

      if timers.dialOffset <= 0 then
        timers.laneTimer = timers.laneTimer + dtSim

        if dragData.prefabs and dragData.prefabs.christmasTree and dragData.prefabs.christmasTree.treeType == ".400" then
          handle400TreeLogic(timers, countDownLights, racer, vehId)
        else
          handle500TreeLogic(timers, countDownLights, racer, vehId)
        end
      end
    end
  end

  if driverLightBlinkState.isBlinking then
    if not dragData.strip.treeLights[driverLightBlinkState.lane] then
      driverLightBlinkState.isBlinking = false
      driverLightBlinkState.isOn = false
      return
    end
    local driverLight = dragData.strip.treeLights[driverLightBlinkState.lane].stageLights.driverLight
    if driverLight and driverLight.obj and simObjectExists(driverLight.obj) then
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


local function onWinnerLightOn(lane)
  if not dragData then return end
  if lane then
    if dragData.strip.treeLights[lane].stageLights.winnerLight and dragData.strip.treeLights[lane].stageLights.winnerLight.obj and simObjectExists(dragData.strip.treeLights[lane].stageLights.winnerLight.obj) then
      dragData.strip.treeLights[lane].stageLights.winnerLight.isOn = true
      dragData.strip.treeLights[lane].stageLights.winnerLight.obj:setHidden(false)
    end
    if dragData.strip.treeLights[lane].stageLights.driverLight and dragData.strip.treeLights[lane].stageLights.driverLight.obj and simObjectExists(dragData.strip.treeLights[lane].stageLights.driverLight.obj) and not driverLightBlinkState.isBlinking then
      dragData.strip.treeLights[lane].stageLights.driverLight.isOn = true
      driverLightBlinkState.lane = lane
      driverLightBlinkState.isBlinking = true
      driverLightBlinkState.timer = 0
    end
  end
  if MPVehicleGE.isOwn(be:getPlayerVehicleID(0)) then
    TriggerServerEvent("txUpdateWinnerLight", jsonEncode( { driverLightBlinkState = driverLightBlinkState, dragData = dragData}))
  end
end

local function blueLightOn()
  if not dragData or not dragData.strip.treeLights or not dragData.strip.treeLights[1] then
    return
  end

  local hasTree = hasTreeLights()
  local blueLight = dragData.strip.treeLights[1].globalLights.blueLight

  -- Update global blue light object if it exists
  if hasTree and blueLight.obj and simObjectExists(blueLight.obj) then
    blueLight.obj:setHidden(false)
  end
  blueLight.isOn = true

  -- Always send to UI, even if tree objects don't exist
  updateTreeLightsUI(nil, {
    globalLights = {
      blueLight = true
    }
  })
end

local function blueLightOff()
  if not dragData or not dragData.strip.treeLights or not dragData.strip.treeLights[1] then
    return
  end

  local hasTree = hasTreeLights()
  local blueLight = dragData.strip.treeLights[1].globalLights.blueLight

  -- Update global blue light object if it exists
  if hasTree and blueLight.obj and simObjectExists(blueLight.obj) then
    blueLight.obj:setHidden(true)
  end
  blueLight.isOn = false

  -- Always send to UI, even if tree objects don't exist
  updateTreeLightsUI(nil, {
    globalLights = {
      blueLight = false
    }
  })
end

local function preStageLightOn(vehId)
  if not vehId or not dragData then return end
  local laneTree = dragData.strip.treeLights[dragData.racers[vehId].lane]
  if not laneTree or not laneTree.stageLights then return end

  if not laneTree.stageLights.prestageLight.isOn then
    local hasTree = hasTreeLights()
    if hasTree and laneTree.stageLights.prestageLight.obj and simObjectExists(laneTree.stageLights.prestageLight.obj) then
      laneTree.stageLights.prestageLight.obj:setHidden(false)
    end
    laneTree.stageLights.prestageLight.isOn = true

    -- Always send to UI, even if tree objects don't exist
    updateTreeLightsUI(vehId, {
      stageLights = {
        prestageLight = true
      }
    })
    if not dragData.strip.treeLights[dragData.racers[vehId].lane].countDownLights.greenLight.isOn and not dragData.strip.treeLights[dragData.racers[vehId].lane].countDownLights.redLight.isOn then
      if dragData.racers[vehId].isPlayable then
        if ui_gameplayAppContainers then
          ui_gameplayAppContainers.clearMessagesFromSource('drag')
        end
        flashMessage("Pre-stage")
      end
    end
  end


end

M.preStageLightOn = preStageLightOn


local function preStageLightOff(vehId)
  if not vehId or not dragData then return end
  local laneTree = dragData.strip.treeLights[dragData.racers[vehId].lane]
  if not laneTree or not laneTree.stageLights then return end

  if laneTree.stageLights.prestageLight.isOn then
    local hasTree = hasTreeLights()
    if hasTree and laneTree.stageLights.prestageLight.obj and simObjectExists(laneTree.stageLights.prestageLight.obj) then
      laneTree.stageLights.prestageLight.obj:setHidden(true)
    end
    laneTree.stageLights.prestageLight.isOn = false

    -- Always send to UI, even if tree objects don't exist
    if dragData.racers[vehId].isPlayable then
      updateTreeLightsUI(vehId, {
        stageLights = {
          prestageLight = false
        }
      })
    end
  end
end
M.preStageLightOff = preStageLightOff


local function stageLightOn(vehId)
  if not vehId or not dragData then return end
  if not dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.isOn then
    if dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj and simObjectExists(dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj) then
      dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj:setHidden(false)
    end
    stagedAmount = stagedAmount + 1
    dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.isOn = true
    if stagedAmount >= #dragData.strip.treeLights then
      blueLightOn()
      stagedAmount = #dragData.strip.treeLights
    end
    if dragData.racers[vehId].isPlayable then
      updateTreeLightsUI(vehId, {
        stageLights = {
          stageLight = true
        }
      })
    end
    if not dragData.strip.treeLights[dragData.racers[vehId].lane].countDownLights.greenLight.isOn and not dragData.strip.treeLights[dragData.racers[vehId].lane].countDownLights.redLight.isOn then
      if dragData.racers[vehId].isPlayable then
        flashMessage("Stage")
      end
    end
  end
end

M.stageLightOn = stageLightOn

local function stageLightOff(vehId)
  if not vehId or not dragData then return end
  if dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.isOn then
    if dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj and simObjectExists(dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj) then
      dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj:setHidden(true)
    end
    dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.isOn = false
    blueLightOff()
    if stagedAmount > 0 then
      stagedAmount = stagedAmount - 1
    end
    if dragData.racers[vehId].isPlayable then
      updateTreeLightsUI(vehId, {
        stageLights = {
          stageLight = false
        }
      })
    end
  end
end
M.stageLightOff = stageLightOff


local function startDragCountdown(vehId, dial)
  if not dragData then return end
  extensions.hook("onDragCountdownStarted", vehId, dial)
  dragData.racers[vehId].treeStarted = true
  dragData.strip.treeLights[dragData.racers[vehId].lane].timers.dialOffset = dial
end

local function setDisqualifiedLights(vehId)
  if not dragData or not vehId then return end

  local racer = dragData.racers[vehId]
  if not racer then return end

  local treeLights = dragData.strip.treeLights[racer.lane]
  local countDownLights = treeLights.countDownLights

  if countDownLights.amberLight1.obj and simObjectExists(countDownLights.amberLight1.obj) then countDownLights.amberLight1.obj:setHidden(true) end
  if countDownLights.amberLight2.obj and simObjectExists(countDownLights.amberLight2.obj) then countDownLights.amberLight2.obj:setHidden(true) end
  if countDownLights.amberLight3.obj and simObjectExists(countDownLights.amberLight3.obj) then countDownLights.amberLight3.obj:setHidden(true) end
  if countDownLights.greenLight.obj and simObjectExists(countDownLights.greenLight.obj) then countDownLights.greenLight.obj:setHidden(true) end
  if countDownLights.redLight.obj and simObjectExists(countDownLights.redLight.obj) then countDownLights.redLight.obj:setHidden(false) end

  countDownLights.amberLight1.isOn = false
  countDownLights.amberLight2.isOn = false
  countDownLights.amberLight3.isOn = false
  countDownLights.greenLight.isOn = false
  countDownLights.redLight.isOn = true
  extensions.hook("startRaceFromTree", vehId)
  if racer.isPlayable then
    updateTreeLightsUI(vehId, {
      countDownLights = {
        amberLight1 = false,
        amberLight2 = false,
        amberLight3 = false,
        greenLight = false,
        redLight = true
      }
    })
    flashMessage("False start", 5)
  end
end



local function dragRaceStarted(vehId)
end

local function stoppingVehicleDrag(vehId)
  if dragData and dragData.racers[vehId] and dragData.racers[vehId].isPlayable then
    flashMessage("Stop the vehicle!", 5)
  end
end

local function dragRaceEndLineReached(vehId)
  updateDisplay(vehId)
end

local function dragRaceVehicleStopped()
  guihooks.trigger('updateTreeLightPhase', false)
  clearAll()
end

local function flashAllLightsAndDisplay()
  if not dragData then return end

  -- Flash sequence: OFF → 1/6s → ON → 1/6s → OFF → 1/6s → ON → 1/6s → OFF (stay off)
  local flashDuration = 1/6 -- 1/6 second intervals
  local totalFlashTime = 4/6 -- 4 intervals total

  extensions.hook('onGameplayFlashMessage', {
    source = 'drag',
    data = {{"SYSTEM RESET", totalFlashTime, 0, false}}
  })

  local flashTimer = 0
  local flashState = 0 -- 0=wait for first on, 1=on, 2=off, 3=on, 4=off, 5=done

  local function updateFlash(dtSim)
    flashTimer = flashTimer + dtSim

    if flashState == 0 and flashTimer >= flashDuration then
      -- First flash on
      for _, laneTree in ipairs(dragData.strip.treeLights) do
        for _, group in pairs(laneTree) do
          if type(group) == "table" then
            for _, light in pairs(group) do
              if type(light) == "table" and light.obj and simObjectExists(light.obj) then
                light.obj:setHidden(false)
              end
            end
          end
        end
      end
      for _, digitTypeData in pairs(dragData.strip.displayDigits) do
        for _, laneTypeData in ipairs(digitTypeData) do
          for _, digit in ipairs(laneTypeData) do
            if digit and simObjectExists(digit) then
              digit:preApply()
              digit:setField('shapeName', 0, "art/shapes/quarter_mile_display/display_0.dae")
              digit:setHidden(false)
              digit:postApply()
            end
          end
        end
      end
      flashState = 1
      flashTimer = 0
    elseif flashState == 1 and flashTimer >= flashDuration then
      -- First flash off
      for _, laneTree in ipairs(dragData.strip.treeLights) do
        for _, group in pairs(laneTree) do
          if type(group) == "table" then
            for _, light in pairs(group) do
              if type(light) == "table" and light.obj and simObjectExists(light.obj) then
                light.obj:setHidden(true)
              end
            end
          end
        end
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
      flashState = 2
      flashTimer = 0
    elseif flashState == 2 and flashTimer >= flashDuration then
      -- Second flash on
      for _, laneTree in ipairs(dragData.strip.treeLights) do
        for _, group in pairs(laneTree) do
          if type(group) == "table" then
            for _, light in pairs(group) do
              if type(light) == "table" and light.obj and simObjectExists(light.obj) then
                light.obj:setHidden(false)
              end
            end
          end
        end
      end
      for _, digitTypeData in pairs(dragData.strip.displayDigits) do
        for _, laneTypeData in ipairs(digitTypeData) do
          for _, digit in ipairs(laneTypeData) do
            if digit and simObjectExists(digit) then
              digit:setHidden(false)
            end
          end
        end
      end
      flashState = 3
      flashTimer = 0
    elseif flashState == 3 and flashTimer >= flashDuration then
      -- Second flash off (final state)
      for _, laneTree in ipairs(dragData.strip.treeLights) do
        for _, group in pairs(laneTree) do
          if type(group) == "table" then
            for _, light in pairs(group) do
              if type(light) == "table" and light.obj and simObjectExists(light.obj) then
                light.obj:setHidden(true)
              end
            end
          end
        end
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
      flashState = 4
      flashTimer = 0
    elseif flashState == 4 and flashTimer >= flashDuration then
      flashState = 5
      clearAll()
      return false -- Stop the update loop
    end

    return true -- Continue the update loop
  end

  -- Store the update function in dragData so it can be called from onUpdate
  dragData.flashUpdate = updateFlash
end

local function resetDragRaceValues()
  flashAllLightsAndDisplay()
end

M.clearAll = clearAll
M.onBeforeDragUnloadAllExtensions = clearLights
M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded

--HOOKS
M.startDragCountdown = startDragCountdown
M.setDisqualifiedLights = setDisqualifiedLights

M.dragRaceStarted = dragRaceStarted
M.dragRaceEndLineReached = dragRaceEndLineReached

M.dragRaceVehicleStopped = dragRaceVehicleStopped
M.resetDragRaceValues = resetDragRaceValues
M.onWinnerLightOn = onWinnerLightOn
M.stoppingVehicleDrag = stoppingVehicleDrag

return M
