-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

--M.dependencies = {"career_modules_delivery_cargoManager","career_modules_delivery_logisticDataBaseManager"}
M.dependencies = {"core_vehicleBridge"}
local cargoManager, database
M.onCareerModulesActivated = function()
  cargoManager = career_modules_delivery_cargoManager
  database = career_modules_delivery_logisticDataBaseManager
  --gameplay_markerInteraction.clearCache()
end
M.dependencies = {"util_stepHandler"}
local cargoOverviewScreenOpen = false
local cargoScreenFacId, cargoScreenPsPath = nil, nil
local cargoOverviewScreenOpenedTime = -1
local cargoOverviewMaxTimeTimestamp = -1
local sentNewCargoNotificationAlready = false

local deliveryModeActive = false
local deliveryAbandonPenaltyFactor = 0.1

-- how far back in time items should be shown
local pastDeliveryTimespan = 60

local vehTypeToCargoSlots = {
  Car = {
    parcel = 6
  },
  Truck = {
    parcel = 14
  },
  Trailer = {
    parcel = 8
  },
}
local function getVehicleCargoSlots(vehId)
  local vehType = "Car"-- TODO: get correct type
  return vehTypeToCargoSlots[vehType]
end


local function formatCargoGroup(group, playerCargoContainers, longLabel, showFirstSeen)
  longLabel = true
  local labelFunction = longLabel and cargoManager.getLocationLabelLong or cargoManager.getLocationLabelShort

  local ret = {
    ids = {}, -- implicit count of included objects in this group
    name = group[1].name,
    originName = labelFunction(group[1].origin),
    locationName = labelFunction(group[1].location),
    destinationName = labelFunction(group[1].destination),
    origin = group[1].origin,
    location = group[1].location,
    destination = group[1].destination,
    type = group[1].type,
    slots = 0,
    distance = group[1].data.originalDistance, -- m
    rewards = {},
    enabled = true, -- not needed in player view
    disableReason = "No space", -- not needed in player view
    targetLocations = {},
    transient = group[1].transient or false,
    _preTransientLocation = group[1]._preTransientLocation or nil,
    remainingOfferTime = group[1].offerExpiresAt - (database.time()),
    remainingDeliveryTime = math.random()*360,
    weight = group[1].weight,
    --firstSeen = group[1].firstSeen,
    modifiers = {}
  }
  if showFirstSeen then
    if group[1].firstSeen and (database.time() - group[1].firstSeen) < 3 then
      ret.showNewTimer = 3 - (database.time() - group[1].firstSeen)
    end
  end
  --ret.name = ret.name .. (group[1].firstSeen and group[1].firstSeen or "not seen")
  local modifierKeys = {}
  for _, v in ipairs(group[1].modifiers) do
    local mod = {}
    mod.type = v.type
    modifierKeys[v.type] = true
    if v.type == "timed" then
      mod.data = {
        active = group[1].location.type == "vehicle" and not group[1].transient,
        deliveryTime = v.deliveryTime,
        paddingTime = v.paddingTime,
        remainingDeliveryTime = v.expirationTimeStamp and (v.expirationTimeStamp - database.time()) or v.deliveryTime,
        paddedRemainingDeliveryTime = v.definitiveExpirationTimeStamp and (v.definitiveExpirationTimeStamp - database.time()) or v.deliveryTime + v.paddingTime,
      }
      mod.data.remainingPaddingTime = mod.data.remainingDeliveryTime > 0 and mod.data.paddingTime or mod.data.paddedRemainingDeliveryTime

    elseif v.type == "fragile" then
      mod.data = {
        active = group[1].location.type == "vehicle" and group[1].transient,
        health = v.health,
        currentHealth = v.currentHealth,
        label = "Fragile: " .. v.currentHealth,
      }
    end
    table.insert(ret.modifiers, mod)
  end

  if not database.isTimedDeliveriesUnlocked() and modifierKeys.timed then
    ret.enabled = false
    ret.disableReason = "Locked"
  elseif not database.isFragileDeliveriesUnlocked() and modifierKeys.fragile then
    ret.enabled = false
    ret.disableReason = "Locked"
  elseif not database.isTimedFragileDeliveriesUnlocked() and modifierKeys.timed and modifierKeys.fragile then
    ret.enabled = false
    ret.disableReason = "Locked"
  end


  ret.rewards = group[1].rewards
  ret.slots = group[1].slots

  if #group == 1 then
    ret.ids = {group[1].id}
  else
    for _, cargo in ipairs(group) do
      table.insert(ret.ids, cargo.id)
      --ret.slots = ret.slots + cargo.slots
      --for key, value in pairs(cargo.rewards) do
      --  ret.rewards[key] = (ret.rewards[key] or 0) + value
      --end
    end
  end

  if playerCargoContainers then
    -- Only add the container with the least free cargo space
    table.sort(playerCargoContainers, function(a,b) return a.freeCargoSlots < b.freeCargoSlots end)
    for _, con in ipairs(playerCargoContainers) do
      local elem = {
        enabled = con.freeCargoSlots >= group[1].slots and con.cargoTypesLookup[group[1].type] and ret.remainingOfferTime > 0,
        label = con.moveToLabel,
        location = con.location
      }
      if elem.enabled then
        elem.disableReason = (not elem.enabled) and "No space a"
        table.insert(ret.targetLocations, elem)
        break
      end
    end
  end
  if not next(ret.targetLocations) then
    ret.enabled = false
    ret.disableReason = "No Space"
  end


  ret.id = ret.ids[#ret.ids]
  --dump(ret)
  return ret
end

local lowestIdSort = function(a,b) return a.ids[1] < b.ids[1] end
local function clusterFormatCargo(cargo, playerCargoContainers, longLabel, updateFirstSeen)
  local ret = {}
  --cargo can only be clustered if their groupId is the same and transient is the same
  --current location also needs to be the same, but that is guaranteed by the caller of this function
  local cargoByGroupId = {}
  for _, c in ipairs(cargo) do
    local gId = string.format("%d-%s-%d", c.groupId, c.transient or false, c.loadedAtTimeStamp or -1)
    cargoByGroupId[gId] = cargoByGroupId[gId] or {}
    cargoManager.ensureCargoDistanceAndRewards(c)
    if updateFirstSeen then
      c.firstSeen = c.firstSeen or database.time()
    end
    table.insert(cargoByGroupId[gId], c)
  end
  -- format each group individually
  for _, group in pairs(cargoByGroupId) do
    table.insert(ret, formatCargoGroup(group, playerCargoContainers, longLabel, updateFirstSeen))
  end
  table.sort(ret, lowestIdSort)
  return ret
end


local function getVehicleCargoContainers(veh)
  return {
    {
      id = 456789,
      name = "Small Container A",
      cargoSlots = {
        parcel = 3
      }
    }, {
      id = 224249,
      name = "Big Container A",
      cargoSlots = {
        parcel = 8
      }
    }
  }
end

local function getVehicleName(vehId)
  local inventoryId = career_modules_inventory.getInventoryIdFromVehicleId(vehId)
  local niceVehicleName = inventoryId and career_modules_inventory.getVehicles()[inventoryId].niceName
  local veh = scenetree.findObjectById(vehId)
  if veh then
    return niceVehicleName and niceVehicleName or "Vehicle " .. veh:getID()
  else
    veh = be:getPlayerVehicle(0)
    local vehID = be:getPlayerVehicleID(0)
    return niceVehicleName and niceVehicleName or "Vehicle UNKOWN? " .. veh:getID()
  end
end

local nearbyRadius = 25*25
local sortByVehIdAndContainerId = function(a,b) if a.vehId == b.vehId then return a.containerId < b.containerId else return a.vehId < b.vehId end end
local function getNearbyVehicleCargoContainers(callback)
  if not core_vehicleBridge then return {} end
  local vehCargoData = {}
  local playerPos = be:getPlayerVehicle(0)
  playerPos = playerPos and playerPos:getPosition() or getCameraPosition()
  local vehs = {}
  for vehId, veh in activeVehiclesIterator() do
    if MPVehicleGE.isOwn(vehId) then
      if veh:getJBeamFilename() ~= "unicycle" and veh.playerUsable ~= false and (playerPos-veh:getPosition()):squaredLength() < nearbyRadius then
        vehCargoData[vehId] = -1
        vehs[vehId] = veh
      end
    end
  end
  for vehId, veh in pairs(vehs) do
    if MPVehicleGE.isOwn(vehId) then
      core_vehicleBridge.requestValue(veh, function(vehCargoContainerData)
        vehCargoData[vehId] = {}

        for _, container in ipairs(vehCargoContainerData[1]) do

          local elem = {
            vehId = vehId,
            containerId = container.id,
            location = {type = "vehicle", vehId = veh:getID(), containerId = container.id},
            name = container.name,
            moveToLabel = getVehicleName(vehId) .. " " .. container.name,
            cargoTypesLookup = tableValuesAsLookupDict(container.cargoTypes),
            cargoTypesString = table.concat(container.cargoTypes,", "),
            totalCargoSlots = container.capacity,
            usedCargoSlots = 0,
            freeCargoSlots = container.capacity,
          }
          elem.rawCargo = cargoManager.getAllCargoForLocation(elem.location)
          --for key, amount in pairs(elem.totalCargoSlots) do
          --  elem.usedCargoSlots[key] = 0
          --end
          for _, cargo in ipairs(elem.rawCargo) do
            elem.usedCargoSlots = elem.usedCargoSlots + cargo.slots
            elem.freeCargoSlots = elem.freeCargoSlots - cargo.slots
          end
          table.insert(vehCargoData[vehId], elem)
        end

        -- check if all cargo was sent
        for key, val in pairs(vehCargoData) do
          if val == -1 then return end
        end

        -- if we're still here, call the function callback to send data back
        local ret = {}
        for _, list in pairs(vehCargoData) do
          for _, elem in ipairs(list) do
            table.insert(ret, elem)
          end
        end
        table.sort(ret, sortByVehIdAndContainerId)
        callback(ret)

      end, "getCargoContainers")
    end
  end
  if not next(vehs) then
    callback({})
  end

end
M.getNearbyVehicleCargoContainers = getNearbyVehicleCargoContainers

local visibleIdsToCargo = {}
local function requestCargoDataForUi(facId, psPath, updateMaxTimeTimestamp)
  if updateMaxTimeTimestamp ~= false then
    cargoOverviewMaxTimeTimestamp = database.time()
    cargoOverviewScreenOpenedTime = cargoOverviewMaxTimeTimestamp - pastDeliveryTimespan
  end
  sentNewCargoNotificationAlready = false
  getNearbyVehicleCargoContainers(function(playerCargoContainers)
    M.setVisibleIdsForBigMap(playerCargoContainers)
    freeroam_bigMapMode.setOnlyIdsVisible(tableKeys(visibleIdsToCargo))
    gameplay_rawPois.clear()
    freeroam_bigMapMarkers.clearMarkers()
    freeroam_bigMapMarkers.setNextMarkersFullAlphaInstant()

    local uiData = {
      player = {
        vehicles = {},
      }
    }
    local facPsLocation
    if facId and facId ~= "undefined" then
      local fac = database.getFacilityById(facId)
      uiData.facility = {
        name = fac.name,
        outgoingCargo = {},
        incomingCargo = {},
      }

      local unlocked, status = database.isFacilityUnlocked(facId)
      if not unlocked then
        uiData.facility.disabled = true
        uiData.facility.disabledReasonHeader = status.disabledReasonHeader
        uiData.facility.disabledReasonContent = status.disabledReasonContent
        uiData.facility.progress = status.progress
      end

      if psPath and psPath ~= "undefined" then
        local ps = database.getParkingSpotByPath(psPath)
        facPsLocation = {type = "facilityParkingspot", facId = facId, psPath = psPath}
        local outgoingCargo = cargoManager.getUndeliveredAllCargoForLocationUnexpired(facPsLocation, cargoOverviewScreenOpenedTime, cargoOverviewMaxTimeTimestamp)

        uiData.facility.outgoingCargo = clusterFormatCargo(outgoingCargo, playerCargoContainers, nil, true)
        --if fac.showIncomingCargo then
        --  local incomingCargo = cargoManager.getAllCargoForDestinationStillAtOriginUnexpired(facPsLocation, cargoOverviewScreenOpenedTime, cargoOverviewMaxTimeTimestamp)
        --  uiData.facility.incomingCargo = clusterFormatCargo(incomingCargo, nil, nil, false)
        --end
      else
        local itemsAtFacility = career_modules_delivery_cargoManager.getAllCargoCustomFilter(function(cargo)
          return cargo.location.facId == facId
          and cargo.offerExpiresAt > cargoOverviewScreenOpenedTime
          and cargo.generatedAtTimestamp <= cargoOverviewMaxTimeTimestamp
        end)
        --dumpz(itemsAtFacility)
        uiData.facility.outgoingCargo = clusterFormatCargo(itemsAtFacility, nil, true, true)
      end
    end
    --dumpz(nearbyVehicles, 1)
    local playerMoneySum = 0
    local playerWeightSum = 0
    local playerMoneySumNonTransient = 0
    local vehToLocationDistanceCache = {}
    for _, con in ipairs(playerCargoContainers) do
      local entry = {
        vehId = con.vehId,
        name = con.name,
        moveToLabel = con.moveToLabel,
        cargoTypesLookup = con.cargoTypesLookup,
        cargoTypesString = con.cargoTypesString,
        totalCargoSlots = con.totalCargoSlots,
        usedCargoSlots = con.usedCargoSlots,
        freeCargoSlots = con.freeCargoSlots,
        cargo = clusterFormatCargo(con.rawCargo, nil, not (facId and facId ~= "undefined")),
        weight = 0
      }
      for _, cargo in ipairs(entry.cargo) do
        playerMoneySum = playerMoneySum + #cargo.ids * cargo.rewards.money
        if not cargo.transient then
          playerMoneySumNonTransient = playerMoneySumNonTransient + #cargo.ids * cargo.rewards.money
        end
        cargo.targetLocations = {}
        local distanceKey = string.format("%d-%s-%s", con.vehId, cargo.destination.facId, cargo.destination.psPath)
        vehToLocationDistanceCache[distanceKey] = vehToLocationDistanceCache[distanceKey] or
          database.distanceBetween(database.getLocationCoordinates(cargo.location), database.getLocationCoordinates(cargo.destination))
        cargo.distance = vehToLocationDistanceCache[distanceKey]

        if cargo.transient then
          if cargo._preTransientLocation.type == "facilityParkingspot" and facPsLocation then
            table.insert(cargo.targetLocations, {label = "Put Back", location = facPsLocation, enabled = true})
            uiData.player.transientCargoExists = true
          end
        end
        for _, otherCon in ipairs(playerCargoContainers) do
          if con.containerId ~= otherCon.containerId then
            table.insert(cargo.targetLocations, {
              label = otherCon.moveToLabel,
              location = otherCon.location,
              enabled = (otherCon.freeCargoSlots >= cargo.slots and otherCon.cargoTypesLookup[cargo.type])
            })
          end
        end
        if not cargo.transient or (cargo.transient and cargo._preTransientLocation.type == "vehicle") then
          table.insert(cargo.targetLocations, {label = "Throw Away", location = {type="deleted"}, enabled = true, extraData = {penalty = cargo.rewards.money * deliveryAbandonPenaltyFactor}})
        end
        if uiData.facility then
          for _, outCargo in ipairs(uiData.facility.outgoingCargo or {}) do
            if cargoManager.sameLocation(outCargo.destination, cargo.destination) then
              outCargo.highlightDestinationName = true
            end
          end

          for _, inCargo in ipairs(uiData.facility.incomingCargo or {}) do
            if cargoManager.sameLocation(inCargo.destination, cargo.destination) then
              inCargo.highlightOriginName = true
            end
          end
        end


        entry.weight = entry.weight + cargo.weight * #cargo.ids
      end
      playerWeightSum = playerWeightSum + entry.weight

      if not uiData.player.vehicles[entry.vehId] then
        uiData.player.vehicles[entry.vehId] = { containers = {}, niceName = getVehicleName(entry.vehId), vehId = entry.vehId}
      end

      table.insert(uiData.player.vehicles[entry.vehId].containers, entry)
    end

    uiData.player.loadedCargoMoneySum = playerMoneySum
    uiData.player.penaltyForAbandon = playerMoneySumNonTransient * deliveryAbandonPenaltyFactor
    uiData.player.weightSum = playerWeightSum
    uiData.player.noContainers = not next(playerCargoContainers)
    -- convert vehicles table to list
    local vehicleInfoList = {}
    for vehId, vehicleInfo in pairs(uiData.player.vehicles) do
      table.sort(vehicleInfo.containers, function(a,b) return a.name < b.name end)
      table.insert(vehicleInfoList, vehicleInfo)
    end
    table.sort(vehicleInfoList, function(a,b) return a.vehId < b.vehId end)
    uiData.player.vehicles = vehicleInfoList

    guihooks.trigger("cargoDataForUiReady", uiData)
  end)
end

-- call this function to move the cargo to a different location. if moved to the player, a transient flag will be added. if moved back to facility, transient flag will be removed.
local function moveCargoFromUi(cargoId, targetLocation)
  --dump(cargoId, targetLocation)
  cargoManager.changeCargoLocation(cargoId, targetLocation, true)
  for poiId, list in pairs(visibleIdsToCargo) do
    for _, cargo in ipairs(list) do
      --dump(cargoId, cargo.id)
      if cargo.id == cargoId then
        --dump(poiId)
        --dump(freeroam_bigMapMode.navigateToMission(poiId))
        return
      end
    end
  end
end

-- call this function to commit the configuration and clear all transient flags.
local function commitDeliveryConfiguration()
  local playerCargo = cargoManager.getAllCargoCustomFilter(function(cargo) return cargo.location.type == "vehicle" end)
  local countTotal, countTransient, countDeleted, deletedMoneySum = 0,0,0,0

  for _, cargo in ipairs(playerCargo) do
    countTotal = countTotal + 1
    if cargo.transient then
      if cargo.location.type ~= "deleted" then
        countTransient = countTransient + 1
      else
        countDeleted = countDeleted + 1
        deletedMoneySum = deletedMoneySum + cargo.rewards.money
      end
    end
  end
  ui_message(string.format("Commited Delivery Configuration. (Cargo Added: %d. Total Cargo Loaded: %d)",countTransient, countTotal))
  if countDeleted > 1 then
    ui_message(string.format("Thrown away %d items. Penalty: %0.2f", countDeleted, deletedMoneySum * deliveryAbandonPenaltyFactor))
    career_modules_playerAttributes.addAttribute("money", -deletedMoneySum  * deliveryAbandonPenaltyFactor, {isGameplay = true, label="Penalty for throwing away cargo."})
  end

  if not deliveryModeActive and countTotal > 0 then
    M.startDeliveryMode()
  end
  cargoManager.clearTransientFlags()
  M.postCargoConfiguration()
end

-- call this function to cancel the delivery - all cargo will be placed back.
local function cancelDeliveryConfiguration()
  cargoManager.undoTransientCargo()
  ui_message("Cancelled Delivery Configuration.")
end


local function postCargoConfiguration(includeVehIds)
  log("I","","postCargoConfiguration")
  local updatePerVehicle = {}
  for vehId, veh in activeVehiclesIterator() do
    if MPVehicleGE.isOwn(vehId) then
      if veh:getJBeamFilename() ~= "unicycle" and veh.playerUsable ~= false then
        updatePerVehicle[vehId] = {}
      end
    end
  end
  for _, cargo in ipairs(cargoManager.getAllCargoCustomFilter(function(cargo) return cargo.location.type == "vehicle" end)) do
    updatePerVehicle[cargo.location.vehId][cargo.location.containerId] = updatePerVehicle[cargo.location.vehId][cargo.location.containerId] or {
      weight = 0,
      containerId = cargo.location.containerId
    }
    if not cargo.weight then dump("No weight", cargo) end
    updatePerVehicle[cargo.location.vehId][cargo.location.containerId].weight = updatePerVehicle[cargo.location.vehId][cargo.location.containerId].weight + (cargo.weight or 0)
  end

  for vehId, data in pairs(updatePerVehicle) do
    if MPVehicleGE.isOwn(vehId) then
      local veh = scenetree.findObjectById(vehId)
      core_vehicleBridge.executeAction(veh, "setCargoContainers", updatePerVehicle[vehId])
      for _, con in pairs(updatePerVehicle[vehId]) do
        log("Container " .. con.containerId .. " => " .. con.weight)
      end
      log("I","","Cargo container weights updated.")
    end
  end

end
M.postCargoConfiguration = postCargoConfiguration

local function highlightCargoInPoi(poiId)
  if not visibleIdsToCargo[poiId] then return end
  local cargoIds = {}
  for _, cargo in ipairs(visibleIdsToCargo[poiId]) do
    table.insert(cargoIds, cargo.cargo.id)
  end
  guihooks.trigger("SendHighlightedCargoIds", cargoIds)
end

local function deliveryMarkerSelected(poiId)
  --dump("markerSelected", poiId)
  if not visibleIdsToCargo[poiId] then return end
  --local cargo = visibleIdsToCargo[poiId][1]
  --dump("navigating to...")
  freeroam_bigMapMode.navigateToMission(poiId)
  highlightCargoInPoi(poiId)
end

M.onBigmapHoveredPoiIdChanged = function(poiId)
  if not cargoOverviewScreenOpen then return end
  highlightCargoInPoi(poiId or freeroam_bigMapMode.selectedPoiId)
end

local function showCargoRoutePreview(cargoId)
  if cargoId == nil then
    freeroam_bigMapMode.clearRoutePreview()
    return
  end
  local cargo = cargoManager.getCargoById(cargoId)
  if not cargo then return end
  local fromPos = cargoManager.getLocationCoordinates(cargo.location)
  local toPos = cargoManager.getLocationCoordinates(cargo.destination)
  if fromPos and toPos then
    freeroam_bigMapMode.setRoutePreviewSimple(fromPos, toPos)
  end
end

local function setCargoRoute(cargoId, origin)
  if cargoId == nil then
    return
  end
  local cargo = cargoManager.getCargoById(cargoId)
  if not cargo then return end
  local toPos = cargoManager.getLocationCoordinates(origin and cargo.origin or cargo.destination)
  if toPos then
    freeroam_bigMapMode.setNavFocus(toPos)
  end
end

M.showCargoRoutePreview = showCargoRoutePreview
M.setCargoRoute = setCargoRoute


M.setVisibleIdsForBigMap = function(playerCargoContainers)
  visibleIdsToCargo = {}

  if cargoScreenFacId then
    local facility = career_modules_delivery_logisticDataBaseManager.getFacilityById(cargoScreenFacId)
    if cargoScreenPsPath then
      local facPsLocation = {type = "facilityParkingspot", facId = cargoScreenFacId, psPath = cargoScreenPsPath}
      -- TODO: also get all the cargo that is to be delivered to the current facility
      local outgoingCargo = cargoManager.getUndeliveredAllCargoForLocationUnexpired(facPsLocation, cargoOverviewScreenOpenedTime, cargoOverviewMaxTimeTimestamp)
      for _, cargo in ipairs(outgoingCargo) do
        local id = string.format("delivery-parking-%s-%s", cargo.destination.facId, cargo.destination.psPath)
        visibleIdsToCargo[id] = visibleIdsToCargo[id] or {}
        table.insert(visibleIdsToCargo[id], {cargo = cargo, outgoing = true, loc = cargo.destination})
      end
      local id = string.format("delivery-parking-%s-%s", facPsLocation.facId, facPsLocation.psPath)
      visibleIdsToCargo[id] = visibleIdsToCargo[id] or {}

      --[[if facility.showIncomingCargo then
        local incomingCargo = cargoManager.getAllCargoForDestinationStillAtOriginUnexpired(facPsLocation, cargoOverviewScreenOpenedTime, cargoOverviewMaxTimeTimestamp)
        for _, cargo in ipairs(incomingCargo) do
          local id = string.format("delivery-parking-%s-%s", cargo.origin.facId, cargo.origin.psPath)
          visibleIdsToCargo[id] = visibleIdsToCargo[id] or {}
          table.insert(visibleIdsToCargo[id], {cargo = cargo, incoming = true, loc = cargo.origin})
        end
      end]]
    else
      local itemsAtFacility = career_modules_delivery_cargoManager.getAllCargoCustomFilter(
        function(cargo)
          return cargo.location.facId == cargoScreenFacId
          and cargo.offerExpiresAt > cargoOverviewScreenOpenedTime
          and cargo.generatedAtTimestamp <= cargoOverviewMaxTimeTimestamp
        end)
      for _, cargo in ipairs(itemsAtFacility) do
        local id = string.format("delivery-parking-%s-%s", cargo.destination.facId, cargo.destination.psPath)
        visibleIdsToCargo[id] = visibleIdsToCargo[id] or {}
        table.insert(visibleIdsToCargo[id], {cargo = cargo, outgoing = true, loc = cargo.destination})
        id = string.format("delivery-parking-%s-%s", cargo.origin.facId, cargo.origin.psPath)
        visibleIdsToCargo[id] = visibleIdsToCargo[id] or {}
        table.insert(visibleIdsToCargo[id], {cargo = cargo, incoming = true, loc = cargo.destination})
      end
      for _, ps in ipairs(facility.pickUpSpots or {}) do
        local id = string.format("delivery-parking-%s-%s", cargoScreenFacId, ps:getPath())
        visibleIdsToCargo[id] = visibleIdsToCargo[id] or {}
      end
    end
  end
  for _, con in ipairs(playerCargoContainers) do
    for _, cargo in ipairs(con.rawCargo) do
      local id = string.format("delivery-parking-%s-%s", cargo.destination.facId, cargo.destination.psPath)
      visibleIdsToCargo[id] = visibleIdsToCargo[id] or {}
      table.insert(visibleIdsToCargo[id], {cargo = cargo, player = true, loc = cargo.destination} )
    end
  end
end

local function enterCargoOverviewScreen(facilityId, parkingSpotPath)
  getNearbyVehicleCargoContainers(function(playerCargoContainers)
    cargoOverviewScreenOpen = true
    cargoScreenFacId, cargoScreenPsPath = facilityId, parkingSpotPath
    cargoOverviewScreenOpenedTime = database.time() - pastDeliveryTimespan
    cargoOverviewMaxTimeTimestamp = database.time()

    M.setVisibleIdsForBigMap(playerCargoContainers)


    gameplay_rawPois.clear()
    --dump(tableKeys(visibleIdsToCargo))
    freeroam_bigMapMode.enterBigmapWithCustomPOIs(tableKeys(visibleIdsToCargo), deliveryMarkerSelected, true, 2)
    guihooks.trigger('ChangeState', {state = 'menu.cargoOverview', params = {facilityId = facilityId, parkingSpotPath = parkingSpotPath}})
    extensions.hook("onEnterCargoOverviewScreen")
  end)
end
M.enterCargoOverviewScreen = enterCargoOverviewScreen


local function exitCargoOverviewScreen(facilityId, parkingSpotPath)
  cargoOverviewScreenOpen = false
  commitDeliveryConfiguration()
  gameplay_rawPois.clear()
  career_career.closeAllMenus()
  freeroam_bigMapMode.exitBigMap(true)
  simTimeAuthority.pause(false) -- this is only necessary because the career pause menu doesnt unpause in time for the bigmap to start, so the bigmap will not unpause by itself
end

local function onCargoGenerated(cargo)
  if not cargoOverviewScreenOpen then return end
  if sentNewCargoNotificationAlready then return end
  if not cargoScreenFacId then return end
  if cargo.origin.facId ~= cargoScreenFacId then return end
  if cargoScreenPsPath and cargo.origin.psPath ~= cargoScreenPsPath then return end
  sentNewCargoNotificationAlready = true
  guihooks.trigger("newCargoAvailable")
end

M.onCargoGenerated = onCargoGenerated


M.requestCargoDataForUi = requestCargoDataForUi
M.moveCargoFromUi = moveCargoFromUi
M.commitDeliveryConfiguration = commitDeliveryConfiguration
M.cancelDeliveryConfiguration = cancelDeliveryConfiguration
M.exitCargoOverviewScreen = exitCargoOverviewScreen

local cargoIdToTasklistElementId = {}
local tasklistElements = {}
local function sendCargoToTasklist()
  cargoIdToTasklistElementId = {}
  tasklistElements = {}
  guihooks.trigger('ClearTasklist')
  M.getNearbyVehicleCargoContainers(function(containers)
    local hook = "SetTasklistTask"
    local cargoCount = 0
    local cargoGrouped = {}
    for _, con in ipairs(containers) do
      for _, cargo in ipairs(con.rawCargo) do
        local gId = string.format("%s-%s", cargoManager.getLocationLabelLong(cargo.destination),
          #cargo.modifiers == 0 and "noMods"
          or string.format("%s-%s-%0.2f", cargo.groupId, cargo.transient or false, cargo.loadedAtTimeStamp or -1)
          )
        cargoCount = cargoCount +1
        cargoGrouped[gId] = (cargoGrouped[gId] or {})
        table.insert(cargoGrouped[gId], cargo.id)
      end
    end
    for _, gId in ipairs(tableKeysSorted(cargoGrouped)) do
      local tasklistElement = {
        cargoIds = cargoGrouped[gId],
        id = gId,
        update = true,
      }
      tasklistElements[gId] = tasklistElement
      for _, cId in ipairs(cargoGrouped[gId]) do
        cargoIdToTasklistElementId[cId] = gId
      end
    end
    if next(tasklistElements) then
      guihooks.trigger("SetTasklistHeader", {
        label = "Active Deliveries",
        subtext = string.format("%d Items loaded.", cargoCount)
      })
    end
  end)
end


M.sendCargoToTasklist = sendCargoToTasklist
local function updateCargoTasklistElements()
  for _, tasklistId in ipairs(tableKeysSorted(tasklistElements)) do
    local elem = tasklistElements[tasklistId]
    if elem.update then
      local first = cargoManager.getCargoById(elem.cargoIds[1])
      local modifierStrings = {string.format("%d Item%s", #elem.cargoIds, #elem.cargoIds~=1 and "s" or "")}

      for _, mod in ipairs(first.modifiers) do
        if mod.type == "timed" then
          local tasklistTime = mod.expirationTimeStamp and (mod.expirationTimeStamp - database.time() > 0 and mod.expirationTimeStamp - database.time()
                or mod.definitiveExpirationTimeStamp - database.time() > 0 and mod.definitiveExpirationTimeStamp - database.time()
                or 0) or mod.deliveryTime
          local tasklistLabel = mod.expirationTimeStamp and (mod.expirationTimeStamp - database.time() > 0 and "Time"
                or mod.definitiveExpirationTimeStamp - database.time() > 0 and "Delayed"
                or "Late") or "Time"
          table.insert(modifierStrings, string.format("%s: %ds", tasklistLabel, tasklistTime))
        elseif mod.type == "fragile" then
          local desc = "Intact"
          if mod.currentHealth < 90 then desc = "Damaged" end
          if mod.currentHealth <= 0 then desc = "Destroyed" end
          table.insert(modifierStrings, string.format("Fragile: %d (%s)", mod.currentHealth, desc))
        end
      end
      guihooks.trigger("SetTasklistTask", {
          clear = true,
          id = "cargo"..tasklistId,
          type = "message"
        }
      )
      guihooks.trigger("SetTasklistTask", {
          label = string.format("Deliver to %s",  cargoManager.getLocationLabelLong(first.destination)),
          subtext = table.concat(modifierStrings, ", "),
          active = true,
          id = "cargo"..tasklistId,
          type = "message"
        }
      )
    end
    elem.update = false
  end
end
M.updateCargoTasklistElements = updateCargoTasklistElements

M.updateTasklistForCargoId = function(cargoId)
  if cargoIdToTasklistElementId[cargoId] and tasklistElements[cargoIdToTasklistElementId[cargoId]] then
    tasklistElements[cargoIdToTasklistElementId[cargoId]].update = true
  end
end

M.onUpdate = function()
  profilerPushEvent("Delivery DeliveryManager")
  M.updateCargoTasklistElements()
  profilerPopEvent("Delivery DeliveryManager")
end


-- poi list stuff
local function onGetRawPoiListForLevel(levelIdentifier, elements)

  --local nearbyVehicles = M.getNearbyVehicleCargoContainers()
  local playerDestinationParkingSpots = {}
  --for _, veh in ipairs(nearbyVehicles) do
    for _, cargo in ipairs(cargoManager.getAllCargoCustomFilter(function(cargo) return cargo.location.type == "vehicle" end)) do
      playerDestinationParkingSpots[cargo.destination.psPath] = playerDestinationParkingSpots[cargo.destination.psPath] or {facId = cargo.destination.facId, cargo = {}}
      table.insert(playerDestinationParkingSpots[cargo.destination.psPath].cargo, cargo)
    end
  --end

  for _, fac in ipairs(freeroam_facilities.getFacilitiesByType("deliveryProvider")) do
    -- only process facilities if the facility is visible
    if database.isFacilityVisible(fac.id) then
      local totalCargoCount = 0
      local lastPsPos = nil
      local allSpotsLookup = {}
      if database.isFacilityVisible(fac.id) and (cargoOverviewScreenOpen or database.isFacilityUnlocked(fac.id)) then
        if next(fac.logisticTypesProvided) then
          for _, ps in ipairs(fac.pickUpSpots or {}) do
            allSpotsLookup[ps:getPath()] = ps
          end
        end
      end
      for _, ps in ipairs(fac.dropOffSpots or {}) do
        if playerDestinationParkingSpots[ps:getPath()] or cargoOverviewScreenOpen then
          allSpotsLookup[ps:getPath()] = ps
        end
      end
      for _, ps in pairs(allSpotsLookup) do
        local id = string.format("delivery-parking-%s-%s", fac.id, ps:getPath())
        local loc = {type = "facilityParkingspot", facId = fac.id, psPath = ps:getPath()}
        local cargoCount = #cargoManager.getUndeliveredAllCargoForLocationUnexpired(loc)
        totalCargoCount = totalCargoCount + cargoCount
        lastPsPos = ps.pos
        local icon = "poi_pickup_round"
        --if cargoOverviewScreenOpen then
        --  icon = "poi_delivery_pickup_3"
        --else
          if playerDestinationParkingSpots[ps:getPath()] then
            icon = "poi_dropoff_round"
          end
        --end
        local focus = playerDestinationParkingSpots[ps:getPath()] ~= nil
        local elem = {
          id = id,
          data = {type = "logisticsParking", facId = fac.id, psPath = ps:getPath(), hasPlayerCargo = playerDestinationParkingSpots[ps:getPath()] and true or false },
          markerInfo = {
            -- only include parking marker if there is an action
            parkingMarker = cargoCount and {path = ps:getPath(), pos = ps.pos, rot = ps.rot, scl = ps.scl, icon = icon, focus = focus} or nil,
          }
        }
        if cargoOverviewScreenOpen then
          elem.markerInfo.bigmapMarker = {pos = ps.pos, name = "Pickup "..fac.name, icon = icon}
        else
          if playerDestinationParkingSpots[ps:getPath()] then
            local desc = string.format("Deliver %d cargo items to this location.", #playerDestinationParkingSpots[ps:getPath()].cargo)
            elem.markerInfo.bigmapMarker = {
              pos = ps.pos,
              name = cargoManager.getLocationLabelLong(playerDestinationParkingSpots[ps:getPath()].cargo[1].destination),
              description = desc,
              icon = "poi_dropoff_round",
              previews = {fac.preview},
              thumbnail = fac.preview,
            }
          end
        end
        table.insert(elements, elem)
      end

      -- one POI for the whole facility to display on bigmap under labourer branch.
      if not cargoOverviewScreenOpen then
        if database.isFacilityUnlocked(fac.id) and next(fac.logisticTypesProvided) then
          local id = string.format("logisticsFacility-%s", fac.id)
          local elems = {}
          if fac.doors and next(fac.doors) then
            freeroam_facilities.walkingMarkerFormatFacility(fac, elems)
          end
          local elem = {
            id = id,
            data = {type = "logisticsOffice", facId = fac.id},
            markerInfo = {
              walkingMarker = next(elems) and elems[1].markerInfo.walkingMarker or nil,
              bigmapMarker = {pos = lastPsPos, name = fac.name, description = string.format("%s\n\n%d Item%s available here.",fac.description, totalCargoCount, totalCargoCount ~= 1 and "s" or ""), icon="poi_delivery_round", previews = {fac.preview}, thumbnail = fac.preview,} or nil
            }
          }
          table.insert(elements, elem)
        end
      end
    end
  end
end
M.onGetRawPoiListForLevel = onGetRawPoiListForLevel



local function onActivityAcceptGatherData(elemData, activityData)
  for _, elem in ipairs(elemData) do
    if elem.type == "logisticsOffice" then
      local data = {
        icon = "poi_delivery_round",
        heading = database.getFacilityById(elem.facId).name,
        preheadings = {"Logistics Office"},
        sorting = {
          type = elem.type,
          id = elem.id
        },
        props = {{
          icon = "icons.general.check",
          keyLabel = "Cargo Overview"
        },{
          icon = "icons.general.check",
          keyLabel = "No Cargo Pickup"
        }},
        buttonLabel = "Inspect Cargo",
        buttonFun = function() enterCargoOverviewScreen(elem.facId) end
      }
      table.insert(activityData, data)
    elseif elem.type == "logisticsParking" then
      -- cargo menu button
      local props = {}
      local data = {
        icon = "poi_pickup_round",
        heading = cargoManager.getLocationLabelLong({type = "facilityParkingspot", facId = elem.facId, psPath = elem.psPath}),
        preheadings = {"Cargo Pickup"},
        sorting = {
          type = elem.type,
          id = elem.id
        },
        props = {{
          icon = "icons.general.check",
          keyLabel = "Cargo Overview"
        }},
        buttonLabel = "Inspect Cargo",
        buttonFun = function() enterCargoOverviewScreen(elem.facId, elem.psPath) end
      }
      local loc = {type = "facilityParkingspot", facId = elem.facId, psPath = elem.psPath}
      local cargoCount = #cargoManager.getUndeliveredAllCargoForLocationUnexpired(loc)
      table.insert(data.props, {
        icon = "icons.general.check",
        keyLabel = string.format("%d Item%s available", cargoCount, cargoCount ~= 1 and "s" or "")
      })

      table.insert(activityData, data)


      -- unload cargo
      M.getNearbyVehicleCargoContainers(function(playerCargoContainers)
        local playerDestinationParkingSpots = {}
        local playerVehIds = {}
        for _, con in ipairs(playerCargoContainers) do
          playerVehIds[con.vehId] = true
          for _, cargo in ipairs(con.rawCargo) do
            playerDestinationParkingSpots[cargo.destination.psPath] = playerDestinationParkingSpots[cargo.destination.psPath] or {facId = cargo.destination.facId, cargo = {}}
            table.insert(playerDestinationParkingSpots[cargo.destination.psPath].cargo, cargo)
          end
        end

        if playerDestinationParkingSpots[elem.psPath] then
          -- move all the cargo in the players inventory, whose destination is this parking spot to the parking spot
          local psLoc = {type = "facilityParkingspot", facId = elem.facId, psPath = elem.psPath}
          for _, con in ipairs(playerCargoContainers) do
            for _, cargo in ipairs(con.rawCargo) do
              if cargoManager.sameLocation(cargo.destination, psLoc) then
                cargoManager.changeCargoLocation(cargo.id, cargo.destination)
              end
            end
          end
          cargoManager.checkDeliveredCargo()
          M.checkExitDeliveryMode()
          M.postCargoConfiguration(tableKeys(playerVehIds))

          -- check saving
          --local ps = database.getParkingSpotByPath(elem.psPath)
          --local veh = be:getPlayerVehicle(0)
          --if not ps or not veh then return end
          --local inside = ps:checkParking(veh)
          career_saveSystem.saveCurrent()
        end
      end)
    end
  end
end
M.onActivityAcceptGatherData = onActivityAcceptGatherData


local deliveryActivity = {
  id = "deliveryMode",
  name = "Delivery Mode",

  vehicleModification = "warning",-- Slow and Fast Repairing, Changing and buying parts, tuning, painting
  vehicleSelling = "warning", --selling a vehicle
  vehicleStorage = "warning", --put vehicles into storage
  vehicleRetrieval = "allowed", --retrieve vehicles from storage

  vehicleShopping = "forbidden",

  interactRefuel = "allowed", --use the refueling POI to refuel vehicle
  interactMission = "warning", --use the mission POI to start a mission
  interactDelivery = "allowed", --use any delivery POI to start delivery mode

  recoveryFlipUpright = "allowed", --flip upright
  recoveryTowToRoad = "allowed", --tow to road
  recoveryTowToGarage = "warning", --tow to garage

  getLabel = function(tag, permission)
    local penalty = M.getDeliveryModePenalty()
    if     tag == "vehicleModification" then
      return string.format("Modifying a vehicle will end Delivery Mode (Penalty: %0.2f$)", penalty)
    elseif tag == "vehicleSelling" then
      return string.format("Selling a vehicle will end Delivery Mode (Penalty: %0.2f$)", penalty)
    elseif tag == "vehicleStorage" then
      return string.format("Storing a vehicle will end Delivery Mode (Penalty: %0.2f$)", penalty)
    elseif tag == "interactMission" then
      return string.format("Starting a Mission will end Delivery Mode (Penalty: %0.2f$)", penalty)
    elseif tag == "recoveryTowToGarage" then
      return string.format("Towing to garage will end Delivery Mode (Penalty: %0.2f$)", penalty)
    elseif tag == "vehicleShopping" then
      return "Disabled during Delivery Mode."
    end
  end
}

local function startDeliveryMode()
  if deliveryModeActive then return end
  log("I","","Delivery Mode Started.")
  deliveryModeActive = true
  career_modules_permissions.setForegroundActivity(deliveryActivity)
  gameplay_rawPois.clear()
end

local function exitDeliveryMode()
  if not deliveryModeActive then return end
  log("I","","Delivery Mode Exited.")
  cargoManager.clearTransientFlags()
  -- get all cargo currently in vehicles.
  local cargoInVehicles = cargoManager.getAllCargoCustomFilter(function(cargo) return cargo.location.type == "vehicle" end)
  --dump(cargoInVehicles)
  if next(cargoInVehicles) then
    local totalMoneyRewards = 0
    for _, cargo in ipairs(cargoInVehicles) do
      totalMoneyRewards = totalMoneyRewards + cargo.rewards.money
      cargoManager.changeCargoLocation(cargo.id, {type="deleted"})
    end
    if totalMoneyRewards > 0 then
      guihooks.trigger("toastrMsg", {type="warning", title="Cargo abandoned", msg=string.format("Cargo was thrown away because delivery mode ended. Penalty: %0.2f$", totalMoneyRewards * deliveryAbandonPenaltyFactor)})
      log("I","",string.format("Penalty for abandoning cargo: %0.2f$", totalMoneyRewards * deliveryAbandonPenaltyFactor))
      career_modules_playerAttributes.addAttribute("money", -totalMoneyRewards  * deliveryAbandonPenaltyFactor, {isGameplay = true, label="Penalty for abandoning cargo."})
      Engine.Audio.playOnce('AudioGui', 'event:>UI>Career>Buy_01')
    end
  end
  deliveryModeActive = false
  career_modules_permissions.clearForegroundActivityIfIdIs('deliveryMode')
  gameplay_rawPois.clear()
  M.postCargoConfiguration()
  --core_gamestate.setGameState("career", "career")
end

local function checkExitDeliveryMode()
  local cargoInVehicles = cargoManager.getAllCargoCustomFilter(function(cargo) return cargo.location.type == "vehicle" end)
  if not next(cargoInVehicles) then
    M.exitDeliveryMode()
  end
end

M.startDeliveryMode = startDeliveryMode
M.exitDeliveryMode = exitDeliveryMode
M.checkExitDeliveryMode = checkExitDeliveryMode
M.isDeliveryModeActive = function() return deliveryModeActive end
M.getDeliveryModePenalty = function()
  local cargoInVehicles = cargoManager.getAllCargoCustomFilter(function(cargo) return cargo.location.type == "vehicle" end)
  --dump(cargoInVehicles)
  if next(cargoInVehicles) then
    local totalMoneyRewards = 0
    for _, cargo in ipairs(cargoInVehicles) do
      totalMoneyRewards = totalMoneyRewards + cargo.rewards.money
    end
    return totalMoneyRewards * deliveryAbandonPenaltyFactor
  end
  return 0
end

-- actions that stop delivery mode

M.onPartShoppingStarted = function()
  if deliveryModeActive then
    log("I","","Stopped Delivery mode because shopping started.")
    M.exitDeliveryMode()
  end
end

M.onCareerPaintingStarted = function()
  if deliveryModeActive then
    log("I","","Stopped Delivery mode because painting started.")
    M.exitDeliveryMode()
  end
end

M.onCareerTuningStarted = function()
  if deliveryModeActive then
    log("I","","Stopped Delivery mode because tuning started.")
    M.exitDeliveryMode()
  end
end

M.onTeleportedToGarage = function(garageId, veh)
  if deliveryModeActive then
    log("I","","Stopped Delivery mode because towed to garage.")
    M.exitDeliveryMode()
  end
end

M.onAnyMissionChanged = function(change)
  if change == "started" then
    if deliveryModeActive then
      log("I","","Stopped Delivery mode because mission started.")
      M.exitDeliveryMode()
    end
  end
end

M.onInventoryPreRemoveVehicleObject = function(inventoryId, vehId)
  if deliveryModeActive then
    local cargoInVehicle = cargoManager.getAllCargoForLocation({type = "vehicle", vehId = vehId})
    if next(cargoInVehicle) then
      local totalMoneyRewards = 0
      for _, cargo in ipairs(cargoInVehicle) do
        totalMoneyRewards = totalMoneyRewards + cargo.rewards.money
        cargoManager.changeCargoLocation(cargo.id, {type="deleted"})
      end
      if totalMoneyRewards > 0 then
        guihooks.trigger("toastrMsg", {type="warning", title="Cargo abandoned", msg=string.format("Cargo was thrown away because vehicle was put into storage. Penalty: %0.2f$", totalMoneyRewards * deliveryAbandonPenaltyFactor)})
        log("I","",string.format("Penalty for abandoning cargo: %0.2f$", totalMoneyRewards * deliveryAbandonPenaltyFactor))
        career_modules_playerAttributes.addAttribute("money", -totalMoneyRewards  * deliveryAbandonPenaltyFactor, {isGameplay = true, label="Penalty for abandoning cargo."})
        Engine.Audio.playOnce('AudioGui', 'event:>UI>Career>Buy_01')
      end
    end
    checkExitDeliveryMode()
  end
end

M.showCargoContainerHelpPopup = function()
  career_modules_linearTutorial.introPopup("cargoContainerHowTo", true)
end

M.onExtensionLoaded = function()
  sendCargoToTasklist()
end

return M