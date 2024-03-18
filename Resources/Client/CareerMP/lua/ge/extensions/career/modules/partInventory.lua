-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.dependencies = {'career_career'}

local imgui = ui_imgui
local jbeamIO = require('jbeam/io')

local partInventory = {}

local coreSlots = {}
local partsBefore = {}
local slotToPartIdMap = {}
local partInventoryOpen = false

local currentVehicleInventoryId

local function getPartsThatMoved(partsBefore, partsAfter)
  -- Compare old parts with new parts to see what has changed
  local movedOut = {}
  local movedIn = {}

  for partId, _ in pairs(partsBefore) do
    if not partsAfter[partId] then
      movedOut[partId] = true
    end
  end
  for partId, _ in pairs(partsAfter) do
    if not partsBefore[partId] then
      movedIn[partId] = true
    end
  end
  return {movedOut = movedOut, movedIn = movedIn}
end

local function initConditionsCallback(_, inventoryId)
  local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
  local vehicleObj = be:getObjectByID(vehObjId)
  queueCallbackInVehicle(vehicleObj, "career_modules_partInventory.changedPartsCallback", "partCondition.getConditions()", inventoryId)
end

local function getPartIdsFromVehicle(inventoryId)
  local result = {}
  for partId, part in pairs(partInventory) do
    if part.location == inventoryId then
      result[partId] = true
    end
  end
  return result
end

local function sellPart(partId)
  local part = partInventory[partId]
  if not part or part.location ~= 0 then return end
  local partName = part.missingFile and "(Missing File)" or part.description.description or "(Unnamed Part)"
  career_modules_playerAttributes.addAttribute("money", career_modules_valueCalculator.getPartValue(part), {label = "Sold Part: " .. partName})
  Engine.Audio.playOnce('AudioGui','event:>UI>Career>Buy_01')
  partInventory[partId] = nil
  if partInventoryOpen then
    M.sendUIData()
  end
end

local function removePartRec(partId, config, removedParts)
  local part = partInventory[partId]
  if not part then return end
  if part.description.slotInfoUi then
    for slotName, slotInfo in pairs(part.description.slotInfoUi) do
      local subPartId = slotToPartIdMap[part.location][slotName]
      if subPartId then
        removePartRec(subPartId, config, removedParts)
      end
    end
  end
  removedParts[partId] = true
  if config then
    config[part.slot] = ""
  end
end

local partsAfter
local function removePart(partId, inventoryId)
  local vehicle = career_modules_inventory.getVehicles()[inventoryId]
  local carModelToLoad = vehicle.model
  local vehicleData = {}
  vehicleData.config = vehicle.config
  vehicleData.keepOtherVehRotation = true
  local removedParts = {}
  removePartRec(partId, vehicleData.config.parts, removedParts)
  partsAfter = getPartIdsFromVehicle(inventoryId)
  for partId, _ in pairs(removedParts) do
    partsAfter[partId] = nil
  end

  local partConditions = vehicle.partConditions

  -- repair the car if the damage is below the threshold
  local numberOfBrokenParts = career_modules_insurance.getNumberOfBrokenParts(partConditions)
  if numberOfBrokenParts > 0 and numberOfBrokenParts < career_modules_insurance.getBrokenPartsThreshold() then
    career_modules_insurance.repairPartConditions({partConditions = partConditions})
  end

  local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
  if vehObjId then
    local vehicleObj = be:getObjectByID(vehObjId)
    core_vehicles.replaceVehicle(carModelToLoad, vehicleData, vehicleObj)
    queueCallbackInVehicle(vehicleObj, "career_modules_partInventory.initConditionsCallback", "partCondition.initConditions(" .. serialize(partConditions) .. ")", inventoryId)
  else
    -- remove parts manually
    for partId, _ in pairs(removedParts) do
      local part = partInventory[partId]
      partConditions[part.name] = nil
      career_modules_inventory.getVehicles()[inventoryId].config.parts[part.slot] = ""
    end
    M.changedPartsCallback(partConditions, inventoryId)
  end
  career_modules_inventory.setVehicleDirty(inventoryId)
