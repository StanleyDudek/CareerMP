-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

M.dependencies = {'gameplay_rawPois', 'core_groundMarkers','core_camera','core_terrain', 'freeroam_bigMapMarkers'}
local logTag = 'bigMapMode'
local clusterMergeRadius = nil
local imgui = ui_imgui
local debugWindow = false

local missionColor = ColorI(255,255,255,255)
local selectedColor = ColorI(255,255,255,255)
local xVector = vec3(1,0,0)
local yVector = vec3(0,1,0)
local zVector = vec3(0,0,1)
local invisibleColor = ColorI(255,255,255,0)
local pureWhite = ColorI(255,255,255,255)
local upVector = vec3(0,0,1)

local groundMarkerAlphaSmoother = newTemporalSmoothing()
local fogDensitySmoother = newTemporalSmoothing()
local shadowLogWeightSmoother = newTemporalSmoothing()
local shadowDistanceSmoother = newTemporalSmoothing()
local routeAnimCounter = 1
local missionRouteAnimCounter
local poiSelectCallback
local horizontalOffsetFactor

local shadowDist = 10000
local verticalResolution = 1080
local minZoomFactor = 5000 -- smaller number means you can zoom in further
local navPathSimplificationFactor = 300 -- smaller number means more simplification
local routeAnimSpeedFactor = 50000 -- smaller number means faster route animation

local bigMap = false

local previousShadowLogWeight
local previousShadowDistance
local previousCamMode
local previousFogDensity
local previousTod
local previouslyPaused
local previousVisibleDistance
local previousUiVisibility
local previousDOF
local previousFreeCamData

local selectedPreviewMissionId
local hoveredPreviewMissionId

M.selectedPoiId = nil
M.hoveredPoiId = nil
M.hoveredListItem = nil
local transitionActive = false -- false = no transition, 1 = transition to big map, 2 = transition from big map
local transitionProgress = 0
local transitionTime = 0
local bigMapCamRotation
local bigMapInitialCamPos
local mapBoundaries
local mouseMoved = false
local uiPopupOpen = false -- TODO If we keep the non modal window, this can be removed
local uiHasFocus = false
local camHeightAboveTerrain = 0
local airSoundId
local mapBoundsFogPool
local simplifiedPath
local showNavigationMarker
local routePreview
local transitionSoundId
local currentlyVisibleIds = {}


-- Level properties
local bigMapTod
local showLevelBorders

local iconRendererId

local blockedInputActions = core_input_actionFilter.createActionTemplate({"gameCam", "vehicleTeleporting", "funStuff", "freeCam", "physicsControls", "vehicleSwitching", "walkingMode", "vehicleMenues", "aiControls", "photoMode", "couplers", "radialMenu", "pause", "missionPopup", "resetPhysics", "appedit", "miniMap"})

local uiActions = {"menu_item_select"}

local function blockUiActions(block)
  core_input_actionFilter.setGroup('bigmapUiActions', uiActions)
  core_input_actionFilter.addAction(0, 'bigmapUiActions', block)
end

local function clearCylinderCache()
  if mapBoundsFogPool then
    for _, fog in ipairs(mapBoundsFogPool) do
      fog:delete()
    end
    mapBoundsFogPool = nil
  end
end

local function setLevelProperties()
  if scenetree.theLevelInfo then
    bigMapTod = scenetree.theLevelInfo.bigMapTimeOfDay
    showLevelBorders = scenetree.theLevelInfo.bigMapLevelBorderVisible
  end
end

local function createLevelBounds()
  if not mapBoundsFogPool then
    mapBoundsFogPool = {}
    for i = 1, 4 do
      local fog = createObject('TSStatic')
      fog:setField('shapeName', 0, "art/shapes/interface/bigmap/bigmap_fog_b_small.dae")

      fog.canSave = false
      fog.useInstanceRenderData = true
      fog.dynamic = true
      fog:registerObject(Sim.getUniqueName("mapBoundFog" .. i))
      mapBoundsFogPool[i] = fog
    end
  end

  local color = spaceSeparated4Values(0,0,0,0)
  for _, fog in ipairs(mapBoundsFogPool) do
    fog.hidden = false
    fog:setField('instanceColor', 0, color)
  end

  local extents = mapBoundaries:getExtents()
  local edgePoint1 = vec3((mapBoundaries.maxExtents.x + mapBoundaries.minExtents.x) / 2, mapBoundaries.minExtents.y, mapBoundaries.maxExtents.z)
  local rayMaxDist = extents.z * 1.1
  local rayDist = castRayStatic(edgePoint1, vec3(0,0,-1), rayMaxDist)
  if rayDist < rayMaxDist then
    edgePoint1.z = edgePoint1.z - rayDist
  end
  local edgePoint2 = vec3(mapBoundaries.minExtents.x, (mapBoundaries.maxExtents.y + mapBoundaries.minExtents.y) / 2, mapBoundaries.maxExtents.z)
  local rayDist = castRayStatic(edgePoint2, vec3(0,0,-1), rayMaxDist)
  if rayDist < rayMaxDist then
    edgePoint2.z = edgePoint2.z - rayDist
  end
  local edgePoint3 = vec3((mapBoundaries.maxExtents.x + mapBoundaries.minExtents.x) / 2, mapBoundaries.maxExtents.y, mapBoundaries.maxExtents.z)
  local rayDist = castRayStatic(edgePoint3, vec3(0,0,-1), rayMaxDist)
  if rayDist < rayMaxDist then
    edgePoint3.z = edgePoint3.z - rayDist
  end
  local edgePoint4 = vec3(mapBoundaries.maxExtents.x, (mapBoundaries.maxExtents.y + mapBoundaries.minExtents.y) / 2, mapBoundaries.maxExtents.z)
  local rayDist = castRayStatic(edgePoint4, vec3(0,0,-1), rayMaxDist)
  if rayDist < rayMaxDist then
    edgePoint4.z = edgePoint4.z - rayDist
  end
  local rot1 = quatFromDir(vec3(-1,0,0), vec3(0,0.6,1))
  local rot2 = quatFromDir(vec3(0,1,0), vec3(0.6,0,1))
  local rot3 = quatFromDir(vec3(1,0,0), vec3(0,-0.6,1))
  local rot4 = quatFromDir(vec3(0,-1,0), vec3(-0.6,0,1))
  mapBoundsFogPool[1]:setPosRot(edgePoint1.x, edgePoint1.y, edgePoint1.z, rot1.x, rot1.y, rot1.z, rot1.w)
  mapBoundsFogPool[2]:setPosRot(edgePoint2.x, edgePoint2.y, edgePoint2.z, rot2.x, rot2.y, rot2.z, rot2.w)
  mapBoundsFogPool[3]:setPosRot(edgePoint3.x, edgePoint3.y, edgePoint3.z, rot3.x, rot3.y, rot3.z, rot3.w)
  mapBoundsFogPool[4]:setPosRot(edgePoint4.x, edgePoint4.y, edgePoint4.z, rot4.x, rot4.y, rot4.z, rot4.w)
  mapBoundsFogPool[1]:setScale(vec3(camHeightAboveTerrain * 0.001, extents.x/1000 * 3, 1))
  mapBoundsFogPool[2]:setScale(vec3(camHeightAboveTerrain * 0.001, extents.y/1000 * 3, 1))
  mapBoundsFogPool[3]:setScale(vec3(camHeightAboveTerrain * 0.001, extents.x/1000 * 3, 1))
  mapBoundsFogPool[4]:setScale(vec3(camHeightAboveTerrain * 0.001, extents.y/1000 * 3, 1))
