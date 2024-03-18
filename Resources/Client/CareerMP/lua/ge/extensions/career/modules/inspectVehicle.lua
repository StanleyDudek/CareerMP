-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.dependencies = {}

local spawnedVehicleInfo
local wasCloseToSpawnedVehicle
local isCloseToSpawnedVehicle
local didTestDrive
local freezeVehicleCounter

local inspectScreenActive = false
local playStateActive

local inspectScreenDist = 6.5
local leaveInspectVehDist = 15
local despawnVehDist = 200
local testDriveInfo

local function spawnVehicle(shopId)
  local vehicleInfo = career_modules_vehicleShopping.getVehiclesInShop()[shopId]
  local spawnOptions = {}
  spawnOptions.config = vehicleInfo.key
  spawnOptions.autoEnterVehicle = false
  local newVeh = core_vehicles.spawnNewVehicle(vehicleInfo.model_key, spawnOptions)
  core_vehicleBridge.executeAction(newVeh,'setIgnitionLevel', 0)
  newVeh:queueLuaCommand(string.format("partCondition.initConditions(nil, %d)", vehicleInfo.Mileage))
  if vehicleInfo.aggregates.Type.Trailer then
    gameplay_walk.addVehicleToBlacklist(newVeh:getId())
  end
  return newVeh
end

local function onInspectScreenChanged(enabled)
  inspectScreenActive = enabled
end

local function setInspectScreen(enabled)
  if enabled == inspectScreenActive then return end
  if enabled then
    guihooks.trigger('ChangeState', {state = 'menu.inspectVehicle', params = {}})
  else
    guihooks.trigger('ChangeState', {state = 'play', params = {}})
  end
end

local function endInspecting()
  career_modules_testDrive.stop(false)
  setInspectScreen(false)
  spawnedVehicleInfo = nil
end