end

-- TODO with this method we might not find a working config, because this just returns a random fitting part, which may have empty core slots
-- TODO one solution would be to allow for empty core slots, but mark them and tell the user that they cant spawn this or use this vehicle until the core slots are filled
local function findFittingPart(slot, vehicleModel)
  for partId, part in pairs(partInventory) do
    if part.location == 0 and part.slot == slot and part.vehicleModel == vehicleModel then
      return partId
    end
  end
end

local newParts

-- Checks which parts need to be added in addition to "partIds" and returns all parts that need to be added
local function fillCoreSlots(partIds, inventoryId)
  local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
  local vehicleObj = be:getObjectByID(vehObjId)
  local jbeamFileName = vehicleObj:getJBeamFilename()

  -- Make a map from slot to its part for the parts which were already in the vehicle and the parts which we want to add
  local combinedSlotToPartMap = deepcopy(slotToPartIdMap[inventoryId])
  for _, partId in ipairs(partIds) do
    local part = partInventory[partId]
    if part then
      combinedSlotToPartMap[part.slot] = true
    end
  end

  local addedParts = false
  local resultParts = deepcopy(partIds)
  for _, partId in ipairs(partIds) do
    local part = partInventory[partId]
    if part and part.description.slotInfoUi then
      for slotName, slotInfo in pairs(part.description.slotInfoUi) do
        if slotInfo.coreSlot and not combinedSlotToPartMap[slotName] then
          -- search in the inventory for a fitting part
          local newPartId = findFittingPart(slotName, jbeamFileName)
          if not newPartId then
            return false
          end
          table.insert(resultParts, newPartId)
          table.insert(newParts, newPartId)
          addedParts = true
        end
      end
    end
  end

  return resultParts, addedParts
end

local function getDisconnectedPartsRec(part, disconnectedParts, parts)
  disconnectedParts[part.slot] = nil
  if part and part.description.slotInfoUi then
    for slotName, slotInfo in pairs(part.description.slotInfoUi) do
      if parts[slotName] then
        getDisconnectedPartsRec(parts[slotName], disconnectedParts, parts)
      end
    end
  end
end

local function getDisconnectedParts(partIds)
  local parts = {}
  for partId, _ in pairs(partIds) do
    local part = deepcopy(partInventory[partId])
    part.id = partId
    parts[part.slot] = part
  end

  local mainPart = parts["main"]
  local disconnectedParts = deepcopy(parts)
  getDisconnectedPartsRec(mainPart, disconnectedParts, parts)
  return disconnectedParts
end