end

local function frameObject(bbox, pitch, yaw, useCamYaw)
  local camMode = core_camera.getGlobalCameras().bigMap
  pitch = pitch or camMode.angle
  yaw = yaw or camMode.rotAngle
  local upperEdgePoint = vec3((bbox.maxExtents.x + bbox.minExtents.x) / 2, bbox.maxExtents.y, bbox.maxExtents.z)
  local lowerEdgePoint = vec3((bbox.maxExtents.x + bbox.minExtents.x) / 2, bbox.minExtents.y, bbox.minExtents.z)
  local lowerCamFovAngle = pitch + camMode.fovMax/2
  local upperCamFovAngle = pitch - camMode.fovMax/2
  local lowerCamFovDir = quatFromAxisAngle(xVector, (lowerCamFovAngle) / 180 * math.pi):__mul(yVector)
  local upperCamFovDir = quatFromAxisAngle(xVector, (upperCamFovAngle) / 180 * math.pi):__mul(yVector)
  local planeNormal = upperCamFovDir:cross(xVector)
  local camPos = lowerEdgePoint - lowerCamFovDir * intersectsRay_Plane(lowerEdgePoint, -lowerCamFovDir, upperEdgePoint, planeNormal)
  if not useCamYaw then
    camPos = camPos - bbox:getCenter()
    camPos = quatFromAxisAngle(zVector, (yaw) / 180 * math.pi):__mul(camPos)
    camPos = camPos + bbox:getCenter()

    -- Move backwards by a certain amount to account for the rotated camera
    local backwardsOffset = (bbox:getCenter() - camPos) * 0.1
    backwardsOffset.z = 0
    camPos = camPos - backwardsOffset
  end
  return camPos
end

local function includeClustersInBbox(bbox)
  for i, poi in ipairs(gameplay_rawPois.getRawPoiListByLevel(getCurrentLevelIdentifier())) do
    if poi.markerInfo.bigmapMarker then
      bbox:extend(poi.markerInfo.bigmapMarker.pos)
    end
  end

  local mapData = map.getMap()
  if mapData and mapData.nodes then
    for _, node in pairs(mapData.nodes) do
      if node.pos:length() < 1e14 then
        bbox:extend(node.pos)
      end
    end
  end
end

local function calculateCamPos()
  local camMode = core_camera.getGlobalCameras().bigMap
  bigMapCamRotation = quatFromDir(vec3(0,0,-1), yVector)
  bigMapCamRotation = quatFromAxisAngle(xVector, -(90 - camMode.angle) / 180 * math.pi):__mul(bigMapCamRotation)
  bigMapCamRotation = bigMapCamRotation:__mul(quatFromAxisAngle(zVector, camMode.rotAngle / 180 * math.pi))

  local camPos = vec3(0,0,0)
  local bbox
  if core_terrain.getTerrain() then
    bbox = core_terrain.getTerrain():getWorldBox()
    includeClustersInBbox(bbox)
  else
    local playerVehicle = be:getPlayerVehicle(0)
    bbox = Box3F()
    bbox:setExtents(vec3(1000, 1000, 1000))
    bbox:setCenter(playerVehicle and playerVehicle:getPosition() + vec3(0,0,500) or vec3(0, 0, 0))
    includeClustersInBbox(bbox)
  end

  -- Clamp the bbox height to a certain minimum height, so all maps behave similarily
  local bboxCenter = bbox:getCenter()
  local extents = bbox:getExtents()
  local heightBefore = extents.z
  extents.z = math.max(extents.z, (extents.x + extents.y) / 12)
  local heightAfter = extents.z
  bboxCenter.z = bboxCenter.z + (heightAfter - heightBefore) / 2
  bbox:setExtents(extents)
  bbox:scale3F(vec3(1.1,1.1,1))
  bbox:setCenter(bboxCenter)

  camPos = frameObject(bbox)
  camHeightAboveTerrain = (camPos.z or 0) - (bbox.minExtents.z or 0)

  -- Add a small offset to the camera to make room for the ui sidebar and the topbar
  local camDir = bigMapCamRotation * yVector
  local camLeft = zVector:cross(camDir):normalized()
  camPos = camPos + camLeft * (camHeightAboveTerrain / 10) * (horizontalOffsetFactor or 1)
  camPos = camPos + camDir:z0() * camHeightAboveTerrain / 10

  shadowDist = camHeightAboveTerrain * 2.5
  bigMapInitialCamPos = camPos
  mapBoundaries = bbox
  camMode.mapBoundaries = mapBoundaries
  horizontalOffsetFactor = nil
end

local function buildTransitionPath(endMarkerData)
  local camMode = core_camera.getGlobalCameras().bigMap
  local previousNearClip = 0.1
  if scenetree.theLevelInfo then
    previousNearClip = scenetree.theLevelInfo.nearClip
  end

  local path = { looped = false, manualFov = false}
  local startPos = core_camera.getPosition()
  local playerVehicle = be:getPlayerVehicle(0)
  if not bigMap then
    -- transition to big map
    local transitionEndPos = bigMapInitialCamPos
    local oobb = playerVehicle:getSpawnWorldOOBB()
    local aabb = Box3F()
    aabb.minExtents = oobb:getCenter() - oobb:getHalfExtents()
    aabb.maxExtents = oobb:getCenter() + oobb:getHalfExtents()

    local vehicleFramePos = frameObject(aabb, 90, nil, true)
    local camDir = core_camera.getQuat() * yVector
    local downwardsRot = quatFromDir(vec3(0,0,-1), camDir)
    local m1 = { fov = core_camera.getFovDeg(), movingEnd = true, movingStart = false, positionSmooth = 0.5, pos = startPos, rot = core_camera.getQuat(), time = 0, trackPosition = false, nearClip = previousNearClip  }
    local m2 = { fov = core_camera.getFovDeg(), movingEnd = true, movingStart = true, positionSmooth = 0.5, pos = vehicleFramePos + 5*(vehicleFramePos-aabb:getCenter()), rot = downwardsRot, time = camMode.posTransitionTime/3, trackPosition = false, nearClip = 1 }
    local m3 = { fov = core_camera.getFovDeg(), movingEnd = false, movingStart = true, positionSmooth = 0.5, pos = vehicleFramePos + 30*(vehicleFramePos-aabb:getCenter()), rot = downwardsRot, time = camMode.posTransitionTime/2, trackPosition = false, nearClip = 1 }
    local m4 = { fov = camMode.fovMax, movingEnd = true, movingStart = true, positionSmooth = 0.1, pos = transitionEndPos, rot = bigMapCamRotation, time = camMode.posTransitionTime, trackPosition = false, nearClip = camMode.nearClipValue}
    path.markers = {m1, m2, m3, m4}
  else
    -- transition to player cam
    local oobb = playerVehicle:getSpawnWorldOOBB()
    local aabb = Box3F()
    aabb.minExtents = oobb:getCenter() - oobb:getHalfExtents()
    aabb.maxExtents = oobb:getCenter() + oobb:getHalfExtents()

    local vehicleFramePos = frameObject(aabb, 90, nil, false)
    local playerCamDir = endMarkerData.rot * yVector
    local downwardsRot = quatFromDir(vec3(0,0,-1), playerCamDir)
    local m1 = { fov = core_camera.getFovDeg(), movingEnd = true, movingStart = false, positionSmooth = 0.5, pos = startPos, rot = core_camera.getQuat(), time = 0, trackPosition = false, nearClip = camMode.nearClipValue  }
    local m2 = { fov = camMode.fovMax, movingEnd = true, movingStart = true, positionSmooth = 0.5, pos = vehicleFramePos + 30*(vehicleFramePos-aabb:getCenter()), rot = downwardsRot, time = camMode.posTransitionTime/2, trackPosition = false, nearClip = 1 }
    local m3 = { fov = endMarkerData.fov, movingEnd = false, movingStart = true, positionSmooth = 0.5, pos = vehicleFramePos + 5*(vehicleFramePos-aabb:getCenter()), rot = downwardsRot, time = camMode.posTransitionTime*(2/3), trackPosition = false, nearClip = 1 }
    local m4 = { fov = endMarkerData.fov, movingEnd = true, movingStart = true, positionSmooth = 0.5, pos = endMarkerData.pos, rot = endMarkerData.rot, time = camMode.posTransitionTime, trackPosition = false, nearClip = previousNearClip }
    path.markers = {m1, m2, m3, m4}
  end

  return path
