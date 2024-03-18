-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local imgui = ui_imgui

M.dependencies = {'career_saveSystem', 'core_recoveryPrompt'}

M.tutorialEnabled = false

local careerModuleDirectory = '/lua/ge/extensions/career/modules/'
local saveFile = "general.json"
local levelName = "west_coast_usa"
local defaultLevel = "/levels/west_coast_usa/main.level.json"
local autosaveEnabled = true

local careerActive = false
local careerModules = {}
local debugActive = true
local closeAfterSaving
local boughtStarterVehicle

local actionsToBlockOnlyInShippingMode = {"dropPlayerAtCameraNoReset"}

local blockedActions = core_input_actionFilter.createActionTemplate({"vehicleTeleporting", "vehicleMenues", "physicsControls", "aiControls", "vehicleSwitching", "funStuff"}, actionsToBlockOnlyInShippingMode)

-- TODO maybe save whenever we go into the esc menu

local function blockInputActions(block)
  if shipping_build then
    core_input_actionFilter.setGroup('careerBlockedDevActions', actionsToBlockOnlyInShippingMode)
    core_input_actionFilter.addAction(0, 'careerBlockedDevActions', block)
  end

  core_input_actionFilter.setGroup('careerBlockedActions', blockedActions)
  core_input_actionFilter.addAction(0, 'careerBlockedActions', block)
end

local function debugMenu()
  if not careerActive then return end
  imgui.SetNextWindowSize(imgui.ImVec2(300, 300), imgui.Cond_FirstUseEver)
  imgui.Begin("Career Debug")

  imgui.Text("Money: " .. career_modules_playerAttributes.getAttribute("money").value)
  imgui.SameLine()
  if imgui.Button("+10000##money") then career_modules_playerAttributes.addAttribute("money", 10000, {label="Cheating"}) end
  imgui.SameLine()
  if imgui.Button("+1000##money") then career_modules_playerAttributes.addAttribute("money", 1000, {label="Cheating"}) end
  imgui.SameLine()
  if imgui.Button("-1000##money") then career_modules_playerAttributes.addAttribute("money", -1000, {label="Cheating"}) end
  imgui.SameLine()
  if imgui.Button("-10000##money") then career_modules_playerAttributes.addAttribute("money", -10000, {label="Cheating"}) end

  imgui.Text("BeamXP: " .. career_modules_playerAttributes.getAttribute("beamXP").value)
  imgui.SameLine()
  if imgui.Button("+1000##beamXP") then career_modules_playerAttributes.addAttribute("beamXP", 1000, {label="Cheating"}) end
  imgui.SameLine()
  if imgui.Button("-1000##beamXP") then career_modules_playerAttributes.addAttribute("beamXP", -1000, {label="Cheating"}) end

  imgui.Text("Bonus Stars: " .. career_modules_playerAttributes.getAttribute("bonusStars").value)
  imgui.SameLine()
  if imgui.Button("+1000##bonusStars") then career_modules_playerAttributes.addAttribute("bonusStars", 1000, {label="Cheating"}) end
  imgui.SameLine()
  if imgui.Button("-1000##bonusStars") then career_modules_playerAttributes.addAttribute("bonusStars", -1000, {label="Cheating"}) end

  for _, branch in ipairs(career_branches.getSortedBranches()) do
    imgui.Text(branch.name ..": " .. career_modules_playerAttributes.getAttribute(branch.attributeKey).value.. " ( Level "..career_branches.getBranchLevel(branch.id).." )")
    imgui.SameLine()
    if imgui.Button("+100##"..branch.name) then career_modules_playerAttributes.addAttribute(branch.attributeKey,100, {label="Cheating"}) end
    imgui.SameLine()
    if imgui.Button("+500##"..branch.name) then career_modules_playerAttributes.addAttribute(branch.attributeKey,500, {label="Cheating"}) end
  end
  if imgui.Button("Quests Debug") then
    career_modules_questDebug.openQuestDebug()
  end
  if imgui.Button("Reload Missions") then gameplay_missions_missions.reloadCompleteMissionSystem() end
  if imgui.Button("Make All Missions Startable") then
    for _, m in ipairs(gameplay_missions_missions.getFilesData()) do
      instance = gameplay_missions_missions.getMissionById(m.id)
      instance.unlocks.startable = true
      instance.unlocks.visible = true
    end
    gameplay_rawPois.clear()
  end
  if imgui.Button("Enter Garage Mode##dasdasd") then
    gameplay_garageMode.start(true)
  end

  if gameplay_garageMode.isActive() then
    if imgui.Button("Exit Garage Mode") then
      gameplay_garageMode.stop()
    end
  end
  if imgui.Button("Save Career") then
    career_saveSystem.saveCurrent()
  end
  local endCareerMode = false
  if imgui.Button("Exit Career Mode") then
    endCareerMode = true
  end

  if imgui.Button("Add this Vehicle as new vehicle to inventory") then
    local inventoryId = career_modules_inventory.addVehicle(be:getPlayerVehicleID(0))
    career_modules_inventory.enterVehicle(inventoryId)
  end

  local currentVehicle = career_modules_inventory.getCurrentVehicle()

  if currentVehicle then
    imgui.Text("Current Vehicle: " .. currentVehicle .. " (" .. career_modules_inventory.getVehicles()[currentVehicle].model .. ")")
  end

  local vehicleToSell
  if imgui.BeginChild1("Owned Vehicles", imgui.ImVec2(0, 150), true) then
    imgui.Text("Change to one of your vehicles")

    for id, data in pairs(career_modules_inventory.getVehicles()) do
      if imgui.Button("id " .. id .. " (" .. data.model .. ")") then
        career_modules_inventory.enterVehicle(id)
      end
      imgui.SameLine()

      if imgui.Button(string.format("sell ##%d",  id)) then
        vehicleToSell = id
      end
    end
  end
  imgui.EndChild()

  if imgui.Button("Part Shop") then
    career_modules_partShopping.startShopping()
  end
  imgui.SameLine()
  if imgui.Button("Part Inventory") then
    career_modules_partInventory.openMenu()
  end

  if imgui.Button("Vehicle Shop") then
    career_modules_vehicleShopping.openShop()
  end
  imgui.SameLine()
  if imgui.Button("Vehicle Inventory") then
    career_modules_inventory.openMenu()
  end

  if imgui.Button("Fuel") then
    career_modules_fuel.startTransaction()
  end

  if imgui.Button("Tuning") then
    career_modules_tuning.start()
  end

  if imgui.Button("Reset insurance data") then
    career_modules_insurance.resetPlPolicyData()
  end

  imgui.Separator()

  career_modules_linearTutorial.debugMenu()

  imgui.End()

  if vehicleToSell then
    career_modules_inventory.sellVehicleFromInventory(vehicleToSell)
  end

  if endCareerMode then
    M.deactivateCareer()
    return true
  end
