
local M = {}

local function onVehicleReady()
	if v.config.model == "unicycle" then
		obj:setGhostEnabled(true)
	end
	obj:queueGameEngineLua("careerMPEnabler.onVehicleReady(" .. obj:getID() .. ") ")
end

local function onConditionCheck()
	if partCondition and partCondition.getConditions() then
		obj:queueGameEngineLua("careerMPEnabler.onConditionCheckCallback(" .. obj:getID() .. ") ")
	end
end

M.onConditionCheck = onConditionCheck

M.onVehicleReady = onVehicleReady

return M