end

local function setTime(time)
  local tod = core_environment.getTimeOfDay()
  if tod then
    tod.time = time
    core_environment.setTimeOfDay(tod)
  end
end

local function resetForceVisible()
  -- Set all markers forceVisible to false
  for i, cluster in ipairs(gameplay_playmodeMarkers.getPlaymodeClusters()) do
    if cluster.type == "missionMarker" then
      cluster.focus = false
    end
  end

  M.navigationPoiId = nil
  M.reachedTargetPos = nil
end

local function setOnlyIdsVisible(list)
  currentlyVisibleIds = list or {}
  freeroam_bigMapMarkers.setupFilter(currentlyVisibleIds, M.clusterMergeRadius)
end
M.setOnlyIdsVisible = setOnlyIdsVisible

local function simplifyRoute(route)
  if not route or #route == 0 then return {} end
  local simple = {}
  local distance = 0
  local stepSize = camHeightAboveTerrain / navPathSimplificationFactor
  for index = 1, tableSize(route) - 1 do
    local pos1 = route[index].pos
    local pos2 = route[index+1].pos
    if distance <= 0 then
      table.insert(simple, pos1)
    end
    distance = distance + pos1:distance(pos2)
    if distance > stepSize then
      distance = 0
    end
  end
  table.insert(simple, route[tableSize(route)].pos)
  return simple
end

local function resetRoute()
  routeAnimCounter = 1
  simplifiedPath = nil
  if core_groundMarkers.currentlyHasTarget() then
    simplifiedPath = simplifyRoute(core_groundMarkers.routePlanner.path)
  else
    showNavigationMarker = false
  end
end

local function setNavFocus(pos)
  extensions.hook("onSetBigmapNavFocus", pos)
  if not be:getPlayerVehicle(0) then
    pos = nil
  end
  core_groundMarkers.setFocus(pos)
  resetRoute()
end

local function reachedTarget()
  if settings.getValue("showMissionMarkers") or (career_career and career_career.isActive()) then
    resetForceVisible()
  end
  M.reachedTargetPos = core_groundMarkers.endWP[1]
  setNavFocus(nil)
end

local function addMissionIdsToList(cluster, missionIdsSorted)
  for i=1, #cluster.containedIds do
    if cluster.elemData[i].type == "mission" then
      local mission = gameplay_missions_missions.getMissionById(cluster.elemData[i].missionId)
      table.insert(missionIdsSorted, {id = cluster.elemData[i].missionId, unlocks = mission.unlocks})
    else
      table.insert(missionIdsSorted, {id = cluster.elemData[i].id})
    end
  end
end
local function depthIdSort(a,b)
  if not a.unlocks or not b.unlocks or a.unlocks.depth == b.unlocks.depth then
    return a.id < b.id
  else
    return a.unlocks.depth < b.unlocks.depth
  end
end

--[[ -- TODO: no longer used, remove?
local function getPoiIds(cluster)
  local missionIdsSorted = {}

  if cluster then
    addMissionIdsToList(cluster, missionIdsSorted)
  else
    for _, cluster in ipairs(gameplay_rawPois.getAllClusters()) do
      addMissionIdsToList(cluster, missionIdsSorted)
    end
  end

  table.sort(missionIdsSorted, depthIdSort)
  local missionIds = {}
  for i, mission in ipairs(missionIdsSorted) do
    missionIds[i] = mission.id
  end
  return missionIds
end
]]
local mouseDragging
local lastMousePos

