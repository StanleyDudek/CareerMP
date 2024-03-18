-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.dependencies = {'career_career'}

local playerData = {trafficActive = 0} -- traffic data, parking data, etc.
local _devTraffic = {traffic = 1, police = 0, parkedCars = 1, active = 1} -- amounts to use while not in shipping mode

M.ensureTraffic = false
M.debugMode = not shipping_build

local function getPlayerData()
  return playerData
end

local function setPlayerData(newId, oldId)
  -- oldId is optional and is used if the vehicle was switched
  playerData.isParked = gameplay_parking.getCurrentParkingSpot(newId) and true or false

  if oldId then
    gameplay_parking.disableTracking(oldId)
  end
  if not gameplay_walk.isWalking() then
    gameplay_parking.enableTracking(newId)
  end

  playerData.traffic = gameplay_traffic.getTrafficData()[newId]
  playerData.parking = gameplay_parking.getTrackingData()[newId]
end

local function setTrafficVars()
  -- temporary police adjustment
  gameplay_traffic.setTrafficVars({enableRandomEvents = false})
  gameplay_police.setPursuitVars({arrestRadius = 15, evadeLimit = 30})
  gameplay_parking.setParkingVars({precision = 0.2}) -- allows for relaxed parking detection
end

local function setupTraffic(forceSetup)
  --if forceSetup or (gameplay_traffic.getState() == "off" and not gameplay_traffic.getTrafficList(true)[1] and playerData.trafficActive == 0) then
    --log("I", "career", "Now spawning traffic for career mode")
    -- TODO: revise this
    --local amount = 1 -- returns amount from user settings; at least 3 vehicles should get spawned
    --if not getAllVehiclesByType()[1] then -- if player vehicle does not exist yet
      --amount = amount - 1
    --end
    --local policeAmount = M.debugMode and _devTraffic.police or 0 -- temporarily disabled by default
    --local extraAmount = policeAmount -- enables traffic pooling
    --playerData.trafficActive = M.debugMode and _devTraffic.active or amount -- store the amount here for future usage
    --if playerData.trafficActive == 0 then playerData.trafficActive = math.huge end

    --gameplay_traffic.queueTeleport = true -- forces traffic vehicles to teleport away
    --gameplay_parking.setupVehicles(M.debugMode and _devTraffic.parkedCars)
    --gameplay_traffic.setupTraffic(M.debugMode and _devTraffic.traffic + extraAmount or amount + extraAmount, 0, {policeAmount = policeAmount, simpleVehs = true, autoLoadFromFile = true})
    --setTrafficVars()

    --M.ensureTraffic = false
  --else
    --if playerData.trafficActive == 0 then
      --playerData.trafficActive = gameplay_traffic.getTrafficVars().activeAmount
    --end
    --if not career_career.tutorialEnabled then
      setPlayerData(be:getPlayerVehicleID(0))
    --end
  --end
end

local function playerPursuitActive()
  return playerData.traffic and playerData.traffic.pursuit and playerData.traffic.pursuit.mode ~= 0
end

local function resetPlayerState()
  setPlayerData(be:getPlayerVehicleID(0))
  if playerData.traffic then playerData.traffic:resetAll() end

  setTrafficVars()
end

local function retrieveFavoriteVehicle()
  local inventory = career_modules_inventory
  local favoriteVehicleInventoryId = inventory.getFavoriteVehicle()
  if not favoriteVehicleInventoryId then return end
  local vehInfo = inventory.getVehicles()[favoriteVehicleInventoryId]
  if not vehInfo then return end

  local vehId = inventory.getVehicleIdFromInventoryId(favoriteVehicleInventoryId)
  if vehId then
    local playerVehObj = be:getPlayerVehicle(0)
    spawn.safeTeleport(be:getObjectByID(vehId), playerVehObj:getPosition(), quatFromDir(playerVehObj:getDirectionVector()), nil, nil, nil, nil, false)
  elseif not vehInfo.timeToAccess and not career_modules_insurance.inventoryVehNeedsRepair(favoriteVehicleInventoryId) then
    inventory.spawnVehicle(favoriteVehicleInventoryId, nil,
    function()
      local playerVehObj = be:getPlayerVehicle(0)
      local vehId = inventory.getVehicleIdFromInventoryId(favoriteVehicleInventoryId)
      spawn.safeTeleport(be:getObjectByID(vehId), playerVehObj:getPosition(), quatFromDir(playerVehObj:getDirectionVector()), nil, nil, nil, nil, false)
    end)
  end
end

local function deleteTrailers(veh)
  local trailerData = core_trailerRespawn.getTrailerData()
  local trailerDataThisVeh = trailerData[veh:getId()]

  if trailerDataThisVeh then
    local trailer = be:getObjectByID(trailerDataThisVeh.trailerId)
    deleteTrailers(trailer)
    career_modules_inventory.removeVehicleObject(career_modules_inventory.getInventoryIdFromVehicleId(trailerDataThisVeh.trailerId))
  end
end

local teleportTrailerJob = function(job)
  local args = job.args[1]
  local vehicle = be:getObjectByID(args.vehicleId)
  local trailer = be:getObjectByID(args.trailerId)
  local vehRot = quat(0,0,1,0) * quat(vehicle:getRefNodeRotation())
  local vehBB = vehicle:getSpawnWorldOOBB()
  local vehBBCenter = vehBB:getCenter()

  local trailerBB = vehicle:getSpawnWorldOOBB()

  spawn.safeTeleport(trailer, vehBBCenter - vehicle:getDirectionVector() * (vehBB:getHalfExtents().y + trailerBB:getHalfExtents().y), vehRot, nil, nil, nil, true, args.resetVeh)

  core_trailerRespawn.getTrailerData()[args.vehicleId] = nil
