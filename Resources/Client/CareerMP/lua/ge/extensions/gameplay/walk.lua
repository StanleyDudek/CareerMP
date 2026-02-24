-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local logTag = "walk"
local vehicleInFront
local atParkingSpeed = true
local showMessageLastFrame = false
local togglingEnabled = true
local vehicleBlacklist = {}

local lowerStoppingSpeed = 5.0/3.6
local higherStoppingSpeed = 6.0/3.6
local up = vec3(0,0,1)
local forward = vec3(0,1,0)
local placePlayerOffsetFromBody = 0.7

local active = false

local function getPlayerUnicycle(veh)
  veh = veh or getPlayerVehicle(0)
  if veh and veh:getJBeamFilename() == "unicycle" then
    return veh
  end
end

local function isWalking()
  return getPlayerUnicycle() ~= nil
end

local function getUnicyleAtPosition(pos, visibilityPoint)
  local unicycle = getPlayerUnicycle()

  if not unicycle then
    for _, veh in ipairs(getAllVehicles()) do
      if veh:getJBeamFilename() == "unicycle" and not veh:getActive() and MPVehicleGE.isOwn(veh:getID()) then
        unicycle = veh
        break
      end
    end
  end
  if unicycle then
    unicycle:setActive(1)
    spawn.safeTeleport(unicycle, pos, nil, nil, visibilityPoint, false)
  else
    local config = career_career and career_career.isActive() and "vehicles/unicycle/beammp_default.pc"
    unicycle = extensions.core_vehicles.spawnNewVehicle("unicycle", {pos = pos, visibilityPoint = visibilityPoint, removeTraffic = false, config = config})
  end
  return unicycle
end

-- returns a position near the driver's door
local function getDoorsidePosRot(veh)
  local refNodes = extensions.core_vehicle_manager.getVehicleData(veh:getId()).vdata.refNodes[0]
  local ref  = veh:getNodePosition(refNodes.ref)
  local left = veh:getNodePosition(refNodes.left)
  local carLeft = (left-ref):normalized()
  local driverNode, rightHandDrive, rightHandDoor = core_camera.getDriverData(veh)
  driverNode = driverNode or 0
  local driverPos = veh:getPosition() + veh:getNodePosition(driverNode)

  local initCorner = rightHandDoor and veh.initialNodePosBB.minExtents or veh.initialNodePosBB.maxExtents
  local initDriverPos = veh:getInitialNodePosition(driverNode)

  local driverPosOffset = initCorner.x - initDriverPos.x
  driverPosOffset = driverPosOffset + (sign(driverPosOffset) * placePlayerOffsetFromBody)

  local pos = driverPos + driverPosOffset * carLeft
  local target = veh:getPosition() + ref
  local front = (target-pos):normalized() -- look from pos towards the center
  front.z = 0

  return pos, front, up
end

local function getDriverPos(veh)
  local driverNode = core_camera.getDriverData(veh)
  return veh:getPosition() + veh:getNodePosition(driverNode or 0)
end

local function setUnicycleInactive(unicycle)
  be.nodeGrabber:clearVehicleFixedNodes(unicycle:getId())
  unicycle:setActive(0)
end

local function getInVehicle(vehicle)
  local unicycle = getPlayerUnicycle()
  be:enterVehicle(0, vehicle)
  if unicycle then
    setUnicycleInactive(unicycle)
  end
end

local function getOutOfVehicle(vehicle, pos, rot)
  local visibilityPoint
  if vehicle and not pos then
    local doorsidePos, front, up = getDoorsidePosRot(vehicle)
    pos = doorsidePos
    visibilityPoint = getDriverPos(vehicle)
  end
  local unicycle = getUnicyleAtPosition(pos, visibilityPoint)

  local camData = core_camera.getCameraDataById(unicycle:getId())
  if camData and camData.unicycle then
    local unicyclePos = unicycle:getPosition()
    local finalDir
    if rot then
      finalDir = rot * forward
    elseif visibilityPoint then
      finalDir = (visibilityPoint - unicyclePos)
    else
      finalDir = forward
    end
    camData.unicycle:setCustomData({pos = unicyclePos, front = finalDir, up = up})
  end
  be:enterVehicle(0, unicycle)
end

local function setRot(front, up)
  if not active then return end
  local unicycle = getPlayerUnicycle()
  local camData = core_camera.getCameraDataById(unicycle:getId())
  if camData and camData.unicycle then
    camData.unicycle:setCustomData({front = front, up = up})
  end
end