local function onUpdate(dtReal, dtSim, dtRaw)
  if not bigMap then return end

  profilerPushEvent("BigMap onPreRender")
  if airSoundId then
    local sound = scenetree.findObjectById(airSoundId)
    if sound then
      sound:setTransform(getCameraTransform())
    end
  end

  local camMode = core_camera.getGlobalCameras().bigMap
  if debugWindow then
    if imgui.Begin("Big Map") then
      local maxFovPtr = imgui.FloatPtr(camMode.fovMax)
      if imgui.SliderFloat("Max FOV", maxFovPtr, 5.0, 90.0, "%.0f") then
        camMode.fovMax = maxFovPtr[0]
        camMode.manualzoom:init(camMode.fovMax, camMode.fovMin, camMode.fovMax)
        camMode:onCameraChanged(true)
      end
      local minFovPtr = imgui.FloatPtr(camMode.fovMin)
      if imgui.SliderFloat("Min FOV", minFovPtr, 5.0, 90.0, "%.0f") then
        camMode.fovMin = minFovPtr[0]
        camMode.manualzoom:init(camMode.fovMax, camMode.fovMin, camMode.fovMax)
        camMode:onCameraChanged(true)
      end
      local anglePtr = imgui.FloatPtr(camMode.angle)
      if imgui.SliderFloat("Angle", anglePtr, 5.0, 90.0, "%.0f") then
        camMode.angle = anglePtr[0]
        camMode:onCameraChanged(true)
      end
      local rotAnglePtr = imgui.FloatPtr(camMode.rotAngle)
      if imgui.SliderFloat("Rotation", rotAnglePtr, 0.0, 360.0, "%.0f") then
        camMode.rotAngle = rotAnglePtr[0]
      end
      local posTransitionTimePtr = imgui.FloatPtr(camMode.posTransitionTime)
      if imgui.SliderFloat("position transition time", posTransitionTimePtr, 0.0, 10.0, "%.1f") then
        camMode.posTransitionTime = posTransitionTimePtr[0]
      end
      local transitionActivePtr = imgui.BoolPtr(camMode.transitionActive)
      if imgui.Checkbox("Activate camera transition", transitionActivePtr) then
        camMode.transitionActive = transitionActivePtr[0]
      end
      local movementSpeedPtr = imgui.FloatPtr(camMode.movementSpeed)
      if imgui.SliderFloat("movement speed", movementSpeedPtr, 0.0, 100.0, "%.0f") then
        camMode.movementSpeed = movementSpeedPtr[0]
      end
      imgui.End()
    end
  end

  if not transitionActive then
    local iconRenderer = scenetree.findObjectById(iconRendererId)
    local playerVehicle = be:getPlayerVehicle(0)
    if iconRenderer and playerVehicle then
      local iconInfo = iconRenderer:getIconByName("playerVehicle")
      if iconInfo then
        iconInfo.worldPosition = playerVehicle:getPosition()
        iconInfo.customSizeFactor = 0.8 + math.sin(os.clock()*4)*0.1

        -- Project the vehicle direction vector on to the camera plane and then determine the angle
        local vehDir = playerVehicle:getDirectionVector()
        local vehicleDirLocalX, vehicleDirLocalY = vehDir:dot(core_camera.getRight()), vehDir:dot(core_camera.getUp())
        local vehicleDirXYLocal = vec3(vehicleDirLocalX,vehicleDirLocalY,0)
        local det = vehicleDirLocalX * yVector.y - vehicleDirLocalY * yVector.x
        local angle = math.atan2(det, vehicleDirXYLocal:dot(yVector))
        iconInfo.rotation = angle
        iconInfo.drawIconShadow = false
      end
    end

    -- check which markers are hovered
    local lastHover = M.hoveredPoiId
    if not getCEFFocusMouse() then
      local hover = freeroam_bigMapMarkers.handleMouse(camMode, uiPopupOpen, mouseMoved, M.selectedPoiId)
      -- a marker is hovered
      if hover then
        if hover ~= M.hoveredPoiId then
          -- A new marker has been hovered
          Engine.Audio.playOnce('AudioGui','event:>UI>Bigmap>Hover_Icon')
        end
        M.hoveredPoiId = hover
      else
        -- The cursor is on the map, but no icon is hovered
        M.hoveredPoiId = nil
      end
    else
      -- The cursor is somewhere on the cef area
      M.hoveredPoiId = nil
    end
    if lastHover ~= M.hoveredPoiId then
      extensions.hook("onBigmapHoveredPoiIdChanged",M.hoveredPoiId)
    end
  else
    -- Interpolate stuff during the transition
    transitionTime = transitionTime + dtReal
    transitionProgress = transitionTime / camMode.posTransitionTime

    local fogDensityGoal
    local shadowLogWeightGoal
    local shadowDistanceGoal
    local todGoal
    local levelBoundAlpha = 0
    if transitionActive == 1 then
      fogDensityGoal = (transitionProgress > 0.33) and 0 or previousFogDensity
      shadowLogWeightGoal = (transitionProgress > 0.5) and 0 or previousShadowLogWeight
      shadowDistanceGoal = shadowDist
      todGoal = (transitionProgress > 0.33) and bigMapTod or previousTod
      levelBoundAlpha = (transitionProgress > 0.33) and 1 or 0
    elseif transitionActive == 2 then
      -- TODO this creates the weird shadows
      fogDensityGoal = (transitionProgress > 0.66) and previousFogDensity or 0
      shadowLogWeightGoal = previousShadowLogWeight
      shadowDistanceGoal = previousShadowDistance
      todGoal = previousTod
      levelBoundAlpha = (transitionProgress > 0.66) and 0 or 1
    else
      fogDensityGoal = 0
    end
    local fogDensity = fogDensitySmoother:getWithRateUncapped(fogDensityGoal, dtReal, 0.01)
    core_environment.setFogDensity(fogDensity)
    if previousShadowLogWeight then
      core_environment.setShadowLogWeight(shadowLogWeightSmoother:getWithRateUncapped(shadowLogWeightGoal, dtReal, 1))
    end
    if previousShadowDistance then
      core_environment.setShadowDistance(shadowDistanceSmoother:getWithRateUncapped(shadowDistanceGoal, dtReal, (shadowDist - previousShadowDistance) * 0.8))
    end

    if mapBoundsFogPool then
      local color = spaceSeparated4Values(0,0,0,levelBoundAlpha)
      for _, fog in ipairs(mapBoundsFogPool) do
        fog:setField('instanceColor', 0, color)
      end
    end

    local currentTod = core_environment.getTimeOfDay()
    if currentTod then
      local currentTime = currentTod.time

      if currentTime ~= todGoal then
        local difference = math.abs(todGoal - currentTime)
        local interpolationSpeed = (dtReal / camMode.posTransitionTime)* 0.5 / (2/3) -- transition speed is enough so that it can change by 0.5 in two thirds of the transition time
        if currentTime < todGoal then
          if difference <= 0.5 then
            currentTod.time = math.min(todGoal, currentTod.time + interpolationSpeed)
          else
            currentTod.time = (currentTod.time - interpolationSpeed) % 1
          end
        else
          if difference <= 0.5 then
            currentTod.time = math.max(todGoal, currentTod.time - interpolationSpeed)
          else
            currentTod.time = (currentTod.time + interpolationSpeed) % 1
          end
        end
        core_environment.setTimeOfDay(currentTod)
      end
    end
  end
  if imgui.IsMouseDragging(0) then
    mouseDragging = true
  end

  freeroam_bigMapMarkers.displayBigMapMarkers(dtReal)

  local mousePos = imgui.GetMousePos()
  if lastMousePos and (mousePos.x ~= lastMousePos.x or mousePos.y ~= lastMousePos.y) then
    mouseMoved = true
  end
  lastMousePos = mousePos
  profilerPopEvent("BigMap onPreRender")
end

local function setActive(active)
  bigMap = active
  if bigMap then
    M.onUpdate = onUpdate
  else
    M.onUpdate = nil
  end
  extensions.hookUpdate("onUpdate")
end

local function activateBigMapCallback()
  local iconRenderer = scenetree.findObjectById(iconRendererId)
  if not iconRenderer then return end
  iconRenderer:loadIconAtlas("core/art/gui/images/iconAtlas.png", "core/art/gui/images/iconAtlas.json");
  local playerVehicle = be:getPlayerVehicle(0)
  iconRenderer:addIcon("playerVehicle", "player", playerVehicle and playerVehicle:getPosition() or vec3(0,0,0))
  local iconInfo = iconRenderer:getIconByName("playerVehicle")
  iconInfo.color = pureWhite
  iconInfo.customSizeFactor = 0.7
  local camDir = core_camera.getQuat() * yVector
  iconRenderer:addIcon("controllerCrosshair", "crosshair", core_camera.getPosition() + camDir * 150);
  local iconInfo = iconRenderer:getIconByName("controllerCrosshair")
  iconInfo.color = pureWhite
  iconRenderer:addIcon("navigationMarker", "navigation_marker", vec3(0,0,0))
  local iconInfo = iconRenderer:getIconByName("navigationMarker")
  iconInfo.color = invisibleColor
  iconInfo.customSizeFactor = 0.5

  transitionActive = false

  core_environment.setFogDensity(0)
  core_environment.setShadowLogWeight(0)
  core_environment.setShadowDistance(shadowDist)
  setTime(bigMapTod)

  fogDensitySmoother:set(0)
  shadowLogWeightSmoother:set(0)
  shadowDistanceSmoother:set(shadowDist)
  setActive(true)
  M.updateMergeRadius(1)

  if mapBoundsFogPool then
    local color = spaceSeparated4Values(0,0,0,1)
    for _, fog in ipairs(mapBoundsFogPool) do
      fog:setField('instanceColor', 0, color)
    end
  end

  extensions.hook("onActivateBigMapCallback")
