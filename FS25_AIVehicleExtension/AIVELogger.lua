--
-- AIVELogger & AIVEWheelUtils for Farming Simulator 25 (FS25)
-- Provides structured console/log.txt diagnostics, pcall error guards,
-- Lua 5.1/5.4 polyfills, FS25 base class shims (AITurnStrategy),
-- and the FS25 Wheel Physics & Kinematics Compatibility Layer.
--

--==============================================================================
-- 1. Lua / GIANTS Engine 10 Compatibility Polyfills & Base Class Shims
--==============================================================================
if table.getn == nil then
	table.getn = function(t)
		if type(t) ~= "table" then
			return 0
		end
		return #t
	end
end

if unpack == nil and table.unpack ~= nil then
	unpack = table.unpack
end

if math.atan2 == nil then
	math.atan2 = function(y, x)
		return math.atan(y, x)
	end
end

if Utils ~= nil and Utils.getNoNil == nil then
	Utils.getNoNil = function(val, defaultVal)
		if val == nil then
			return defaultVal
		end
		return val
	end
end

-- In FS25, GIANTS removed the global AITurnStrategy base class.
-- Define a complete compatibility base class so Class(AITurnStrategyMogli, AITurnStrategy)
-- and AITurnStrategy.new(customMt) work identically to FS22.
if AITurnStrategy == nil then
	AITurnStrategy = {}
	local AITurnStrategy_mt = type(Class) == "function" and Class(AITurnStrategy) or { __index = AITurnStrategy }

	function AITurnStrategy.new(customMt)
		local self = setmetatable({}, customMt or AITurnStrategy_mt)
		self.isTurning = false
		self.turnLeft = false
		self.vehicle = nil
		return self
	end

	function AITurnStrategy:delete()
	end

	function AITurnStrategy:setAIVehicle(vehicle, parent)
		self.vehicle = vehicle
		self.parent = parent
	end

	function AITurnStrategy:update(dt)
	end

	function AITurnStrategy:getDriveData(dt, vX, vY, vZ, turnData)
		return nil, nil, nil, nil, nil
	end

	function AITurnStrategy:startTurn(turnData)
		self.isTurning = true
		return true
	end

	function AITurnStrategy:onEndTurn(turnLeft)
		self.isTurning = false
	end

	function AITurnStrategy:draw()
	end

	function AITurnStrategy:addDebugText(text)
	end
end

if AIDriveStrategy == nil then
	AIDriveStrategy = {}
	local AIDriveStrategy_mt = type(Class) == "function" and Class(AIDriveStrategy) or { __index = AIDriveStrategy }

	function AIDriveStrategy.new(reconstructionData, customMt)
		local self = setmetatable({}, customMt or AIDriveStrategy_mt)
		self.vehicle = nil
		return self
	end

	function AIDriveStrategy:delete()
	end

	function AIDriveStrategy:setAIVehicle(vehicle)
		self.vehicle = vehicle
	end

	function AIDriveStrategy:update(dt)
	end

	function AIDriveStrategy:getDriveData(dt, vX, vY, vZ)
		return nil, nil, nil, nil, nil
	end

	function AIDriveStrategy:updateDriving(dt)
	end

	function AIDriveStrategy:addDebugText(text)
	end
end

--==============================================================================
-- 2. AIVELogger: Structured Console & log.txt Error/Debug Logger
--==============================================================================
AIVELogger = {}
AIVELogger.MOD_NAME   = "FS25_AIVehicleExtension"
AIVELogger.VERSION    = "2.6.0.3"
AIVELogger.LEVEL_OFF   = 0
AIVELogger.LEVEL_ERROR = 1
AIVELogger.LEVEL_WARN  = 2
AIVELogger.LEVEL_INFO  = 3
AIVELogger.LEVEL_DEBUG = 4
AIVELogger.LEVEL_TRACE = 5

AIVELogger.currentLevel = AIVELogger.LEVEL_INFO
AIVELogger.maxHistory   = 250
AIVELogger.history      = {}
AIVELogger.errorCounts  = {}
AIVELogger.stats = {
	errors   = 0,
	warnings = 0,
	infos    = 0,
	debugs   = 0,
	safeCallsCaught = 0
}

