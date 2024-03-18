-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.dependencies = {"career_career"}

local inventoryId

local originComputerId
local chosenPaints

local function getPrimerColor()
  local brightnessOffset = (math.random() * 2 - 1) * 0 -- no randomness for now
  local paint = {
    baseColor = {0.8 + brightnessOffset, 0.775 + brightnessOffset, 0.695 + brightnessOffset},
    clearcoat = 0,
    clearcoatRoughness = 1,
    metallic = 0.9,
    roughness = 1
  }

  return paint
end

local function findBaseColors(partConditions)
  local colors
  for partName, partCondition in pairs(partConditions) do
    if not colors then
      if partCondition.visualState and partCondition.visualState.paint and partCondition.visualState.paint.originalPaints then
        colors = partCondition.visualState.paint.originalPaints
      end
    end
    if string.find(partName, "body") then
      if partCondition.visualState and partCondition.visualState.paint and partCondition.visualState.paint.originalPaints then
        return partCondition.visualState.paint.originalPaints
      end
    end
  end
  return colors
end

local function getPaintData()
  local vehicleInfo = career_modules_inventory.getVehicles()[inventoryId]
  local partConditions = vehicleInfo.partConditions
  local colors = findBaseColors(partConditions)

  return colors
end

local function startActual(_originComputerId)
  originComputerId = _originComputerId
  if originComputerId then
    guihooks.trigger('ChangeState', {state = 'menu.painting', params = {}})
  end
  guihooks.trigger("onCareerPaintingStarted")
  extensions.hook("onCareerPaintingStarted")
end

local function start(_inventoryId, _originComputerId)
  inventoryId = _inventoryId or career_modules_inventory.getInventoryIdsInClosestGarage(true)
  if not inventoryId or not career_modules_inventory.getMapInventoryIdToVehId()[inventoryId] then return end

  local numberOfBrokenParts = career_modules_insurance.getNumberOfBrokenParts(career_modules_inventory.getVehicles()[inventoryId].partConditions)
  if numberOfBrokenParts > 0 and numberOfBrokenParts < career_modules_insurance.getBrokenPartsThreshold() then
    career_modules_insurance.startRepair(inventoryId, nil, function() startActual(_originComputerId) end)
  else
    startActual(_originComputerId)
  end
end

local function close()
  if originComputerId then
    local computer = freeroam_facilities.getFacility("computer", originComputerId)
    career_modules_computer.openMenu(computer)
  else
    career_career.closeAllMenus()
  end
  career_modules_inventory.spawnVehicle(inventoryId, 2)
end

local function apply()
  local gameVehID = be:getPlayerVehicleID(0)
  local invID = career_modules_inventory.getInventoryIdFromVehicleId(gameVehID)
  local autosavePath = career_saveSystem.getSaveRootDirectory() .. MPConfig.getNickname() .. "/autosave1"
  local inventoryData = jsonReadFile(autosavePath .. "/career/inventory.json")
  local vehicleData = jsonReadFile(autosavePath .. "/career/vehicles/" .. invID .. ".json")
  if vehicleData then
    vehicleData.config.paints = chosenPaints
    local vehPaints = vehicleData.config.paints
    local serverVehID = MPVehicleGE.getServerVehicleID(gameVehID)
    jsonWriteFile(autosavePath .. "/career/vehicles/" .. invID .. ".json", vehicleData, true)
    career_modules_inventory.vehicles[invID] = vehicleData
    TriggerServerEvent("paintUpdate", jsonEncode( { serverVehID, vehPaints }))
  end
  local vehicle = career_modules_inventory.getVehicles()[invID]
  vehicle.partConditions = lpack.decode(vehicle.partConditions)
  for partName, partCondition in pairs(vehicle.partConditions) do
    if partCondition.visualState and partCondition.visualState.paint.originalPaints then
      partCondition.visualState.paint.odometer = 0
      partCondition.visualState.paint.originalPaints = chosenPaints
    end
  end

  close()
  career_modules_inventory.setVehicleDirty(invID)
end

local function onComputerAddFunctions(menuData, computerFunctions)
  if not menuData.computerFacility.functions["painting"] then return end

  for _, vehicleData in ipairs(menuData.vehiclesInGarage) do
    local inventoryId = vehicleData.inventoryId
    local permissionStatus, permissionLabel = career_modules_permissions.getStatusForTag("vehicleModification")

    local buttonDisabled =
      vehicleData.needsRepair or
      menuData.tutorialTuningActive or
      menuData.tutorialPartShoppingActive or
      permissionStatus == "forbidden"

    local label = "Painting" ..(permissionLabel and ("\n"..permissionLabel) or "")

    local computerFunctionData = {
      id = "painting",
      label = label,
      callback = function() start(inventoryId, menuData.computerFacility.id) end,
      disabled = buttonDisabled
    }
    if vehicleData.needsRepair then
      computerFunctionData.disableReason = "fix vehicle body first"
    end

    computerFunctions.vehicleSpecific[inventoryId][computerFunctionData.id] = computerFunctionData
  end
end

local function setPaints(paints)
  chosenPaints = paints

  if tableSize(chosenPaints) < 3 then
    for i = tableSize(chosenPaints)+1, 3 do
      chosenPaints[i] = chosenPaints[i-1]
    end
  end

  local vehicleObject = be:getObjectByID(career_modules_inventory.getMapInventoryIdToVehId()[inventoryId])
  vehicleObject:queueLuaCommand(string.format("partCondition.setAllPartPaints(%s, 0)", serialize(chosenPaints)))
end

local function getFactoryPaint()
  local id = career_modules_inventory.getMapInventoryIdToVehId()[inventoryId]
  local info = core_vehicles.getVehicleDetails(id)
  return info.model and info.model.paints or {}
end

M.start = start
M.apply = apply
M.close = close
M.getPaintData = getPaintData
M.setPaints = setPaints
M.getFactoryPaint = getFactoryPaint

M.getPrimerColor = getPrimerColor

M.onComputerAddFunctions = onComputerAddFunctions

return M