local function installParts(partIds, inventoryId)
  local vehicle = career_modules_inventory.getVehicles()[inventoryId]
  local carModelToLoad = vehicle.model
  local vehicleData = {}
  vehicleData.config = vehicle.config
  vehicleData.keepOtherVehRotation = true

  local addedParts
  newParts = {}
  repeat
    partIds, addedParts = fillCoreSlots(partIds, inventoryId)
    if not partIds then return false end
  until not addedParts

  if tableSize(newParts) > 0 then
    guihooks.trigger('openNewPartsPopup', newParts)
  end

  partsAfter = getPartIdsFromVehicle(inventoryId)

  -- Check which parts need to be removed from partIds because they have been replaced by other parts
  for _, newPartId in ipairs(partIds) do
    local newPart = partInventory[newPartId]

    -- remove parts in partsAfter that have the same slot as one of the newly added parts in partsId
    for oldPartId, _ in pairs(partsAfter) do
      local oldPart = partInventory[oldPartId]
      if oldPart.slot == newPart.slot then
        -- remove the part
        vehicle.partConditions[oldPart.name] = nil
        vehicleData.config.parts[oldPart.slot] = ""
        partsAfter[oldPartId] = nil
      end
    end

    partsAfter[newPartId] = true
  end

  -- Get parts that have now been disconnected from the rest because they are child parts from removed parts
  local disconnectedParts = getDisconnectedParts(partsAfter)
  for slot, part in pairs(disconnectedParts) do
    -- remove the part
    vehicle.partConditions[part.name] = nil
    vehicleData.config.parts[part.slot] = ""
    partsAfter[part.id] = nil
  end

  -- add new parts to the vehicles config
  for _, partId in ipairs(partIds) do
    local part = partInventory[partId]
    if part then
      vehicleData.config.parts[part.slot] = part.name
    end
  end

  -- Make a map from slot to its part
  local combinedSlotToPartMap = deepcopy(slotToPartIdMap[inventoryId])
  for _, partId in ipairs(partIds) do
    local part = partInventory[partId]
    if part then
      combinedSlotToPartMap[part.slot] = true
    end
  end

  for _, partId in ipairs(partIds) do
    local part = partInventory[partId]
    if part and part.description.slotInfoUi then
      for slotName, slotInfo in pairs(part.description.slotInfoUi) do
        if not slotInfo.coreSlot and not combinedSlotToPartMap[slotName] then
          vehicleData.config.parts[slotName] = ""
        end
      end
    end
  end

  -- Add the partCondition of the new part to the vehicle
  for _, partId in ipairs(partIds) do
    local part = partInventory[partId]
    if part then
      vehicle.partConditions[part.name] = part.partCondition
    end
  end

  local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
  local vehicleObj = be:getObjectByID(vehObjId)
  core_vehicles.replaceVehicle(carModelToLoad, vehicleData, vehicleObj)

  -- repair the car if the damage is below the threshold
  local numberOfBrokenParts = career_modules_insurance.getNumberOfBrokenParts(vehicle.partConditions)
  if numberOfBrokenParts > 0 and numberOfBrokenParts < career_modules_insurance.getBrokenPartsThreshold() then
    career_modules_insurance.repairPartConditions({partConditions = vehicle.partConditions})
  end

  queueCallbackInVehicle(vehicleObj, "career_modules_partInventory.initConditionsCallback", "partCondition.initConditions(" .. serialize(vehicle.partConditions) .. ")", inventoryId)
  career_modules_inventory.setVehicleDirty(inventoryId)
  return true
end

local function doesPartFitVehicle(inventoryId, part)
  local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
  if not vehObjId then return false end
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehObjId)
  local vehObj = be:getObjectByID(vehObjId)
  return (vehObj:getJBeamFilename() == part.vehicleModel) and vehicleData.chosenParts[part.slot]
end

local function generateAndGetPartsFromVehicle(inventoryId, allAvailableParts)
  local vehicle = career_modules_inventory.getVehicles()[inventoryId]
  local vehObjId = career_modules_inventory.getVehicleIdFromInventoryId(inventoryId)
  local vehObj = be:getObjectByID(vehObjId)
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehObjId)
  local partConditions = vehicle.partConditions
  if not partConditions then return {} end
  local availableParts = jbeamIO.getAvailableParts(vehicleData.ioCtx)
  local slotMap = jbeamIO.getAvailableSlotMap(vehicleData.ioCtx)

  -- Make a map from part to its slot
  local partToSlotMap = {}
  for slotName, partName in pairs(vehicleData.chosenParts) do
    if partName ~= "" then
      partToSlotMap[partName] = slotName
    end
  end

  for slotName, partNames in pairs(slotMap) do
    for _, partName in ipairs(partNames) do
      if not partToSlotMap[partName] then
        partToSlotMap[partName] = slotName
      end
    end
  end

  local result = {}
  for partName, partInfo in pairs(allAvailableParts and availableParts or partConditions) do
    local jbeamData = jbeamIO.getPart(vehicleData.ioCtx, partName)

    local part = {}
    part.name = partName
    part.value = jbeamData.information.value or 100
    part.partCondition = allAvailableParts and {integrityValue = 1, odometer = 0, visualValue = 1} or partInfo
    part.description = availableParts[partName] or "no description found"
    part.tags = {}

    -- TODO in the future we can use part.slotType here
    part.slot = partToSlotMap[partName]
    part.vehicleModel = vehObj:getJBeamFilename()
    part.location = inventoryId

    result[partName] = part
  end

  return result