function AIVELogger.formatMessage(levelStr, context, msg, ...)
	local formatted = tostring(msg or "")
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, formatted, ...)
		if ok then
			formatted = res
		end
	end
	local ctx = context and ("[" .. tostring(context) .. "] ") or ""
	return string.format("[%s][%s] %s%s", AIVELogger.MOD_NAME, levelStr, ctx, formatted)
end

function AIVELogger.pushHistory(levelStr, fullMessage)
	local timeMs = 0
	if g_currentMission ~= nil and g_currentMission.time ~= nil then
		timeMs = g_currentMission.time
	end
	table.insert(AIVELogger.history, {
		time = timeMs,
		level = levelStr,
		message = fullMessage
	})
	if #AIVELogger.history > AIVELogger.maxHistory then
		table.remove(AIVELogger.history, 1)
	end
end

function AIVELogger.error(context, msg, ...)
	if AIVELogger.currentLevel < AIVELogger.LEVEL_ERROR then return end
	AIVELogger.stats.errors = AIVELogger.stats.errors + 1
	local fullMsg = AIVELogger.formatMessage("ERROR", context, msg, ...)
	AIVELogger.pushHistory("ERROR", fullMsg)
	if Logging ~= nil and Logging.error ~= nil then
		Logging.error("%s", fullMsg)
	else
		print("Error: " .. fullMsg)
	end
end

function AIVELogger.warn(context, msg, ...)
	if AIVELogger.currentLevel < AIVELogger.LEVEL_WARN then return end
	AIVELogger.stats.warnings = AIVELogger.stats.warnings + 1
	local fullMsg = AIVELogger.formatMessage("WARN", context, msg, ...)
	AIVELogger.pushHistory("WARN", fullMsg)
	if Logging ~= nil and Logging.warning ~= nil then
		Logging.warning("%s", fullMsg)
	else
		print("Warning: " .. fullMsg)
	end
end

function AIVELogger.info(context, msg, ...)
	if AIVELogger.currentLevel < AIVELogger.LEVEL_INFO then return end
	AIVELogger.stats.infos = AIVELogger.stats.infos + 1
	local fullMsg = AIVELogger.formatMessage("INFO", context, msg, ...)
	AIVELogger.pushHistory("INFO", fullMsg)
	if Logging ~= nil and Logging.info ~= nil then
		Logging.info("%s", fullMsg)
	else
		print(fullMsg)
	end
end

function AIVELogger.debug(context, msg, ...)
	if AIVELogger.currentLevel < AIVELogger.LEVEL_DEBUG then return end
	AIVELogger.stats.debugs = AIVELogger.stats.debugs + 1
	local fullMsg = AIVELogger.formatMessage("DEBUG", context, msg, ...)
	AIVELogger.pushHistory("DEBUG", fullMsg)
	if Logging ~= nil and Logging.devInfo ~= nil then
		Logging.devInfo("%s", fullMsg)
	else
		print(fullMsg)
	end
end

function AIVELogger.errorOnce(key, context, msg, ...)
	local k = tostring(key or msg)
	local count = (AIVELogger.errorCounts[k] or 0) + 1
	AIVELogger.errorCounts[k] = count
	if count == 1 or count == 10 or count % 100 == 0 then
		local suffix = count > 1 and string.format(" (repeated %dx)", count) or ""
		AIVELogger.error(context, tostring(msg) .. suffix, ...)
	end
end

function AIVELogger.safeCall(context, fn, ...)
	if type(fn) ~= "function" then
		AIVELogger.errorOnce("nil_fn_" .. tostring(context), context, "Attempted to call a non-function value")
		return false, nil
	end
	local args = { ... }
	local ok, r1, r2, r3, r4 = xpcall(function()
		return fn(unpack(args))
	end, function(err)
		local tb = ""
		if debug ~= nil and debug.traceback ~= nil then
			tb = "\n" .. tostring(debug.traceback("", 2))
		end
		return tostring(err) .. tb
	end)
	if not ok then
		AIVELogger.stats.safeCallsCaught = AIVELogger.stats.safeCallsCaught + 1
		AIVELogger.errorOnce("safecall_" .. tostring(context), context, "Runtime exception caught: %s", tostring(r1))
		return false, nil
	end
	return true, r1, r2, r3, r4