end

local function setupCareerActionsAndUnpause()
  blockInputActions(true)
  simTimeAuthority.pause(false)
  simTimeAuthority.set(1)
end

local function onCareerModulesActivated(alreadyInLevel)
  setupCareerActionsAndUnpause()
end

local function toggleCareerModules(active, alreadyInLevel)
  if active then
    table.clear(careerModules)
    local extensionFiles = {}
    local files = FS:findFiles(careerModuleDirectory, '*.lua', -1, true, false)
    for i = 1, tableSize(files) do
      extensions.luaPathToExtName(modulePath)
      local extensionFile = string.gsub(files[i], "/lua/ge/extensions/", "")
      extensionFile = string.gsub(extensionFile, ".lua", "")
      --if not string.find(extensionFile, "delivery") then
        table.insert(extensionFiles, extensionFile)
        table.insert(careerModules, extensions.luaPathToExtName(extensionFile))
      --else
        --log("I","","Skipping "..extensionFile .. " for now while it is WIP (temporary)")
      --end
    end
    extensions.load(careerModules)

    -- prevent these extensions from being unloaded when switching level
    for _, extension in ipairs(extensionFiles) do
      setExtensionUnloadMode(extensions.luaPathToExtName(extension), "manual")
    end

    for _, moduleName in ipairs(careerModules) do
      if extensions[moduleName].onCareerActivated then
        extensions[moduleName].onCareerActivated()
      end
    end

    onCareerModulesActivated(alreadyInLevel)
    extensions.hook("onCareerModulesActivated", alreadyInLevel)
  else
    for _, name in ipairs(careerModules) do
      extensions.unload(name)
    end
    table.clear(careerModules)
  end
end


local function onUpdate(dtReal, dtSim, dtRaw)
  if not careerActive then return end
  if not shipping_build then
    if debugMenu() then
      return
    end
  end
end

