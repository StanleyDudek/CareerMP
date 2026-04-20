-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.dependencies = {"career_career"}

local computerTetherRangeSphere = 20 --meter
local computerTetherRangeBox = 20 --meter
local tether

local computerFunctions
local computerId
local computerFacilityName
local menuData = {}

local function openMenu(computerFacility, resetActiveVehicleIndex, activityElement)
  computerFunctions = {general = {}, vehicleSpecific = {}}
  computerId = computerFacility.id
  computerFacilityName = computerFacility.name

  menuData = {vehiclesInGarage = {}, resetActiveVehicleIndex = resetActiveVehicleIndex}
  local inventoryIds = career_modules_inventory.getInventoryIdsInClosestGarage()

  for _, inventoryId in ipairs(inventoryIds) do
    local vehicleData = {}
    vehicleData.inventoryId = inventoryId
    vehicleData.needsRepair = career_modules_insurance_insurance.inventoryVehNeedsRepair(inventoryId) or nil
    local vehicleInfo = career_modules_inventory.getVehicles()[inventoryId]
    vehicleData.vehicleName = vehicleInfo and vehicleInfo.niceName
    vehicleData.dirtyDate = vehicleInfo and vehicleInfo.dirtyDate
    table.insert(menuData.vehiclesInGarage, vehicleData)

    computerFunctions.vehicleSpecific[inventoryId] = {}
  end

  menuData.computerFacility = computerFacility
  if not career_modules_linearTutorial.getTutorialFlag("partShoppingComplete") then
    menuData.tutorialPartShoppingActive = true
  elseif not career_modules_linearTutorial.getTutorialFlag("tuningComplete") then
    menuData.tutorialTuningActive = true
  end

  extensions.hook("onComputerAddFunctions", menuData, computerFunctions)

  --local computerPos = freeroam_facilities.getAverageDoorPositionForFacility(computerFacility)
  local door = computerFacility.doors[1]
  tether = nil
  if door then
    tether = career_modules_tether.startDoorTether(door, computerTetherRangeBox, M.closeMenu)
  end
  if not tether then
    tether = career_modules_tether.startSphereTether(computerPos, computerTetherRangeSphere, M.closeMenu)
  end

  guihooks.trigger('ChangeState', {state = 'computer'})
  extensions.hook("onComputerOpened")
end

local function computerButtonCallback(buttonId, inventoryId)
  local functionData
  if inventoryId then
    functionData = computerFunctions.vehicleSpecific[inventoryId][buttonId]
  else
    functionData = computerFunctions.general[buttonId]
  end

  functionData.callback(computerId)
end

local function getComputerUIData()
  local data = {}
  local computerFunctionsForUI = deepcopy(computerFunctions)
  computerFunctionsForUI.vehicleSpecific = {}

  -- convert keys of the table to string, because js doesnt support number keys
  for inventoryId, computerFunction in pairs(computerFunctions.vehicleSpecific) do
    computerFunctionsForUI.vehicleSpecific[tostring(inventoryId)] = computerFunction
  end

  local vehiclesForUI = deepcopy(menuData.vehiclesInGarage)
  for i, vehicleData in ipairs(vehiclesForUI) do
    vehicleData.thumbnail = career_modules_inventory.getVehicleThumbnail(vehicleData.inventoryId) .. "?" .. (vehicleData.dirtyDate or "")
    vehicleData.inventoryId = tostring(vehicleData.inventoryId)
  end

  data.computerFunctions = computerFunctionsForUI
  data.vehicles = vehiclesForUI
  data.facilityName = computerFacilityName
  data.resetActiveVehicleIndex = menuData.resetActiveVehicleIndex
  data.computerId = computerId
  return data
end

local function onMenuClosed()
  if tether then tether.remove = true tether = nil end
  extensions.hook("onComputerClosed")
end

local function closeMenu()
  career_career.closeAllMenus()
end

local function openComputerMenuById(computerId)
  local computer = freeroam_facilities.getFacility("computer", computerId)
  career_modules_computer.openMenu(computer)
end

M.openMenu = openMenu
M.openComputerMenuById = openComputerMenuById
M.onMenuClosed = onMenuClosed
M.closeMenu = closeMenu

M.getComputerUIData = getComputerUIData
M.computerButtonCallback = computerButtonCallback

M.reasons = {
  tutorialActive = {
    type = "text",
    label = "Disabled during tutorial."
  },
  needsRepair = {
    type = "needsRepair",
    label = "The vehicle needs to be repaired first."
  }
}

return M