end

function AIVELogger.safeStopAIJob(vehicle, msgClass)
	if vehicle == nil or type(vehicle.stopCurrentAIJob) ~= "function" then
		return
	end
	local msg = nil
	if type(msgClass) == "table" and type(msgClass.new) == "function" then
		local ok, m = pcall(msgClass.new)
		if ok then msg = m end
	end
	if msg == nil and AIMessageErrorUnknown ~= nil and type(AIMessageErrorUnknown.new) == "function" then
		local ok, m = pcall(AIMessageErrorUnknown.new)
		if ok then msg = m end
	end
	AIVELogger.info("DriveStrategy", "Stopping AI job on '%s'", tostring(type(vehicle.getName) == "function" and vehicle:getName() or "vehicle"))
	pcall(vehicle.stopCurrentAIJob, vehicle, msg)
end

--==============================================================================
-- 3. AIVEWheelUtils: FS25 Wheel Physics & AI Kinematics Compatibility Layer
--==============================================================================
-- In FS25:
--  1) The AI helper no longer binds to `self.maxTurningRadiusWheel` or `wheel.driveNode` parents.
--  2) Wheel properties (`rotMax`, `rotMin`, `rotSpeed`, `steeringAngle`, `positionX/Y/Z`,
--     `steeringAxleScale`, `lateralStiffness`, `hasGroundContact`, `driveNode`, `repr`)
--     are nested under `wheel.physics` (or `wheel.steering`) instead of directly on `wheel`.
--  3) `AIVEWheelUtils` unifies access and computes exact Ackermann vehicle kinematics
--     directly from wheel physics nodes, articulated axes, or AI steering nodes.
--==============================================================================
AIVEWheelUtils = {}

function AIVEWheelUtils.getWheelProp(wheel, propName, defaultVal)
	if type(wheel) ~= "table" then
		return defaultVal
	end
	if wheel[propName] ~= nil then
		return wheel[propName]
	end
	if type(wheel.physics) == "table" and wheel.physics[propName] ~= nil then
		return wheel.physics[propName]
	end
	if type(wheel.steering) == "table" and wheel.steering[propName] ~= nil then
		return wheel.steering[propName]
	end
	return defaultVal
end

function AIVEWheelUtils.getWheelNode(wheel)
	if type(wheel) ~= "table" then
		return nil
	end
	if wheel.repr ~= nil and wheel.repr ~= 0 then
		return wheel.repr
	end
	if type(wheel.physics) == "table" and wheel.physics.repr ~= nil and wheel.physics.repr ~= 0 then
		return wheel.physics.repr
	end
	if wheel.driveNode ~= nil and wheel.driveNode ~= 0 then
		return wheel.driveNode
	end
	if type(wheel.physics) == "table" and wheel.physics.driveNode ~= nil and wheel.physics.driveNode ~= 0 then
		return wheel.physics.driveNode
	end
	if wheel.node ~= nil and wheel.node ~= 0 then
		return wheel.node
	end
	return nil
end

function AIVEWheelUtils.getWheelDriveNode(wheel)
	if type(wheel) ~= "table" then
		return nil
	end
	if wheel.driveNode ~= nil and wheel.driveNode ~= 0 then
		return wheel.driveNode
	end
	if type(wheel.physics) == "table" and wheel.physics.driveNode ~= nil and wheel.physics.driveNode ~= 0 then
		return wheel.physics.driveNode
	end
	return AIVEWheelUtils.getWheelNode(wheel)
end

function AIVEWheelUtils.hasGroundContact(wheel)
	if type(wheel) ~= "table" then
		return false
	end
	if type(wheel.physics) == "table" and wheel.physics.hasGroundContact ~= nil then
		return wheel.physics.hasGroundContact
	end
	if wheel.hasGroundContact ~= nil then
		return wheel.hasGroundContact
	end
	return true
