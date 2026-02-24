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
  if not changes then return end
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
    dragData.strip.treeLights = initTree()
    dragData.strip.displayDigits = initDisplay()
    guihooks.trigger('updateTreeLightStaging', true)
  end
end

local function clearLights()
  --log("I", logTag, "Clear all the lights")
  rand = math.random() + 2
  stagedAmount = 0
  if not dragData then return end
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
  --log("I", logTag, "Clear all the displays")
  if not dragData then return end
  for _, digitTypeData in pairs(dragData.strip.displayDigits) do
    for _,laneTypeData in ipairs(digitTypeData) do
      for _,digit in ipairs(laneTypeData) do
        digit:setHidden(true)
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
  local timeDisplayValue = {}
  local speedDisplayValue = {}
  local timeDigits = {}
  local speedDigits = {}

  local lane = dragData.racers[vehId].lane

  local timeVal =  dragData.racers[vehId].timers.time_1_4.value
  local velVal = dragData.racers[vehId].timers.velAt_1_4.value * 2.237 -- convert from m/s to mph

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
  if MPVehicleGE.isOwn(be:getPlayerVehicleID(0)) then
    TriggerServerEvent("txUpdateDisplay", jsonEncode( { lane = lane, timeDisplayValue = timeDisplayValue, speedDisplayValue = speedDisplayValue, dragData = dragData } ))
  end
end

local function handle400TreeLogic(timers, countDownLights, racer, vehId)
  if timers.laneTimer > rand and not timers.laneTimerFlag then
    timers.laneTimer = 0
    timers.laneTimerFlag = true

    countDownLights.amberLight1.obj:setHidden(false)
    countDownLights.amberLight2.obj:setHidden(false)
    countDownLights.amberLight3.obj:setHidden(false)
    countDownLights.amberLight1.isOn = true
    countDownLights.amberLight2.isOn = true
    countDownLights.amberLight3.isOn = true
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
    countDownLights.amberLight1.obj:setHidden(true)
    countDownLights.amberLight2.obj:setHidden(true)
    countDownLights.amberLight3.obj:setHidden(true)
    countDownLights.greenLight.obj:setHidden(racer.isDesqualified)
    countDownLights.redLight.obj:setHidden(not racer.isDesqualified)
    countDownLights.amberLight1.isOn = false
    countDownLights.amberLight2.isOn = false
    countDownLights.amberLight3.isOn = false
    countDownLights.greenLight.isOn = not racer.isDesqualified
    countDownLights.redLight.isOn = racer.isDesqualified
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

  local lightStages = {
    {1.0, 1.5, "amberLight1", false},
    {1.5, 2.0, "amberLight1", true, "amberLight2", false},
    {2.0, 2.5, "amberLight2", true, "amberLight3", false},
    {2.5, math.huge, "amberLight3", true, "greenLight", racer.isDesqualified}
  }

  for _, stage in ipairs(lightStages) do
    if t > stage[1] and t < stage[2] then

      if countDownLights[stage[3]].isOn == stage[4] then
        countDownLights[stage[3]].obj:setHidden(stage[4])
        countDownLights[stage[3]].isOn = not stage[4]
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
        countDownLights[stage[5]].obj:setHidden(stage[6])
        countDownLights[stage[5]].isOn = not stage[6]
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
      countDownLights.greenLight.obj:setHidden(racer.isDesqualified)
      countDownLights.greenLight.isOn = not racer.isDesqualified
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

local function onUpdate(dtReal, dtSim, dtRaw)
  for vehId, racer in pairs(dragData.racers) do
    if racer.treeStarted and not racer.isDesqualified then
      local treeLights = dragData.strip.treeLights[racer.lane]
      local timers = treeLights.timers
      local countDownLights = treeLights.countDownLights
      if not timers.dialOffset then
        timers.dialOffset = 0
      end
      timers.dialOffset = timers.dialOffset - dtSim

      if timers.dialOffset <= 0 then
        timers.laneTimer = timers.laneTimer + dtSim

        if dragData.prefabs.christmasTree.treeType == ".400" then
          handle400TreeLogic(timers, countDownLights, racer, vehId)
        else
          handle500TreeLogic(timers, countDownLights, racer, vehId)
        end
      end
    end
  end

  if driverLightBlinkState.isBlinking then
    local driverLight = dragData.strip.treeLights[driverLightBlinkState.lane].stageLights.driverLight
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


local function onWinnerLightOn(lane)
  if not dragData then return end
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
  if MPVehicleGE.isOwn(be:getPlayerVehicleID(0)) then
    TriggerServerEvent("txUpdateWinnerLight", jsonEncode( { driverLightBlinkState = driverLightBlinkState, dragData = dragData}))
  end
end

local function blueLightOn()
  -- Check if blue light exists in any lane
  if not dragData.strip.treeLights[1].globalLights.blueLight.obj then
    return
  end

  -- Update global blue light
  dragData.strip.treeLights[1].globalLights.blueLight.obj:setHidden(false)
  dragData.strip.treeLights[1].globalLights.blueLight.isOn = true

  updateTreeLightsUI(nil, {
    globalLights = {
      blueLight = true
    }
  })
end

local function blueLightOff()
  -- Check if blue light exists in any lane
  if not dragData.strip.treeLights[1].globalLights.blueLight.obj then
    return
  end

  -- Update global blue light
  dragData.strip.treeLights[1].globalLights.blueLight.obj:setHidden(true)
  dragData.strip.treeLights[1].globalLights.blueLight.isOn = false

  updateTreeLightsUI(nil, {
    globalLights = {
      blueLight = false
    }
  })
end

local function preStageLightOn(vehId)
  if not vehId or not dragData then return end
  if not dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.prestageLight.isOn then
    dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.prestageLight.obj:setHidden(false)
    dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.prestageLight.isOn = true
    updateTreeLightsUI(vehId, {
      stageLights = {
        prestageLight = true
      }
    })
    if not dragData.strip.treeLights[dragData.racers[vehId].lane].countDownLights.greenLight.isOn and not dragData.strip.treeLights[dragData.racers[vehId].lane].countDownLights.redLight.isOn then
      if dragData.racers[vehId].isPlayable then
        -- Clear old drag messages when entering prestage (new race sequence)
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
  if dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.prestageLight.isOn then
    dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.prestageLight.obj:setHidden(true)
    dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.prestageLight.isOn = false
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
    if dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj then
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
    if dragData.strip.treeLights[dragData.racers[vehId].lane].stageLights.stageLight.obj then
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

  countDownLights.amberLight1.obj:setHidden(true)
  countDownLights.amberLight2.obj:setHidden(true)
  countDownLights.amberLight3.obj:setHidden(true)
  countDownLights.greenLight.obj:setHidden(true)
  countDownLights.redLight.obj:setHidden(false)

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

local function resetDragRaceValues()
  clearAll()
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