end

-- TODO maybe also save for each part taken off the subparts that are attached to it
-- option 2: when detaching a part, put all the subparts seperately into the inventory and whenever you attach a part, all it's slots will be made empty

local function movePart(to, partId)
  local part = partInventory[partId]
  if not part then return end

  local from = part.location

  -- we cant change parts of inaccessible vehicles
  local vehicles = career_modules_inventory.getVehicles()
  if vehicles[from] and vehicles[from].timeToAccess then return end
  if vehicles[to] and vehicles[to].timeToAccess then return end

  if from >= 1 then
    if coreSlots[from][part.slot] then return end
  end

  if to >= 1 then
    if not doesPartFitVehicle(to, part) then return end
  end

  if from >= 1 then
    partsBefore = getPartIdsFromVehicle(from)
    removePart(partId, from)
  end

  -- the "to" vehicle should always be spawned
  -- TODO havent looked much further into if it is possible without spawning
  if to >= 1 then
    partsBefore = getPartIdsFromVehicle(to)
    installParts({partId}, to)
  end

  -- The part couldnt be moved
  return false
end

local function updateVehicleMaps()
  -- Build a map of core slots
  table.clear(coreSlots)
  for partId, part in pairs(partInventory) do
    coreSlots[part.location] = coreSlots[part.location] or {}
    if part.description.slotInfoUi then
      for slotName, slotInfo in pairs(part.description.slotInfoUi) do
        if slotInfo.coreSlot then
          coreSlots[part.location][slotName] = slotInfo.coreSlot
        end
      end
    end
  end

  -- TODO does this need to be cached?
  -- Make a map from slot to its part
  table.clear(slotToPartIdMap)
  for partId, part in pairs(partInventory) do
    slotToPartIdMap[part.location] = slotToPartIdMap[part.location] or {}
    slotToPartIdMap[part.location][part.slot] = partId
  end
end

-- TODO could even update once every time before removing a part
local function updatePartConditionsInInventory()
  for partId, part in pairs(partInventory) do
    if part.location > 0 and career_modules_inventory.getVehicles()[part.location].partConditions[part.name] then
      part.partCondition = career_modules_inventory.getVehicles()[part.location].partConditions[part.name]
    end
  end
end

local function addPartToInventory(part)
  local idCounter = 1
  while partInventory[idCounter] do
    idCounter = idCounter + 1
  end
  partInventory[idCounter] = part
end

local function changedPartsCallback(partConditions, inventoryId)
  career_modules_inventory.getPartConditionsCallback(partConditions, inventoryId)
  local partsThatMoved = getPartsThatMoved(partsBefore, partsAfter)
  partsAfter = nil
  local vehicle = career_modules_inventory.getVehicles()[inventoryId]
  for partId, _ in pairs(partsThatMoved.movedOut) do
    local part = partInventory[partId]
    part.location = 0
    vehicle.changedSlots[part.slot] = true
  end
  for partId, _ in pairs(partsThatMoved.movedIn) do
    local part = partInventory[partId]
    part.location = inventoryId
    vehicle.changedSlots[part.slot] = true
  end
  updateVehicleMaps()
  if career_career.isAutosaveEnabled() then
    career_saveSystem.saveCurrent()
  end
  if partInventoryOpen then
    M.sendUIData()
  end
end

local function addNewPartsToInventory(inventoryId)
  local newParts = generateAndGetPartsFromVehicle(inventoryId)
  for partName, part in pairs(newParts) do
    addPartToInventory(part)
  end
  return newParts