end

function AIVEWheelUtils.getLateralStiffness(wheel)
	return AIVEWheelUtils.getWheelProp(wheel, "lateralStiffness", 1)
end

function AIVEWheelUtils.getWheelRotSpeed(wheel)
	return AIVEWheelUtils.getWheelProp(wheel, "rotSpeed", 0)
end

function AIVEWheelUtils.getWheelSteeringAngle(wheel)
	return AIVEWheelUtils.getWheelProp(wheel, "steeringAngle", 0)
end

function AIVEWheelUtils.getWheelRotMax(wheel)
	return AIVEWheelUtils.getWheelProp(wheel, "rotMax", 0)
end

function AIVEWheelUtils.getWheelRotMin(wheel)
	return AIVEWheelUtils.getWheelProp(wheel, "rotMin", 0)
end

function AIVEWheelUtils.getWheelPosition(wheel, refNode)
	if type(wheel) ~= "table" then
		return 0, 0, 0
	end
	-- FS25 physics.position* is relative to the wheel's rigid component.
	-- The front axle can be another component (e.g. 6R), so those numbers
	-- cannot be compared to rear-wheel positions until transformed.
	local wNode = AIVEWheelUtils.getWheelNode(wheel)
	if wNode ~= nil and wNode ~= 0 and refNode ~= nil and refNode ~= 0 and type(localToLocal)=="function" then
		local ok, x, y, z = pcall(localToLocal, wNode, refNode, 0, 0, 0)
		if ok and x ~= nil then
			return x, y, z
		end
	end
	local px = AIVEWheelUtils.getWheelProp(wheel, "positionX", nil)
	local py = AIVEWheelUtils.getWheelProp(wheel, "positionY", nil)
	local pz = AIVEWheelUtils.getWheelProp(wheel, "positionZ", nil)
	if px ~= nil and py ~= nil and pz ~= nil then return px, py, pz end
	return 0, 0, 0
end

function AIVEWheelUtils.getWheelsList(vehicle)
	if type(vehicle) ~= "table" then
		return {}
	end
	if type(vehicle.getWheels) == "function" then
		local ok, wheels = pcall(vehicle.getWheels, vehicle)
		if ok and type(wheels) == "table" then
			return wheels
		end
	end
	if type(vehicle.spec_wheels) == "table" and type(vehicle.spec_wheels.wheels) == "table" then
		return vehicle.spec_wheels.wheels
	end
	return {}
end

function AIVEWheelUtils.getAISteeringSpeed(vehicle)
	if type(vehicle) == "table" then
		if type(vehicle.getAISteeringSpeed) == "function" then
			local ok, spd = pcall(vehicle.getAISteeringSpeed, vehicle)
			if ok and type(spd) == "number" then
				return spd
			end
		end
		if type(vehicle.spec_aiVehicle) == "table" and type(vehicle.spec_aiVehicle.aiSteeringSpeed) == "number" then
			return vehicle.spec_aiVehicle.aiSteeringSpeed
		end
		if type(vehicle.spec_aiDrivable) == "table" and type(vehicle.spec_aiDrivable.aiSteeringSpeed) == "number" then
			return vehicle.spec_aiDrivable.aiSteeringSpeed
		end
	end
	return 0.001
end

