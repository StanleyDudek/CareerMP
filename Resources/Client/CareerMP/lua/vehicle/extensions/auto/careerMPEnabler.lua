
local M = {}

local function onVehicleReady()
	obj:queueGameEngineLua("careerMPEnabler.onVehicleReady(" .. obj:getID() .. ") ")
end

M.onVehicleReady = onVehicleReady

return M