local function removeNonTrafficVehicles()
  local safeIds = gameplay_traffic.getTrafficList(true)
  safeIds = arrayConcat(safeIds, gameplay_parking.getParkedCarsList(true))
  for i = be:getObjectCount()-1, 0, -1 do
    local objId = be:getObject(i):getID()
    if not tableContains(safeIds, objId) then
      be:getObject(i):delete()
    end
  end
end

local function activateCareer(removeVehicles)
  if careerActive then return end
  -- load career
  local saveSlot, savePath = career_saveSystem.getCurrentSaveSlot()
  if not saveSlot then return end

  if removeVehicles == nil then
    removeVehicles = true
  end
  if core_groundMarkers then core_groundMarkers.setFocus(nil) end

  careerActive = true
  log("I", "Loading career from " .. savePath .. "/career/" .. saveFile)
  local careerData = (savePath and jsonReadFile(savePath .. "/career/" .. saveFile)) or {}
  local levelToLoad = careerData.level or levelName
  boughtStarterVehicle = careerData.boughtStarterVehicle

  if not getCurrentLevelIdentifier() or (getCurrentLevelIdentifier() ~= levelToLoad) then
    spawn.preventPlayerSpawning = true
    freeroam_freeroam.startFreeroam(path.getPathLevelMain(levelToLoad))
    toggleCareerModules(true)
  else
    if removeVehicles then
      --core_vehicles.removeAll()
    else
      --removeNonTrafficVehicles()
    end
    toggleCareerModules(true, true)
    M.onUpdate = onUpdate
  end

  gameplay_rawPois.clear()
  core_recoveryPrompt.setDefaultsForCareer()
  extensions.hook("onCareerActive", true)
  guihooks.trigger('ClearTasklist')
  core_gamestate.setGameState("career","career", nil)

  career_modules_playerDriving.ensureTraffic = true

  if career_modules_linearTutorial.isLinearTutorialActive() then
    M.setAutosaveEnabled(false)
    print("Disabling autosave because we are in tutorial!")
  end
end

local function deactivateCareer(saveCareer)
  if not careerActive then return end
  M.onUpdate = nil
  if saveCareer then
    --career_saveSystem.saveCurrent(true) -- not sure if we want to allow saving here
  end
  careerActive = false
  toggleCareerModules(false)
  blockInputActions(false)
  gameplay_rawPois.clear()
  core_recoveryPrompt.setDefaultsForFreeroam()
  extensions.hook("onCareerActive", false)
  guihooks.trigger("HideCareerTasklist")
end

local function deactivateCareerAndReloadLevel(saveCareer)
  if not careerActive then return end
  deactivateCareer(saveCareer)
  freeroam_freeroam.startFreeroam(path.getPathLevelMain(getCurrentLevelIdentifier()))
end

local function isActive()
  return careerActive
end

local function enableTutorial(enabled)
  if enabled then
    log("I","","Tutorial for career enabled.")
  end
  M.tutorialEnabled = enabled or false
end

local function createOrLoadCareerAndStart(name, specificAutosave)
  --M.tutorialEnabled = string.find(string.lower(name), "tutorial") and true or false
  --M.vehSelectEnabled = string.find(string.lower(name), "vehselect") and true or false
  log("I","",string.format("Create or Load Career: %s - %s", name, specificAutosave))
  if career_saveSystem.setSaveSlot(name, specificAutosave) then
    activateCareer()
    return true
  end
  return false
end

local function onSaveCurrentSaveSlot(currentSavePath)
  if not careerActive then return end

  local filePath = currentSavePath .. "/career/" .. saveFile
  -- read the info file
  local data = {}

  data.level = getCurrentLevelIdentifier()
  data.boughtStarterVehicle = boughtStarterVehicle

  jsonWriteFile(filePath, data, true)
end

local function onBeforeSetSaveSlot(currentSavePath, currentSaveSlot)
  if isActive() then
    deactivateCareer()
  end
end

local function onClientStartMission(levelPath)
  if careerActive then
    M.onUpdate = onUpdate
    setupCareerActionsAndUnpause()
    core_gamestate.setGameState("career","career", nil)
  end
end