-- Computes vehicle kinematics (maxSteering, radius, wheelBase) for FS25 without
-- requiring FS22's deprecated `self.maxTurningRadiusWheel` binding.
function AIVEWheelUtils.computeVehicleKinematics(vehicle, refNode)
	local maxSteering = math.rad(30)
	local radius      = 6.0
	local wheelBase   = 3.5

	if type(vehicle) ~= "table" then
		return maxSteering, radius, wheelBase
	end

	-- 1. Check Articulated Axis first
	local specArt = vehicle.spec_articulatedAxis
	if specArt ~= nil and specArt.componentJoint ~= nil and specArt.rotMax ~= nil and math.abs(specArt.rotMax) > 1e-3 then
		maxSteering = 0.5 * math.abs(specArt.rotMax)
		if vehicle.maxTurningRadius ~= nil and vehicle.maxTurningRadius > 1 then
			radius = vehicle.maxTurningRadius
		else
			radius = 6.5
		end
		local wheels = AIVEWheelUtils.getWheelsList(vehicle)
		local minZ, maxZ = nil, nil
		for _, wheel in pairs(wheels) do
			local _, _, pz = AIVEWheelUtils.getWheelPosition(wheel, refNode)
			if minZ == nil or pz < minZ then minZ = pz end
			if maxZ == nil or pz > maxZ then maxZ = pz end
		end
		if minZ ~= nil and maxZ ~= nil and (maxZ - minZ) > 0.5 then
			wheelBase = maxZ - minZ
		else
			wheelBase = math.tan(maxSteering) * radius
		end
		return maxSteering, radius, wheelBase
	end

	-- 2. Standard / 4WS / Tracked vehicles in FS25:
	local wheels = AIVEWheelUtils.getWheelsList(vehicle)
	local bestSteeredWheel = vehicle.maxTurningRadiusWheel
	local maxRotAngle = 0
	local minZ, maxZ = nil, nil
	local steeredZSum, steeredCount = 0, 0
	local fixedZSum, fixedCount = 0, 0

	for _, wheel in pairs(wheels) do
		local rotMax = math.abs(AIVEWheelUtils.getWheelRotMax(wheel))
		local rotMin = math.abs(AIVEWheelUtils.getWheelRotMin(wheel))
		local rotSpeed = math.abs(AIVEWheelUtils.getWheelRotSpeed(wheel))
		local wheelMaxAngle = math.max(rotMax, rotMin)
		local _, _, pz = AIVEWheelUtils.getWheelPosition(wheel, refNode)

		if minZ == nil or pz < minZ then minZ = pz end
		if maxZ == nil or pz > maxZ then maxZ = pz end

		if wheelMaxAngle > 1e-3 or rotSpeed > 1e-3 then
			steeredZSum = steeredZSum + pz
			steeredCount = steeredCount + 1
			if wheelMaxAngle > maxRotAngle then
				maxRotAngle = wheelMaxAngle
				bestSteeredWheel = wheel
			end
		else
			fixedZSum = fixedZSum + pz
			fixedCount = fixedCount + 1
		end
	end

	-- Determine wheelbase from axles
	if steeredCount > 0 and fixedCount > 0 then
		local avgSteeredZ = steeredZSum / steeredCount
		local avgFixedZ   = fixedZSum / fixedCount
		local dist = math.abs(avgSteeredZ - avgFixedZ)
		if dist > 0.5 then
			wheelBase = dist
		elseif minZ ~= nil and maxZ ~= nil and (maxZ - minZ) > 0.5 then
			wheelBase = maxZ - minZ
		end
	elseif minZ ~= nil and maxZ ~= nil and (maxZ - minZ) > 0.5 then
		wheelBase = maxZ - minZ
	end

	-- If FS22-style maxTurningRadiusWheel or bestSteeredWheel is found, refine using Ackermann geometry
	if bestSteeredWheel ~= nil and maxRotAngle > 1e-3 then
		local wx, _, wz = AIVEWheelUtils.getWheelPosition(bestSteeredWheel, refNode)
		local rotMax = math.max(math.abs(AIVEWheelUtils.getWheelRotMax(bestSteeredWheel)), math.abs(AIVEWheelUtils.getWheelRotMin(bestSteeredWheel)))
		local axleScale = math.abs(AIVEWheelUtils.getWheelProp(bestSteeredWheel, "steeringAxleScale", 0))
		local zDiff = wheelBase
		if fixedCount > 0 then
			zDiff = math.abs(wz - (fixedZSum / fixedCount))
		elseif minZ ~= nil and maxZ ~= nil then
			zDiff = maxZ - minZ
		end
		if zDiff > 0.5 then
			wheelBase = zDiff * (1 + axleScale)
		end
		local xDiff = math.max(0, math.abs(wx) - 0.1)
		local rCalc = zDiff / math.tan(rotMax) + xDiff
		if vehicle.maxTurningRadius ~= nil and vehicle.maxTurningRadius > 1 then
			radius = math.max(rCalc, vehicle.maxTurningRadius)
		else
			radius = math.max(2.5, rCalc)
		end
		maxSteering = math.atan2(wheelBase, radius)
	else
		-- Tracked/crawler or vehicle where wheel rotMax is managed by FS25 AIDrivable
		if vehicle.maxTurningRadius ~= nil and vehicle.maxTurningRadius > 1 then
			radius = vehicle.maxTurningRadius
		end
		maxSteering = math.atan2(wheelBase, math.max(radius, 1.0))
	end

	maxSteering = math.min(math.max(maxSteering, math.rad(10)), math.rad(75))
	radius      = math.max(radius, 2.0)
	wheelBase   = math.max(wheelBase, 1.2)

	AIVELogger.debug("WheelUtils", "Computed FS25 kinematics for '%s': wheelBase=%.2fm, radius=%.2fm, maxSteering=%.1f deg",
		tostring(vehicle.configFileName or (type(vehicle.getName) == "function" and vehicle:getName() or "vehicle")), wheelBase, radius, math.deg(maxSteering))

	return maxSteering, radius, wheelBase