end

local function deactivateBigMapCallback(closeEscMenu)
  if not previouslyPaused then
    simTimeAuthority.pause(false)
  end
  core_environment.setShadowLogWeight(previousShadowLogWeight)
  core_environment.setShadowDistance(previousShadowDistance)
  core_environment.setFogDensity(previousFogDensity)
  ui_visibility.set(previousUiVisibility)
  setTime(previousTod)
  if previousVisibleDistance then
    scenetree.theLevelInfo.visibleDistance = previousVisibleDistance
    scenetree.theLevelInfo:postApply()
  end

  if previousDOF then
    local DOFPostEffect = scenetree.findObject("DOFPostEffect")
    DOFPostEffect:enable()
  end
  setActive(false)

  -- unblock input action
  core_input_actionFilter.setGroup('bigmapBlockedActions', blockedInputActions)
  core_input_actionFilter.addAction(0, 'bigmapBlockedActions', false)
  blockUiActions(false)
  transitionActive = false

  if mapBoundsFogPool then
    for _, fog in ipairs(mapBoundsFogPool) do
      fog.hidden = true
    end
  end
  freeroam_bigMapPoiProvider.requestMissionLocationsForMinimap()

  if closeEscMenu then
    guihooks.trigger('MenuHide')
  end
  gameplay_markerInteraction.skipNextIconFading()
  --gameplay_markerInteraction.setForceReevaluateOpenPrompt()
  freeroam_bigMapMarkers.clearMarkers()
  M.deselect()
  extensions.hook("onDeactivateBigMapCallback")
  poiSelectCallback = nil
end

local function endTransition(activateBigMap, closeEscMenu, stopTransitionSound)
  core_camera.setByName(0, not activateBigMap and previousCamMode or "bigMap", false, activateBigMap and {initialCamData = {pos = bigMapInitialCamPos, rot = bigMapCamRotation}})
  ui_visibility.set(previousUiVisibility)

  if stopTransitionSound and transitionSoundId then
    local sfxSource = scenetree.findObjectById(transitionSoundId)
    if sfxSource then
      sfxSource:stop(0.1)
    end
  end

  if activateBigMap then
    activateBigMapCallback()
  else
    deactivateBigMapCallback(closeEscMenu)
  end
end

local camPath
local function startTransition(endMarkerData, closeEscMenu)
  extensions.hook("onBigmapStartTransition",activateBigMap, closeEscMenu)
  endMarkerData.pos = vec3(endMarkerData.pos)
  endMarkerData.rot = quat(endMarkerData.rot.x, endMarkerData.rot.y, endMarkerData.rot.z, endMarkerData.rot.w)
  camPath = buildTransitionPath(endMarkerData)
  local currentBigMap = bigMap
  local initData = {}

  initData.useDtReal = true
  initData.finishedPath = function()
    endTransition(not currentBigMap, closeEscMenu)
  end
  transitionActive = currentBigMap and 2 or 1
  transitionTime = 0
  transitionProgress = 0
  setActive(true)
  ui_visibility.set(false)
  core_paths.playPath(camPath, 0, initData)
  if transitionActive == 1 then
    local sfxSource = Engine.Audio.playOnce('AudioGui','event:>UI>Bigmap>Whoosh_In')
    transitionSoundId = sfxSource and sfxSource.sourceId
  else
    local sfxSource = Engine.Audio.playOnce('AudioGui','event:>UI>Bigmap>Whoosh_Out')
    transitionSoundId = sfxSource and sfxSource.sourceId
  end
end

local function enterBigMapActual(instant)
  if bigMap then return end
  --freeroam_bigMapMarkers.buildPoiList() -- removed(testing)
  --freeroam_bigMapMarkers.setupFilter()

  core_camera.setLookBack(0, false) -- Disable lookback before going into bigmap
  local canvas = scenetree.findObject("Canvas")
  if canvas then
    verticalResolution = GFXDevice.getVideoMode().height
  end
  if not (iconRendererId and scenetree.objectExistsById(iconRendererId)) then
    local iconRenderer = createObject("BeamNGWorldIconsRenderer")
    iconRenderer:registerObject("");
    iconRenderer.maxIconScale = 1
    iconRenderer.mConstantSizeIcons = true
    iconRenderer.canSave = false
    iconRendererId = iconRenderer:getId()
  end

  gameplay_rawPois.clear()
  freeroam_bigMapMarkers.clearMarkers()


  if core_groundMarkers.currentlyHasTarget() then
    resetRoute()
  end

  pushActionMap("BigMap")

  -- make the action map let through inputs, so the throttle cant get stuck on the vehicle
  local am = scenetree.findObject("BigMapActionMap")
  if am then am.trapHandledEvents = false end

  previousShadowLogWeight = core_environment.getShadowLogWeight()
  previousShadowDistance = core_environment.getShadowDistance()
  if commands.isFreeCamera() then
    previousFreeCamData = {pos = core_camera.getPosition(), rot = core_camera.getQuat(), fov = core_camera.getFovDeg()}
  else
    previousFreeCamData = nil
  end
  previousCamMode = core_camera.getActiveCamName()
  if previousCamMode == "path" then previousCamMode = "orbit" end
  previousFogDensity = core_environment.getFogDensity()
  previousTod = core_environment.getTimeOfDay() and core_environment.getTimeOfDay().time
  previouslyPaused = simTimeAuthority.getPause()
  previousUiVisibility = ui_visibility.get()

  local DOFPostEffect = scenetree.findObject("DOFPostEffect")
  if DOFPostEffect then
    previousDOF = DOFPostEffect:isEnabled()
    DOFPostEffect:disable()
  end

  simTimeAuthority.pause(true)

  local camMode = core_camera.getGlobalCameras().bigMap
  setLevelProperties()
  calculateCamPos()
  if showLevelBorders then
    createLevelBounds()
  else
    clearCylinderCache()
  end

  previousVisibleDistance = nil
  if (camHeightAboveTerrain * 5) > scenetree.theLevelInfo.visibleDistance then
    previousVisibleDistance = scenetree.theLevelInfo.visibleDistance
    scenetree.theLevelInfo.visibleDistance = camHeightAboveTerrain * 5
    scenetree.theLevelInfo:postApply()
  end

  camMode.fovMin = clamp(minZoomFactor / camHeightAboveTerrain, 10, camMode.fovMax)
  if commands.isFreeCamera() or not be:getPlayerVehicle(0) or instant then
    -- In freecam, skip the path transition
    commands.setGameCamera()
    core_camera.setByName(0, 'bigMap', false, {initialCamData = {pos = bigMapInitialCamPos, rot = bigMapCamRotation}})
    activateBigMapCallback()
  else
    core_camera.getGlobalCameras().transition:start(false, {callback = startTransition})
    core_camera.setByName(0, 'bigMap', false, {initialCamData = {pos = bigMapInitialCamPos, rot = bigMapCamRotation}})
  end

  local sound = scenetree.findObjectById(airSoundId)
  if sound then
    sound:play(-1)
    sound:setVolume(1)
    sound:setTransform(getCameraTransform())
  end

  groundMarkerAlphaSmoother:set(0)
  fogDensitySmoother:set(previousFogDensity)
  if previousShadowLogWeight then
    shadowLogWeightSmoother:set(previousShadowLogWeight)
  end
  if previousShadowDistance then
    shadowDistanceSmoother:set(previousShadowDistance or 0)
  end
  transitionTime = 0
  transitionProgress = 0

  if not poiSelectCallback then
    guihooks.trigger('MenuOpenModule', 'menu.bigmap')
  end

  -- block some actions
  core_input_actionFilter.setGroup('bigmapBlockedActions', blockedInputActions)
  core_input_actionFilter.addAction(0, 'bigmapBlockedActions', true)
  blockUiActions(true)

  extensions.hook("onBigMapActivated")