end

local function teleportToGarage(garageId, veh, resetVeh)
  freeroam_bigMapMode.navigateToMission(nil)
  freeroam_facilities.teleportToGarage(garageId, veh, resetVeh)

  local trailerData = core_trailerRespawn.getTrailerData()
  local primaryTrailerData = trailerData[veh:getId()]
  if primaryTrailerData then
    local teleportArgs = {
      trailerId = primaryTrailerData.trailerId,
      vehicleId = veh:getId(),
      resetVeh = resetVeh
    }
    core_jobsystem.create(teleportTrailerJob, 0.1, teleportArgs)

    career_modules_inventory.updatePartConditionsOfSpawnedVehicles(
      function()
        local trailer = be:getObjectByID(primaryTrailerData.trailerId)
        deleteTrailers(trailer)
      end
    )
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
end

local function onVehicleParkingStatus(vehId, data)
  if not gameplay_missions_missionManager.getForegroundMissionId() and not career_modules_linearTutorial.isLinearTutorialActive() and vehId == be:getPlayerVehicleID(0) then
    if data.event == "valid" then -- this refers to fully stopping while aligned in a parking spot
      if not playerData.isParked then
        playerData.isParked = true
        career_saveSystem.saveCurrent()
        log("I", "career", "Player saved progress in parking spot")
      end
    elseif data.event == "exit" then
      playerData.isParked = false
    end
  end
end

local function onTrafficStarted()
  if not career_career.tutorialEnabled and not gameplay_missions_missionManager.getForegroundMissionId() then
    gameplay_traffic.insertTraffic(be:getPlayerVehicleID(0), true) -- assumes that player vehicle is ready
    setPlayerData(be:getPlayerVehicleID(0))
    gameplay_traffic.setActiveAmount(playerData.trafficActive)

    for k, v in pairs(gameplay_traffic.getTrafficData()) do
      if v.role.name == "police" then
        v.activeProbability = 0.15 -- this should be based on career progression as well as zones
      end
    end
  end
end

local function onTrafficStopped()
  if playerData.traffic then table.clear(playerData.traffic) end

  if M.ensureTraffic then -- temp solution to reset traffic
    setupTraffic(true)
  end
end

local function onPursuitAction(vehId, data)
  if not gameplay_missions_missionManager.getForegroundMissionId() and vehId == be:getPlayerVehicleID(0) then
    if data.type == "start" then -- pursuit started
      gameplay_parking.disableTracking(vehId)
      --core_recoveryPrompt.deactivateAllButtons()
      log("I", "career", "Police pursuing player, now deactivating recovery prompt buttons")
    elseif data.type == "reset" or data.type == "evade" then -- pursuit ended, return to normal
      if not gameplay_walk.isWalking() then
        gameplay_parking.enableTracking(vehId)
      end
      --core_recoveryPrompt.setDefaultsForCareer()
      log("I", "career", "Pursuit ended, now activating recovery prompt buttons")
    elseif data.type == "arrest" then -- pursuit arrest, make the player pay a fine
      local fine = data.mode * data.uniqueOffensesCount * 100 -- fine value is WIP
      --fine = math.min(fine, career_modules_playerAttributes.getAttribute("money").value)
      career_modules_payment.pay({money = {amount = fine}}, {label = "Fine for being arrested by the police"})
      ui_message(translateLanguage("ui.traffic.policeFine", "You got fined by the police: ")..fine, 5, "careerPursuit")
    end
  end
end

local function onPlayerCameraReady()
  setupTraffic() -- spawns traffic while the loading screen did not fade out yet
end

local function onVehicleSwitched(oldId, newId)
  if not career_career.tutorialEnabled and not gameplay_missions_missionManager.getForegroundMissionId() then
    setPlayerData(newId, oldId)
  end
end

local function onUpdate(dtReal, dtSim, dtRaw)
  if not playerPursuitActive() then return end

  -- for now, prevent pursuit softlock by making the police give up
  if not playerData.pursuitStuckTimer then playerData.pursuitStuckTimer = 0 end
  if (playerData.traffic.speed < 3 and playerData.traffic.pursuit.timers.arrest == 0 and playerData.traffic.pursuit.timers.evade == 0)
  or not gameplay_police.getNearestPoliceVehicle(be:getPlayerVehicleID(0), false, true) then
    playerData.pursuitStuckTimer = playerData.pursuitStuckTimer + dtSim
    if playerData.pursuitStuckTimer >= 10 then
      log("I", "career", "Ending pursuit early due to conditions")
      gameplay_police.evadeVehicle(be:getPlayerVehicleID(0), true)
      playerData.pursuitStuckTimer = 0
    end
  else
    playerData.pursuitStuckTimer = 0
  end
end

local function onCareerModulesActivated(alreadyInLevel)
  if alreadyInLevel then
    setupTraffic()
  end
end

local function onExtensionLoaded()
end

local function onClientStartMission()
  setupTraffic()
end

M.getPlayerData = getPlayerData
M.retrieveFavoriteVehicle = retrieveFavoriteVehicle
M.playerPursuitActive = playerPursuitActive
M.resetPlayerState = resetPlayerState
M.teleportToGarage = teleportToGarage

M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onPlayerCameraReady = onPlayerCameraReady
M.onTrafficStarted = onTrafficStarted
M.onTrafficStopped = onTrafficStopped
M.onPursuitAction = onPursuitAction
M.onVehicleParkingStatus = onVehicleParkingStatus
M.onVehicleSwitched = onVehicleSwitched
M.onCareerModulesActivated = onCareerModulesActivated
M.onClientStartMission = onClientStartMission
M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate

return M