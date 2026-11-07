--
-- mogliScreen.lua — Adapted for Farming Simulator 25 (FS25)
-- Fixes global `InputBinding` crash (`g_inputBinding`), guards FocusManager and GUI profiles,
-- and delegates settings UI to the FS25 two-page HUD panel so broken FS22 ScreenElement XML profiles
-- never lock the game or mouse cursor.
--

local mogliScreenVersion = 2.50
local mogliScreenClass   = g_currentModName .. ".mogliScreen"

if _G[mogliScreenClass] ~= nil and _G[mogliScreenClass].version ~= nil and _G[mogliScreenClass].version >= mogliScreenVersion then
	print("Factory class " .. tostring(mogliScreenClass) .. " already exists in version " .. tostring(_G[mogliScreenClass].version))
else
	local mogliScreen = {}
	mogliScreen.version = mogliScreenVersion

	_G[mogliScreenClass] = mogliScreen

	function mogliScreen.newClass(_globalClassName_, _vehicleClassName_, _settingsPage_)
		local _newClass_ = {}
		local mt = nil
		if ScreenElement ~= nil then
			mt = Class(_newClass_, ScreenElement)
		else
			mt = { __index = _newClass_ }
		end

		function _newClass_.new(target, custom_mt)
			local self = {}
			if ScreenElement ~= nil and ScreenElement.new ~= nil then
				local ok, inst = pcall(ScreenElement.new, target, custom_mt or mt)
				if ok and type(inst) == "table" then
					self = inst
				else
					setmetatable(self, custom_mt or mt)
				end
			else
				setmetatable(self, custom_mt or mt)
			end
			self.mogliTexts = {}
			self.isOpen = false
			return self
		end

		function _newClass_:setVehicle(vehicle)
			self.vehicle = vehicle
		end

		-- In FS25, instead of opening the incompatible FS22 ScreenElement XML dialog,
		-- clicking the settings icon toggles Page 2 of the FS25 HUD directly on the vehicle!
		function _newClass_:showGui(vehicle)
			if vehicle ~= nil and _vehicleClassName_ ~= nil and _G[_vehicleClassName_] ~= nil then
				local hud = _G[_vehicleClassName_].acHud
				if hud ~= nil then
					hud.MaxPage = 2
					if hud.Page == 2 then
						hud.Page = 1
					else
						hud.Page = 2
					end
					hud:setGuiActive(vehicle, true)
					if AIVELogger ~= nil then
						AIVELogger.info("GUI", "Switched FS25 HUD to settings page %d for vehicle '%s'.", hud.Page, tostring(vehicle:getName()))
					end
					return
				end
			end
		end

		function _newClass_:onOpen()
			self.isOpen = true
			if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
				pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, true)
			end
		end

		function _newClass_:onClose()
			self.isOpen = false
			self.vehicle = nil
			if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
				pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, false)
			end
		end

		function _newClass_:onClickBack()
			self:onClose()
		end

		function _newClass_:onClickOk()
			self:onClose()
		end

		function _newClass_:update(dt)
		end

		function _newClass_:draw()
		end

		_G[_globalClassName_] = _newClass_
	end
end
