
local M = {}

local uniCol = true

local function onVehicleReady()
	obj:queueGameEngineLua("careerMPEnabler.onVehicleReady(" .. obj:getID() .. ") ")
	obj:queueGameEngineLua("careerMPPerPartPaint.onVehicleReady(" .. obj:getID() .. ") ")
end

local function setUnicycleGhost(enabled)
	uniCol = enabled
end

local function onConditionCheck()
	if partCondition and partCondition.getConditions() then
		obj:queueGameEngineLua("careerMPPerPartPaint.onConditionCheckCallback(" .. obj:getID() .. ") ")
	end
end

local function onUpdateGFX()
	if not uniCol then
		obj:setGhostEnabled(true)
	end
end

M.onUpdateGFX = onUpdateGFX

M.onConditionCheck = onConditionCheck

M.setUnicycleGhost = setUnicycleGhost

M.onVehicleReady = onVehicleReady

return M
