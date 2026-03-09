
local M = {}

local function onVehicleReady()
	if v.config.model == "unicycle" then
		obj:setGhostEnabled(true)
	end
	obj:queueGameEngineLua("careerMPEnabler.onVehicleReady(" .. obj:getID() .. ") ")
end

M.onVehicleReady = onVehicleReady

return M
