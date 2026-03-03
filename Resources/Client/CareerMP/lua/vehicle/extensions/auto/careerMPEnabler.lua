
local M = {}

local function onVehicleReady()
	obj:queueGameEngineLua("careerMPEnabler.onVehicleReady(" .. obj:getID() .. ") ")
end

local function callback(id, distance)
	obj:queueGameEngineLua("careerMPEnabler.callback(" .. id .. ", " .. distance .. ") ")
end

M.onVehicleReady = onVehicleReady

M.callback = callback

return M
