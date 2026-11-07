--
-- register.lua — FS25 Adaptation for AI Vehicle Extension
-- Loads AIVELogger & AIVEWheelUtils first, then AIVehicleExtension and AIVEScreen,
-- and injects AIVehicleExtension into all AI-capable FS25 vehicle types.
--

AIVehicleExtensionRegister = {}
AIVehicleExtensionRegister.isLoaded = true
AIVehicleExtensionRegister.g_currentModDirectory = g_currentModDirectory
AIVehicleExtensionRegister.specName = "AIVehicleExtension"

-- 1. Load Logger, Polyfills, AITurnStrategy Base Class & FS25 Wheel Physics Adapter first
source(Utils.getFilename("AIVELogger.lua", g_currentModDirectory))

-- 2. Load AIVehicleExtension (which sources mogliBase, mogliHud, AIVEEvents, FieldBitmap,
--    AIAnimCurve, AutoSteeringEngine, AIDriveStrategyMogli, AIDriveStrategyCombine131,
--    AIDriveStrategyCollisionOtherAI) and AIVEScreen
source(Utils.getFilename("AIVehicleExtension.lua", g_currentModDirectory))
source(Utils.getFilename("AIVEScreen.lua", g_currentModDirectory))
source(Utils.getFilename("AIVETransferTask.lua", g_currentModDirectory))
source(Utils.getFilename("AIVEAIJob.lua", g_currentModDirectory))
source(Utils.getFilename("AIVEPerformance.lua", g_currentModDirectory))

function AIVehicleExtensionRegister:beforeFinalizeVehicleTypes()
	-- In FS25, TypeManager.finalizeTypes is called for vehicle, placeable, handTool, and constructionBrush.
	-- Only inject into the "vehicle" TypeManager.
	if self == nil or self.typeName ~= "vehicle" then
		return
	end

	if AIVehicleExtension == nil then
		AIVELogger.error("Register", "Failed to add specialization AIVehicleExtension (AIVehicleExtension is nil)")
		return
	end

	local injectedCount = 0
	local typesTable = type(self.getTypes) == "function" and self:getTypes() or self.types
	if type(typesTable) == "table" then
		for k, typeDef in pairs(typesTable) do
			if typeDef ~= nil and k ~= "locomotive" and type(typeDef.specializationsByName) == "table" then
				local isAIVehicle = false
				local hasNotAIVE  = true
				for name, _ in pairs(typeDef.specializationsByName) do
					if name == "aiFieldWorker" then
						isAIVehicle = true
					end
					if name == AIVehicleExtensionRegister.specName then
						hasNotAIVE = false
					end
				end
				if isAIVehicle and hasNotAIVE then
					AIVELogger.debug("Register", "Adding AIVehicleExtension to vehicleType '%s'", tostring(k))
					typeDef.specializationsByName[AIVehicleExtensionRegister.specName] = AIVehicleExtension
					if type(typeDef.specializationNames) == "table" then
						table.insert(typeDef.specializationNames, AIVehicleExtensionRegister.specName)
					end
					if type(typeDef.specializations) == "table" then
						table.insert(typeDef.specializations, AIVehicleExtension)
					end
					injectedCount = injectedCount + 1
				end
			end
		end
	end

	AIVELogger.info("Register", "Successfully injected '%s' into %d FS25 vehicle types.", tostring(AIVehicleExtensionRegister.specName), injectedCount)
end

if TypeManager ~= nil and TypeManager.finalizeTypes ~= nil then
	TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, AIVehicleExtensionRegister.beforeFinalizeVehicleTypes)
end