-- pos and rot are optional
local function setWalkingMode(enabled, pos, rot, force)
  if (enabled == active) or ((not atParkingSpeed or not togglingEnabled or (core_replay.getState() == 'playback')) and not force) then
    return false, getPlayerUnicycle() and getPlayerUnicycle():getId()
  end
  if enabled then
    if not getPlayerUnicycle() then
      extensions.hook("onBeforeWalkingModeToggled", enabled)
      getOutOfVehicle(getPlayerVehicle(0), pos, rot)
    end
  else
    if vehicleInFront then
      extensions.hook("onBeforeWalkingModeToggled", enabled, vehicleInFront:getId())
      getInVehicle(vehicleInFront)
    else
      extensions.hook("onBeforeWalkingModeToggled", enabled)
      setUnicycleInactive(getPlayerUnicycle())
    end
  end
  local playerUnicycle = getPlayerUnicycle()
  if enabled then
    return playerUnicycle ~= nil, playerUnicycle and playerUnicycle:getId()
  else
    return not playerUnicycle, playerUnicycle and playerUnicycle:getId()
  end
end

local function toggleWalkingMode()
  if active then
    if vehicleInFront then
      setWalkingMode(false)
    end
  else
    setWalkingMode(true)
  end
end

-- TODO if we got rid of the moving threshold, we could get rid of the update function when walking mode is not active
local vehVelocity = vec3()
local function setAtParkingSpeed(veh, dtSim)
  -- prevent flicker while hovering over threshold speed by using a different limit on each direction
  if veh then
    vehVelocity:set(veh:getVelocityXYZ())
    local vehicleSpeed = vehVelocity:len()
    if vehicleSpeed < lowerStoppingSpeed then atParkingSpeed = true end
    if vehicleSpeed > higherStoppingSpeed then atParkingSpeed = false end
  else
    atParkingSpeed = true
  end
end

local p1, p2, p3, p4, p5, p6, p7, p8 = vec3(), vec3(), vec3(), vec3(), vec3(), vec3(), vec3(), vec3()
local bbPoints = {}
local function getBBPoints(bbCenter, bbAxis0, bbAxis1, bbAxis2)
  p1:set(bbCenter) p1:setAdd(bbAxis0) p1:setAdd(bbAxis1) p1:setSub(bbAxis2)
  p2:set(bbCenter) p2:setAdd(bbAxis0) p2:setAdd(bbAxis1) p2:setAdd(bbAxis2)
  p3:set(bbCenter) p3:setSub(bbAxis0) p3:setAdd(bbAxis1) p3:setAdd(bbAxis2)
  p4:set(bbCenter) p4:setSub(bbAxis0) p4:setAdd(bbAxis1) p4:setSub(bbAxis2)
  p5:set(bbCenter) p5:setAdd(bbAxis0) p5:setSub(bbAxis1) p5:setSub(bbAxis2)
  p6:set(bbCenter) p6:setAdd(bbAxis0) p6:setSub(bbAxis1) p6:setAdd(bbAxis2)
  p7:set(bbCenter) p7:setSub(bbAxis0) p7:setSub(bbAxis1) p7:setAdd(bbAxis2)
  p8:set(bbCenter) p8:setSub(bbAxis0) p8:setSub(bbAxis1) p8:setSub(bbAxis2)
  bbPoints[1] = p1; bbPoints[2] = p2; bbPoints[3] = p3; bbPoints[4] = p4;
  bbPoints[5] = p5; bbPoints[6] = p6; bbPoints[7] = p7; bbPoints[8] = p8;
  return bbPoints
end


local function boundingBoxDistance(pos, otherBBCenter, otherBBAxis0, otherBBAxis1, otherBBAxis2)
  local bbPoints = getBBPoints(otherBBCenter, otherBBAxis0, otherBBAxis1, otherBBAxis2)

  -- 1,2,3,4 front
  -- 5,6,7,8 back
  local minDist = math.huge
  -- lower bbPoints
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[1], bbPoints[4]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[4], bbPoints[8]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[8], bbPoints[5]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[5], bbPoints[1]))

  -- upper bbPoints
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[2], bbPoints[3]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[3], bbPoints[7]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[7], bbPoints[6]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[6], bbPoints[2]))

  -- left
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[1], bbPoints[6]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[2], bbPoints[5]))
  -- front
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[1], bbPoints[3]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[2], bbPoints[4]))
  -- right
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[3], bbPoints[8]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[4], bbPoints[7]))
  -- back
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[5], bbPoints[7]))
  minDist = math.min(minDist, pos:distanceToLineSegment(bbPoints[6], bbPoints[8]))
  return minDist
end