end

function AIVEWheelUtils.getCurrentSteeringAngle(vehicle)
	if type(vehicle) ~= "table" then
		return 0
	end

	local specArt = vehicle.spec_articulatedAxis
	if specArt ~= nil and specArt.componentJoint ~= nil and specArt.rotMax ~= nil and math.abs(specArt.rotMax) > 1e-3 then
		local rt = vehicle.rotatedTime or 0
		return 0.5 * math.min(math.max(-rt * specArt.rotMax, specArt.rotMin or -specArt.rotMax), specArt.rotMax)
	end

	local steeringAngle = 0
	local wheels = AIVEWheelUtils.getWheelsList(vehicle)
	for _, wheel in pairs(wheels) do
		local rotSpeed = AIVEWheelUtils.getWheelRotSpeed(wheel)
		local wAngle   = AIVEWheelUtils.getWheelSteeringAngle(wheel)
		if math.abs(rotSpeed) > 1e-3 then
			if math.abs(wAngle) > math.abs(steeringAngle) then
				if rotSpeed > 0 then
					steeringAngle = wAngle
				else
					steeringAngle = -wAngle
				end
			end
		end
	end

	-- Fallback for FS25 when wheel.steeringAngle is not directly exposed or vehicle uses rotatedTime
	if math.abs(steeringAngle) < 1e-4 and vehicle.rotatedTime ~= nil and math.abs(vehicle.rotatedTime) > 1e-4 then
		local maxSteer = (vehicle.aiveChain and vehicle.aiveChain.maxSteering) or (vehicle.acDimensions and vehicle.acDimensions.maxSteering) or math.rad(30)
		if vehicle.rotatedTime > 0 and vehicle.maxRotTime ~= nil and vehicle.maxRotTime > 1e-4 then
			steeringAngle = (vehicle.rotatedTime / vehicle.maxRotTime) * maxSteer
		elseif vehicle.rotatedTime < 0 and vehicle.minRotTime ~= nil and vehicle.minRotTime < -1e-4 then
			steeringAngle = -(vehicle.rotatedTime / vehicle.minRotTime) * maxSteer
		end
	end

	return steeringAngle
end

function AIVEWheelUtils.updateWheelsPhysics(vehicle, dt, currentSpeed, acceleration, doHandbrake, requiredDriveMode)
	if vehicle == nil or WheelsUtil == nil or WheelsUtil.updateWheelsPhysics == nil then
		return
	end
	local driveMode = requiredDriveMode
	if driveMode == nil then
		if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil and g_currentMission.missionInfo.stopAndGoBraking ~= nil then
			driveMode = g_currentMission.missionInfo.stopAndGoBraking
		else
			driveMode = true
		end
	end
	local ok, err = pcall(WheelsUtil.updateWheelsPhysics, vehicle, dt, currentSpeed, acceleration, doHandbrake, driveMode)
	if not ok then
		AIVELogger.errorOnce("updateWheelsPhysics", "WheelUtils", "WheelsUtil.updateWheelsPhysics failed: %s", tostring(err))
	end
