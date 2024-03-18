-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.dependencies = {'career_career'}

local unlockedSpawnpoints = {}
local fileName = "spawnPoints.json"
local levelInfo = nil
local function getSpawnPointTranslation(spawnPointName)
  local levelData = core_levels.getLevelByName(getCurrentLevelIdentifier())
  if levelData and levelData.spawnPoints then
    for _, spawnPointData in ipairs(levelData.spawnPoints) do
      if spawnPointData.objectname == spawnPointName then
        return translateLanguage(spawnPointData.translationId, spawnPointData.translationId)
      end
    end
  end
  return ""
end

local discoveryDistance = 75
local updateTime = 1
local lastUpdateTimer = updateTime
local function onUpdate(dtReal, dtSim, dtRaw)
  -- Check if an undiscovered spawn point is close
  if career_modules_linearTutorial then
    if not career_modules_linearTutorial.getTutorialFlag('spawnPointDiscoveryEnabled') then return end
  end
  if not (getCurrentLevelIdentifier() and career_modules_inventory and career_modules_inventory.getCurrentVehicle() and be:getPlayerVehicle(0)) then return end
  lastUpdateTimer = lastUpdateTimer + dtReal
  if lastUpdateTimer < updateTime then return end

  local currentLevel = getCurrentLevelIdentifier()
  if not currentLevel then return end

  if not levelInfo or levelInfo.levelName ~= string.lower(currentLevel) then
    levelInfo = nil
    for _, info in ipairs(core_levels.getList()) do
      if string.lower(info.levelName) == string.lower(currentLevel) then
        levelInfo = info
      end
    end
  end
  if not levelInfo or not levelInfo.spawnPoints then return end

  local playerPos = nil

    for _,spawnPoint in pairs(levelInfo.spawnPoints) do
      if not M.isSpawnPointDiscovered(currentLevel, spawnPoint.objectname) then
        local obj = scenetree.findObject(spawnPoint.objectname)
        if obj then
          playerPos = playerPos or be:getPlayerVehicle(0):getPosition()
          if obj:getPosition():distance(playerPos) < discoveryDistance then
            unlockedSpawnpoints[currentLevel][spawnPoint.objectname] = true
            --log("I", "", "New quick travel point discovered: " .. spawnPoint.objectname)
            --[[local helper = {
              ttl = 10,
              msg = {txt = "ui.career.quickTravelPointDiscovered", context = {spawnPointName = spawnPoint.translationId or spawnPoint.objectname}},
              category = 'careerUnlockedSpawnpoints',
              icon = 'info'
            }
            guihooks.trigger('Message',helper)]]
            career_modules_logbook.spawnPointUnlocked(spawnPoint)
            extensions.hook("onSpawnPointUnlocked", spawnPoint)
            gameplay_rawPois.clear()
          end
        end
      end
    end

  lastUpdateTimer = 0
end

local function getUnlockedSpawnpointsData()
  return unlockedSpawnpoints or {}
end

local function loadDataFromFile()
  local saveSlot, savePath = career_saveSystem.getCurrentSaveSlot()
  if not saveSlot then return end
  unlockedSpawnpoints = (savePath and jsonReadFile(savePath .. "/career/"..fileName)) or {}
end

local function isSpawnPointDiscovered(level, spawnPointName)
  if not unlockedSpawnpoints[level] then
    unlockedSpawnpoints[level] = {}
  end
  return unlockedSpawnpoints[level][spawnPointName]
end

local function onExtensionLoaded()
  if not career_career.isActive() then return false end
  loadDataFromFile()
end

local function onCareerActive(active)
  loadDataFromFile()
end

-- this should only be loaded when the career is active
local function onSaveCurrentSaveSlot(currentSavePath)
  jsonWriteFile(currentSavePath .. "/career/"..fileName, unlockedSpawnpoints, true)
end

local function onClientStartMission()

end



M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.isSpawnPointDiscovered = isSpawnPointDiscovered
M.onClientStartMission = onClientStartMission
M.getUnlockedSpawnpointsData = getUnlockedSpawnpointsData
return M