end

local function debugMenu()
  imgui.SetNextWindowSize(imgui.ImVec2(300, 300), imgui.Cond_FirstUseEver)
  local partInventoryOpenPtr = imgui.BoolPtr(true)
  imgui.Begin("Part Inventory", partInventoryOpenPtr)
  if not partInventoryOpenPtr[0] then
    partInventoryOpen = false
  end
  imgui.BeginChild1("vehiclePartsOuter", imgui.ImVec2(220, 0), imgui.WindowFlags_ChildWindow)
  imgui.Text("Parts in current vehicle")
  imgui.BeginChild1("partsInVehicle", imgui.ImVec2(200, 0), imgui.WindowFlags_ChildWindow)
    for partId, part in pairs(partInventory) do
      if part.location == currentVehicleInventoryId then
        local disabled
        if coreSlots[part.location][part.slot] then
          imgui.BeginDisabled()
          disabled = true
        end
        if imgui.Button(part.description.description .. "##inVehicle") then
          movePart(0, partId)
        end
        if disabled then imgui.EndDisabled() end
      end
    end
  imgui.EndChild()
  imgui.EndChild()
  imgui.SameLine()
  imgui.BeginChild1("inventoryPartsOuter", imgui.ImVec2(0, 0), imgui.WindowFlags_ChildWindow)
  imgui.Text("Parts in inventory")

  if imgui.BeginTable('', 8, tableFlags) then
    imgui.TableSetupScrollFreeze(0,1)
    imgui.TableSetupColumn("Id",nil,5)
    imgui.TableSetupColumn("Name",nil,20)
    imgui.TableSetupColumn("Vehicle Model",nil,10)
    imgui.TableSetupColumn("Description",nil,20)
    imgui.TableSetupColumn("Distance Driven",nil,10)
    imgui.TableSetupColumn("Value",nil,5)
    imgui.TableSetupColumn("Location",nil,5)
    imgui.TableSetupColumn("Put into current vehicle",nil,20)
    imgui.TableHeadersRow()
    imgui.TableNextColumn()
    for partId, part in pairs(partInventory) do
      imgui.Text("" .. partId)
      imgui.TableNextColumn()
      imgui.Text(part.name)
      imgui.TableNextColumn()
      imgui.Text(part.vehicleModel)
      imgui.TableNextColumn()
      imgui.Text(part.description.description)
      imgui.TableNextColumn()
      imgui.Text("" .. part.partCondition["odometer"])
      imgui.TableNextColumn()
      imgui.Text("" .. part.value)
      imgui.TableNextColumn()
      imgui.Text("" .. part.location)
      imgui.TableNextColumn()
      local disabled
      if not doesPartFitVehicle(currentVehicleInventoryId, part) then
        imgui.BeginDisabled()
        disabled = true
      end
      if imgui.Button("Put in vehicle##inInventory" .. partId) then
        movePart(currentVehicleInventoryId, partId)
      end
      if disabled then imgui.EndDisabled() end
      imgui.TableNextColumn()
    end

    imgui.EndTable()
  end
  if imgui.BeginPopupModal("newPartsPopup") then
    imgui.Text("The following core slots have been filled automatically with parts from your inventory:")
    for _, partId in ipairs(newParts) do
      local part = partInventory[partId]
      imgui.Text(string.format("%s: Part Id: %d, %s", part.slot, partId, part.description.description))
    end

    if imgui.Button("OK") then imgui.CloseCurrentPopup() end
    imgui.EndPopup()
  end
  imgui.EndChild()
  imgui.End()
end