end

function AIVEWheelUtils.setMotorSpeedLimit(vehicle, maxSpeed)
	if type(vehicle) ~= "table" then return end
	local motor = vehicle.motor
	if motor == nil and vehicle.spec_motorized ~= nil then
		motor = vehicle.spec_motorized.motor
	end
	if motor == nil and type(vehicle.getMotor) == "function" then
		local ok, m = pcall(vehicle.getMotor, vehicle)
		if ok then motor = m end
	end
	if motor ~= nil and type(motor.setSpeedLimit) == "function" then
		pcall(motor.setSpeedLimit, motor, maxSpeed)
	end
end

--==============================================================================
-- 4. Mod Conflict Detector (Courseplay, AutoDrive, Basegame FS25 Steering Assist)
--==============================================================================
AIVEConflictGuard = {}

function AIVEConflictGuard.isExternalAIActive(vehicle)
	if type(vehicle) ~= "table" then
		return false, nil
	end
	-- 1. Courseplay check
	if type(vehicle.getIsCpActive) == "function" then
		local ok, active = pcall(vehicle.getIsCpActive, vehicle)
		if ok and active then
			return true, "Courseplay"
		end
	end
	if vehicle.spec_cpMod ~= nil and vehicle.spec_cpMod.isActive then
		return true, "Courseplay"
	end
	-- 2. AutoDrive check
	if vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil and type(vehicle.ad.stateModule.isActive) == "function" then
		local ok, active = pcall(vehicle.ad.stateModule.isActive, vehicle.ad.stateModule)
		if ok and active then
			return true, "AutoDrive"
		end
	end
	-- 3. FS25 Basegame Steering Assist (GPS) check when manual AIVE auto-steer is requested
	if vehicle.spec_aiAutomaticSteering ~= nil and type(vehicle.getIsAIAutomaticSteeringEnabled) == "function" then
		local ok, active = pcall(vehicle.getIsAIAutomaticSteeringEnabled, vehicle)
		if ok and active then
			return true, "FS25_AutomaticSteering"
		end
	end
	return false, nil
end

--==============================================================================
-- 5. Console Commands Registration for FS25 Debugging
--==============================================================================
function AIVELogger:consoleCommandSetLogLevel(levelStr)
	local lvl = tonumber(levelStr)
	if lvl == nil or lvl < 0 or lvl > 5 then
		return string.format("Usage: aiveLogLevel [0..5] (0=OFF, 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG, 5=TRACE). Current=%d", AIVELogger.currentLevel)
	end
	AIVELogger.currentLevel = lvl
	return string.format("[%s] Log level set to %d", AIVELogger.MOD_NAME, lvl)
end

function AIVELogger:consoleCommandStatus()
	local msg = string.format("[%s v%s] Errors=%d, Warnings=%d, Infos=%d, CaughtExceptions=%d",
		AIVELogger.MOD_NAME, AIVELogger.VERSION,
		AIVELogger.stats.errors, AIVELogger.stats.warnings, AIVELogger.stats.infos, AIVELogger.stats.safeCallsCaught)
	print(msg)
	local controlledVeh = nil
	if g_currentMission ~= nil then
		controlledVeh = g_currentMission.controlledVehicle
		if controlledVeh == nil and g_localPlayer ~= nil and type(g_localPlayer.getCurrentVehicle) == "function" then
			local ok, v = pcall(g_localPlayer.getCurrentVehicle, g_localPlayer)
			if ok then controlledVeh = v end
		end
	end
	if controlledVeh ~= nil and controlledVeh.acParameters ~= nil then
		local maxS, rad, wb = AIVEWheelUtils.computeVehicleKinematics(controlledVeh, controlledVeh.aiveRefNode or (controlledVeh.components and controlledVeh.components[1] and controlledVeh.components[1].node))
		local extActive, extMod = AIVEConflictGuard.isExternalAIActive(controlledVeh)
		local vInfo = string.format("Controlled Vehicle: %s | AIVE Enabled=%s | AutoSteer=%s | AIStarted=%s | WheelBase=%.2fm | TurnRadius=%.2fm | MaxSteer=%.1f deg | ExternalAI=%s",
			tostring(controlledVeh:getName()),
			tostring(controlledVeh.acParameters.enabled),
			tostring(controlledVeh.aiveAutoSteer),
			tostring(controlledVeh.aiveIsStarted),
			wb, rad, math.deg(maxS),
			tostring(extActive and extMod or "none"))
		print(vInfo)
		return msg .. " | " .. vInfo
	end
	return msg .. " | No controlled AIVE vehicle active."
