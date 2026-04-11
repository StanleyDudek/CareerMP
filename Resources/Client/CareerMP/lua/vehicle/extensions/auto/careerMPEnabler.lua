
local M = {}

local function onVehicleReady()
	obj:queueGameEngineLua("careerMPEnabler.onVehicleReady(" .. obj:getID() .. ") ")
	obj:queueGameEngineLua("careerMPPerPartPaint.onVehicleReady(" .. obj:getID() .. ") ")
end

local function setUnicycleGhost(enabled)
	obj:setGhostEnabled(enabled)
end

local function onConditionCheck()
	if partCondition and partCondition.getConditions() then
		obj:queueGameEngineLua("careerMPPerPartPaint.onConditionCheckCallback(" .. obj:getID() .. ") ")
	end
end

M.onConditionCheck = onConditionCheck

M.setUnicycleGhost = setUnicycleGhost

M.onVehicleReady = onVehicleReady

return M