local beamXPLevels ={
    {requiredValue = 0}, -- to reach lvl 1
    {requiredValue = 100},-- to reach lvl 2
    {requiredValue = 300},-- to reach lvl 3
    {requiredValue = 600},-- to reach lvl 4
    {requiredValue = 1000},-- to reach lvl 5
}
local function getBeamXPLevel(xp)
  local level = -1
  local neededForNext = -1
  local curLvlProgress = -1
  for i, lvl in ipairs(beamXPLevels) do
    if xp >= lvl.requiredValue then
      level = i
    end
  end
  if beamXPLevels[level+1] then
    neededForNext = beamXPLevels[level+1].requiredValue
    curLvlProgress = xp - beamXPLevels[level].requiredValue
  end
  return level, curLvlProgress, neededForNext
end

local function formatSaveSlotForUi(saveSlot)
  local data = {}
  data.id = saveSlot

  local autosavePath = career_saveSystem.getSaveRootDirectory() .. saveSlot .. "/autosave1"
  local infoData = jsonReadFile(autosavePath .. "/info.json")

  local currentSaveSlot, _ = career_saveSystem.getCurrentSaveSlot()
  if career_career.isActive() and currentSaveSlot == saveSlot then

    -- current save slot
    data.tutorialActive = career_modules_linearTutorial.isLinearTutorialActive()
    data.money = career_modules_playerAttributes.getAttribute("money")
    data.beamXP = career_modules_playerAttributes.getAttribute("beamXP")
    data.bonusStars = career_modules_playerAttributes.getAttribute("bonusStars")
    data.beamXP.level, data.beamXP.curLvlProgress, data.beamXP.neededForNext = getBeamXPLevel(data.beamXP.value)

    for bId, br in pairs(career_branches.getBranches()) do
      local attKey = br.attributeKey
      data[attKey] = deepcopy(career_modules_playerAttributes.getAttribute(attKey) or {value=br.defaultValue or 0})
      data[attKey].level, data[attKey].curLvlProgress, data[attKey].neededForNext = career_branches.calcBranchLevelFromValue(data[attKey].value, bId)
    end
    data.currentVehicle = career_modules_inventory.getCurrentVehicle() and career_modules_inventory.getVehicles()[career_modules_inventory.getCurrentVehicle()]
  else

    -- save slot from file
    local attData = jsonReadFile(autosavePath .. "/career/playerAttributes.json")
    local inventoryData = jsonReadFile(autosavePath .. "/career/inventory.json")

    if attData then
      data.money = deepcopy(attData.money) or {value=0}
      data.beamXP = deepcopy(attData.beamXP) or {value=0}
      data.bonusStars = deepcopy(attData.bonusStars) or {value=0}
      data.beamXP.level, data.beamXP.curLvlProgress, data.beamXP.neededForNext = getBeamXPLevel(data.beamXP.value)
      for bId, br in pairs(career_branches.getBranches()) do
        local attKey = br.attributeKey
        data[attKey] = deepcopy(attData[attKey] or {value=br.defaultValue or 0})
        data[attKey].level, data[attKey].curLvlProgress, data[attKey].neededForNext = career_branches.calcBranchLevelFromValue(data[attKey].value, bId)
      end
    end

    if inventoryData and inventoryData.currentVehicle then
      local vehicleData = jsonReadFile(autosavePath .. "/career/vehicles/" .. inventoryData.currentVehicle .. ".json")
      if vehicleData then
        data.currentVehicle = vehicleData.niceName
      end
    end
  end

  -- add the infoData raw
  if infoData and infoData.version then
    infoData.outdatedVersion = career_saveSystem.getSaveSystemVersion() > infoData.version
    tableMerge(data, infoData)
  end

  return data
end

local function sendAllCareerSaveSlotsData()
  local res = {}
  for _, saveSlot in ipairs(career_saveSystem.getAllSaveSlots()) do
    local saveSlotData = formatSaveSlotForUi(saveSlot)
    if saveSlotData then
      table.insert(res, saveSlotData)
    end
  end

  table.sort(res, function(a,b) return (a.creationDate or "Z") < (b.creationDate or "Z") end)
  guihooks.trigger("allCareerSaveSlots", res)
  return res
end

local function sendCurrentSaveSlotData()
  if not careerActive then return end
  local saveSlot = career_saveSystem.getCurrentSaveSlot()
  if saveSlot then
    return formatSaveSlotForUi(saveSlot)
  end
end

local function getAutosavesForSaveSlot(saveSlot)
  local res = {}
  for _, saveData in ipairs(career_saveSystem.getAllAutosaves(saveSlot)) do
    local data = jsonReadFile(career_saveSystem.getSaveRootDirectory() .. saveSlot .. "/" .. saveData.name .. "/career/playerAttributes.json")
    if data then
      data.id = saveSlot
      data.autosaveName = saveData.name
      table.insert(res, data)
    end
  end
  return res