local updateVehicleParts
local addNewVehiclePartsInventoryId
local function onUpdate()
  -- Add a new vehicles' parts to the inventory
  if addNewVehiclePartsInventoryId and career_modules_inventory.getVehicleIdFromInventoryId(addNewVehiclePartsInventoryId) and career_modules_inventory.getVehicles()[addNewVehiclePartsInventoryId].partConditions then
    local newParts = addNewPartsToInventory(addNewVehiclePartsInventoryId)
    extensions.hook("onAddedVehiclePartsToInventory", addNewVehiclePartsInventoryId, newParts)
    updateVehicleMaps()
    addNewVehiclePartsInventoryId = nil
  end

  -- Update cached maps for the current vehicle
  -- TODO why does this need to be async?
  if updateVehicleParts and (currentVehicleInventoryId and career_modules_inventory.getVehicles()[currentVehicleInventoryId].partConditions) then
    updateVehicleMaps()
    updateVehicleParts = nil
  end

  if not shipping_build and partInventoryOpen then
    debugMenu()
  end
end

local function sendUIData()
  local data = {}
  local partList = {}
  local vehicles = career_modules_inventory.getVehicles()

  data.brokenVehicleInventoryIds = {}
  for inventoryId, _ in pairs(career_modules_inventory.getVehicles()) do
    data.brokenVehicleInventoryIds[tostring(inventoryId)] = career_modules_insurance.inventoryVehNeedsRepair(inventoryId)
  end

  for partId, part in pairs(partInventory) do
    if part.slot ~= "main" then
      local newPart = deepcopy(part)
      if newPart.location ~= 0 and coreSlots[newPart.location][newPart.slot] then
        newPart.isInCoreSlot = true
      end
      newPart.id = partId
      newPart.fitsCurrentVehicle = doesPartFitVehicle(currentVehicleInventoryId, part) and true or false
      newPart.finalValue = career_modules_valueCalculator.getPartValue(newPart)
      newPart.accessible = not (vehicles[newPart.location] and (vehicles[newPart.location].timeToAccess or data.brokenVehicleInventoryIds[newPart.location]))
      table.insert(partList, newPart)
    end
  end
  data.partList = partList
  data.currentVehicle = currentVehicleInventoryId
  guihooks.trigger('partInventoryData', data)
end

local function onVehicleSaveFinished(currentSavePath, oldSaveDate)
  -- TODO use the oldSaveDate
  -- TODO we could split this into multiple files, so that we dont have to rewrite the whole file for each autosave
  -- maybe one file per vehicle
  -- also the vehicle files themselves have some duplicated info like the part condition. we could replace that with references to parts from here

  local partInventoryCopy = deepcopy(partInventory)
  for partId, part in pairs(partInventoryCopy) do
    part.description = nil
  end
  jsonWriteFile(currentSavePath .. "/career/partInventory.json", {lpack.encode(partInventoryCopy)}, true)
end

local function updatePartDescriptionsWithJBeamInfo()
  local jBeamPartInfos = {}
  local vehicleModels = {}

  for partId, part in pairs(partInventory) do
    vehicleModels[part.vehicleModel] = true
  end

  -- TODO if we need this data more often, we can put it in a local table in this file
  for vehicleModel, _ in pairs(vehicleModels) do
    local vehicleDir = string.format("/vehicles/%s/", vehicleModel)
    if FS:directoryExists(vehicleDir) then
      local vehicleFolders = {vehicleDir, "/vehicles/common/"}
      local ioCtx = jbeamIO.startLoading(vehicleFolders)
      jBeamPartInfos[vehicleModel] = jbeamIO.getAvailableParts(ioCtx)
    end
  end

  for partId, part in pairs(partInventory) do
    local partInfosVehicleModel = jBeamPartInfos[part.vehicleModel]
    if not partInfosVehicleModel then
      part.description = {}
      part.missingFile = true
    elseif partInfosVehicleModel[part.name] then
      part.description = jBeamPartInfos[part.vehicleModel][part.name]
    else
      part.description = {}
      part.missingFile = true
    end
  end
end