local otherBBCenter, otherBBAxis0, otherBBAxis1, otherBBAxis2 = vec3(), vec3(), vec3(), vec3()
local vehPos = vec3()
local function onUpdate(dtReal, dtSim)
  local showMessage = false

  vehicleInFront = nil
  if active then
    local unicycle = getPlayerUnicycle()
    vehPos:set(unicycle:getPositionXYZ())
    local closestHit = 2
    for _, veh in ipairs(getAllVehicles()) do
      local vehId = veh:getID()
      if not vehicleBlacklist[vehId] and veh.playerUsable ~= false and veh:getActive() and veh:getJBeamFilename() ~= "unicycle" then
        otherBBCenter:set(be:getObjectOOBBCenterXYZ(vehId))
        otherBBAxis0:set(be:getObjectOOBBHalfAxisXYZ(vehId, 0))
        otherBBAxis1:set(be:getObjectOOBBHalfAxisXYZ(vehId, 1))
        otherBBAxis2:set(be:getObjectOOBBHalfAxisXYZ(vehId, 2))

        if be:getObjectOOBBIsInitialized(vehId) then
          local dist = boundingBoxDistance(vehPos, otherBBCenter, otherBBAxis0, otherBBAxis1, otherBBAxis2)
          if dist < closestHit then
            vehicleInFront = veh
            closestHit = dist
          end
        end
      end
    end

    if vehicleInFront then
      setAtParkingSpeed(vehicleInFront, dtSim)
      if atParkingSpeed and togglingEnabled then
        showMessage = true
      end
    end

    -- set visibility of unicycle vehicle
    local alpha
    if core_camera.getActiveGlobalCameraName() then
      local camPos = core_camera.getPosition()
      local driverNode = core_camera.getDriverDataById(unicycle:getId())
      local driverPos = unicycle:getPosition() + unicycle:getNodePosition(driverNode or 0)
      alpha = clamp(camPos:distance(driverPos) - 0.1, 0, 1)
    else
      alpha = 0
    end

    unicycle:setMeshAlpha(alpha, "", false)
  else
    setAtParkingSpeed(getPlayerVehicle(0), dtSim)
  end

  if showMessage ~= showMessageLastFrame then
    if showMessage then
      ui_message("ui.inputActions.gameplay.toggleWalkingMode.enterMessage", 10, "walkingmode")
    else
      ui_message("", 0, "walkingmode")
    end
  end
  showMessageLastFrame = showMessage
end

local function getVehicleInFront()
  return vehicleInFront
end

local function isAtParkingSpeed()
  return atParkingSpeed
end

local function onSerialize()
  return {togglingEnabled = togglingEnabled, vehicleBlacklist = vehicleBlacklist}
end

local function onDeserialize(data)
  togglingEnabled = data.togglingEnabled
  vehicleBlacklist = data.vehicleBlacklist
  active = getPlayerUnicycle() ~= nil
end

local function getPosRot()
  local unicycle = getPlayerUnicycle()
  if active and unicycle then
    return unicycle:getPosition(), core_camera.getQuat()
  end
end

local function getPosXYZ()
  local unicycle = getPlayerUnicycle()
  if active and unicycle then
    return unicycle:getPositionXYZ()
  end
end

local function getRotXYZW()
  local unicycle = getPlayerUnicycle()
  if active and unicycle then
    return core_camera.getQuatXYZW()
  end
end

local function enableToggling(enabled)
  togglingEnabled = enabled
end

local function isTogglingEnabled()
  return togglingEnabled
end

local function addVehicleToBlacklist(vehId)
  vehicleBlacklist[vehId] = true
end

local function removeVehicleFromBlacklist(vehId)
  vehicleBlacklist[vehId] = nil
end

local function isVehicleBlacklisted(vehId)
  return vehicleBlacklist[vehId]
end

local function clearBlacklist()
  vehicleBlacklist = {}
end

local function getBlacklist()
  return vehicleBlacklist
end

local function onClientStartMission(levelPath)
  clearBlacklist()
  togglingEnabled = true
end

local function onVehicleSwitched(oldId, newId, player)
  if player ~= 0 then return end

  -- Reset the alpha to 1 when switching away from a unicycle
  local unicycle = scenetree.findObjectById(oldId)
  if unicycle and unicycle.getJBeamFilename and unicycle:getJBeamFilename() == "unicycle" then
    unicycle:setMeshAlpha(1, "", false)
  end

  active = getPlayerUnicycle() ~= nil
end

M.isWalking = isWalking
M.getPosRot = getPosRot
M.getVehicleInFront = getVehicleInFront
M.isAtParkingSpeed = isAtParkingSpeed
M.toggleWalkingMode = toggleWalkingMode
M.enableToggling = enableToggling
M.isTogglingEnabled = isTogglingEnabled
M.setWalkingMode = setWalkingMode
M.getInVehicle = getInVehicle
M.getDoorsidePosRot = getDoorsidePosRot
M.getPlayerUnicycle = getPlayerUnicycle
M.addVehicleToBlacklist = addVehicleToBlacklist
M.removeVehicleFromBlacklist = removeVehicleFromBlacklist
M.isVehicleBlacklisted = isVehicleBlacklisted
M.clearBlacklist = clearBlacklist
M.getBlacklist = getBlacklist
M.setRot = setRot
M.getPosXYZ = getPosXYZ
M.getRotXYZW = getRotXYZW

M.onUpdate = onUpdate
M.onSerialize = onSerialize
M.onDeserialize = onDeserialize
M.onClientStartMission = onClientStartMission
M.onVehicleSwitched = onVehicleSwitched

return M