local function showVehicle(vehicleInfo)
  print("-----------------------------------------SHOW VEHICLE")
  dump(vehicleInfo)
  print("-----------------------------------------SHOW VEHICLE")
  
  if spawnedVehicleInfo then
    print("-----------------------------------------spawnedVehicleInfo")
    dump(spawnedVehicleInfo)
    print("-----------------------------------------spawnedVehicleInfo")
    local veh = be:getObjectByID(spawnedVehicleInfo.vehId)
    if veh then veh:delete() end
  end

  local vehObj
  if vehicleInfo then
    vehObj = spawnVehicle(vehicleInfo.shopId)
    spawnedVehicleInfo = {shopId = vehicleInfo.shopId, vehId = vehObj:getID(), name = vehicleInfo.Brand .. " " .. vehicleInfo.Name, value = vehicleInfo.Value}
    if vehicleInfo.sellerId ~= "private" then
      --local dealership = freeroam_facilities.getDealership(vehicleInfo.sellerId)
      --local plateText = dealership.testDrive.licencePlate or string.sub(dealership.name, math.min(7, #dealership.name))
      --core_vehicles.setPlateText(plateText, vehObj:getID())
    end
    career_modules_testDrive.resetData()
    career_modules_inspectVehicle.onUIPlayStateChanged(true)
  else
    endInspecting()
  end

  freezeVehicleCounter = 5
  wasCloseToSpawnedVehicle = false
  didTestDrive = false
  return vehObj
end

local function leaveInspectVehicleJob(job)
  local needsRepair = job.args[1]
  local abandonTestDrive = job.args[2]

  gameplay_walk.addVehicleToBlacklist(spawnedVehicleInfo.vehId)
  showVehicle(nil)
  job.sleep(0.20)
  if abandonTestDrive or needsRepair then
    local helper = {
      ttl = 5,
      msg = "You have left the sale ...",
      category = "flowgraphh"
    }
    guihooks.trigger('Message',helper)
  end
  if needsRepair then
    career_modules_insurance.makeTestDriveDamageClaim()
  end
end

local function leaveInspectVehicle(needsRepair, abandonTestDrive)
  if spawnedVehicleInfo == nil then return end
  if abandonTestDrive == nil then abandonTestDrive = false end
  core_jobsystem.create(leaveInspectVehicleJob, 1, needsRepair, abandonTestDrive)
end

local function defineTestDriveInfo(vehicleInfo, parkingSpot)
  if vehicleInfo.sellerId == "private" then
    testDriveInfo = {
      timeLimit = 120,
      abandonFees = 0
    }
  else
    local dealership = freeroam_facilities.getDealership(vehicleInfo.sellerId)
    local route
    if dealership.testDrive then
      if dealership.testDrive.parkingSpotRoutes then
        for i, parkingSpotRoute in pairs(dealership.testDrive.parkingSpotRoutes) do
          if parkingSpotRoute.parkingSpotName == parkingSpot.name then
            route = parkingSpotRoute.route
          end
        end
      end
      testDriveInfo = {
        timeLimit = dealership.testDrive.timeLimit,
        areaLimit = dealership.testDrive.areaLimit,
        abandonFees = dealership.testDrive.abandonFees or 0,
        route = route,
        dealershipName = dealership.name,
        dealershipPreview = dealership.preview
      }
      if dealership.testDrive.enableEndParkingSpot then
        testDriveInfo.endParkingSpot = parkingSpot
      end
    else
      testDriveInfo = {}
      log('W','testDrive', "Dealership : '" .. dealership.name .. "' doesn't have any 'testDriveRules' which shouldn't be possible. At least one constraint has to be given")
    end
  end

  testDriveInfo.vehicleInfo = vehicleInfo
end

local function turnTowardsPos(pos)
  core_vehicleBridge.requestValue(be:getPlayerVehicle(0), function()
    gameplay_walk.setRot(pos - be:getPlayerVehicle(0):getPosition())
  end , 'ping')
end

local function showDealershipVehicle(vehicleInfo, teleportToVehicle)
  local vehObj = showVehicle(vehicleInfo)
  if not vehObj then return end

  local parkingSpot
  local spawnPointElsewhere

  if vehicleInfo.sellerId == "private" then
    parkingSpot = gameplay_parking.getParkingSpots().byName[vehicleInfo.parkingSpotName]
    spawnPointElsewhere = true
  else
    local dealership = freeroam_facilities.getDealership(vehicleInfo.sellerId)
    local parkingSpots = freeroam_facilities.getParkingSpotsForFacility(dealership)
    parkingSpot = gameplay_sites_sitesManager.getBestParkingSpotForVehicleFromList(vehObj:getID(), parkingSpots)

    if vehicleInfo.sellerId == career_modules_vehicleShopping.getCurrentSellerId() then
      gameplay_walk.setWalkingMode(true)
      turnTowardsPos(parkingSpot.pos)
    else
      spawnPointElsewhere = true
    end
  end

  parkingSpot:moveResetVehicleTo(vehObj:getID(), nil, nil, nil, nil, true)

  if teleportToVehicle then
    career_modules_quickTravel.quickTravelToPos(parkingSpot.pos, true)
  else
    if spawnPointElsewhere then
      core_groundMarkers.setFocus(parkingSpot.pos)
    end
  end

  defineTestDriveInfo(vehicleInfo, parkingSpot)
end

local function buySpawnedVehicle()
  local vehObj = be:getObjectByID(spawnedVehicleInfo.vehId)
  career_modules_testDrive.stop(false)
  core_vehicleBridge.executeAction(vehObj, 'setFreeze', false)
  career_modules_vehicleShopping.buySpawnedVehicle(spawnedVehicleInfo)
  endInspecting()
end

local function sendUIData()
  local veh = be:getObjectByID(spawnedVehicleInfo.vehId)
  if not veh then return end

  core_vehicleBridge.requestValue(veh,
    function(res)
      guihooks.trigger('inspectVehicleData',
      {
        spawnedVehicleInfo = spawnedVehicleInfo,
        needsRepair = career_modules_insurance.partConditionsNeedRepair(res.result),
        isTutorial = career_modules_linearTutorial and career_modules_linearTutorial.isLinearTutorialActive() or false,
        didTestDrive = didTestDrive,
        claimPrice = career_modules_insurance.getTestDriveClaimPrice()
      })
    end,
    'getPartConditions')
end

local function onUpdate(dtReal, dtSim, dtRaw)
  if not spawnedVehicleInfo then return end

  local vehObj = be:getObjectByID(spawnedVehicleInfo.vehId)
  local playerVehObj = be:getPlayerVehicle(0)
  local distanceToVeh = vehObj:getPosition():distance(playerVehObj:getPosition())
  isCloseToSpawnedVehicle = distanceToVeh < inspectScreenDist

  -- Freeze the vehicle after some frames
  if freezeVehicleCounter then
    freezeVehicleCounter = freezeVehicleCounter - 1
    if freezeVehicleCounter <= 0 then
      core_vehicleBridge.executeAction(vehObj, 'setFreeze', true)
      freezeVehicleCounter = nil
    end
  end

  -- enable/disable the inspect screen only when in play mode or in the inspect screen.
  -- specifically not in the esc menu
  if playStateActive or inspectScreenActive then
    if isCloseToSpawnedVehicle and not career_modules_testDrive.hasAbandonned() then
      setInspectScreen(true)
      wasCloseToSpawnedVehicle = true
    else
      if not career_modules_testDrive.isActive() then
        setInspectScreen(false)
      end
    end
  end

  if wasCloseToSpawnedVehicle and distanceToVeh > leaveInspectVehDist and not career_modules_testDrive.isActive() and not career_modules_testDrive.hasAbandonned() then
    career_modules_insurance.genericVehNeedsRepair(spawnedVehicleInfo.vehId,
      function() leaveInspectVehicle(true, true) end,
      function() leaveInspectVehicle(false, true) end
    )
  end

  if wasCloseToSpawnedVehicle and distanceToVeh > despawnVehDist then
    -- TODO also put a timelimit in case the player doesnt drive to the vehicle
    showVehicle(nil)
  end
end

local function onUIPlayStateChanged(enteredPlay)
  playStateActive = enteredPlay
end

local function onAnyMissionChanged(state, mission)
  if not careerActive then return end
  if mission then
    if state == "started" then
      showVehicle(nil)
    end
  end
end

local function onTestDriveStarted()
  didTestDrive = true
end

local function startTestDrive()
  career_modules_testDrive.start(spawnedVehicleInfo.vehId, testDriveInfo)
end

local function endTestDrive()
  career_modules_testDrive.stop()
end

local function getSpawnedVehicleInfo()
  return spawnedVehicleInfo
end

--this function is only used during tutorial
local function repairVehicleJob(job)
  ui_fadeScreen.start(1)
  job.sleep(1.5)
  career_modules_insurance.payRepairIfNeededGenericVeh(spawnedVehicleInfo.vehId)
  ui_fadeScreen.stop(1)
  job.sleep(1.0)
end

local function repairVehicle()
  core_jobsystem.create(repairVehicleJob)
end

M.repairVehicle = repairVehicle
M.showVehicle = showVehicle
M.buySpawnedVehicle = buySpawnedVehicle
M.startTestDrive = startTestDrive
M.endTestDrive = endTestDrive
M.showDealershipVehicle = showDealershipVehicle
M.endInspecting = endInspecting
M.leaveInspectVehicle = leaveInspectVehicle
M.sendUIData = sendUIData
M.onInspectScreenChanged = onInspectScreenChanged
M.getSpawnedVehicleInfo = getSpawnedVehicleInfo

M.onAnyMissionChanged = onAnyMissionChanged
M.onTestDriveStarted = onTestDriveStarted
M.onUpdate = onUpdate
M.onUIPlayStateChanged = onUIPlayStateChanged

return M