end

function AIVELogger:consoleCommandSettings()
	local vehicle = g_currentMission ~= nil and g_currentMission.controlledVehicle or nil
	if vehicle == nil and g_localPlayer ~= nil and type(g_localPlayer.getCurrentVehicle) == "function" then
		vehicle = g_localPlayer:getCurrentVehicle()
	end
	if vehicle == nil or vehicle.acParameters == nil then
		return "Enter an AIVE vehicle first."
	end
	AIVehicleExtension.onAIVEScreen(vehicle)
	return "AIVE settings panel opened."
end

function AIVELogger:consoleCommandSelfTest()
	AIVELogger.info("SelfTest", "Starting FS25_AIVehicleExtension diagnostic self-test...")
	local checks = 0
	local passed = 0

	local function check(name, cond, detail)
		checks = checks + 1
		if cond then
			passed = passed + 1
			AIVELogger.info("SelfTest", "[PASS] %s (%s)", name, tostring(detail or "OK"))
		else
			AIVELogger.error("SelfTest", "[FAIL] %s (%s)", name, tostring(detail or "Failed"))
		end
	end

	check("Polyfill table.getn", type(table.getn) == "function" and table.getn({1, 2, 3}) == 3, "table.getn({1,2,3}) == 3")
	check("Polyfill unpack", type(unpack) == "function", "unpack available")
	check("AITurnStrategy Base Class", type(AITurnStrategy) == "table", "Loaded")
	check("AIVehicleExtension Global", type(AIVehicleExtension) == "table", "Loaded")
	check("AIVEHud Global", type(AIVEHud) == "table", "Loaded")
	check("AutoSteeringEngine Global", type(AutoSteeringEngine) == "table", "Loaded")
	check("FieldBitmap Global", type(FieldBitmap) == "table", "Loaded")
	check("AIDriveStrategyMogli Global", type(AIDriveStrategyMogli) == "table", "Loaded")
	check("AITurnStrategyMogli Global", type(AITurnStrategyMogli) == "table", "Loaded")
	check("AITurnStrategyMogliDefault Global", type(AITurnStrategyMogliDefault) == "table", "Loaded")
	check("Incremental field scanner", type(FieldBitmap) == "table"
		and type(FieldBitmap.beginForFieldAtWorldPosition) == "function", "No coroutine required")
	for _, name in ipairs({"AIDriveStrategyMogli", "AIDriveStrategyCombine131", "AIDriveStrategyCollisionOtherAI"}) do
		local class = _G[name]
		local ok, instance = false, nil
		if type(class) == "table" and type(class.new) == "function" then
			ok, instance = pcall(class.new)
		end
		check(name .. " FS25 constructor", ok and type(instance) == "table"
			and instance.getDriveData == class.getDriveData
			and instance.setAIVehicle == class.setAIVehicle, "Custom methods preserved")
	end

	return string.format("[%s] Self-test complete: %d/%d checks passed.", AIVELogger.MOD_NAME, passed, checks)
end


AIVELogger.info("Bootstrap", "AIVELogger & AIVEWheelUtils v%s initialized for Farming Simulator 25.", AIVELogger.VERSION)
