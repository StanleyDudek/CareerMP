--CareerMP Player Payments (CLIENT) by Dudekahedron, 2026

local M = {}

local nickname = MPConfig.getNickname()

local paymentAllowed = false
local paymentTimer = 0
local paymentTimerThreshold = 2.125
local paymentID = 1

local function payPlayer(player_name, amount)
	if paymentAllowed then
		paymentTimer = 0
		paymentAllowed = false
		local target_player_id
		if amount then
			amount = math.abs(amount)
		end
		if player_name and player_name ~= nickname then
			local selfMoney = career_modules_playerAttributes.getAttribute("money").value
			if selfMoney then
				local validTransaction = selfMoney - amount >= 0
				if validTransaction then
					local players = MPVehicleGE.getPlayers()
					for _, playerData in pairs(players) do
						if playerData.name == player_name then
							target_player_id = playerData.playerID
							local data = jsonEncode({money = amount, tags = {"gameplay"}, label = "Paid player: " .. player_name, target_player_id = target_player_id, target_player_name = player_name})
							TriggerServerEvent("payPlayer", data)
							break
						end
					end
				else
					guihooks.trigger('toastrMsg', {type = "error", title = "Invalid transaction!", msg = "You do not have enough money to pay " .. player_name .. "!", config = {timeOut = 2000}})
				end
			else
				guihooks.trigger('toastrMsg', {type = "error", title = "Invalid transaction!", msg = "Player attribute not found!", config = {timeOut = 2000}})
			end
		else
			guihooks.trigger('toastrMsg', {type = "error", title = "Invalid transaction!", msg = "You cannot pay yourself!", config = {timeOut = 2000}})
		end
	end
end

local function rxPayment(data)
	local paymentData = jsonDecode(data)
	career_modules_playerAttributes.addAttributes({money = paymentData.money}, {tags = paymentData.tags, label = "Payment from player: " .. paymentData.sender})
	career_saveSystem.saveCurrent()
	guihooks.trigger('toastrMsg', {type = "info", title = "Transaction #" .. paymentID, msg = paymentData.sender .. " paid you $" .. paymentData.money, config = {timeOut = 2000}})
	paymentID = paymentID + 1
end

local function rxBounce(data)
	local paymentData = jsonDecode(data)
	guihooks.trigger('toastrMsg', {type = "error", title = "Payment returned!", msg = "You are being ratelimited! Your payment of $" .. paymentData.money .. " to " .. paymentData.target_player_name .. " was returned.", config = {timeOut = 2000}})
end

local function rxConfirmation(data)
	local paymentData = jsonDecode(data)
	career_modules_playerAttributes.addAttributes({money = -paymentData.money}, {tags = paymentData.tags, label = paymentData.label})
	career_saveSystem.saveCurrent()
	guihooks.trigger('toastrMsg', {type = "info", title = "Transaction #" .. paymentID, msg = "You paid " .. paymentData.target_player_name .. " $" .. paymentData.money, config = {timeOut = 2000}})
	paymentID = paymentID + 1
end

local function rxDeny(data)
	local paymentData = jsonDecode(data)
	guihooks.trigger('toastrMsg', {type = "error", title = "Payments disabled!", msg = "This server has disabled the player payment system! Your payment of $" .. paymentData.money .. " to " .. paymentData.target_player_name .. " was returned.", config = {timeOut = 2000}})
end

local function onWorldReadyState(state)
	if state == 2 then
		nickname = MPConfig.getNickname()
	end
end

local function onUpdate(dtReal)
	if worldReadyState == 2 then
		paymentTimer = paymentTimer + dtReal
		if paymentTimer > paymentTimerThreshold then
			paymentAllowed = true
		end
	end
end

local function onExtensionLoaded()
	AddEventHandler("rxPayment", rxPayment)
	AddEventHandler("rxBounce", rxBounce)
	AddEventHandler("rxConfirmation", rxConfirmation)
	AddEventHandler("rxDeny", rxDeny)
	log('W', 'careerMP', 'CareerMP Player Payments LOADED!')
end

local function onExtensionUnloaded()
	log('W', 'careerMP', 'CareerMP Player Payments UNLOADED!')
end

M.payPlayer = payPlayer

M.onWorldReadyState = onWorldReadyState
M.onUpdate = onUpdate

M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded

M.onInit = function() setExtensionUnloadMode(M, 'manual') end

return M