function AIVehicleExtensionRegister:loadMap(name)
	AIVehicleExtensionRegister.mogliTexts = {}
	if g_i18n ~= nil and type(g_i18n.texts) == "table" then
		for n, t in pairs(g_i18n.texts) do
			AIVehicleExtensionRegister.mogliTexts[n] = t
		end
	end

	local l10nFilenamePrefixFull = Utils.getFilename("modDesc_l10n", AIVehicleExtensionRegister.g_currentModDirectory)
	local l10nXmlFile = nil
	local langs = { g_languageShort, "en", "de", "ru" }
	for _, lang in ipairs(langs) do
		if type(lang) == "string" and lang ~= "" then
			local l10nFilename = l10nFilenamePrefixFull .. "_" .. lang .. ".xml"
			if fileExists(l10nFilename) then
				l10nXmlFile = loadXMLFile("TempConfig", l10nFilename)
				break
			end
		end
	end
	if l10nXmlFile ~= nil and l10nXmlFile ~= 0 then
		local textI = 0
		while true do
			local key = string.format("l10n.longTexts.longText(%d)", textI)
			if not hasXMLProperty(l10nXmlFile, key) then
				break
			end
			local tName = getXMLString(l10nXmlFile, key .. "#name")
			local text  = getXMLString(l10nXmlFile, key)
			if tName ~= nil and text ~= nil then
				AIVehicleExtensionRegister.mogliTexts[tName] = text:gsub("\r\n", "\n")
			end
			textI = textI + 1
		end
		delete(l10nXmlFile)
	end

	if AIVehicleExtension ~= nil and type(AIVehicleExtension.initSpecialization) == "function" then
		pcall(AIVehicleExtension.initSpecialization)
	end

	if addConsoleCommand ~= nil then
		pcall(addConsoleCommand, "aiveLogLevel", "Set FS25_AIVehicleExtension log level (0-5)", "consoleCommandSetLogLevel", AIVELogger)
		pcall(addConsoleCommand, "aiveStatus", "Print FS25_AIVehicleExtension status and active vehicle kinematics", "consoleCommandStatus", AIVELogger)
		pcall(addConsoleCommand, "aiveSelfTest", "Run FS25_AIVehicleExtension diagnostic self-test", "consoleCommandSelfTest", AIVELogger)
		pcall(addConsoleCommand, "aiveSettings", "Open the AIVE settings panel on the current vehicle", "consoleCommandSettings", AIVELogger)
		pcall(addConsoleCommand, "aiveProfile", "AIVE CPU measurements: on, off, report", "consoleCommand", AIVEPerformance)
	end

	AIVELogger.info("Mission", "Map loaded ('%s'). %s v%s ready (Left Shift+H: HUD, Left Ctrl+H: Settings).",
		tostring(name), AIVELogger.MOD_NAME, AIVELogger.VERSION)
end

function AIVehicleExtensionRegister:saveSavegame(savegame)
end

function AIVehicleExtensionRegister:loadSavegame()
end

function AIVehicleExtensionRegister:deleteMap()
	FieldBitmap.fieldMod = nil
	AIVEFieldDispatcher.reset()
	AIVEPerformance.enabled=false;AIVEPerformance.stats={}
	if removeConsoleCommand ~= nil then
		pcall(removeConsoleCommand, "aiveSelfTest")
		pcall(removeConsoleCommand, "aiveStatus")
		pcall(removeConsoleCommand, "aiveLogLevel")
		pcall(removeConsoleCommand, "aiveSettings")
		pcall(removeConsoleCommand, "aiveProfile")
	end
	if type(g_AIVEScreen) == "table" and type(g_AIVEScreen.delete) == "function" then
		pcall(function() g_AIVEScreen:delete() end)
		g_AIVEScreen = nil
	end
end

function AIVehicleExtensionRegister:mouseEvent(posX, posY, isDown, isUp, button)
	if g_AIVEScreen ~= nil and g_AIVEScreen:mouseEvent(posX,posY,isDown,isUp,button) then return end
	local controlledVehicle = nil
	if g_currentMission ~= nil then
		controlledVehicle = g_currentMission.controlledVehicle
	end
	if controlledVehicle == nil and g_localPlayer ~= nil and type(g_localPlayer.getCurrentVehicle) == "function" then
		local ok, v = pcall(g_localPlayer.getCurrentVehicle, g_localPlayer)
		if ok then
			controlledVehicle = v
		end
	end
	if type(controlledVehicle) == "table" and AIVEHud ~= nil and type(AIVEHud.mouseEvent) == "function" then
		AIVEHud.mouseEvent(controlledVehicle, posX, posY, isDown, isUp, button)
	end
end

function AIVehicleExtensionRegister:keyEvent(unicode, sym, modifier, isDown)
	if isDown and g_AIVEScreen ~= nil and g_AIVEScreen.isOpen
			and (sym == 27 or (Input ~= nil and sym == Input.KEY_esc)) then
		g_AIVEScreen:onClose()
	end
end

function AIVehicleExtensionRegister:update(dt)
	if g_AIVEScreen ~= nil then g_AIVEScreen:update(dt) end
	if AIVehicle ~= nil
			and AIVehicleExtension ~= nil
			and AIVehicleExtension.aiUpdateLowFrequencyDelay ~= nil
			and AIVehicleExtension.aiUpdateLowFrequencyDelay ~= AIVehicleExtension.extendedFrequencyDelay
			and (AIVehicleExtension.numberOfExtendedWorkers or 0) <= 0
			and AIVehicle.aiUpdateLowFrequencyDelay == AIVehicleExtension.extendedFrequencyDelay then
		AIVehicle.aiUpdateLowFrequencyDelay = AIVehicleExtension.aiUpdateLowFrequencyDelay
	end
end

function AIVehicleExtensionRegister:draw()
	if g_AIVEScreen ~= nil then g_AIVEScreen:draw() end
end

addModEventListener(AIVehicleExtensionRegister)