end

local function enterBigMap(instant)
  if bigMap or (core_camera.getActiveCamName() == "bigMap" and not commands.isFreeCamera()) or not getCurrentLevelIdentifier() then return end
  enterBigMapActual(instant)
end

local function exitBigMap(instant, closeEscMenu, forceGameCam)
  if not bigMap then return end

  -- when forcing the game cam and previousFreeCamData is not nil, then we change it to orbit cam
  if forceGameCam and previousFreeCamData then
    previousFreeCamData = nil
    previousCamMode = "orbit"
  end

  instant = instant or previousFreeCamData
  if instant then
    freeroam_bigMapMarkers.clearMarkers()
  else
    freeroam_bigMapMarkers.hideMarkers()
  end
  local camMode = core_camera.getGlobalCameras().bigMap
  local playerVehicle = be:getPlayerVehicle(0)
  if playerVehicle and not instant and not transitionActive then
    core_camera.getGlobalCameras().transition:start(false, {callback = function(endMarkerData) startTransition(endMarkerData, closeEscMenu) end})
    core_camera.setByName(0, previousCamMode, false)
  else
    if previousFreeCamData or not playerVehicle then
      commands.setFreeCamera()
      if previousFreeCamData then
        local pos = previousFreeCamData.pos
        local rot = previousFreeCamData.rot
        core_camera.setPosRot(0, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
        core_camera.setFOV(0, previousFreeCamData.fov)
      end
    else
      core_camera.setByName(0, previousCamMode, false)
    end
    deactivateBigMapCallback(closeEscMenu)
  end
  local sound = scenetree.findObjectById(airSoundId)
  if sound then
    sound:stop(-1)
    sound:setVolume(1)
    sound:setTransform(getCameraTransform())
  end

  groundMarkerAlphaSmoother:set(1)
  fogDensitySmoother:set(0)
  shadowLogWeightSmoother:set(0)
  shadowDistanceSmoother:set(shadowDist)
  uiPopupOpen = false

  local iconRenderer = scenetree.findObjectById(iconRendererId)
  if iconRenderer then
    iconRenderer:removeAllIcons()
  end
  popActionMap("BigMap")
  currentlyVisibleIds = {}
end

local function bigMapActive()
  return bigMap
end

local function isTransitionActive()
  return transitionActive
end

local function toggleBigMap()
  if transitionActive then
    if transitionActive == 1 then
      endTransition(true, nil, true)
    else
      endTransition(false, true, true)
    end
  else
    if bigMap then
      exitBigMap(false, true)
    else
      enterBigMap()
    end
  end
end

local function zoom(value)
  local camMode = core_camera.getGlobalCameras().bigMap
  if camMode then
    camMode:zoom(value)
  end
end

local zoomInValue = 0
local zoomOutValue = 0
local function zoomInOut(value, zoomIn)
  if zoomIn then
    zoomInValue = -value
  else
    zoomOutValue = value
  end
  core_camera.cameraZoom(zoomInValue + zoomOutValue)
end

local function controllerZoom(value, zoomIn)
  core_camera.cameraZoom(value)
end

local function pointRayDistance(point, rayPos, rayDir)
  return (point - rayPos):cross(rayDir):length() / rayDir:length()
end

local function onCameraPreRender(camData)
  if not bigMapActive() then return end
  profilerPushEvent("bigmap onCameraPreRender")
  if not transitionActive then
    local iconRenderer = scenetree.findObjectById(iconRendererId)
    if iconRenderer then
      local iconInfo = iconRenderer:getIconByName("controllerCrosshair")
      if iconInfo then
        local camDir = camData.res.rot * yVector
        iconInfo.worldPosition = camData.res.pos + camDir * 150
        if mouseMoved or uiHasFocus then
          iconInfo.color = invisibleColor
        else
          iconInfo.color = pureWhite
        end
      end

      local iconInfo = iconRenderer:getIconByName("navigationMarker")
      if iconInfo then
        if showNavigationMarker and core_groundMarkers.currentlyHasTarget() then
          local resolutionFactor = 800 / M.getVerticalResolution()
          local camQuat = camData.res.rot
          local camUp = camQuat * upVector
          local camToCluster = core_groundMarkers.endWP[1] - camData.res.pos
          local camToClusterLeft = camUp:cross(camToCluster):normalized()
          local camToUpperPoint = quatFromAxisAngle(camToClusterLeft, (resolutionFactor * 0.015 * core_camera.getFovRad())):__mul(camToCluster)

          iconInfo.worldPosition = camData.res.pos + camToUpperPoint
          iconInfo.color = pureWhite
        else
          iconInfo.color = invisibleColor
        end
      end
    end
  else
    -- Snap the camera to a straight line in part of the path to make it more stable
    if camPath then
      if transitionActive == 1 then
        if transitionTime < camPath.markers[3].time then
          local lineP1P3 = camPath.markers[3].pos - camPath.markers[1].pos
          local camVec = camData.res.pos - camPath.markers[1].pos
          local dotProduct = lineP1P3:dot(camVec)
          camData.res.pos = camPath.markers[1].pos + (lineP1P3:normalized() * (dotProduct / lineP1P3:length()))
        end
      elseif transitionActive == 2 then
        if transitionTime > camPath.markers[2].time then
          local lineP2P4 = camPath.markers[4].pos - camPath.markers[2].pos
          local camVec = camData.res.pos - camPath.markers[2].pos
          local dotProduct = lineP2P4:dot(camVec)
          camData.res.pos = camPath.markers[2].pos + (lineP2P4:normalized() * (dotProduct / lineP2P4:length()))
        end
      end
    end
  end

  -- Calculate the alpha based on the type and progress of transition
  local alphaGoal
  if transitionActive == 1 then
    alphaGoal = (transitionProgress > 0.5) and 1 or 0
  elseif transitionActive == 2 then
    alphaGoal = 0
  else
    alphaGoal = 1
  end
  local navRouteAlpha = groundMarkerAlphaSmoother:getWithRateUncapped(alphaGoal, camData.dtReal, 0.85)
  local simplifiedPathLength = simplifiedPath and tableSize(simplifiedPath)
  if simplifiedPathLength and simplifiedPathLength > 1 then
    local lineWidth = (camHeightAboveTerrain * camData.res.fov) / 20000
    local h, s, v = RGBtoHSV(unpack(core_groundMarkers.color)) -- groundMarkerColor
    local r, g, b = HSVtoRGB(h, s, 1)
    local color = ColorF(r, g, b, navRouteAlpha)
    for index = 1, routeAnimCounter do
      local pos1 = simplifiedPath[index]
      local pos2 = simplifiedPath[index+1]
      local b = camData.res.pos * 0.8
      local newPos1 = pos1 * 0.2; newPos1:setAdd(b)
      local newPos2 = pos2 * 0.2; newPos2:setAdd(b)
      debugDrawer:drawCylinder(newPos1, newPos2, lineWidth/2, color)
    end
    routeAnimCounter = math.min(simplifiedPathLength - 1, routeAnimCounter + (camHeightAboveTerrain/camData.dtReal) / routeAnimSpeedFactor)
  end

  -- display mission route preview
  if routePreview and #routePreview > 1 then
    local lineWidth = (camHeightAboveTerrain * camData.res.fov) / 20000
    local h, s, v = RGBtoHSV(unpack(core_groundMarkers.color or {0.1, 0.25, 0.5})) -- groundMarkerColor
    local r, g, b = HSVtoRGB(h, 0.3, 1) -- routePreviewCol
    local color = ColorF(r, g, b, navRouteAlpha * 0.7)

    for index = 1, #routePreview-1 do
      local pos1 = routePreview[index]
      local pos2 = routePreview[index+1]
      local b = camData.res.pos * 0.85
      local newPos1 = pos1 * 0.15; newPos1:setAdd(b)
      local newPos2 = pos2 * 0.15; newPos2:setAdd(b)
      debugDrawer:drawCylinder(newPos1, newPos2, lineWidth/6, color)
    end
  end

  profilerPopEvent("bigmap onCameraPreRender")
end

local function getMissionById(missionId)
  local mission = gameplay_missions_missions.getMissionById(missionId)

  -- this is a hack for "-1"-location suffix
  if not mission then
    mission = gameplay_missions_missions.getMissionById(string.sub(missionId, 1, -3))
  end
  return mission
end

local function clearRoutePreview() routePreview = nil end
M.clearRoutePreview = clearRoutePreview
local function setRoutePreview(unsimplifiedRoute)
  missionRouteAnimCounter = 1
  if not unsimplifiedRoute then
    routePreview = nil
  else
    routePreview = simplifyRoute(unsimplifiedRoute)
  end
end
M.setRoutePreview = setRoutePreview
local function setRoutePreviewSimple(from, to)
  local ret = {from, to}
  -- calculate in-world route
  local route = require('/lua/ge/extensions/gameplay/route/route')()
  route:setupPathMulti(ret)
  routePreview = simplifyRoute(route.path)
end
M.setRoutePreviewSimple = setRoutePreviewSimple

local function showMissionWorldPreview(missionId)
  local mission = getMissionById(missionId)
  if not mission then return end

  missionRouteAnimCounter = 1
  if mission.getWorldPreviewRoute then
    routePreview = simplifyRoute(mission:getWorldPreviewRoute())
    return missionId
  else
    routePreview = nil
  end
end


-- called from the UI when a poi is hovered in the list.
local function poiHovered(poiIdInCluster, hovered)
  if hovered then
    hoveredPreviewMissionId = showMissionWorldPreview(poiIdInCluster)
  else
    if selectedPreviewMissionId then
      showMissionWorldPreview(selectedPreviewMissionId)
    else
      clearRoutePreview()
    end
    hoveredPreviewMissionId = nil
  end
  M.hoveredListItem = hovered and poiIdInCluster or nil
end

local function deselect()
  --local missionIds = getPoiIds()
  guihooks.trigger("onReducedPoiList", {missionIds = {}})
  extensions.hook("onPoiSelectedFromBigmap",nil)
  if M.selectedPoiId then
    M.selectedPoiId = nil

    if not hoveredPreviewMissionId then
      clearRoutePreview()
    end
    selectedPreviewMissionId = nil
  end
end

local function navigateToMission(poiId)
  if career_modules_testDrive and career_modules_testDrive.isActive() then return end
  resetForceVisible()

  for i, cluster in ipairs(gameplay_playmodeMarkers.getPlaymodeClusters()) do
    local marker = gameplay_playmodeMarkers.getMarkerForCluster(cluster)
    if cluster.containedIdsLookup and cluster.containedIdsLookup[poiId] then
      cluster.focus = true
      setNavFocus(marker.pos)
      showNavigationMarker = false
      M.navigationPoiId = poiId
      extensions.hook("onNavigateToMission", poiIdInCluster)
      return marker
    end
  end
  -- if none has been found, use the bigmapMarkers instead
  for i, poi in ipairs(gameplay_rawPois.getRawPoiListByLevel(getCurrentLevelIdentifier())) do
    if poi.id ==  poiId and poi.markerInfo.bigmapMarker then
      setNavFocus(poi.markerInfo.bigmapMarker.pos)
      showNavigationMarker = false
      M.navigationPoiId = poiId
      extensions.hook("onNavigateToMission", poiIdInCluster)
      return marker
    end
  end

  extensions.hook("onNavigateToMission",nil)
  setNavFocus(nil)

end

local function onMenuItemNavigation()
  if bigMapActive() then
    blockUiActions(false)
    uiHasFocus = true
  end
end

-- called from the UI
local function selectPoi(poiIdInCluster)
  M.selectedPoiId = poiIdInCluster
  selectedPreviewMissionId = showMissionWorldPreview(poiIdInCluster)
  onMenuItemNavigation()
  extensions.hook("onPoiSelectedFromBigmap", poiIdInCluster)
  if poiSelectCallback then
    poiSelectCallback(poiIdInCluster)
  end
end

local function teleportFromBigmapToTarget(veh, pos, rot)
  if career_career.isActive() then
    spawn.safeTeleport(veh, pos, rot, nil, nil, nil, nil, false)
  else
    spawn.safeTeleport(veh, pos, rot)
    veh:resetBrokenFlexMesh()
  end

  if core_groundMarkers.currentlyHasTarget() then
    setNavFocus(core_groundMarkers.endWP[1])
  end
  exitBigMap(false, true, true)
  core_camera.resetCamera(0)
  extensions.hook("teleportedFromBigmap")
end

local function teleportToPoi(poiId)
  for _, poi in ipairs(gameplay_rawPois.getRawPoiListByLevel(getCurrentLevelIdentifier())) do
    if poiId == poi.id then
      local veh = be:getPlayerVehicle(0)
      if veh then
        local pos, rot = (poi.markerInfo.bigmapMarker.quickTravelPosRotFunction or nop)(poi, veh)
        if pos and rot then
          teleportFromBigmapToTarget(veh, pos, rot)
        end
      end
    end
  end
end

local function camMoveController(upDown, value)
  if core_camera and not uiPopupOpen then
    if upDown then
      core_camera.moveForwardBackward(sign(value) * value^2)
    else
      core_camera.moveLeftRight(sign(value) * value^2)
    end
    if uiHasFocus then
      blockUiActions(true)
      uiHasFocus = false
    end
  end
  mouseMoved = false
end

local function closePopupCallback()
  blockUiActions(true)
  uiPopupOpen = false
end

local function openPopupCallback()
  if not mouseMoved then
    camMoveController(true, 0)
    camMoveController(false, 0)
  end
  blockUiActions(false)
  uiPopupOpen = true -- TODO turn to false to test non-modal window
end

local function camMoveKey(value, direction)
  if core_camera then
    if direction == 1 then
      core_camera.moveforward(value)
    elseif direction == 2 then
      core_camera.movebackward(value)
    elseif direction == 3 then
      core_camera.moveleft(value)
    else
      core_camera.moveright(value)
    end
  end
end

-- called when the user clicks the mouse
local function clickOnMap()

  -- deselecting the current marker
  log("I", "", string.format("Sel: %s Hov: %s HasTgt: %s", M.selectedPoiId, M.hoveredPoiId, dumps(core_groundMarkers.currentlyHasTarget())))
  if M.selectedPoiId and (not M.hoveredPoiId or M.selectedPoiId == M.hoveredPoiId) then
    deselect()
    return
  end

  -- clicking the map to set a route anywhere.
  if not M.hoveredPoiId and not core_groundMarkers.currentlyHasTarget() then
    local ray
    if mouseMoved then
      ray = getCameraMouseRay()
    else
      local camDir = core_camera.getQuat() * yVector
      ray = {pos = core_camera.getPosition(), dir = camDir}
    end
    local hitDist = castRayStatic(ray.pos, ray.dir, 50000)
    if hitDist < 50000 then
      setNavFocus(ray.pos + ray.dir * hitDist)
      showNavigationMarker = true
      Engine.Audio.playOnce('AudioGui','event:>UI>Bigmap>Route')
    end
    return
  end

  -- remove navigation when the ground is clicked, but only when no mission is selected
  if not M.selectedPoiId and not M.hoveredPoiId and core_groundMarkers.currentlyHasTarget() then
    navigateToMission(nil)
    return
  end

  -- selecting a marker
  if M.hoveredPoiId then
    local missionIds = freeroam_bigMapMarkers.getIdsFromHoveredPoiId(M.hoveredPoiId)
    if not tableIsEmpty(missionIds) then
      local missionIdsById = {}
      for _, v in ipairs(missionIds) do
        missionIdsById[v] = true
      end
      guihooks.trigger("onReducedPoiList", {missionIds = missionIdsById, selectOrder = missionIds, defaultHighlight = mouseMoved ~= true})
      selectPoi(M.hoveredPoiId)
    end
    Engine.Audio.playOnce('AudioGui','event:>UI>Bigmap>Select_Icon')
    return
  end
end

local function onMouseButton(buttonDown)
  local camMode = core_camera.getGlobalCameras().bigMap
  local clickedOnMap = true
  if not buttonDown and not mouseDragging then
    clickOnMap()
  end
  if not buttonDown then
    mouseDragging = false
  end
  camMode:onMouseButton(buttonDown, mouseDragging)
end

local function onControllerSelect()
  -- check if ray intersects with iconPos / cluster.radius. then show it to UI
  if not mouseMoved and not uiHasFocus then
    clickOnMap()
  end
end

local function updateMergeRadius(factor)
  local camMode = core_camera.getGlobalCameras().bigMap
  local maxMergeRadius = (camHeightAboveTerrain * camMode.fovMax) / 1000
  local minMergeRadius = (camHeightAboveTerrain * camMode.fovMin) / 1000
  M.clusterMergeRadius = lerp(minMergeRadius, maxMergeRadius, factor)
  freeroam_bigMapMarkers.setupFilter(currentlyVisibleIds, M.clusterMergeRadius)
  --updateOnlyIdsVisible(true)
end

local function onSerialize()
  local data = {}
  data.airSoundId = airSoundId
  data.bigMap = bigMap
  if bigMap then
    -- Just calling exitBigMap in onSerialize doesnt work correctly for some reason, so we have to do some stuff manually
    data.previousCamMode = previousCamMode
    exitBigMap(true, true)
  end
  clearCylinderCache()

  return data
end

local function onDeserialized(v)
  airSoundId = v.airSoundId
  if v.bigMap then
    local _previousCamMode = v.previousCamMode
    extensions.core_jobsystem.create(
      function (job)
        job.sleep(0.1)
        enterBigMapActual(true)
        previousCamMode = _previousCamMode
      end
    )
  end
end

local function getVerticalResolution()
  return verticalResolution
end

local function onClientStartMission(levelPath)
  setActive(false)
  airSoundId = Engine.Audio.createSource('AudioGui', 'event:>UI>Bigmap>Ambience')
end

local function onClientEndMission(levelPath)
  clearCylinderCache()
  deselect()
  resetForceVisible()
  setNavFocus(nil)
end

local function onNavgraphReloaded()
  if bigMap then
    exitBigMap(true)
    enterBigMap(true)
  end
end

local changeUiFilterPressed = {}
local function onChangeUiFilter(value, dir)
  if not changeUiFilterPressed[dir] and value > 0.65 then
    changeUiFilterPressed[dir] = true
    guihooks.trigger("onChangeBigmapFilterIndex", {change = dir})
  end

  if changeUiFilterPressed[dir] and value < 0.35 then
    changeUiFilterPressed[dir] = nil
  end
end

local function isUIPopupOpen()
  return uiPopupOpen
end

local function enterBigmapWithCustomPOIs(poiIds, callback, instant, _horizontalOffsetFactor)
  horizontalOffsetFactor = _horizontalOffsetFactor
  poiSelectCallback = callback
  enterBigMap(instant)
  setOnlyIdsVisible(poiIds)
end

local function onExtensionLoaded()
	log('W', "mpBigMapMode", "--------------------------------------MP BIG MAP MODE")
end

-- public interface
M.enterBigMap = enterBigMap
M.exitBigMap = exitBigMap
M.toggleBigMap = toggleBigMap
M.bigMapActive = bigMapActive
M.isTransitionActive = isTransitionActive
M.zoom = zoom
M.zoomInOut = zoomInOut
M.controllerZoom = controllerZoom
M.navigateToMission = navigateToMission
M.selectPoi = selectPoi
M.teleportToPoi = teleportToPoi
M.closePopupCallback = closePopupCallback
M.openPopupCallback = openPopupCallback
M.clusterMergeRadius = 10 -- TODO adjust this merge radius
M.updateMergeRadius = updateMergeRadius
M.deselect = deselect
M.resetForceVisible = resetForceVisible
M.setNavFocus = setNavFocus
M.reachedTarget = reachedTarget
M.getVerticalResolution = getVerticalResolution
M.poiHovered = poiHovered
M.isUIPopupOpen = isUIPopupOpen
M.enterBigmapWithCustomPOIs = enterBigmapWithCustomPOIs

M.onClientStartMission    = onClientStartMission
M.onClientEndMission      = onClientEndMission
M.onMouseButton = onMouseButton
M.onControllerSelect = onControllerSelect
M.camMoveController = camMoveController
M.camMoveKey = camMoveKey
M.onCameraPreRender = onCameraPreRender
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized
M.onMenuItemNavigation = onMenuItemNavigation
M.onNavgraphReloaded = onNavgraphReloaded
M.onChangeUiFilter = onChangeUiFilter

M.onInit = function() setExtensionUnloadMode(M, "manual") end

M.onExtensionLoaded = onExtensionLoaded

return M