local function onExtensionLoaded()
  if not career_career.isActive() then return false end
  local saveSlot, savePath = career_saveSystem.getCurrentSaveSlot()
  if not saveSlot then return end
  local jsonData = savePath and jsonReadFile(savePath .. "/career/partInventory.json")
  if jsonData then
    partInventory = (lpack.decode(jsonData[1]))
  else
    partInventory = {}
  end
  updatePartDescriptionsWithJBeamInfo()
  updateVehicleMaps()
end

local function onEnterVehicleFinished(currentVehicle)
  if not currentVehicle then return end

  -- Update the cached vehicle maps when entering a new vehicle
  updateVehicleParts = true
end

local function onPartShoppingTransactionComplete()
  updateVehicleMaps()
end

local function onVehicleAdded(inventoryId)
  addNewVehiclePartsInventoryId = inventoryId
end

local function onVehicleRemoved(inventoryId)
  local partsToRemove = {}
  for partId, part in pairs(partInventory) do
    if part.location == inventoryId then
      partsToRemove[partId] = true
    end
  end

  for partId, _ in pairs(partsToRemove) do
    partInventory[partId] = nil
  end
end

local function getPart(inventoryId, slot)
  for partId, part in pairs(partInventory) do
    if part.location == inventoryId and part.slot == slot then
      return part
    end
  end
end

local originComputerId
local function openMenu(_originComputerId)
  partInventoryOpen = true
  currentVehicleInventoryId = career_modules_inventory.getCurrentVehicle()
  if not currentVehicleInventoryId then
    currentVehicleInventoryId = career_modules_inventory.getInventoryIdsInClosestGarage(true)
  end

  originComputerId = _originComputerId

  if currentVehicleInventoryId then
    career_modules_inventory.updatePartConditions(nil, currentVehicleInventoryId, function() guihooks.trigger('ChangeState', {state = 'menu.partInventory', params = {}}) end)
  else
    guihooks.trigger('ChangeState', {state = 'menu.partInventory', params = {}})
  end
  extensions.hook("onCareerPartsInventoryMenu")
end

local function closeMenu()
  if originComputerId then
    local computer = freeroam_facilities.getFacility("computer", originComputerId)
    career_modules_computer.openMenu(computer)
  else
    career_career.closeAllMenus()
  end
end

local function partInventoryClosed()
  partInventoryOpen = false
end

local function getSlotToPartIdMap()
  return slotToPartIdMap
end

local function getInventory()
  return partInventory
end

local function onComputerAddFunctions(menuData, computerFunctions)
  if not menuData.computerFacility.functions["partInventory"] then return end

  local computerFunctionData = {
    id = "partInventory",
    label = "My Parts",
    callback = function() openMenu(menuData.computerFacility.id) end,
    disabled = menuData.tutorialPartShoppingActive or menuData.tutorialTuningActive
  }
  computerFunctions.general[computerFunctionData.id] = computerFunctionData
end

M.doesPartFitVehicle = doesPartFitVehicle
M.generateAndGetPartsFromVehicle = generateAndGetPartsFromVehicle
M.movePart = movePart
M.changedPartsCallback = changedPartsCallback
M.initConditionsCallback = initConditionsCallback
M.sendUIData = sendUIData
M.openMenu = openMenu
M.closeMenu = closeMenu
M.partInventoryClosed = partInventoryClosed
M.getSlotToPartIdMap = getSlotToPartIdMap
M.getInventory = getInventory
M.addPartToInventory = addPartToInventory
M.getPart = getPart
M.updatePartConditionsInInventory = updatePartConditionsInInventory
M.sellPart = sellPart

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onVehicleSaveFinished = onVehicleSaveFinished
M.onEnterVehicleFinished = onEnterVehicleFinished
M.onVehicleAdded = onVehicleAdded
M.onVehicleRemoved = onVehicleRemoved
M.onComputerAddFunctions = onComputerAddFunctions
M.onPartShoppingTransactionComplete = onPartShoppingTransactionComplete

return M