end

local function onClientEndMission(levelPath)
  if not careerActive then return end
  local levelNameToLoad = path.levelFromPath(levelPath)
  if levelNameToLoad == levelName then
    deactivateCareer()
  end
end

local function onSerialize()
  local data = {}
  if careerActive then
    data.reactivate = true
    deactivateCareer()
  end
  return data
end

local function onDeserialized(v)
  if v.reactivate then
    activateCareer(false)
  end
end

local function sendCurrentSaveSlotName()
  guihooks.trigger("currentSaveSlotName", {saveSlot = career_saveSystem.getCurrentSaveSlot()})
end

local function onVehicleSaveFinished()
  if closeAfterSaving then
    shutdown(0)
  end
end

local function onPreWindowClose()
  --[[if careerActive then
    Engine.cancelShutdown()
    closeAfterSaving = true
    career_saveSystem.saveCurrent()
  end]]
end

local function onAnyMissionChanged(state, mission)
  if not careerActive then return end
  if mission then
    if state == "stopped" then
      blockInputActions(true)
    elseif state == "started" then
      blockInputActions(false)
    end
  end
end

local physicsPausedFromOutside = false
local function onSimTimePauseCalled(paused)
  physicsPausedFromOutside = paused
end

local function requestPause(pause)
  if careerActive then
    if
      pause == simTimeAuthority.getPause()
      or physicsPausedFromOutside
      then return end
    simTimeAuthority.pause(pause)
    physicsPausedFromOutside = false
  end
end

local function hasBoughtStarterVehicle()
  return boughtStarterVehicle
end

local function onVehicleAddedToInventory(data)
  -- if data.vehicleInfo is present, then the vehicle was bought
  if not boughtStarterVehicle and data.vehicleInfo then
    boughtStarterVehicle = true
    career_modules_vehicleShopping.generateVehicleList()
  end
end

local function closeAllMenus()
  guihooks.trigger('ChangeState', {state = 'play', params = {}})
end

local function isAutosaveEnabled()
  return autosaveEnabled
end

local function setAutosaveEnabled(enabled)
  autosaveEnabled = enabled
end

local function getAdditionalMenuButtons()
  local ret = {}
  --table.insert(ret, {label = "Test", luaFun = "print('Test!')"})
  if career_modules_delivery_deliveryManager.isDeliveryModeActive() then
    table.insert(ret, {label = "My Cargo", luaFun = "career_modules_delivery_deliveryManager.enterCargoOverviewScreen(nil, nil)"})
  end
  return ret
end

local function onExtensionLoaded()
	log('W', "mpCareer", "--------------------------------------MP CAREER")
end

M.getAdditionalMenuButtons = getAdditionalMenuButtons
M.enableTutorial = enableTutorial
M.createOrLoadCareerAndStart = createOrLoadCareerAndStart
M.activateCareer = activateCareer
M.deactivateCareer = deactivateCareer
M.deactivateCareerAndReloadLevel = deactivateCareerAndReloadLevel
M.isActive = isActive
M.sendAllCareerSaveSlotsData = sendAllCareerSaveSlotsData
M.sendCurrentSaveSlotData = sendCurrentSaveSlotData
M.getAutosavesForSaveSlot = getAutosavesForSaveSlot
M.requestPause = requestPause
M.hasBoughtStarterVehicle = hasBoughtStarterVehicle
M.closeAllMenus = closeAllMenus
M.isAutosaveEnabled = isAutosaveEnabled
M.setAutosaveEnabled = setAutosaveEnabled

M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onBeforeSetSaveSlot = onBeforeSetSaveSlot
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized
M.onClientStartMission = onClientStartMission
M.onClientEndMission = onClientEndMission
M.onExtensionLoaded = onExtensionLoaded
M.onAnyMissionChanged = onAnyMissionChanged
M.onSimTimePauseCalled = onSimTimePauseCalled
M.onVehicleSaveFinished = onVehicleSaveFinished
M.onPreWindowClose = onPreWindowClose
M.onVehicleAddedToInventory = onVehicleAddedToInventory

M.sendCurrentSaveSlotName = sendCurrentSaveSlotName

M.onInit = function() setExtensionUnloadMode(M, "manual") end

return M
