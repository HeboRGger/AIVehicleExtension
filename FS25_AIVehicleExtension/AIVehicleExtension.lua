--
-- AIVehicleExtension
-- Extended AIFieldWorker
--
-- @author	mogli aka biedens

 
AIVehicleExtension = {}
local AtDirectory = g_currentModDirectory

------------------------------------------------------------------------
-- INCLUDES
------------------------------------------------------------------------
source(Utils.getFilename("mogliBase.lua", g_currentModDirectory))
_G[g_currentModName..".mogliBase"].newClass( "AIVehicleExtension", "acParameters" )
------------------------------------------------------------------------
source(Utils.getFilename("mogliHud.lua", g_currentModDirectory))
_G[g_currentModName..".mogliHud"].newClass( "AIVEHud", "atHud" )
------------------------------------------------------------------------
source(Utils.getFilename("AIVEEvents.lua", g_currentModDirectory))
------------------------------------------------------------------------
source(Utils.getFilename("FieldBitmap.lua", g_currentModDirectory))
--source(Utils.getFilename("FieldScanner.lua", g_currentModDirectory))
source(Utils.getFilename("AIAnimCurve.lua", g_currentModDirectory))
source(Utils.getFilename("AutoSteeringEngine.lua", g_currentModDirectory))
source(Utils.getFilename("AIVELands.lua", g_currentModDirectory))
source(Utils.getFilename("AIVEFieldDispatcher.lua", g_currentModDirectory))
source(Utils.getFilename("AIVEObstacles.lua", g_currentModDirectory))
source(Utils.getFilename("AIDriveStrategyMogli.lua", g_currentModDirectory))
source(Utils.getFilename("AIDriveStrategyCombine131.lua", g_currentModDirectory))
source(Utils.getFilename("AIDriveStrategyCollisionOtherAI.lua", g_currentModDirectory))
------------------------------------------------------------------------

------------------------------------------------------------------------
-- statEvent
------------------------------------------------------------------------
AIVehicleExtension.acDevFeatures = (AIVEGlobals.devFeatures > 0)
function AIVehicleExtension:statEvent( name, dt )
	if AIVEGlobals.showStat > 0 then
		if self.acStat == nil then self.acStat = {} end
		if self.acStat[name] == nil then self.acStat[name] = { t=0, n=0 } end
		self.acStat[name].t = self.acStat[name].t + dt
		self.acStat[name].n = self.acStat[name].n + 1
	end
end
------------------------------------------------------------------------
-- debugPrint
------------------------------------------------------------------------
function AIVehicleExtension:debugPrint( ... )
	if AIVELogger ~= nil and AIVELogger.currentLevel >= AIVELogger.LEVEL_DEBUG then
		AIVELogger.debug(type(self) == "table" and type(self.getName) == "function" and self:getName() or "Vehicle", ...)
	elseif AIVEGlobals.devFeatures > 0
			and ( type( self ) ~= "table"
				 or type( self.getIsEntered ) ~= "function"
				 or self:getIsEntered() ) then
		print( ... )
	end
	if type(self) == "table" and AIVEGlobals.showInfo > 0 and self.atMogliInitDone and self.atHud ~= nil then
		self.atHud.InfoText = tostring( ... )
	end
end

function AIVehicleExtension:aiveAddDebugText( s )
	AIVehicleExtension.debugPrint( self, s )
end

AIVehicleExtension.saveAttributesMapping = { 
			{ name="enabled"        , xml = "acDefaultOn",	  valueType = XMLValueType.BOOL , default = true  },
			{ name="upNDown"				, xml = "acUTurn",			  valueType = XMLValueType.BOOL , default = true },
			{ name="straight"       , xml = "acStraight",		  valueType = XMLValueType.BOOL , default = true },
			{ name="rightAreaActive", xml = "acAreaRight",	  valueType = XMLValueType.BOOL , default = false },
			{ name="headland"				, xml = "acHeadland",		  valueType = XMLValueType.BOOL , default = false },
			{ name="collision"			, xml = "acCollision",	  valueType = XMLValueType.BOOL , default = true },
			{ name="inverted"				, xml = "acInverted",		  valueType = XMLValueType.BOOL , default = false },
			{ name="isHired"				, xml = "acIsHired",		  valueType = XMLValueType.BOOL , default = false },
			{ name="bigHeadland"		, xml = "acBigHeadland",  valueType = XMLValueType.BOOL , default = true  },
			{ name="turnModeIndex"	, xml = "acTurnMode",		  valueType = XMLValueType.INT  , default = 1 }, 
			{ name="turnModeIndexC"	, xml = "acTurnModeC",	  valueType = XMLValueType.INT  , default = 1 }, 
			{ name="widthOffset"		, xml = "acWidthOffset",  valueType = XMLValueType.FLOAT, default = 0 }, 
			{ name="turnOffset"			, xml = "acTurnOffset",	  valueType = XMLValueType.FLOAT, default = 0 }, 
			{ name="angleFactor"		, xml = "acAngleFactorN", valueType = XMLValueType.FLOAT, default = 0.5 },
			{ name="precision"		  , xml = "acPrecision",    valueType = XMLValueType.INT  , default = 1 }, 
			{ name="noSteering"			, xml = "acNoSteering",	  valueType = XMLValueType.BOOL , default = false },
			{ name="useAIFieldFct"	, xml = "acUseAIField",	  valueType = XMLValueType.BOOL , default = false },
			{ name="waitForPipe"		, xml = "acWaitForPipe",  valueType = XMLValueType.BOOL , default = true  },
			{ name="turnLow"			  , xml = "acTurnLow",      valueType = XMLValueType.BOOL , default = false },
			{ name="showTrace" 			, xml = "acShowTrace",    valueType = XMLValueType.BOOL , default = true },
			{ name="maxCircles" 		, xml = "acMaxCircles",		valueType = XMLValueType.INT  , default = 0 }, 
			{ name="noSprayer" 			, xml = "acNoSprayer",		valueType = XMLValueType.BOOL , default = false }, 
			{ name="circlesDone" 		, xml = "acCirclesDone",	valueType = XMLValueType.FLOAT, default = -1 }, 
			{ name="startAngle"			, xml = "acStartAngle", 	valueType = XMLValueType.FLOAT, default = -4 },
			{ name="fieldCenterX"		, xml = "acFieldCenterX", valueType = XMLValueType.FLOAT, default = 0 },
			{ name="fieldCenterZ"		, xml = "acFieldCenterZ", valueType = XMLValueType.FLOAT, default = 0 },
			{ name="circleLands", xml="acCircleLands", valueType=XMLValueType.BOOL, default=false },
			{ name="fieldGroup", xml="acFieldGroup", valueType=XMLValueType.BOOL, default=false },
		}																														
AIVehicleExtension.turnStageNoNext = { -4, -3, -2, -1, 0, 21, 22, 23, 198, 199 } --{ 0 }
AIVehicleExtension.turnStageEnd	= { 
	--{ 4, -1 },
		{ 14, -1 },
	--{ 23, 25 },
		{ 25, 27 },
		{ 27, -2 },
		{ 28, -2 },
		{ 29, -2 },
		{ 33, 36 },
		{ 34, 36 },
		{ 36, 38 },
		{ 38, -1 },
		{ 41, 43 },
		{ 43, 45 },
		{ 45, 49 },
		{ 46, 49 },
		{ 47, 49 },
		{ 49, -2 },
		{ 53, 56 },
		{ 54, 56 },
		{ 59, -2 },
		{ 60, -2 },
		{ 75, 79 },
		{ 76, 79 },
		{ 77, 79 },
		{ 78, 79 },
		{ 79, -2 },
		{ 83, 85 },
		{ 86, -2 },
		{ 89, -1 },
		{ 99, -1 },
		{103, -1 },
		{108, -1 },
		{114, -2 },
		{119, -2 },
		{124, -1 }}

------------------------------------------------------------------------
-- prerequisitesPresent
------------------------------------------------------------------------
function AIVehicleExtension.prerequisitesPresent(specializations)
	return true
end

function AIVehicleExtension.registerEventListeners(vehicleType)
	for _,n in pairs( { "onLoad", 
											"onPostLoad", 
											"onPreUpdate", 
											"onUpdate", 
											"onDraw",
											"onLeaveVehicle",
											"onEnterVehicle",
											"onReadStream", 
											"onWriteStream", 
											"onReadUpdateStream",
											"onWriteUpdateStream", 
											"saveToXMLFile", 
											"onRegisterActionEvents",
											"onStateChange",
											"onPreDelete",
											"onAIFieldWorkerStart",
											"onAIFieldWorkerEnd",
											"onAIFieldWorkerTurnProgress"} ) do
		SpecializationUtil.registerEventListener(vehicleType, n, AIVehicleExtension)
	end 
end 


function AIVehicleExtension.registerOverwrittenFunctions(vehicleType)
	SpecializationUtil.registerOverwrittenFunction(vehicleType, "getStartableAIJob", AIVehicleExtension.getStartableAIJob)
end

function AIVehicleExtension.initSpecialization()
	local schemaSavegame = Vehicle.xmlSchemaSavegame
	if schemaSavegame then 
		for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
			schemaSavegame:register( attr.valueType, "vehicles.vehicle(?)." .. AIVehicleExtensionRegister.specName .. "#".. attr.xml, "AIVehicleExtension: ".. attr.xml)
		end
		schemaSavegame:register(XMLValueType.STRING,"vehicles.vehicle(?)."..AIVehicleExtensionRegister.specName.."#groupWorkKey","AIVE field group operation")
		schemaSavegame:register(XMLValueType.FLOAT,"vehicles.vehicle(?)."..AIVehicleExtensionRegister.specName.."#groupWorkArea","AIVE initial work area")
	end		
end 

------------------------------------------------------------------------
-- load
------------------------------------------------------------------------
function AIVehicleExtension:onLoad(saveGame)

	-- for courseplay	
	self.acIsCPStopped				= false
	self.acTurnStage					= 0
	self.acPause							= false	
	self.acParameters				  = AIVehicleExtension.getParameterDefaults( )
	self.acAxisSide					  = 0
	self.acIsLowered          = 0
	self.acTurnMode           = ""
	self.acDebugPrint			  	= AIVehicleExtension.debugPrint
	self.aiveAddDebugText     = AIVehicleExtension.aiveAddDebugText
	self.waitForTurnTime      = 0
	self.turnTimer            = 0
	self.aiRescueTimer        = 0
	
	self.acDeltaTimeoutWait	  = 1600
	self.acDeltaTimeoutRun		= 80
	self.acDeltaTimeoutStop	  = 30000
	self.acDeltaTimeoutStart	= 6000
	self.acDeltaTimeoutNoTurn = 2 * self.acDeltaTimeoutWait --math.max(AIVEUtils.getNoNil( self.waitForTurnTimeout , 2000 ), 1000 )
	self.acRecalculateDt			= 0
	self.acWaitTimer					= 0
	self.acTurnOutsideTimer   = 0
	self.acImplMoveDownTimer  = 0
	self.aiveCanStartArtAxis  = false
	
	self.acAutoRotateBackSpeedBackup = self.autoRotateBackSpeed	
	
	local tempNode
	if type(self.getAISteeringNode) == "function" then 
		tempNode = self:getAISteeringNode()
	end 
	if tempNode == nil then
		tempNode = self.components[1].node
	end
	
	self.acRefNode = createTransformGroup( "acNewRefNode" )
	link( tempNode, self.acRefNode )

	self.acOtherCombineCollisionTriggerL = 0
	self.acOtherCombineCollisionTriggerR = 0
	self.onOtherAICollisionTrigger = AIVehicleExtension.onOtherAICollisionTrigger
	
	AIVehicleExtension.addCollisionTriggers( self )
	
	self.acChopperWithCourseplay = false
	if self.getCanStartAIVehicle == nil then
		self.getCanStartAIVehicle = function(v)
			if type(v.getCanStartFieldWork) == "function" then
				return v:getCanStartFieldWork()
			end
			return true
		end
	end
	if self.getIsFieldWorkActive == nil then
		self.getIsFieldWorkActive = function(v)
			if v.spec_aiFieldWorker ~= nil and v.spec_aiFieldWorker.isActive ~= nil then
				return v.spec_aiFieldWorker.isActive
			end
			if type(v.getIsAIActive) == "function" then
				return v:getIsAIActive()
			end
			return false
		end
	end 
end

------------------------------------------------------------------------
-- printCallstack
------------------------------------------------------------------------
function AIVehicleExtension.printCallstack()
	AIVEHud.printCallstack()
end

------------------------------------------------------------------------
-- initMogliHud
------------------------------------------------------------------------
function AIVehicleExtension:onWidthDec()
	if self.acParameters ~= nil then
		self.acParameters.widthOffset = math.max(-2.0, (self.acParameters.widthOffset or 0) - 0.125)
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:onWidthInc()
	if self.acParameters ~= nil then
		self.acParameters.widthOffset = math.min(2.0, (self.acParameters.widthOffset or 0) + 0.125)
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:getWidthOffsetText(old)
	local w = (self.acParameters ~= nil and self.acParameters.widthOffset ~= nil) and self.acParameters.widthOffset or 0
	return string.format("%s: %+0.3fm", tostring(old or AIVEHud.getText("AIVE_WIDTH_OFFSET")), w)
end

function AIVehicleExtension:onTurnOffsetDec()
	if self.acParameters ~= nil then
		self.acParameters.turnOffset = math.max(-10.0, (self.acParameters.turnOffset or 0) - 0.25)
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:onTurnOffsetInc()
	if self.acParameters ~= nil then
		self.acParameters.turnOffset = math.min(10.0, (self.acParameters.turnOffset or 0) + 0.25)
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:onToggleInverted()
	if self.acParameters ~= nil then
		self.acParameters.inverted = not self.acParameters.inverted
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:evalInverted()
	return self.acParameters ~= nil and self.acParameters.inverted or false
end

function AIVehicleExtension:onToggleWaitForPipe()
	if self.acParameters ~= nil then
		self.acParameters.waitForPipe = not self.acParameters.waitForPipe
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:evalWaitForPipe()
	return self.acParameters == nil or self.acParameters.waitForPipe
end

function AIVehicleExtension:onToggleCollision()
	if self.acParameters ~= nil then
		self.acParameters.collision = not self.acParameters.collision
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:evalCollision()
	return self.acParameters == nil or self.acParameters.collision
end

function AIVehicleExtension:onCyclePrecisionAndMagic()
	if self.acParameters ~= nil then
		self.acParameters.precision = ((self.acParameters.precision or 1) + 1) % 3
		AIVehicleExtension.sendParameters(self)
	end
end

function AIVehicleExtension:getPrecisionText(old)
	local p = (self.acParameters ~= nil and self.acParameters.precision ~= nil) and self.acParameters.precision or 1
	local pKey = "AIVE_PRECISION_" .. tostring(math.min(math.max(p, 0), 2))
	return string.format("%s: %s", AIVEHud.getText("AIVE_PRECISION"), AIVEHud.getText(pKey))
end

function AIVehicleExtension:initMogliHud()
	if self.atMogliInitDone then
		return
	end

	local mogliRows = 2
	local mogliCols = 8
	AIVEHud.init( self, AtDirectory, "AIVEHud", 0.85, "AIVE_TEXTHELPPANELON", "AIVE_TEXTHELPPANELOFF", "AIVE_HELPPANEL", 0.5-0.015*mogliCols, 0.0108, mogliCols, mogliRows, AIVehicleExtension.sendParameters, nil, nil, nil, nil, mogliCols, 1 )
	AIVEHud.setTitle( self, "AIVE_VERSION" )

	-- Row 1: Primary AI Controls
	local workerButton=AIVEHud.addButton(self, "dds/hire_on.dds", "dds/hire_off.dds", AIVehicleExtension.onToggleWorker, nil, 1,1, "AIVE_WORKER_START", "AIVE_WORKER_STOP", AIVehicleExtension.getWorkerText, AIVehicleExtension.getWorkerImage)
	if workerButton~=nil then workerButton.dynamicTooltip=true end
	AIVEHud.addButton(self, "dds/active_right.dds",   "dds/active_left.dds",   AIVehicleExtension.setAreaLeft,   AIVehicleExtension.evalAreaLeft,   2,1, "AIVE_ACTIVESIDERIGHT", "AIVE_ACTIVESIDELEFT" )
	AIVEHud.addButton(self, nil,                      nil,                     AIVehicleExtension.setUTurn,      nil,                               3,1, "AIVE_SETTINGS", "AIVE_SETTINGS", AIVehicleExtension.getUTurnText, AIVehicleExtension.getUTurnImage )
	AIVEHud.addButton(self, nil,                      nil,                     AIVehicleExtension.setHeadland,   nil,                               4,1, "AIVE_SETTINGS", "AIVE_SETTINGS", AIVehicleExtension.getHeadlandText, AIVehicleExtension.getHeadlandImage )
	AIVEHud.addButton(self, nil,                      nil,                     AIVehicleExtension.setTurnMode,   nil,                               5,1, "AIVE_SETTINGS", "AIVE_SETTINGS", AIVehicleExtension.getTurnModeText, AIVehicleExtension.getTurnModeImage )
	AIVEHud.addButton(self, nil,                      nil,                     AIVehicleExtension.onSteerPause,  nil,                               6,1, "AIVE_SETTINGS", "AIVE_SETTINGS", AIVehicleExtension.getSteerPauseText, AIVehicleExtension.getSteerPauseImage )
	AIVEHud.addButton(self, nil,                      nil,                     AIVehicleExtension.onRaiseNext,   nil,                               7,1, "AIVE_SETTINGS", "AIVE_SETTINGS", AIVehicleExtension.getRaiseNextText, AIVehicleExtension.getRaiseNextImage )
	AIVEHud.addButton(self, "dds/setings.dds",        nil,                     AIVehicleExtension.onAIVEScreen,  nil,                               8,1, "AIVE_SETTINGS", "AIVE_SETTINGS" )

	-- Row 2: FS25 Extended Settings Row (Width Offset -/+, Turn Offset -/+, Reverse Cab, Wait For Pipe, Collision, Precision & Field Scan)
	AIVEHud.addButton(self, "dds/smaller.dds",        nil,                     AIVehicleExtension.onWidthDec,             nil,                                   1,2, "AIVE_WIDTH_OFFSET", "AIVE_WIDTH_OFFSET", AIVehicleExtension.getWidthOffsetText )
	AIVEHud.addButton(self, "dds/bigger.dds",         nil,                     AIVehicleExtension.onWidthInc,             nil,                                   2,2, "AIVE_WIDTH_OFFSET", "AIVE_WIDTH_OFFSET", AIVehicleExtension.getWidthOffsetText )
	AIVEHud.addButton(self, "dds/backward.dds",       nil,                     AIVehicleExtension.onTurnOffsetDec,        nil,                                   3,2, "AIVE_TURN_OFFSET",  "AIVE_TURN_OFFSET",  AIVehicleExtension.getTurnOffset )
	AIVEHud.addButton(self, "dds/forward.dds",        nil,                     AIVehicleExtension.onTurnOffsetInc,        nil,                                   4,2, "AIVE_TURN_OFFSET",  "AIVE_TURN_OFFSET",  AIVehicleExtension.getTurnOffset )
	AIVEHud.addButton(self, "dds/inverted.dds",       "dds/notInverted.dds",   AIVehicleExtension.onToggleInverted,       AIVehicleExtension.evalInverted,       5,2, "AIVE_INVERTED_ON",  "AIVE_INVERTED_OFF" )
	AIVEHud.addButton(self, "dds/wait.dds",           "dds/no_wait.dds",       AIVehicleExtension.onToggleWaitForPipe,    AIVehicleExtension.evalWaitForPipe,    6,2, "AIVE_WAIT_FOR_PIPE","AIVE_WAIT_FOR_PIPE" )
	AIVEHud.addButton(self, "dds/collision_on.dds",   "dds/collision_off.dds", AIVehicleExtension.onToggleCollision,      AIVehicleExtension.evalCollision,      7,2, "AIVE_COLLISION_ON", "AIVE_COLLISION_OFF" )
	AIVEHud.addButton(self, "dds/magic.dds",          nil,                     AIVehicleExtension.onCyclePrecisionAndMagic, nil,                                 8,2, "AIVE_PRECISION",    "AIVE_PRECISION",    AIVehicleExtension.getPrecisionText )

	if type( self.atHud ) == "table" then
		self.atMogliInitDone = true
	else
		print("ERROR: Initialization of AIVehicleExtension HUD failed")
	end
end

------------------------------------------------------------------------
-- draw
------------------------------------------------------------------------
function AIVehicleExtension:onDraw()
	if self.atMogliInitDone then
		local alwaysDrawTitle = false
		if self.aiveIsStarted or self.aiveAutoSteer then
			alwaysDrawTitle = true
		end
		if g_AIVEScreen == nil or not g_AIVEScreen.isOpen then
			AIVEHud.draw(self,true,alwaysDrawTitle)
		end
	end	
	if self.isClient and self:getIsEntered() and self.acParameters ~= nil
			and self.acParameters.showTrace and (self.aiveIsStarted or self.aiveAutoSteer) then
		AutoSteeringEngine.drawFieldEdge(self)
	end
end

------------------------------------------------------------------------
-- onLeaveVehicle
------------------------------------------------------------------------
function AIVehicleExtension:onLeaveVehicle()
	if g_AIVEScreen ~= nil and g_AIVEScreen.vehicle == self then
		g_AIVEScreen:onClose()
	end
	if self.atMogliInitDone then
		AIVEHud.onLeave(self)
	end
end

------------------------------------------------------------------------
-- onEnterVehicle
------------------------------------------------------------------------
function AIVehicleExtension:onEnterVehicle()
	if self.atMogliInitDone then
		AIVEHud.onEnter(self)
	end
end

------------------------------------------------------------------------
-- addCollisionTriggers
------------------------------------------------------------------------
function AIVehicleExtension:addCollisionTriggers()
	if not ( self.isServer ) then
		return
	end
	if self.acI3D == nil then
		AIVehicleExtension.debugPrint( self, "loading collision I3D..." )
		AIVehicleExtension.removeCollisionTriggers( self )
		if g_i3DManager ~= nil and type(g_i3DManager.loadSharedI3DFile) == "function" then
			local ok, i3d = pcall(g_i3DManager.loadSharedI3DFile, g_i3DManager, Utils.getFilename("AutoCombine.i3d", AtDirectory))
			if ok and i3d ~= nil and i3d ~= 0 then
				self.acI3D = getChild(i3d,"AutoCombine")
				if self.acI3D ~= nil and self.acI3D ~= 0 then
					self.acOtherCombineCollisionTriggerL = getChild(self.acI3D,"otherCombColliTriggerL")
					self.acOtherCombineCollisionTriggerR = getChild(self.acI3D,"otherCombColliTriggerR")
					link(self.acRefNode,self.acI3D)
					AIVehicleExtension.disableCollisionTriggers( self, true )
				end
			end
		end
	end
	if self.acCollidingVehicles == nil then
		self.acCollidingVehicles = {}
		if self.acOtherCombineCollisionTriggerR ~= nil and self.acOtherCombineCollisionTriggerR ~= 0 then
			AIVehicleExtension.debugPrint( self, "adding right trigger..." )
			local triggerID = self.acOtherCombineCollisionTriggerR
			self.acCollidingVehicles[triggerID] = {}
			addTrigger( triggerID, "onOtherAICollisionTrigger", self )
		end
		if self.acOtherCombineCollisionTriggerL ~= nil and self.acOtherCombineCollisionTriggerL ~= 0 then
			AIVehicleExtension.debugPrint( self, "adding left trigger..." )
			local triggerID = self.acOtherCombineCollisionTriggerL
			self.acCollidingVehicles[triggerID] = {}
			addTrigger( triggerID, "onOtherAICollisionTrigger", self )
		end
	end
end

------------------------------------------------------------------------
-- removeCollisionTriggers
------------------------------------------------------------------------
function AIVehicleExtension:removeCollisionTriggers()
	if self.acOtherCombineCollisionTriggerL ~= nil and self.acOtherCombineCollisionTriggerL ~= 0 then
		AIVehicleExtension.debugPrint( self, "removing left trigger..." )
		removeTrigger( self.acOtherCombineCollisionTriggerL )
	end
	if self.acOtherCombineCollisionTriggerR ~= nil and self.acOtherCombineCollisionTriggerR ~= 0 then
		AIVehicleExtension.debugPrint( self, "removing right trigger..." )
		removeTrigger( self.acOtherCombineCollisionTriggerR )
	end
	if self.acI3D ~= nil then
		AIVehicleExtension.debugPrint( self, "deleting collision I3D..." )
		AutoSteeringEngine.deleteNode( self.acI3D )
	end
	self.acI3D = nil
	self.acOtherCombineCollisionTriggerL = 0
	self.acOtherCombineCollisionTriggerR = 0
	self.acCollidingVehicles = nil
end

------------------------------------------------------------------------
-- enableCollisionTriggers
------------------------------------------------------------------------
function AIVehicleExtension:enableCollisionTriggers()
	if self.acI3D ~= nil and not ( self.aiveCollisionTriggersEnabled ) then 
		setTranslation( self.acI3D, 0, 0, 0 )
		self.aiveCollisionTriggersEnabled = true 
	end 
end 

------------------------------------------------------------------------
-- disableCollisionTriggers
------------------------------------------------------------------------
function AIVehicleExtension:disableCollisionTriggers( noUnlink )
	if self.acI3D ~= nil and ( noUnlink or self.aiveCollisionTriggersEnabled == nil or self.aiveCollisionTriggersEnabled ) then 
		setTranslation( self.acI3D, 1000000, 1000000, 1000000 )
		self.aiveCollisionTriggersEnabled = false 
	end 
end 

------------------------------------------------------------------------
-- delete
------------------------------------------------------------------------
function AIVehicleExtension:onPreDelete()
	if g_AIVEScreen ~= nil and g_AIVEScreen.vehicle == self then g_AIVEScreen:onClose() end
	AIVehicleExtension.removeCollisionTriggers( self )
	
	if self.atMogliInitDone then
		AIVEHud.delete(self)
	end
	AutoSteeringEngine.deleteChain(self)

	if self.atShiftedMarker ~= nil then
		for _,marker in pairs( {"aiCurrentLeftMarker", "aiCurrentRightMarker", "aiCurrentBackMarker"} ) do
			AutoSteeringEngine.deleteNode( self.atShiftedMarker[marker] )
		end
		self.atShiftedMarker = nil
	end
end

------------------------------------------------------------------------
-- delete
------------------------------------------------------------------------
function AIVehicleExtension:onDelete()
end

------------------------------------------------------------------------
-- getStartableAIJob
------------------------------------------------------------------------
function AIVehicleExtension:getStartableAIJob(superFunc)
	if self.acParameters ~= nil and self.isClient and self.getIsControlled ~= nil and self.getIsEntered ~= nil and self:getIsControlled() and self:getIsEntered() then 
		print('Sending acParameters to server...')
		for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
			print( '  self.acParameters.'..tostring(attr.name)..': "'..tostring(self.acParameters[attr.name])..'"' )
		end 
		AIVehicleExtension.sendParameters(self)
	end
	return superFunc(self)
end

------------------------------------------------------------------------
-- mouse event callbacks
------------------------------------------------------------------------
function AIVehicleExtension.getControlVehicle(vehicle)
	if vehicle == nil then return nil end
	return vehicle.rootVehicle or (type(vehicle.getRootVehicle)=="function" and vehicle:getRootVehicle()) or vehicle
end

function AIVehicleExtension.isNativeSteeringSelected(vehicle)
	local root=AIVehicleExtension.getControlVehicle(vehicle)
	local spec=root and root.spec_aiModeSelection
	return spec~=nil and AIModeSelection~=nil and AIModeSelection.MODE~=nil
		and AIModeSelection.MODE.STEERING_ASSIST~=nil and spec.currentMode==AIModeSelection.MODE.STEERING_ASSIST
end

local function workerText(key, fallback)
	local value=AIVEHud.getText(key)
	return value==key and fallback or value
end

local function workerTime()
	return g_time or (g_currentMission and g_currentMission.time) or 0
end

function AIVehicleExtension.isWorkerActive(vehicle)
	local root=AIVehicleExtension.getControlVehicle(vehicle)
	if root==nil then return false end
	if type(root.getIsAIActive)=="function" then return root:getIsAIActive()==true end
	return type(root.getIsFieldWorkActive)=="function" and root:getIsFieldWorkActive()==true
end

function AIVehicleExtension.isWorkerButtonPending(vehicle)
	local root=AIVehicleExtension.getControlVehicle(vehicle)
	return root~=nil and root.aiveGuiWorkerButtonUntil~=nil and workerTime()<root.aiveGuiWorkerButtonUntil
end

function AIVehicleExtension:getWorkerText()
	if AIVehicleExtension.isWorkerButtonPending(self) then
		return workerText("AIVE_WORKER_PENDING","Sending worker command...")
	elseif AIVehicleExtension.isWorkerActive(self) then
		return workerText("AIVE_WORKER_STOP","Stop AIVE worker")
	end
	return workerText("AIVE_WORKER_START","Start AIVE worker")
end

function AIVehicleExtension:getWorkerImage()
	return AIVehicleExtension.isWorkerActive(self) and "dds/hire_on.dds" or "dds/hire_off.dds"
end

local function workerWarning(vehicle,key,fallback)
	local message=workerText(key,fallback)
	if vehicle.atHud~=nil then AIVEHud.setInfoText(vehicle,message) end
	if g_currentMission and type(g_currentMission.showBlinkingWarning)=="function" then
		g_currentMission:showBlinkingWarning(message,4000)
	end
	return false
end

-- Only an explicit GUI start changes the native mode. H keeps its native
-- short/long-press handling; the native request still validates farm/job access.
function AIVehicleExtension:onToggleWorker()
	self=AIVehicleExtension.getControlVehicle(self)
	if self==nil or self.acParameters==nil or type(self.toggleAIVehicle)~="function" then return false end
	if AIVehicleExtension.isWorkerButtonPending(self) then return false end
	local external,name=false,nil
	if AIVEConflictGuard~=nil then external,name=AIVEConflictGuard.isExternalAIActive(self) end
	if external and name~="FS25_AutomaticSteering" then
		return workerWarning(self,"AIVE_WORKER_EXTERNAL","Stop Courseplay/AutoDrive before using the AIVE worker.")
	end
	if g_currentMission and type(g_currentMission.getHasPlayerPermission)=="function"
			and not g_currentMission:getHasPlayerPermission("hireAssistant") then
		return workerWarning(self,"AIVE_WORKER_NO_PERMISSION","You do not have permission to hire a worker.")
	end
	if AIVehicleExtension.isWorkerActive(self) then
		self.aiveGuiWorkerButtonUntil=workerTime()+750
		self:toggleAIVehicle()
		return true
	end
	if type(self.getCanStartAIVehicle)=="function" and not self:getCanStartAIVehicle() then
		return workerWarning(self,"AIVE_WORKER_NOT_READY","A worker cannot start on this vehicle right now.")
	end
	local mode=self.spec_aiModeSelection
	if mode~=nil and (AIModeSelection==nil or AIModeSelection.MODE==nil
			or type(self.setAIModeSelection)~="function") then
		return workerWarning(self,"AIVE_WORKER_NOT_READY","A worker cannot start on this vehicle right now.")
	end
	if mode~=nil and mode.currentMode==AIModeSelection.MODE.STEERING_ASSIST then
		self.aiveGuiWorkerSession={previousMode=mode.currentMode,requestedAt=workerTime(),observedActive=false}
	end
	if self.spec_aiAutomaticSteering and self.spec_aiAutomaticSteering.steeringEnabled
			and type(self.setAIAutomaticSteeringEnabled)=="function" then
		self:setAIAutomaticSteeringEnabled(false)
	end
	if self.aiveAutoSteer then AIVehicleExtension.onAutoSteer(self,false) end
	if mode~=nil then self:setAIModeSelection(AIModeSelection.MODE.WORKER) end
	self.acParameters.enabled=true
	self.acPause=false
	AIVehicleExtension.sendParameters(self)
	self.aiveGuiWorkerButtonUntil=workerTime()+750
	self:toggleAIVehicle()
	return true
end

function AIVehicleExtension.updateGuiWorkerSession(vehicle)
	local session=vehicle.aiveGuiWorkerSession
	if session==nil then return end
	if AIVehicleExtension.isWorkerActive(vehicle) then
		session.observedActive=true
	elseif session.observedActive or workerTime()-session.requestedAt>=5000 then
		vehicle.aiveGuiWorkerSession=nil
		-- Do not undo a different mode the player selected while the job ran.
		if vehicle.spec_aiModeSelection and vehicle.spec_aiModeSelection.currentMode==AIModeSelection.MODE.WORKER then
			vehicle:setAIModeSelection(session.previousMode)
		end
	end
end

function AIVehicleExtension:onAIVEScreen()
	self=AIVehicleExtension.getControlVehicle(self)
	if self==nil then return end
	if self.acParameters == nil or (g_gui ~= nil and g_gui:getIsGuiVisible()) then return end
	AIVehicleExtension.initMogliHud(self)
	if g_AIVEScreen == nil then g_AIVEScreen = AIVEScreen.new() end
	if g_AIVEScreen.isOpen and g_AIVEScreen.vehicle == self then
		g_AIVEScreen:onClose()
	else
		g_AIVEScreen:showGui(self)
	end
end

--*****************************************************************

function AIVehicleExtension:aiveUIGetheadland()
	if self.acParameters == nil then 
		return 0 
	end 
	if not self.acParameters.headland then 
		return 1 
	end 
	if self.acParameters.bigHeadland then 
		return 3 
	end 
	return 2 
end 
function AIVehicleExtension:aiveUISetheadland( value )
	if self.acParameters == nil then 
		return 
	end 
	if value <= 1 then 
		self.acParameters.headland = false 
	else
		self.acParameters.headland = true 
		if value >= 3 then 	
			self.acParameters.bigHeadland = true 
		else 
			self.acParameters.bigHeadland = false 
		end 
	end 
end 

function AIVehicleExtension:aiveUIGetupNDown()
	if self.acParameters == nil then 
		return 0 
	end 
	if self.acParameters.circleLands then return 4 end
	if     not self.acParameters.upNDown then 
		return 1 
	elseif not self.acParameters.straight then 
		return 2 
	end 
	return 3 
end 
function AIVehicleExtension:aiveUISetupNDown( value )
	if self.acParameters == nil then 
		return 
	end 
	self.acParameters.circleLands = value == 4
	if value <= 1 or value == 4 then
		self.acParameters.upNDown  = false 
		self.acParameters.straight = false 
	else
		self.acParameters.upNDown  = true  
		if value >= 3 then 	
			self.acParameters.straight = true 
		else 
			self.acParameters.straight = false 
		end 
	end 
end 

function AIVehicleExtension:aiveUIGetrightAreaActive()
	if self.acParameters == nil then 
		return 0
	end 
	if self.acParameters.rightAreaActive then 
		return 2
	end 
	return 1	
end 
function AIVehicleExtension:aiveUISetrightAreaActive( value )
	if self.acParameters == nil then 
		return
	end 
	if value >= 2 then 
		self.acParameters.rightAreaActive = true 		
		self.acParameters.leftAreaActive	= false 
	else 
		self.acParameters.rightAreaActive = false 
		self.acParameters.leftAreaActive	= true
	end 
end 


function AIVehicleExtension:aiveUIGetwidthOffset()
	if self.acParameters == nil then 
		return 0
	end 
	local i = math.floor( self.acParameters.widthOffset * 8 + 17.5 )
	return i
end 
function AIVehicleExtension:aiveUISetwidthOffset( value )
	if self.acParameters == nil then 
		return
	end 
	self.acParameters.widthOffset = ( value - 17 ) / 8
end 

function AIVehicleExtension:aiveUIGetturnOffset()
	if self.acParameters == nil then 
		return 0
	end 
	local i = table.getn(AIVehicleExtension.Distance)
	for j=1,i-1 do
		local d2 = 0.5 * ( AIVehicleExtension.Distance[j] + AIVehicleExtension.Distance[j+1] )
		if self.acParameters.turnOffset < d2 then
			i = j 
			break 
		end
	end
	return i
end 
function AIVehicleExtension:aiveUISetturnOffset( value )
	if self.acParameters == nil or AIVehicleExtension.Distance[value] == nil then 
		return
	end 
	self.acParameters.turnOffset = AIVehicleExtension.Distance[value]
end 



--*****************************************************************

function AIVehicleExtension:onRaiseNext()
	if self:getIsFieldWorkActive() then
		if self.aiveIsStarted then 
			AIVehicleExtension.setNextTurnStage(self)
		end
	else
		local moveDown = not ( AIVehicleExtension.getIsLowered( self ) )
		AIVehicleExtension.setImplMoveDownClient(self, moveDown,true)
		if self.acParameters ~= nil and not moveDown and self.acParameters.upNDown then
			self.acParameters.leftAreaActive	= not self.acParameters.leftAreaActive 
			self.acParameters.rightAreaActive = not self.acParameters.rightAreaActive
			AIVehicleExtension.sendParameters( self )
		end
	end
end

function AIVehicleExtension:getRaiseNextText()
	if self:getIsFieldWorkActive() then
		if not self.aiveIsStarted then 
			return ""
		else
			for _,ts in pairs( AIVehicleExtension.turnStageNoNext ) do
				if self.acTurnStage == ts then
					return ""
				end
			end
			return AIVEHud.getText( "AIVE_NEXTTURNSTAGE" )
		end
	else
		if AIVehicleExtension.getIsLowered( self ) == nil then
			return ""
		elseif AIVehicleExtension.getIsLowered( self ) then
			return AIVEHud.getText( "AIVE_STEER_RAISE" )
		else
			return AIVEHud.getText( "AIVE_STEER_LOWER" )
		end
	end
	return ""
end

function AIVehicleExtension:getRaiseNextImage()
	if self:getIsFieldWorkActive() then
		if not self.aiveIsStarted then 
			return "empty.dds"
		else
			for _,ts in pairs( AIVehicleExtension.turnStageNoNext ) do
				if self.acTurnStage == ts then
					return "dds/no_next.dds"
				end
			end
			return "dds/next.dds"
		end
	else
		if AIVehicleExtension.getIsLowered( self ) == nil then
			return "empty.dds"
		elseif AIVehicleExtension.getIsLowered( self ) then
			return "dds/raise_impl.dds"
		else
			return "dds/lower_impl.dds"
		end
	end
	return "empty.dds"
end

function AIVehicleExtension:onSteerPause()
	if self:getIsFieldWorkActive() then
		if self.aiveIsStarted then 
			AIVehicleExtension.setPause(self,not self.acPause)
		end
	else
		AIVehicleExtension.onAutoSteer( self, not ( self.aiveAutoSteer ) )
	end
end

function AIVehicleExtension:getSteerPauseText()
	if self:getIsFieldWorkActive() then
		if not self.aiveIsStarted then 
			return ""
		elseif self.acPause then
			return AIVEHud.getText( "AIVE_PAUSE_OFF" )
		else
			return AIVEHud.getText( "AIVE_PAUSE_ON" )
		end
	else
		if self.aiveAutoSteer then
			return AIVEHud.getText( "AIVE_STEER_OFF" )
		else
			return AIVEHud.getText( "AIVE_STEER_ON" )
		end
	end
	return ""
end

function AIVehicleExtension:getSteerPauseImage()
	if self:getIsFieldWorkActive() then
		if not self.aiveIsStarted then 
			return "empty.dds"
		elseif self.acPause then
			return "dds/pause.dds"
		else
			return "dds/no_pause.dds"
		end
	else
		if self.aiveAutoSteer then
			return "dds/auto_steer_on.dds"
		else
			return "dds/auto_steer_off.dds"
		end
	end
	return "empty.dds"
end

function AIVehicleExtension.showGui(self,on)
	if on then
		if self.atMogliInitDone == nil or not self.atMogliInitDone then
			AIVehicleExtension.initMogliHud(self)
		end
		AIVEHud.showGui(self,true)
	elseif self.atMogliInitDone then
		AIVEHud.showGui(self,false)
	end
end

function AIVehicleExtension:setUTurn(enabled)
	if self.aiveIsStarted or self.aiveAutoSteer then return end
	AIVehicleExtension.aiveUISetupNDown(self, AIVehicleExtension.aiveUIGetupNDown(self) % 4 + 1)
end

function AIVehicleExtension:getUTurnImage()
	if self.acParameters == nil or not self.acParameters.enabled then 
		return "dds/no_uturn.dds"
	elseif not self.acParameters.upNDown then 
		return "dds/no_uturn2.dds"
	elseif not self.acParameters.straight then 
		return "dds/uturn.dds"
	else 
		return "dds/no_uturn.dds"
	end
	return "empty.dds"
end

function AIVehicleExtension:getUTurnText()
	if self.acParameters == nil or not self.acParameters.enabled then 
		return ""
	elseif self.acParameters.circleLands then
		return AIVEHud.getText("AIVE_CIRCLE_LANDS")
	elseif not self.acParameters.upNDown then
		return AIVEHud.getText("AIVE_UTURN_OFF")
	elseif not self.acParameters.straight then 
		return AIVEHud.getText("AIVE_UTURN_ON")
	else 
		return AIVEHud.getText("AIVE_UTURN_ON2")
	end
	return ""
end

function AIVehicleExtension:evalAreaLeft()
	return not self.acParameters.leftAreaActive
end

function AIVehicleExtension:setAreaLeft(enabled)
--if not enabled then return end
	self.acParameters.leftAreaActive	= enabled
	self.acParameters.rightAreaActive = not enabled
end

function AIVehicleExtension:evalAreaRight()
	return not self.acParameters.rightAreaActive
end

function AIVehicleExtension:setAreaRight(enabled)
--if not enabled then return end
	self.acParameters.rightAreaActive = enabled
	self.acParameters.leftAreaActive	= not enabled
end

function AIVehicleExtension:evalStart()
	return not self:getIsFieldWorkActive() or not self:getCanStartAIVehicle()
end

function AIVehicleExtension:getStartImage()
	if self:getIsFieldWorkActive() then
		return "dds/on.dds"
	elseif self:getCanStartAIVehicle() then
		return "dds/off.dds"
	end
	return "empty.dds"
end

function AIVehicleExtension:evalEnable()
	if     self:getIsFieldWorkActive()          then
		return not ( self.aiveIsStarted )
	elseif self.acParameters.enabled then
		return false
	end
	return not ( self.aiveIsStarted )
end

function AIVehicleExtension:onEnable(enabled)
	if self:getCanStartAIVehicle() then
		if not ( self:getIsFieldWorkActive() ) then
			self.acParameters.enabled = enabled
		end
	end
end

function AIVehicleExtension:getEnableImage()
	if not self:getCanStartAIVehicle()  then
		return "dds/off.dds"	
	elseif self.acParameters.enabled then
		return "dds/auto_combine.dds"
	else
		return "dds/ai_combine.dds"
	end
end

function AIVehicleExtension:getTurnOffset(old)
	local new = ""
	if self.acDimensions == nil or self.acDimensions.headlandCount == nil then
		new = string.format(old..": %0.2fm",self.acParameters.turnOffset)
	else
		new = string.format(old..": %0.2fm (%i x)",self.acParameters.turnOffset,self.acDimensions.headlandCount)
	end
	return new
end

function AIVehicleExtension:getTurnIndexComp( upNDown )
	local u = upNDown
	if upNDown == nil and self.acParameters ~= nil then
		u = self.acParameters.upNDown
	end
	
	if not ( u ) then
		return "turnModeIndexC"
	end
	return "turnModeIndex"
end

function AIVehicleExtension:evalTurnStage()
	if self:getIsFieldWorkActive() then
		if self.aiveIsStarted then
			for _,ts in pairs( AIVehicleExtension.turnStageNoNext ) do
				if self.acTurnStage == ts then
					return false
				end
			end
			return true
	--else
	--	if self.turnStage > 0 and self.turnStage < 4 then
	--		return true
	--	end
		end
	end
	
	return false
end

function AIVehicleExtension:nextTurnStage()
	AIVehicleExtension.setNextTurnStage(self)
end

function AIVehicleExtension:evalPause()
	if not self.aiveIsStarted then 
		return true 
	end 
	if not self:getIsFieldWorkActive() then
		return true
	end
	if not self.acPause then
		return true
	end
	return false
end

function AIVehicleExtension:setPause(enabled)
	if not self.aiveIsStarted then 
		return	
	end 
	if not self:getIsFieldWorkActive() then
		return 
	end
	
	self.acPause = enabled
	
	if enabled then
		AIVehicleExtension.setInt32Value( self, "speed2Level", 0 )
	else
		AIVehicleExtension.setInt32Value( self, "speed2Level", 2 )
	end
	
	if g_server ~= nil then
		g_server:broadcastEvent(AIVEPauseEvent.new(self,enabled), nil, nil, self)
	else
		g_client:getServerConnection():sendEvent(AIVEPauseEvent.new(self,enabled))
	end
end


function AIVehicleExtension:getPauseImage()
	if not self.aiveIsStarted then 
		return "empty.dds"
	end 
	if not self:getIsFieldWorkActive() then
		return "empty.dds"
	end
	if not self.acPause then
		return "dds/no_pause.dds"
	end
	return "dds/pause.dds"
end

function AIVehicleExtension:evalAutoSteer()
	return self:getIsFieldWorkActive() or not ( self.aiveAutoSteer )
end

function AIVehicleExtension:onAutoSteer(enabled)
	if enabled then
		local external=AIVEConflictGuard~=nil and AIVEConflictGuard.isExternalAIActive(self)
		if external or AIVehicleExtension.isNativeSteeringSelected(self) then return end
	end
	if self:getIsFieldWorkActive() then
		if self.aiveAutoSteer then
			AIVehicleExtension.setInt32Value( self, "autoSteer", 2 )
		end
	elseif enabled then
		AIVehicleExtension.setInt32Value( self, "autoSteer", 1 )
		AIVehicleExtension.setImplMoveDownClient(self,true,true)
	else
		AIVehicleExtension.setInt32Value( self, "autoSteer", 0 )
	end
end

function AIVehicleExtension:onMagic(enabled)
	self.aiveJobMemory=nil
	AIVehicleExtension.initMogliHud(self)
	AIVehicleExtension.invalidateState( self )
end

function AIVehicleExtension:onRaiseImpl(enabled)
	if		 self:getIsFieldWorkActive() 
			or self.acParameters == nil then
	-- do nothing
	else
		AIVehicleExtension.setImplMoveDownClient(self,enabled,true)
		if self.acParameters ~= nil and not enabled and self.acParameters.upNDown then
			self.acParameters.leftAreaActive	= not self.acParameters.leftAreaActive 
			self.acParameters.rightAreaActive = not self.acParameters.rightAreaActive
			AIVehicleExtension.sendParameters( self )
		end
	end
end

function AIVehicleExtension:evalRaiseImpl()
	if AIVehicleExtension.getIsLowered( self ) then
		return false
	end
	return true
end

function AIVehicleExtension:getRaiseImplImage()
	if		 self:getIsFieldWorkActive() 
			or self.acParameters == nil then
		return "empty.dds"
	elseif AIVehicleExtension.getIsLowered( self ) == nil then
		return "empty.dds"
	elseif AIVehicleExtension.getIsLowered( self ) then
		return "dds/raise_impl.dds"
	end
	return "dds/lower_impl.dds"
end

function AIVehicleExtension:setTurnMode()
	AIVehicleExtension.checkAvailableTurnModes( self, true )
	local c = AIVehicleExtension.getTurnIndexComp(self)
	self.acParameters[c] = self.acParameters[c] + 1
	if self.acParameters[c] > table.getn( self.acTurnModes ) then
		self.acParameters[c] = 1
	end
	self.acTurnMode = self.acTurnModes[self.acParameters[c]]
end

function AIVehicleExtension:getTurnModeImage()
	local img = "empty.dds"
	
	if     self.acTurnMode == nil then
		img = "empty.dds"
	elseif self.acTurnMode == "8" then
		img = "dds/bigUTurn8.dds"
	elseif self.acTurnMode == "O" then
		img = "dds/noRevUTurn.dds"
	elseif self.acTurnMode == "A" then
		img = "dds/smallUTurn.dds"
	elseif self.acTurnMode == "Y" then
		img = "dds/smallUTurn2.dds"
	elseif self.acTurnMode == "T" then
		img = "dds/bigUTurn.dds"
	elseif self.acTurnMode == "C" then
		img = "dds/noRevSide.dds"
	elseif self.acTurnMode == "L" then
		img = "dds/smallSide.dds"
	elseif self.acTurnMode == "K" then
		img = "dds/bigSide.dds"
	elseif self.acTurnMode == "7" then
		img = "dds/bigSide7.dds"
	end

	if AIVEGlobals.devFeatures > 0 then
		if self.acLastBigImg == nil or self.acLastBigImg ~= img then
			self.acLastBigImg = img
			print(img)
		end
	end
	
	return img
end

function AIVehicleExtension:getTurnModeText(old)
	if self.acTurnMode ~= nil then
		return AIVEHud.getText("AIVE_TURN_MODE_"..self.acTurnMode)
	end
end

function AIVehicleExtension:setTurnMode()
	AIVehicleExtension.checkAvailableTurnModes( self, true )
	local c = AIVehicleExtension.getTurnIndexComp(self)
	self.acParameters[c] = self.acParameters[c] + 1
	if self.acParameters[c] > table.getn( self.acTurnModes ) then
		self.acParameters[c] = 1
	end
	self.acTurnMode = self.acTurnModes[self.acParameters[c]]
end

function AIVehicleExtension:setHeadland(old)
	if     self.acParameters == nil then 
	elseif self.acParameters.circleLands then return
	elseif self.acParameters.upNDown then
		if not self.acParameters.headland then
			self.acParameters.headland    = true
			self.acParameters.bigHeadland = false
		elseif not self.acParameters.bigHeadland then
			self.acParameters.headland    = true
			self.acParameters.bigHeadland = true
		else
			self.acParameters.headland    = false
			self.acParameters.bigHeadland = false
		end
	elseif self.acParameters.maxCircles >= 6 then 
		self.acParameters.maxCircles = 0
	elseif self.acParameters.maxCircles >= 5 then 
		self.acParameters.maxCircles = 6
	elseif self.acParameters.maxCircles >= 4 then 
		self.acParameters.maxCircles = 5
	elseif self.acParameters.maxCircles >= 3 then 
		self.acParameters.maxCircles = 4
	elseif self.acParameters.maxCircles >= 2 then 
		self.acParameters.maxCircles = 3
	elseif self.acParameters.maxCircles >= 1 then 
		self.acParameters.maxCircles = 2
	else 
		self.acParameters.maxCircles = 1
	end
end

function AIVehicleExtension:getHeadlandImage()
	if self.acParameters == nil then 
		return "dds/noHeadland.dds"
	elseif not self.acParameters.enabled then 
		return "dds/noHeadland.dds"
	elseif self.acParameters.circleLands then
		return "dds/no_0.dds"
	elseif self.acParameters.upNDown then
		if not self.acParameters.headland then
			return "dds/noHeadland.dds"
		elseif not self.acParameters.bigHeadland then
			return "dds/small_headland.dds"
		else
			return "dds/big_headland.dds"
		end
	elseif self.acParameters.maxCircles >= 6 then 
		return "dds/no_6.dds"
	elseif self.acParameters.maxCircles >= 5 then 
		return "dds/no_5.dds"
	elseif self.acParameters.maxCircles >= 4 then 
		return "dds/no_4.dds"
	elseif self.acParameters.maxCircles >= 3 then 
		return "dds/no_3.dds"
	elseif self.acParameters.maxCircles >= 2 then 
		return "dds/no_2.dds"
	elseif self.acParameters.maxCircles >= 1 then 
		return "dds/no_1.dds"
	end
	return "dds/no_0.dds"
end

function AIVehicleExtension:getHeadlandText(old)
	if self.acParameters == nil then 
		return ""
	elseif not self.acParameters.enabled then 
		return ""
	elseif self.acParameters.circleLands then
		return AIVEHud.getText("AIVE_LANDS_THRESHOLD")
	elseif self.acParameters.upNDown then
		local st, bt = " (-)", " (+)"
		if self.isServer and ( self.acCheckStateTimer ~= nil or self.aiveIsStarted or self.aiveAutoSteer ) then
			local s, b = AIVehicleExtension.getHeadlandSmallBig( self )
			st = string.format(" (%5.2fm)",s)
			bt = string.format(" (%5.2fm)",b)
		end
		if not self.acParameters.headland then
			return AIVEHud.getText("AIVE_HEADLAND_ON")
		elseif not self.acParameters.bigHeadland then
			return AIVEHud.getText("AIVE_HEADLAND")..st
		else
			return AIVEHud.getText("AIVE_HEADLAND")..bt
		end
	elseif self.acParameters ~= nil and self.acParameters.maxCircles > 0 then 
		return AIVEHud.getText("AIVE_MAXCIRCLES").." "..tostring(self.acParameters.maxCircles)
	end
	return AIVEHud.getText("AIVE_HEADLAND_ON")
end

function AIVehicleExtension:onToggleTrace()
	if self.acParameters ~= nil then 
		self.acParameters.showTrace = not ( self.acParameters.showTrace )
	end 
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------

function AIVehicleExtension.updatePauseAction(vehicle)
	if not vehicle.isClient or vehicle.aivePauseActionEventId==nil then return end
	local active=vehicle.aiveIsStarted==true and vehicle:getIsFieldWorkActive()==true
	if active~=vehicle.aivePauseActionActive and g_inputBinding and g_inputBinding.setActionEventActive then
		g_inputBinding:setActionEventActive(vehicle.aivePauseActionEventId,active)
		vehicle.aivePauseActionActive=active
	end
end

function AIVehicleExtension:onRegisterActionEvents(isSelected, isOnActiveVehicle)
	if self.isClient then
		if self.aiveActionEvents == nil then
			self.aiveActionEvents = {}
		else
			self:clearActionEventsTable( self.aiveActionEvents )
		end
		self.aivePauseActionEventId=nil;self.aivePauseActionActive=nil
		if AIVehicleExtension.getControlVehicle(self)~=self then return end
		local active=isSelected or isOnActiveVehicle
		if type(self.getIsActiveForInput)=="function" then active=self:getIsActiveForInput(true,true) end
		if not active then
			return
		end

		local actions = {
			"AIVE_HELPPANEL",
			"AIVE_START_AIVE",
			"AIVE_STEER",
			"AIVE_SWAP_SIDE",
			"AIVE_ENABLE",
			"AIVE_UTURN_ON_OFF",
			"AIVE_STEERING",
			"AIVE_RAISE",
			"AIVE_PAUSE"
		}

		for _, actionName in ipairs( actions ) do
			local inputAct = InputAction ~= nil and InputAction[actionName] or nil
			if inputAct ~= nil then
				local pBool1, pBool2, pBool3, pBool4 = false, true, false, true
				if actionName=="AIVE_PAUSE" then pBool4=self.aiveIsStarted==true and self:getIsFieldWorkActive()==true end
				local ok, _, eventId = pcall(self.addActionEvent, self, self.aiveActionEvents, inputAct, self, AIVehicleExtension.actionCallback, pBool1, pBool2, pBool3, pBool4)
				if ok and eventId ~= nil and g_inputBinding ~= nil and g_inputBinding.setActionEventTextVisibility ~= nil then
					pcall(g_inputBinding.setActionEventTextVisibility, g_inputBinding, eventId, actionName == "AIVE_HELPPANEL" or actionName == "AIVE_START_AIVE" or actionName == "AIVE_STEER")
				end
				if ok and actionName=="AIVE_PAUSE" then self.aivePauseActionEventId=eventId end
			end
		end
		AIVehicleExtension.updatePauseAction(self)
	end
end

-- The selected implement resets active binding masks after the root vehicle.
-- Re-register the root's shortcuts after that reset, in the vehicle context.
function AIVehicleExtension.afterSelectedImplementActionEvents(vehicle,excludedVehicle)
	local root=AIVehicleExtension.getControlVehicle(vehicle)
	if root==vehicle or not root or not root.isClient or not root.acParameters or excludedVehicle==vehicle then return end
	if g_gui and g_gui:getIsGuiVisible() then return end
	if g_currentMission and g_currentMission.isPlayerFrozen then return end
	if type(vehicle.getIsActiveForInput)~="function" or not vehicle:getIsActiveForInput(false,true) then return end
	g_inputBinding:beginActionEventsModification(Vehicle.INPUT_CONTEXT_NAME)
	AIVehicleExtension.onRegisterActionEvents(root,false,true)
	g_inputBinding:endActionEventsModification()
end

if Vehicle~=nil and type(Vehicle.registerActionEvents)=="function" then
	Vehicle.registerActionEvents=Utils.appendedFunction(Vehicle.registerActionEvents,AIVehicleExtension.afterSelectedImplementActionEvents)
end

function AIVehicleExtension:actionCallback(actionName, keyStatus, arg4, arg5, arg6)
	self=AIVehicleExtension.getControlVehicle(self)
	if self==nil or self.acParameters==nil then return end
	AIVehicleExtension.debugPrint( self, tostring(actionName)..": "..tostring(keyStatus) )
	if g_AIVEScreen ~= nil and g_AIVEScreen.isOpen then
		if actionName == "AIVE_START_AIVE" or actionName == "AIVE_HELPPANEL" then
			g_AIVEScreen:onClose()
		end
		return
	end

	local guiActive = false
	if self.atHud ~= nil and self.atHud.GuiActive ~= nil then
		guiActive = self.atHud.GuiActive
	end

	if actionName == "AIVE_HELPPANEL" then
		AIVehicleExtension.showGui( self, not guiActive )
	elseif actionName == "AIVE_START_AIVE" then
		AIVehicleExtension.onAIVEScreen( self )
	elseif actionName == "AIVE_ENABLE" then
		if self.acParameters ~= nil then
			AIVehicleExtension.onEnable( self, not self.acParameters.enabled )
			AIVehicleExtension.sendParameters(self)
		end
	elseif actionName == "AIVE_SWAP_SIDE" then
		self.acParameters.leftAreaActive  = self.acParameters.rightAreaActive
		self.acParameters.rightAreaActive = not self.acParameters.leftAreaActive
		AIVehicleExtension.sendParameters(self)
	elseif actionName == "AIVE_STEER" then
		local extActive, extMod = false, nil
		if AIVEConflictGuard ~= nil then
			extActive, extMod = AIVEConflictGuard.isExternalAIActive(self)
		end
		if extActive then
			if AIVELogger ~= nil then
				AIVELogger.warn("ConflictGuard", "Cannot enable AIVE AutoSteer while %s is active on '%s'", tostring(extMod), tostring(self:getName()))
			end
			return
		end
		AIVehicleExtension.onAutoSteer(self, not ( self.aiveAutoSteer ))
	elseif actionName == "AIVE_STEERING" then
		self.acParameters.noSteering = not self.acParameters.noSteering
		AIVehicleExtension.sendParameters(self)
	elseif actionName == "AIVE_UTURN_ON_OFF" then
		AIVehicleExtension.setUTurn(self)
		AIVehicleExtension.sendParameters(self)
	elseif actionName == "IMPLEMENT_EXTRA" then
		self.acCheckPloughSide = true
	elseif actionName == "AIVE_RAISE" and not self.aiveIsStarted then
		if self.acParameters ~= nil and self.acParameters.upNDown and self.acImplementsMoveDown then
			self.acParameters.leftAreaActive  = not self.acParameters.leftAreaActive
			self.acParameters.rightAreaActive = not self.acParameters.rightAreaActive
			AIVehicleExtension.sendParameters( self )
		end
		AIVehicleExtension.setImplMoveDownClient(self, not ( AIVehicleExtension.getIsLowered( self ) ), true)
	elseif actionName == "AXIS_MOVE_SIDE_VEHICLE"
			and self.aiveIsStarted
			and self.acParameters ~= nil
			and not self.acParameters.noSteering then
		if math.abs( keyStatus ) > 0.05 then
			self.acAxisSide = keyStatus
		else
			self.acAxisSide = 0
		end
	elseif actionName == "AIVE_PAUSE"
			and self.aiveIsStarted then
		AIVehicleExtension.setPause(self,not self.acPause)
	end
end

------------------------------------------------------------------------
-- AIVehicleExtension.onPreUpdate
------------------------------------------------------------------------
function AIVehicleExtension:onPreUpdate( dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected )

	if      self.aiveAutoSteer
			and self.isClient
			and self.getIsEntered  ~= nil
			and self.acParameters  ~= nil 
			and self.spec_drivable ~= nil
			and self:getIsEntered()
			and self:getIsActiveForInput(true, true)
		--and ( self.aiveAutoSteer or ( self.aiveIsStarted and not self.acParameters.noSteering ) )
			and math.abs( self.spec_drivable.lastInputValues.axisSteer ) > 0.05 then 
		self.acAxisSide = self.spec_drivable.lastInputValues.axisSteer
	elseif self.aiveIsStarted then
	else 
		self.acAxisSide = 0
	end 
end

------------------------------------------------------------------------
-- AIVehicleExtension.onUpdate
------------------------------------------------------------------------

-- FS25 schedules its field-worker updates itself. The legacy low-frequency
-- method is no longer registered on vehicles. Do not call it or run a second
-- drive update from onUpdate; AIVE participates through its drive strategy.

function AIVehicleExtension:onUpdate( dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected )
	AIVehicleExtension.updateGuiWorkerSession(self)

	if self.aiveIsStarted and not ( self:getIsFieldWorkActive() ) then 
		self.aiveIsStarted = false
	end 
	AIVehicleExtension.updatePauseAction(self)

	if      self.acParameters ~= nil
			and self.acParameters.enabled
			and ( self.aiveIsStarted or self:getCanStartAIVehicle() ) then 
		AIVehicleExtension.checkState( self, false, true )
	end 
		
	if self.aiveToolsDirty then 
		AIVehicleExtension.invalidateState( self )
		self.aiveToolsDirty = nil
	end 
	
	if atDump and self:getIsActiveForInput(false) then
		AIVehicleExtension.acDump2(self)
	end

	
	if self.isServer then		
-- in MP on server only 

		if      AIVEGlobals.otherAIColli > 0
				and self.aiveIsStarted
				and self.acParameters ~= nil
				and self.acParameters.collision
				and not self.acParameters.upNDown then 
			AIVehicleExtension.enableCollisionTriggers( self )
		else
			AIVehicleExtension.disableCollisionTriggers( self )
		end 
	
		if      ( self.aiveIsStarted or self.aiveAutoSteer )
				and self.acDimensions              ~= nil
				and self.acDimensions.acRefNodeZ   ~= nil
				and self.acDimensions.wheelBase    ~= nil 
				and self.acDimensions.wheelParents ~= nil then
				
			if AutoSteeringEngine.hasArticulatedAxis( self, true ) then	
				local node = getParent( self.acRefNode )
				local dx = 0
				local dz = 0
				local dn = 0
				for n,i in pairs( self.acDimensions.wheelParents ) do
					local x,_,z = AutoSteeringEngine.getRelativeTranslation( node, n )
					dx = dx + x
					dz = dz + z
					dn = dn + i
				end
				if dn > 0 then
					dx = dx / dn
					dz = dz / dn
				end
				local _,angle,_ = getRotation( self.spec_articulatedAxis.rotationNode )
				self.acDimensions.artAxisR = angle 
				angle = 0.5 * angle
				self.acDimensions.artAxisX = dx 
				self.acDimensions.artAxisZ = dz 
				self.acDimensions.refNodeAngle = angle 
			else
				self.acDimensions.artAxisX = 0 
				self.acDimensions.artAxisZ = 0 
				self.acDimensions.refNodeAngle = 0
			end
			
			if self.acParameters.inverted then
				self.acDimensions.refNodeAngle = self.acDimensions.refNodeAngle + math.pi
			end
			local _,y,_ = getRotation( self.acRefNode )
			if math.abs( y - self.acDimensions.refNodeAngle ) > 0.01 then
				setRotation( self.acRefNode, 0, self.acDimensions.refNodeAngle, 0 )				
			end
			
			if self.acDimensions.refNodeTranslation == nil then 
				self.acDimensions.refNodeTranslation = { 0, 0, 0 }
			end 
			local lx,ly,lz = unpack( self.acDimensions.refNodeTranslation )
			local wx,wy,wz = getWorldTranslation( self.acRefNode )
			local ty       = getTerrainHeightAtWorldPos( g_currentMission.terrainRootNode, wx,wy,wz )		
			local rx,ry,rz = self.acDimensions.artAxisX, ly + ty - wy, self.acDimensions.artAxisZ + self.acDimensions.acRefNodeZ
		
			if self.acDimensions.refNodeTranslation == nil or math.abs( lx-rx ) > 0.01 or math.abs( ly-ry ) > 0.01 or math.abs( lz-rz ) > 0.01 then
				self.acDimensions.refNodeTranslation = { rx,ry,rz }
				setTranslation( self.acRefNode, rx,ry,rz )
			end 
		end

		if     self.aiveIsStarted      then
			if AIVEGlobals.devFeatures <= 0 or self.atHud.InfoText == nil or self.atHud.InfoText == "" then
				AIVEHud.setInfoText( self )
				if self.acDimensions ~= nil and self.acDimensions.distance ~= nil then
					AIVEHud.setInfoText( self, AIVEHud.getText( "AIVE_WORKWIDTH" ) .. string.format(" %0.2fm", self.acDimensions.distance+self.acDimensions.distance) )
				end
				if self.acTurnStage ~= nil and self.acTurnStage ~= 0 and self.acTurnStage < 198 then
					AIVEHud.setInfoText( self, AIVEHud.getInfoText(self) .. string.format(" (%i)", self.acTurnStage) )
				end
			end
			
			if      self.courseplayers              ~= nil 
					and table.getn( self.courseplayers ) > 0
					and self.specializations            ~= nil
					and self.overloading                ~= nil					
					and SpecializationUtil.hasSpecialization(Combine, self.specializations)
					and type(self.getFillUnitCapacity) == "function" and self:getFillUnitCapacity(self.overloading.fillUnitIndex) <= 0 then
				self.acChopperWithCourseplay = true
			else
				self.acChopperWithCourseplay = false 
			end
			
			if self.acParameters.straight then 
				if not ( self.acIsStraight ) then 
					AIVehicleExtension.setAIDirection( self )
				end 
				
				self.acIsStraight = true  
			else 
				self.acIsStraight = false 
			end 
			
			if self.acParameters.maxCircles > 0 and not self.acParameters.circleLands and not self.acParameters.upNDown and self.aiveCurrentField ~= nil then
				if -math.pi <= self.acParameters.startAngle and self.acParameters.startAngle <= math.pi then 
					if not AutoSteeringEngine.checkField( self, self.acParameters.fieldCenterX, self.acParameters.fieldCenterZ ) then 
						self.acParameters.startAngle  = -4
						self.acParameters.circlesDone = -1
					end 
				end 
				local wx,wy,wz = getWorldTranslation( self.acRefNode )
				if self.acParameters.circlesDone < 0 then 
					self.acParameters.fieldCenterX = self.aiveFieldCenterX
					self.acParameters.fieldCenterZ = self.aiveFieldCenterZ
					self.acParameters.startAngle   = math.atan2( wx - self.acParameters.fieldCenterX, wz - self.acParameters.fieldCenterZ )
					self.acParameters.circlesDone  = 0
				else  
					local a = ( math.atan2( wx - self.acParameters.fieldCenterX, wz - self.acParameters.fieldCenterZ ) - self.acParameters.startAngle ) / ( math.pi + math.pi )
					if self.acParameters.leftAreaActive then 
						a = -a 
					end
					while a < self.acParameters.circlesDone - 0.5 do 
						a = a + 1
					end 
					self.acParameters.circlesDone = a
				end 
				if self.acParameters.circlesDone > self.acParameters.maxCircles + 0.1 then 
					print("AIVE did some circles: "..tostring(self.acParameters.circlesDone))
					self.acParameters.upNDown      = true
					self.acParameters.headland     = false 
					self.acParameters.straight		 = false
					self.acParameters.circlesDone  = -1
					self.acParameters.startAngle	 = -4
					self.acParameters.fieldCenterX = 0 
					self.acParameters.fieldCenterZ = 0 
					AIVehicleExtension.sendParameters(self)
				end 
			end 
						
		elseif self.aiveAutoSteer then
			self.stopMotorOnLeave = false
			self.deactivateOnLeave = false
		else
			self.acTurnStage = 0
		end
	
		if      AutoSteeringEngine.hasArticulatedAxis( self )
				and ( self.aiveCanStartArtAxisTimer == nil or g_currentMission.time > self.aiveCanStartArtAxisTimer + 1000 ) then
				
			AIVehicleExtension.checkState( self )

			self.aiveCanStartArtAxisTimer = g_currentMission.time
			local backup = 0
			if self.aiveCanStartArtAxis then
				backup = 1
			end
			local canStart = 0
			
			if self.aiveChain ~= nil then			
				AutoSteeringEngine.checkTools( self )
				for _,tool in pairs(self.aiveChain.tools) do
					if tool.aiForceTurnNoBackward then
						canStart = 1
					else
						canStart = 0
						break
					end
				end
			end
		
			if canStart ~= backup then
				AIVehicleExtension.setInt32Value( self, "aiveCanStartArtAxis", canStart )
			end
		end 

		local lb = AIVehicleExtension.getIsLoweredServer( self )
		local lv
		if lb == nil then
			lv = 0
		elseif lb then
			lv = 2
		else
			lv = 1
		end
		if self.acIsLowered ~= lv then
			AIVehicleExtension.setInt32Value( self, "lowered", lv )
		end
	end
	
	if			AIVEGlobals.showTrace > 0 and self:getIsEntered() 
			and self.isClient 
			and self.isServer 
			and self.acParameters ~= nil and self.acParameters.showTrace 
			and self.atHud ~= nil and self.atHud.GuiActive 
			and ( self.aiveIsStarted or self.aiveAutoSteer ) then			
		if			AIVEGlobals.showTrace > 0 
				and self.acDimensions ~= nil
				and ( self:getIsFieldWorkActive() or self.aiveAutoSteer ) then	
			AutoSteeringEngine.drawLines( self )
		end
	end	
	
	if self.aiveRequestActionEventUpdate then 
		self.aiveRequestActionEventUpdate = nil 
		self:requestActionEventUpdate()
	end 
end

------------------------------------------------------------------------
-- AIVehicleExtension.onStateChange
------------------------------------------------------------------------
function AIVehicleExtension:onStateChange(state, data)
	if state == VehicleStateChange.ATTACH or state == VehicleStateChange.DETACH then
    self.aiveToolsDirty = true
	end
end

------------------------------------------------------------------------
-- AIVehicleExtension.shiftAIMarker
------------------------------------------------------------------------
function AIVehicleExtension:setAIDirection()
	local dx,_,dz = localDirectionToWorld(self.acRefNode, 0, 0, 1)
	if g_currentMission.snapAIDirection then
		local snapAngle = self:getDirectionSnapAngle()
		local maxGroundAngle = (g_currentMission.fieldGroundSystem ~= nil and type(g_currentMission.fieldGroundSystem.getGroundAngleMaxValue) == "function") and g_currentMission.fieldGroundSystem:getGroundAngleMaxValue() or 7
		local terrainAngle = math.pi / math.max(maxGroundAngle + 1, 8)
		snapAngle = math.max(snapAngle, terrainAngle)
		local angleRad = MathUtil.getYRotationFromDirection(dx, dz)
		angleRad = math.floor(angleRad / snapAngle + 0.5) * snapAngle
		dx, dz = MathUtil.getDirectionFromYRotation(angleRad)
	else
		local length = MathUtil.vector2Length(dx, dz)
		dx = dx / length
		dz = dz / length
	end

	self.aiDriveDirection = {dx, dz}
	local x,_,z = getWorldTranslation(self.acRefNode)
	self.aiDriveTarget = {x, z}
	
	if self.isServer then 
		AIVehicleExtension.checkState( self )
		if self.aiveChain.toolCount > 0 then 
			local dir
			if self.acParameters.leftAreaActive then 
				dir = -1 
			else 
				dir = 1
			end 
			local dir2 = 0
			
			local best,prev = nil, nil
			for i=0,24 do 
				local d = i * dir2 * dir * 0.125
				local x = self.aiveChain.activeX + d
				
				local sx
				local sz
				local hasField1 = true  
				local hasFruit  = false 
				for z=0,30 do 
					z1 = z + 1
					sx = self.aiDriveTarget[1] + x * self.aiDriveDirection[2] + ( math.max( 0, self.aiveChain.maxZ ) + z ) * self.aiDriveDirection[1]
				  sz = self.aiDriveTarget[2] - x * self.aiDriveDirection[1] + ( math.max( 0, self.aiveChain.maxZ ) + z ) * self.aiDriveDirection[2]
					if AutoSteeringEngine.checkField( self, sx,sz ) then
						break 
					end 
				end 
				for z=1,100 do 
					local wx = sx + z * self.aiDriveDirection[1]
					local wz = sz + z * self.aiDriveDirection[2]
					if AutoSteeringEngine.checkField( self, wx,wz ) then 
						hasField1 = true  
						if AutoSteeringEngine.hasFruitsSimple( self, sx, sz, wx, dz, dir ) then 
							hasFruit = true 
							AIVehicleExtension.debugPrint( self, "Fruits at "..tostring(i)..", "..tostring(dir2)..", "..tostring(z1).." .. "..tostring(z))
							break 
						end 
					elseif hasField1 then 
						hasField1 = false 
					else 
						AIVehicleExtension.debugPrint( self, "EOF at "..tostring(i)..", "..tostring(dir2)..", "..tostring(z1).." .. "..tostring(z))
						break 
					end 
				end 
				if i == 0 then 
					if hasFruit then 
						dir2 = 1 
					else 
						dir2 = -1 
					end 
				elseif dir2 < 0 then  
					if hasFruit then 
						AIVehicleExtension.debugPrint( self,  "Exit at "..tostring(i).." / "..tostring(dir2).." / "..tostring(prev))
						best = prev 
						break 
					end 
				else 
					if not hasFruit then 
						AIVehicleExtension.debugPrint( self,  "Exit at "..tostring(i).." / "..tostring(dir2).." / "..tostring(prev))
						best = d 
						break 
					end 
				end 
				prev = d
			end 
			
			if best ~= nil then 
				local x,_,z = localToWorld(self.acRefNode, best, 0, 0 )
				self.aiDriveTarget = {x, z}
			end 
		end 
	end 
end 

------------------------------------------------------------------------
-- AIVehicleExtension.resetAIMarker
------------------------------------------------------------------------
function AIVehicleExtension:resetAIMarker()
	if self.atShiftedMarker ~= nil then 
	--AIVehicleExtension.debugPrint( self, "resetting shifted marker")
		self.atLastMarkerShift = 0
		for _,marker in pairs( {"aiCurrentLeftMarker", "aiCurrentRightMarker", "aiCurrentBackMarker"} ) do 						
			setTranslation( self.atShiftedMarker[marker], 0, 0, 0 )
		end 		
	end 		
end 

------------------------------------------------------------------------
-- AIVehicleExtension:setImplMoveDownClient(moveDown)
------------------------------------------------------------------------
function AIVehicleExtension:setImplMoveDownClient( moveDown, immediate, noEventSend )

	local value = 0
	if moveDown then
		value = value + 2
	end
	if immediate then
		value = value + 1
	end
	AIVehicleExtension.setInt32Value( self, "moveDown", value )
	
end
	
------------------------------------------------------------------------
-- AIVehicleExtension:setAIImplementsMoveDown(moveDown)
------------------------------------------------------------------------
function AIVehicleExtension:setAIImplementsMoveDown( moveDown, immediate )
	if self.acImplementsMoveDown == nil or self.acImplementsMoveDown ~= moveDown then
		AutoSteeringEngine.setToolsAreLowered( self, moveDown, immediate )
	end
	if immediate then
		AutoSteeringEngine.ensureToolIsLowered( self, moveDown )
	end
	
	self.acImplementsMoveDown  = moveDown
	self.acImplementsMoveDown2 = moveDown
	self.acImplMoveDownTimer   = 0 
end

------------------------------------------------------------------------
-- setStatus
------------------------------------------------------------------------
function AIVehicleExtension:setStatus( newStatus, noEventSend )
	
	if self ~= nil and self.atMogliInitDone and self.atHud ~= nil and ( self.atHud.Status == nil or self.atHud.Status ~= newStatus ) then
		AIVehicleExtension.setInt32Value( self, "status", AIVEUtils.getNoNil( newStatus, 0 ) )
	end
	
end

------------------------------------------------------------------------
-- getAvailableTurnModes
------------------------------------------------------------------------
function AIVehicleExtension:getAvailableTurnModes( upNDown )

	local turnModes = {}
	
	if self.acDimensions == nil then
		AIVehicleExtension.calculateDimensions( self )
	end

	local sut, rev, revS, noHire = AutoSteeringEngine.getTurnMode( self )

	if upNDown then
		if rev	then
			if self.acDimensions.zBack ~= nil and self.acDimensions.zBack > 0 then
				table.insert( turnModes, "Y" )
			elseif AIVEGlobals.enableAUTurn > 0 and sut then
				table.insert( turnModes, "A" )
			end
		end
		if revS then
			table.insert( turnModes, "T" )
		end
		table.insert( turnModes, "O" )
		if self.acDimensions.zBack ~= nil and self.acDimensions.zBack < 0 then
			table.insert( turnModes, "8" )
		end
	else
		if self.acDimensions.zBack ~= nil and self.acDimensions.zBack > 0 then
			if revS then --and not self.acChopperWithCourseplay then
				table.insert( turnModes, "7"	)
			end
			if rev	then
				table.insert( turnModes, "L"	)
			end
		else
			if rev	then
				table.insert( turnModes, "L"	)
			end
			if revS then
				table.insert( turnModes, "7"	)
			end
		end
		if AIVEGlobals.enableKUTurn > 0 then
			table.insert( turnModes, "K"	)
		end
		table.insert( turnModes, "C"	)
	end
		
	return turnModes
end

------------------------------------------------------------------------
-- checkAvailableTurnModes
------------------------------------------------------------------------
function AIVehicleExtension:checkAvailableTurnModes( noEventSend )

	if noHire then
		self.acParameters.isHired = false
	end
	
	self.acTurnModes = AIVehicleExtension.getAvailableTurnModes( self, self.acParameters.upNDown )
	
	local c = AIVehicleExtension.getTurnIndexComp(self)
	
	if		 self.acParameters[c] == nil
			or self.acParameters[c] < 1 then
		self.acParameters[c] = 1
		if noEventSend == nil or not noEventSend then
			AIVehicleExtension.sendParameters(self)
		end
	elseif self.acParameters[c] > table.getn( self.acTurnModes ) then
		self.acParameters[c] = table.getn( self.acTurnModes )
		if noEventSend == nil or not noEventSend then
			AIVehicleExtension.sendParameters(self)
		end
	end

	self.acTurnMode = self.acTurnModes[self.acParameters[c]]
end

------------------------------------------------------------------------
-- invalidateState
------------------------------------------------------------------------
function AIVehicleExtension:invalidateState( detachIndex )

	AIVEHud.setInfoText( self )
	AutoSteeringEngine.checkTools1( self, true )
	AutoSteeringEngine.invalidateField( self, true )		
	AutoSteeringEngine.initFruitBuffer( self )
	if self.acDimensions ~= nil then
		self.acDimensions = nil
		AIVehicleExtension.checkState( self, true, true )
	end
	self.acCheckStateTimer = nil
	
end

------------------------------------------------------------------------
-- checkState
------------------------------------------------------------------------
function AIVehicleExtension:checkState( force, clientOnly )

	if self.aiToolsDirtyFlag then
		self.acDimensions      = nil
		self.acCheckStateTimer = nil
		return 
	end
	
	if      not ( force )
			and self.acCheckStateTimer ~= nil
			and self.acDimensions			~= nil
			and self.acCheckStateTimer > g_currentMission.time
			and ( clientOnly or self.acCheckStateServer ) then
		return 
	end
	
	if self.acDimensions == nil then
		AIVehicleExtension.calculateDimensions( self )
	end
	
	self.acCheckStateTimer  = g_currentMission.time + AIVEGlobals.maxDtSumT
	self.acCheckStateServer = not ( clientOnly )
	
	local s = AutoSteeringEngine.getSpecialToolSettings( self )
	
	if s.rightOnly then
		self.acParameters.upNDown				  = false
		self.acParameters.straight			  = false
		self.acParameters.leftAreaActive	= true
		self.acParameters.rightAreaActive = false
	end
	if s.leftOnly then
		self.acParameters.upNDown				  = false
		self.acParameters.straight			  = false
		self.acParameters.leftAreaActive	= false
		self.acParameters.rightAreaActive = true
	end
	
	AIVehicleExtension.checkAvailableTurnModes( self )
	
	AIVehicleExtension.calculateDistances( self )
	
	local h = 0
	local c = 0
--if			self.acParameters.collision
--		and self.acParameters.upNDown
--	--and self.acTurnStage ~=	-3 
--	--and self.acTurnStage ~= -13 
--	--and self.acTurnStage ~= -23 
--		then
--	c = self.acDimensions.collisionDist
--end
	if			self.acParameters.headland 
			and self.acParameters.upNDown 
		--and self.acTurnStage ~=	-3 
		--and self.acTurnStage ~= -13 
		--and self.acTurnStage ~= -23 
			then
		h = self.acDimensions.headlandDist
	end
	
	AutoSteeringEngine.initTools( self, self.acDimensions.maxSteeringAngle, self.acParameters.leftAreaActive, self.acParameters.widthOffset, h, c, self.acTurnMode )
	
	if not ( clientOnly ) then
		AutoSteeringEngine.initSteering( self )
	end
end

------------------------------------------------------------------------
-- autoSteer
------------------------------------------------------------------------
-- Use the chain's look-ahead target, as the worker does, rather than sending
-- its first (discretized) node angle straight to the wheels. Convert curvature
-- with FS25's wheel geometry; angle/maxSteering is not its steering calibration.
function AIVehicleExtension.getAutoSteerAxis(vehicle, angle, targetX, targetZ, dt)
	local maxAngle=vehicle.acDimensions.maxSteeringAngle
	local wanted=-angle/math.max(maxAngle,1e-4)
	local node=type(vehicle.getAIRootNode)=="function" and vehicle:getAIRootNode()
		or (type(vehicle.getAIDirectionNode)=="function" and vehicle:getAIDirectionNode()) or vehicle.acRefNode
	if node and targetX and targetZ and type(vehicle.getSteeringRotTimeByCurvature)=="function" then
		local _,y,_=getWorldTranslation(node)
		local x,_,z=worldToLocal(node,targetX,y,targetZ)
		local lengthSq=x*x+z*z
		if z>0.25 and lengthSq>0.25 then
			local rotTime=vehicle:getSteeringRotTimeByCurvature(2*x/lengthSq)
			if type(rotTime)=="number" and rotTime==rotTime and math.abs(rotTime)<math.huge then
				if type(vehicle.getReverserDirection)=="function" and vehicle:getReverserDirection()<0 then rotTime=-rotTime end
				local limit=rotTime>=0 and vehicle.maxRotTime or -(vehicle.minRotTime or -1)
				if limit and limit>1e-4 then wanted=-rotTime/limit end
			end
		end
	end
	local direction=type(vehicle.getSteeringDirection)=="function" and vehicle:getSteeringDirection() or 1
	if math.abs(direction)<1e-4 then direction=1 end
	wanted=wanted/direction
	wanted=AIVEUtils.clamp(wanted,-1,1)
	local elapsed=math.max(dt or 0,0)
	local filtered=vehicle.aiveAutoSteerFilteredAxis
	if filtered==nil then filtered=wanted else filtered=filtered+(wanted-filtered)*(1-math.exp(-elapsed/90)) end
	vehicle.aiveAutoSteerFilteredAxis=filtered
	local previous=vehicle.aiveAutoSteerAxis
	if previous==nil then
		local rotated=vehicle.rotatedTime or 0
		local limit=rotated>=0 and vehicle.maxRotTime or -(vehicle.minRotTime or -1)
		previous=limit and limit>1e-4 and -rotated/limit/direction or 0
	end
	local speed=AIVEWheelUtils.getAISteeringSpeed(vehicle)
	local limit=math.max(math.abs(vehicle.maxRotTime or 1),math.abs(vehicle.minRotTime or -1),1e-4)
	local step=elapsed*speed/limit
	local axis=AIVEUtils.clamp(filtered,previous-step,previous+step)
	vehicle.aiveAutoSteerAxis=axis
	return axis
end

function AIVehicleExtension:newUpdateVehiclePhysics( superFunc, axisForward, axisSide, doHandbrake, dt )
	if self.aiveAutoSteer and AIVehicleExtension.isNativeSteeringSelected(self) then
		AIVehicleExtension.setInt32Value(self,"autoSteer",0)
	end

	if self.isServer and self.aiveAutoSteer then 	
		self.acParameters.straight = false 
		AIVehicleExtension.checkState( self )
		
		local doit = true  
		if self.acTurnStage ~= 199 then
			self.acTurnStage = 198
		end
		
		if not AutoSteeringEngine.hasTools( self ) then
			self.acTurnStage = 0
			AIVehicleExtension.setStatus( self, 0 )
			doit = false 
			self.aiveAutoSteerAxis,self.aiveAutoSteerFilteredAxis=nil,nil
		end

		if doit then 
			local fruitsDetected, fruitsAll = AutoSteeringEngine.hasFruits( self )
			local fruitsAdvance = fruitsDetected
			if not fruitsAdvance and AutoSteeringEngine.hasFruits( self, true ) then
				fruitsAdvance = true
			end
			
			local isMovedDown = AIVehicleExtension.getIsLoweredServer( self )
			
		--==============================================================		
			if fruitsAdvance and self.acImplementsMoveDown then
			--AutoSteeringEngine.getIsAIReadyForWork( self )
			end
				
			local vX,vY,vZ = getWorldTranslation( self.acRefNode )
			AutoSteeringEngine.setAiWorldPosition( self, vX, vY, vZ )
			
			local inField, target, angleFactor, nilAngle

			if self.acTurnStage == 199 then
				inField     = true
				angleFactor = self.acParameters.angleFactor
			--nilAngle    = "L"
				
			--if	   self.turnTimer < 0 
			--		or AutoSteeringEngine.getIsAtEnd( self ) then
			--	target = math.min( math.max( 0.5 * AutoSteeringEngine.getTurnAngle(self), -self.acDimensions.maxSteeringAngle ), self.acDimensions.maxSteeringAngle )
			--	if AutoSteeringEngine.getNoReverseIndex( self ) <= 0 then
			--		target = math.max( target, 0 )
			--	end
			--	if not self.acParameters.leftAreaActive then
			--		target = -target
			--	end
			--end
			else
				inField     = false
				angleFactor = 1
			--nilAngle    = "M"
			end
			
			local detected, angle, border, tX, _, tZ, dist
			
			if fruitsAdvance then 
				detected, angle, border, tX, _, tZ, dist = AutoSteeringEngine.processChain( self, inField, target, angleFactor, nilAngle )	
			else 
				detected, angle, border, tX, _, tZ, dist = false, 0, 0, 0, 0 
			end 
			
		--==============================================================						
				
			self.turnTimer = self.turnTimer - dt
			
			if fruitsDetected and detected and border <= 0 then
				AIVehicleExtension.setStatus( self, 1 )
				if self.acTurnStage ~= 199 then
					self.acTurnStage = 199
					AutoSteeringEngine.clearTrace( self )
					AutoSteeringEngine.saveDirection( self, false, false, true )
				elseif AutoSteeringEngine.getIsAtEnd( self ) then
					if not self.acParameters.leftAreaActive then
						angle = math.max( angle, 0 )
					else
						angle = math.min( angle, 0 )
					end
				end
				AutoSteeringEngine.saveDirection( self, true, true, true )
				self.turnTimer = self.acDeltaTimeoutRun
			elseif self.acTurnStage == 199 and self.turnTimer >= 0 then
				if border > 0 then
					AIVehicleExtension.setStatus( self, 3 )
				else
					if AutoSteeringEngine.getIsAtEnd( self ) then
						if not self.acParameters.leftAreaActive then
							angle = math.max( angle, 0 )
						else
							angle = math.min( angle, 0 )
						end
					end
					if fruitsDetected then
						self.turnTimer = self.acDeltaTimeoutRun
					end			
					AIVehicleExtension.setStatus( self, 2 )
				end
			else
				if self.acTurnStage == 199 and border <= 0 then
					self:setCruiseControlState( Drivable.CRUISECONTROL_STATE_OFF )
				end

				if border > 0 then
					AIVehicleExtension.setStatus( self, 3 )
				else
					AIVehicleExtension.setStatus( self, 2 )
				end
				
				self.acTurnStage = 198
			end
						
			if     self.acAxisSideFactor == nil then
				self.acAxisSideFactor = 0
			elseif self:getIsEntered() and math.abs( self.acAxisSide ) > 0 then
				self.acAxisSideFactor = math.max( self.acAxisSideFactor - dt, 0 )
			elseif self.movingDirection < -1E-2 or not self.acImplementsMoveDown then	
				self.acAxisSideFactor = math.max( self.acAxisSideFactor - dt, 0 )
			elseif not detected then
				self.acAxisSideFactor = math.max( self.acAxisSideFactor - dt, 0 )
			elseif border > 0 then 
				self.acAxisSideFactor = math.min( self.acAxisSideFactor + 10 * dt, 1000 )
			elseif not detected then 
				self.acAxisSideFactor = math.max( self.acAxisSideFactor - dt, 0 )
			else
				self.acAxisSideFactor = math.min( self.acAxisSideFactor + dt, 1000 )
			end
			
			local f = 0.001 * self.acAxisSideFactor
			
			local useTarget=detected and border<=0 and self.acTurnStage==199
			local newAxisSide=AIVehicleExtension.getAutoSteerAxis(self,angle,useTarget and tX or nil,useTarget and tZ or nil,dt)
	
			if     f <= 0 then
				newAxisSide = axisSide
				self.aiveAutoSteerAxis,self.aiveAutoSteerFilteredAxis=nil,nil
			elseif f  < 1 then
				newAxisSide = (1-f) * axisSide + f * newAxisSide
			end
			
			axisSide = AIVEUtils.clamp( newAxisSide, -1, 1)		
		end
		
		self.lastAxisSide = axisSide 
	else
		self.aiveAutoSteerAxis,self.aiveAutoSteerFilteredAxis=nil,nil
	end

	return superFunc( self, axisForward, axisSide, doHandbrake, dt )
end

if Drivable ~= nil and Drivable.updateVehiclePhysics ~= nil then
	Drivable.updateVehiclePhysics = Utils.overwrittenFunction( Drivable.updateVehiclePhysics, AIVehicleExtension.newUpdateVehiclePhysics )
end

------------------------------------------------------------------------
-- getSaveAttributesAndNodes
------------------------------------------------------------------------

function AIVehicleExtension:saveToXMLFile(xmlFile, key)
	for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
		if attr.always or self.acParameters[attr.name] ~= attr.default then			
			xmlFile:setValue(key .. "#" .. attr.xml, self.acParameters[attr.name])
		end
	end
	if self.aiveSavedGroup then
		xmlFile:setValue(key.."#groupWorkKey",self.aiveSavedGroup.key)
		xmlFile:setValue(key.."#groupWorkArea",self.aiveSavedGroup.area)
	end
end

------------------------------------------------------------------------
-- loadFromAttributesAndNodes
------------------------------------------------------------------------
function AIVehicleExtension:onPostLoad(savegame)
	if savegame ~= nil then
		local groupKey=savegame.xmlFile:getValue(savegame.key.."."..AIVehicleExtensionRegister.specName.."#groupWorkKey")
		local groupArea=savegame.xmlFile:getValue(savegame.key.."."..AIVehicleExtensionRegister.specName.."#groupWorkArea")
		if type(groupKey)=="string" and type(groupArea)=="number" and groupArea>0 then self.aiveSavedGroup={key=groupKey,area=groupArea} end
		for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
			local v = savegame.xmlFile:getValue(savegame.key .. "." .. AIVehicleExtensionRegister.specName .. "#" .. attr.xml )
			if v ~= nil then 
				self.acParameters[attr.name] = v 
			end 
		end		
		
		self.acParameters.leftAreaActive	= not self.acParameters.rightAreaActive
		self.acParameters.precision = math.min(2,math.max(0,self.acParameters.precision or 1))
		if self.acParameters.circleLands then self.acParameters.upNDown=false;self.acParameters.straight=false end
		self.acDimensions								  = nil
	end
end

------------------------------------------------------------------------
-- calculateDimensions
------------------------------------------------------------------------
function AIVehicleExtension.calculateDimensions( self )
	if self.aiToolsDirtyFlag then
		self.acDimensions = nil
		return
	elseif self.acDimensions ~= nil then
		return
	end

	self.acDimensions            = {}
	self.acDimensions.zOffset    = 0
	self.acDimensions.acRefNodeZ = 0

	-- In FS25, the AI helper does not bind to self.maxTurningRadiusWheel, and wheel properties live in wheel.physics.
	-- We use AIVEWheelUtils.computeVehicleKinematics to accurately compute maxSteeringAngle, radius, and wheelBase.
	if AIVEWheelUtils ~= nil and AIVEWheelUtils.computeVehicleKinematics ~= nil then
		local maxSteer, rad, wb = AIVEWheelUtils.computeVehicleKinematics(self, self.acRefNode)
		self.acDimensions.maxSteeringAngle = maxSteer
		self.acDimensions.radius           = rad
		self.acDimensions.wheelBase        = wb
	else
		local r = self.maxRotation or 25
		if r < 2 then r = math.deg(r) end
		self.acDimensions.maxSteeringAngle = math.rad(math.min(r, 60))
		self.acDimensions.radius           = AIVEUtils.getNoNil(self.maxTurningRadius, 6) * 1.1
		self.acDimensions.wheelBase        = math.tan(self.acDimensions.maxSteeringAngle) * self.acDimensions.radius
	end

	self.acDimensions.artAxisR = 0
	self.acDimensions.artAxisX = 0
	self.acDimensions.artAxisZ = 0

	self.acDimensions.wheelParents = {}
	local wheels = AIVEWheelUtils ~= nil and AIVEWheelUtils.getWheelsList(self) or (self.spec_wheels and self.spec_wheels.wheels or {})
	for _, wheel in pairs(wheels) do
		local dNode = AIVEWheelUtils ~= nil and AIVEWheelUtils.getWheelDriveNode(wheel) or wheel.driveNode
		if dNode ~= nil and dNode ~= 0 then
			local ok, node = pcall(getParent, dNode)
			if ok and node ~= nil and node ~= 0 then
				self.acDimensions.wheelParents[node] = (self.acDimensions.wheelParents[node] or 0) + 1
			end
		end
	end

	AIVehicleExtension.debugPrint( self, string.format("FS25 kinematics -> wb: %0.3fm, r: %0.3fm, maxSteer: %0.1f deg, z: %0.3fm",
		self.acDimensions.wheelBase, self.acDimensions.radius, math.deg(self.acDimensions.maxSteeringAngle), self.acDimensions.acRefNodeZ ))
end

------------------------------------------------------------------------
-- getHeadlandSmallBig
------------------------------------------------------------------------
function AIVehicleExtension:getHeadlandSmallBig()
	if self.acDimensions == nil then
		AIVehicleExtension.calculateDimensions( self )
	end
	AIVehicleExtension.calculateDistances( self )
	local nri   = AutoSteeringEngine.getNoReverseIndex( self )
  local small = AIVehicleExtension.calculateHeadland( self.acTurnMode, self.acDimensions.distance, 
																											self.acDimensions.zBack, self.acDimensions.toolDistance, self.acDimensions.frontToBack,
																											self.acDimensions.radius, self.acDimensions.radius75, self.acDimensions.wheelBase, false, nri )
	local big   = AIVehicleExtension.calculateHeadland( self.acTurnMode, self.acDimensions.distance, 
																											self.acDimensions.zBack, self.acDimensions.toolDistance, self.acDimensions.frontToBack,
																											self.acDimensions.radius, self.acDimensions.radius75, self.acDimensions.wheelBase, true,  nri )
	
	return small, big
end

------------------------------------------------------------------------
-- calculateHeadland
------------------------------------------------------------------------
function AIVehicleExtension.calculateHeadland( turnMode, realWidth, zBack, toolDist, frontToBack, radius, radius75, wheelBase, big, noRevIdx )

	local width = 1.5
	if big then
		if realWidth ~= nil and realWidth > width then
			width = realWidth
		end
		width = width + 2
	end
	
--local frontToBack = 1
--if noRevIdx ~= nil and noRevIdx <= 0 and turnMode == "T" then
--	frontToBack = math.max( -zBack, 1 )
--elseif big then
--	frontToBack = math.max( toolDist - zBack, 1 )
--end
	
	
	local ret = 0
	if		 turnMode == "A"
			or turnMode == "L" then
	--ret	 = math.max( 2, toolDist ) + math.abs( wheelBase ) + math.abs( zBack ) + frontToBack
		ret	 = 1 + math.max( frontToBack - toolDist + math.abs( wheelBase ) + 1, 
												 - toolDist - zBack )
		if big then
			ret = ret + 3
		end
		ret	 = math.max( ret, width ) 
	elseif turnMode == "C" then
		ret	 = width + math.max( -zBack, 0 ) + radius
	else
		local r = radius
		local z = 0
	--if turnMode == "O" or turnMode == "8" then
	--	r = 0.5 * ( radius + radius75 )
	--end 
		if turnMode == "O" then -- or turnMode == "8" then
			local beta = math.acos( math.min(math.max(realWidth / r, 0),1) )
			z	= 2.2 * radius * math.sin( beta )
			if big then
				z = z + 1.1
			end
		end
		ret	= width + r + math.max( frontToBack - toolDist + z, toolDist )
	end
	
	if ret < 0 then
		ret = 0
	end
	
	return ret
end

------------------------------------------------------------------------
-- calculateDistances
------------------------------------------------------------------------
function AIVehicleExtension.calculateDistances( self )

	self.acDimensions.distance		 = 99
	self.acDimensions.toolDistance = 99
	
	local rd = false 
	if self.spec_reverseDriving ~= nil and self.spec_reverseDriving.isReverseDriving then
		rd = true 
	end 
	
	AutoSteeringEngine.checkChain( self, self.acRefNode, self.acDimensions.wheelBase, self.acDimensions.maxSteeringAngle, self.acDimensions.radius,
																 self.acParameters.widthOffset, self.acParameters.turnOffset, rd, 
																 self.acParameters.useAIFieldFct, self.acParameters.precision )

	self.acDimensions.distance, self.acDimensions.toolDistance, self.acDimensions.zBack, self.acDimensions.frontToBack, self.acDimensions.radius75 
								= AutoSteeringEngine.checkTools( self )
	
	self.acDimensions.distance0				= self.acDimensions.distance
	if self.acParameters.widthOffset ~= nil then
		self.acDimensions.distance			= self.acDimensions.distance0 + self.acParameters.widthOffset
	end
	
	local optimDist = self.acDimensions.distance
	if self.acDimensions.radius > optimDist then
		self.acDimensions.uTurnAngle		 = math.acos( optimDist / self.acDimensions.radius )
	else
		self.acDimensions.uTurnAngle		 = 0
	end

	self.acDimensions.insideDistance = math.max( 0, self.acDimensions.toolDistance - 1 - self.acDimensions.distance +(self.acDimensions.radius * math.cos( self.acDimensions.maxSteeringAngle )) )
	self.acDimensions.uTurnDistance	= math.max( 0, self.acDimensions.toolDistance, self.acDimensions.distance - self.acDimensions.radius )
	self.acDimensions.headlandDist	 = AIVehicleExtension.calculateHeadland( self.acTurnMode, self.acDimensions.distance, 
																					self.acDimensions.zBack, self.acDimensions.toolDistance, self.acDimensions.frontToBack, 
																					self.acDimensions.radius, self.acDimensions.radius75, self.acDimensions.wheelBase, self.acParameters.bigHeadland, 
																					AutoSteeringEngine.getNoReverseIndex( self ) )
	self.acDimensions.collisionDist	= 1 + AIVehicleExtension.calculateHeadland( self.acTurnMode, math.max( self.acDimensions.distance, 1.5 ), 
																					self.acDimensions.zBack, self.acDimensions.toolDistance, self.acDimensions.frontToBack,
																					self.acDimensions.radius, self.acDimensions.radius75, self.acDimensions.wheelBase, self.acParameters.bigHeadland,
																					AutoSteeringEngine.getNoReverseIndex( self ) )
	self.acDimensions.uTurnDist4x   = 1 + math.max( math.max( self.acDimensions.toolDistance - self.acDimensions.radius, self.acDimensions.distance ) - self.acDimensions.radius, 0 )
	--if self.acShowDistOnce == nil then
	--	self.acShowDistOnce = 1
	--else
	--	self.acShowDistOnce = self.acShowDistOnce + 1
	--end
	--if self.acShowDistOnce <= 30 then
	--	AIVehicleExtension.debugPrint( self, string.format("max( %0.3f , 1.5 ) + max( - %0.3f, 0 ) + max( %0.3f - %0.3f, 1 ) + %0.3f = %0.3f", self.acDimensions.distance, zBack, self.acDimensions.toolDistance, zBack, self.acDimensions.radius, self.acDimensions.headlandDist ) )
	--end
	
	if self.acParameters.turnOffset ~= nil then
		self.acDimensions.insideDistance = math.max( 0, self.acDimensions.insideDistance + self.acParameters.turnOffset )
		self.acDimensions.uTurnDistance	 = math.max( 0, self.acDimensions.uTurnDistance	 + self.acParameters.turnOffset )
		self.acDimensions.headlandDist	 = math.max( 0, self.acDimensions.headlandDist	 + self.acParameters.turnOffset )
		self.acDimensions.collisionDist	 = math.max( 0, self.acDimensions.collisionDist	 + self.acParameters.turnOffset )
		self.acDimensions.uTurnDist4x    = self.acDimensions.uTurnDist4x + self.acParameters.turnOffset
	end
	
	self.acDimensions.headlandCount = 0
	if self.acDimensions.distance > 0 then
		local w = self.acDimensions.distance + self.acDimensions.distance
		self.acDimensions.headlandCount	= math.ceil( ( self.acDimensions.headlandDist ) / w )
		--self.acDimensions.headlandDist	 = w * self.acDimensions.headlandCount
	end
	--self.acDimensions.headlandDist		 = math.min( math.max( self.acDimensions.headlandDist, 0 ), AIVEGlobals.chainMinLen )
end

------------------------------------------------------------------------
-- Manually switch to next turn stage
------------------------------------------------------------------------
function AIVehicleExtension:setNextTurnStage(noEventSend)
	local spec = self.spec_aiFieldWorker

	if self.isServer and spec.driveStrategies ~= nil then
		for i,d in pairs( spec.driveStrategies ) do
			if type( d.gotoNextStage ) == "function" then
				d:gotoNextStage()
			end
		end
	end

	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(AIVENextTSEvent.new(self), nil, nil, self)
		else
			g_client:getServerConnection():sendEvent(AIVENextTSEvent.new(self))
		end
	end
end

function AIVehicleExtension:setIsReverseDriving( isReverseDriving, noEventSend )
	if self.acParameters ~= nil then
		self.acParameters.inverted = isReverseDriving
		AIVehicleExtension.sendParameters( self )
	end
end

------------------------------------------------------------------------
-- Event stuff
------------------------------------------------------------------------
function AIVehicleExtension.getParameterDefaults()
	parameters = {}

	for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
		parameters[attr.name] = attr.default
	end
	parameters.leftAreaActive	= not parameters.rightAreaActive

	return parameters
end

function AIVehicleExtension:getParameters()
	if self.acParameters == nil then
		self.acParameters = AIVehicleExtension.getParameterDefaults( )
	end
	self.acParameters.leftAreaActive	= not self.acParameters.rightAreaActive

	return self.acParameters
end

function AIVehicleExtension.readStreamHelper(streamId)
	print('Receiving parameters...')

	local parameters = {}
	
	for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
		if		 attr.valueType == XMLValueType.BOOL then
			parameters[attr.name] = streamReadBool(streamId)
		elseif attr.valueType == XMLValueType.INT then
			parameters[attr.name] = streamReadInt8(streamId)
		else--if attr.valueType == XMLValueType.FLOAT then
			parameters[attr.name] = streamReadFloat32(streamId)
		end

		print( '  self.acParameters.'..tostring(attr.name)..': "'..tostring(parameters[attr.name])..'"' )
	end 
		
	return parameters
end

function AIVehicleExtension.writeStreamHelper(streamId, parameters)
	print('Sending parameters...')
	
	for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
		print( '  self.acParameters.'..tostring(attr.name)..': "'..tostring(parameters[attr.name])..'"' )

		if		 attr.valueType == XMLValueType.BOOL then
			streamWriteBool(streamId, AIVEUtils.getNoNil( parameters[attr.name], attr.default ))
		elseif attr.valueType == XMLValueType.INT then
			streamWriteInt8(streamId, AIVEUtils.getNoNil( parameters[attr.name], attr.default ))
		else--if attr.valueType == XMLValueType.FLOAT then
			streamWriteFloat32(streamId, AIVEUtils.getNoNil( parameters[attr.name], attr.default ))
		end
	end
end

local AIVESetParametersdLog = 0
function AIVehicleExtension:setParameters(parameters)

	if self == nil then
		if AIVESetParametersdLog < 10 then
			AIVESetParametersdLog = AIVESetParametersdLog + 1
			print("------------------------------------------------------------------------")
			print("AIVehicleExtension:setParameters: self == nil")
			AIVEHud.printCallstack()
			print("------------------------------------------------------------------------")
		end
		return
	end

	local turnOffset = 0
	if self.acParameters ~= nil and self.acParameters.turnOffset ~= nil then
		turnOffset = self.acParameters.turnOffset
	end
	local widthOffset = 0
	if self.acParameters ~= nil and self.acParameters.widthOffset ~= nil then
		widthOffset = self.acParameters.widthOffset
	end
	
	self.acParameters = {}
	for _,attr in pairs( AIVehicleExtension.saveAttributesMapping ) do
		self.acParameters[attr.name] = AIVEUtils.getNoNil( parameters[attr.name], attr.default )
	end

	self.acParameters.leftAreaActive	= not self.acParameters.rightAreaActive
end

function AIVehicleExtension:onReadStream(streamId, connection)
	AIVehicleExtension.setParameters( self, AIVehicleExtension.readStreamHelper(streamId) )
end

function AIVehicleExtension:onWriteStream(streamId, connection)
	AIVehicleExtension.writeStreamHelper(streamId,AIVehicleExtension.getParameters(self))
end

function AIVehicleExtension:onReadUpdateStream(streamId, timestamp, connection)
  if connection:getIsServer() then
		if streamReadBool( streamId ) then
			self.acTurnStage = streamReadUInt8( streamId ) - 10
			self.acAxisSide  = streamReadInt8( streamId ) * 0.01
		end
  end 
end 

function AIVehicleExtension:onWriteUpdateStream(streamId, connection, dirtyMask)
  if not connection:getIsServer() then
		if self.aiveIsStarted or self.aiveAutoSteer then
			streamWriteBool(streamId, true )
			streamWriteUInt8(streamId, AIVEUtils.clamp( 10 + self.acTurnStage, 0, 255 ) )
			streamWriteInt8(streamId, math.floor( AIVEUtils.clamp( 0.5 + 100 * self.acAxisSide, -100, 100 ) ) )
		else
			streamWriteBool(streamId, false )
		end
	end 
end 

function AIVehicleExtension:sendParameters(noEventSend)
	if self.acDimensions ~= nil then
		AIVehicleExtension.calculateDistances( self )
	end

	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(AIVEParametersEvent.new(self, AIVehicleExtension.getParameters(self)), nil, nil, self)
		else
			g_client:getServerConnection():sendEvent(AIVEParametersEvent.new(self, AIVehicleExtension.getParameters(self)))
		end
	end
end


if AIVEGlobals.devFeatures > 0 then
	addConsoleCommand("acReset", "Reset global AIVehicleExtension variables to defaults.", "acReset", AIVehicleExtension)
end
function AIVehicleExtension:acReset()
	AutoSteeringEngine.globalsReset()
	AutoSteeringEngine.resetCounter = AutoSteeringEngine.resetCounter + 1
	for name,value in pairs(AIVEGlobals) do
		print(tostring(name).." "..tostring(value))		
	end
end

-- acSave
if AIVEGlobals.devFeatures > 0 then
	addConsoleCommand("acSave", "Save the global AIVehicleExtension variables.", "acSave", AIVehicleExtension)
end
function AIVehicleExtension:acSave()
	AutoSteeringEngine.globalsCreate()	
	for name,value in pairs(AIVEGlobals) do
		print(tostring(name).." "..tostring(value))		
	end
end

-- acSet
if AIVEGlobals.devFeatures > 0 then
	addConsoleCommand("acSet", "Change one of the global AIVehicleExtension variables.", "acSet", AIVehicleExtension)
end
function AIVehicleExtension:acSet(name,svalue)

	local value
	if svalue ~= nil then
		value = tonumber( svalue )
	end
	
	print("acSet "..tostring(name).." "..tostring(value))

	local found = false
	
	local old=nil
	for n,o in pairs(AIVEGlobals) do
		if n == name then
			found = true
			old	 = o
			break
		end
	end
	
	if found then
		if value == nil or old == new then
			print(tostring(AIVEGlobals[name]))
		else
			AIVEGlobals[name]=value
			print("Old value: "..tostring(old).." new value: "..tostring(value))
			AutoSteeringEngine.resetCounter = AutoSteeringEngine.resetCounter + 1
		end
	else
		print("Usage: acSet <name> <value>")
		print("Possible names are:")
		
		for n,old in pairs(AIVEGlobals) do
			print("	" .. n .. ": "..tostring(AIVEGlobals[n]))
		end
	end
	
end

-- acDump
if AIVEGlobals.devFeatures > 0 then
	addConsoleCommand("acDump", "Dump internal state of AIVehicleExtension", "acDump", AIVehicleExtension)
end
function AIVehicleExtension:acDump()
	atDump = true
end

function AIVehicleExtension:acDump2()	
	atDump = nil
	for i=1,AIVEGlobals.chainMax+1 do
		local text = string.format("i: %i, a: %i",i,self.aseChain.nodes[i].angle)
		if self.aseChain.nodes[i].status >=	1 then
			text = text .. string.format(" s: %i",math.deg( self.aseChain.nodes[i].steering ))
		end
		if self.aseChain.nodes[i].status >=	2 then
			text = text .. string.format(" r: %i",math.deg( self.aseChain.nodes[i].rotation ))
		end
		if self.aseChain.nodes[i].status >=	3 then
			for j=1,table.getn(self.aseTools) do
				if			self.aseChain.nodes[i].tool[j]	 ~= nil 
						and self.aseChain.nodes[i].tool[j].x ~= nil 
						and self.aseChain.nodes[i].tool[j].z ~= nil then
					local x1,y1,z1 = localToWorld( self.aseChain.nodes[i].index, self.aseChain.nodes[i].tool[j].x, 0, self.aseChain.nodes[i].tool[j].z )
					local x2,y2,z2 = worldToLocal( self.aseChain.refNode, x1, y1, z1 )
					text = text .. string.format( " x: %0.3f z: %0.3f",x2,z2)							
				end
			end
		end
		
		print(text)
	end
end

--==============================================================				
--==============================================================			
------------------------------------------------------------------------
-- AIVehicleExtension:detectAngle
------------------------------------------------------------------------
function AIVehicleExtension:detectAngle( smooth )
	return AutoSteeringEngine.processChain( self, ( self.acTurnStage == 0 or self.acTurnStage == 199 ) )
end

------------------------------------------------------------------------
-- AIVehicleExtension:getMaxAngleWithTool
------------------------------------------------------------------------
function AIVehicleExtension:getMaxAngleWithTool( outside, wide )
	
	if AutoSteeringEngine.getNoReverseIndex( self ) <= 0 then
		if outside then
			return -self.acDimensions.maxSteeringAngle
		end
		return self.acDimensions.maxSteeringAngle
	end
	
	local turn75 = AutoSteeringEngine.getMaxSteeringAngle75( self )
	local angle
	local toolAngle = AutoSteeringEngine.getToolAngle( self )	
	if not self.acParameters.leftAreaActive then
		toolAngle = -toolAngle
	end
	
	local maxToolAngle = AutoSteeringEngine.getMaxToolAngle( self )
	local maxAngle     = self.acDimensions.maxSteeringAngle
	local extremeTA    = math.pi * 0.5
	local extremeAngle = -self.acDimensions.maxSteeringAngle
	local targetAngle  = turn75.alpha
	local midAngle     = math.min(1.1*targetAngle,maxAngle)

	if wide then 
		maxAngle         = turn75.alpha
	end 	
	if outside then 
		maxToolAngle = -maxToolAngle 
		maxAngle     = -maxAngle 
		extremeTA    = -extremeTA
		extremeAngle = -extremeAngle
		targetAngle  = -targetAngle 
		midAngle     = -midAngle
	end 
	
	angle = AIVEUtils.interpolate( toolAngle,{{ 0,                maxAngle },
																						{ 0.8*maxToolAngle, midAngle },
																						{ 0.97*maxToolAngle,targetAngle },
																						{ 1.03*maxToolAngle,0.5*targetAngle },
																						{ 1.1*maxToolAngle, 0 },
																						{	extremeTA,        extremeAngle }} )
	
--local f = 2
--if AutoSteeringEngine.hasArticulatedAxis( self ) then
--	f = 1
--end
--
--if outside then
--	angle = AIVEUtils.clamp( -turn75.alpha + f * ( -toolAngle - maxToolAngle ), -self.acDimensions.maxSteeringAngle, 0 )
--else                                                                                                   
--	angle = AIVEUtils.clamp(  turn75.alpha - f * (  toolAngle - maxToolAngle ), 0, self.acDimensions.maxSteeringAngle )
--end
	
	if AIVEGlobals.devFeatures > 0 then -- and math.abs( toolAngle ) >= maxToolAngle - 0.01745 then
		self:acDebugPrint( string.format("Tool angle: ts: %d a: %0.1f° mt: %0.1f° ms: %0.1f° to: %0.1f°", self.acTurnStage, math.deg(angle), math.deg(maxToolAngle), math.deg(self.acDimensions.maxSteeringAngle), math.deg(toolAngle) ) )
	end
	
	return angle
end

------------------------------------------------------------------------
-- AIVehicleExtension:waitForAnimTurnStage
------------------------------------------------------------------------
function AIVehicleExtension:waitForAnimTurnStage( turnStage )
	if     turnStage <  0
			or ( turnStage == 0 and AIVEGlobals.raiseNoFruits > 0 )
			or turnStage == 3
			or turnStage == 8
			or turnStage == 26 or turnStage == 27
			or turnStage == 38
			or turnStage == 48 or turnStage == 49
			or turnStage == 59 or turnStage == 60 or turnStage == 61 
			or turnStage == 77 or turnStage == 78 or turnStage == 79 then
		return true
	end
	return false
end			

------------------------------------------------------------------------
-- AIVehicleExtension:checkCorrectField
------------------------------------------------------------------------
function AIVehicleExtension:checkIsCorrectField()
--local wx,_,wz = localToWorld( self.aseChain.refNode, 0.5 * ( self.aseActiveX + self.aseOtherX ), 0, 0.5 * ( self.aseStart + self.aseDistance ) )
--if self.aseCurrentField ~= nil and not AutoSteeringEngine.checkField( self, wx, wz ) then
--	local checkFunction, areaTotalFunction = AutoSteeringEngine.getCheckFunction( self )
--	if AutoSteeringEngine.checkFieldNoBuffer( wx, wz, checkFunction ) then
--		return false 
--	end
--end
	
	return true
end

------------------------------------------------------------------------
-- AIVehicleExtension:stopWaiting
------------------------------------------------------------------------
function AIVehicleExtension:stopWaiting( angle )
	local a
	if self.acParameters.leftAreaActive then
		a = angle 
	else	 
		a = -angle 
	end
	
	local rd = false 
	if self.spec_reverseDriving ~= nil and self.spec_reverseDriving.isReverseDriving then
		rd = true 
	end 
	if math.abs( a - AutoSteeringEngine.currentSteeringAngle( self, rd ) ) < 0.05236 then -- 3° 
		return true 
	end
	return false
end

------------------------------------------------------------------------
-- AIVehicleExtension:navigationFallbackRetry
------------------------------------------------------------------------
function AIVehicleExtension:navigationFallbackRetry( uTurn )
	local x, z, allowedToDrive = AIVehicleExtension.getTurnVector( self, uTurn )
	local a = AutoSteeringEngine.normalizeAngle( math.pi - AutoSteeringEngine.getTurnAngle( self )	)
	local angle = 0

	if z < 1 and math.abs( a ) > 0.9 * math.pi then
		angle = 0
	elseif x > 0 then
		-- D: turn away from target point for next try
		angle = -self.acDimensions.maxSteeringAngle
	else
		-- E: turn away from target point for next try
		angle =  self.acDimensions.maxSteeringAngle
	end
	
	return angle
end

------------------------------------------------------------------------
-- AIVehicleExtension:navigationFallbackRotateMinus
------------------------------------------------------------------------
function AIVehicleExtension:navigationFallbackRotateMinus( uTurn )
	local angle = -self.acDimensions.maxSteeringAngle					
	if not self.acParameters.leftAreaActive then
		angle = -angle		
	end	
	return angle
end

------------------------------------------------------------------------
-- AIVehicleExtension:getTurnVector
------------------------------------------------------------------------
function AIVehicleExtension:getTurnVector( uTurn, turn2Outside )

	local x, z = AutoSteeringEngine.getTurnVector( self, AIVEUtils.getNoNil( uTurn, false ), AIVEUtils.getNoNil( turn2Outside, false ) )
 
	return x, z, true
end

------------------------------------------------------------------------
-- AIVehicleExtension:getToolAngle
------------------------------------------------------------------------
function AIVehicleExtension:getToolAngle()

	local toolAngle = AutoSteeringEngine.getToolAngle( self )
	if not self.acParameters.leftAreaActive then
		toolAngle = -toolAngle
	end
	
	return toolAngle
end
	
------------------------------------------------------------------------
-- AIVehicleExtension:getStraighBackwardsAngle
------------------------------------------------------------------------
function AIVehicleExtension:getStraighBackwardsAngle( iTarget )

	local target = math.rad( AIVEUtils.getNoNil( iTarget, 0 ) )

	local turnAngle = AutoSteeringEngine.getTurnAngle( self ) 
	if self.acParameters.leftAreaActive then
		turnAngle = -turnAngle
	end
	
	local ta  = turnAngle
	turnAngle = AutoSteeringEngine.normalizeAngle( turnAngle - target )
	
	self:acDebugPrint( "gSBA init: target: "..AutoSteeringEngine.degToString( iTarget ).." current: "..AutoSteeringEngine.radToString( ta ).." delta: "..AutoSteeringEngine.radToString( turnAngle ))
	
	return AIVehicleExtension.getStraighBackwardsAngle2( self, turnAngle, target )
end

------------------------------------------------------------------------
-- AIVehicleExtension:getStraighBackwardsAngle2
------------------------------------------------------------------------
function AIVehicleExtension:getStraighBackwardsAngle2( turnAngle, iTarget )
	
	local taJoints = AutoSteeringEngine.getTaJoints1( self, self.acRefNode, self.acDimensions.zOffset )

	if 	 	 AutoSteeringEngine.tableGetN( taJoints  ) < 1
			or self.aiveChain         == nil
			or self.aiveChain.trace   == nil
			or self.aiveChain.trace.a == nil then
		self:acDebugPrint( "gSBA: no tools with joint found: "..AutoSteeringEngine.radToString( -turnAngle ))
		local m = self.acDimensions.maxSteeringAngle
		return AIVEUtils.clamp( -turnAngle, -m, m )
	end

	local yv = -self.aiveChain.trace.a - math.pi
	if iTarget ~= nil then
		if self.acParameters.leftAreaActive then
			yv = AutoSteeringEngine.normalizeAngle( yv + iTarget )
		else
			yv = AutoSteeringEngine.normalizeAngle( yv - iTarget )
		end
	end
	
	local yt = AutoSteeringEngine.getWorldYRotation( taJoints[1].nodeTrailer )
	
	local maxToolAngle = AIVEGlobals.maxToolAngle
	
	local maxWorldRatio = 0.75 / AutoSteeringEngine.tableGetN( taJoints  )
	local ratio  = AIVEUtils.clamp( AutoSteeringEngine.normalizeAngle( yv - yt ) / maxToolAngle, -maxWorldRatio, maxWorldRatio )
	local target = ratio

	self:acDebugPrint( AutoSteeringEngine.radToString( yv ) .." - " ..AutoSteeringEngine.radToString( yt ) .." => "..string.format("ratio: %5.3f", ratio) )
	
	local sumTargetFactors = 0
	for _,joint in pairs( taJoints ) do
		sumTargetFactors = sumTargetFactors + joint.targetFactor
	end
	
	local maxToolDegrees = maxToolAngle / sumTargetFactors
	for _,joint in pairs( taJoints ) do
		target    = joint.targetFactor * ratio
		degree    = AutoSteeringEngine.getRelativeYRotation( joint.nodeVehicle, joint.nodeTrailer )
		self:acDebugPrint( "f: "..tostring(joint.targetFactor)
											.." / "..tostring(sumTargetFactors)
											..", d: "..AutoSteeringEngine.radToString(degree)
											..", t: "..AutoSteeringEngine.radToString(target))
		if joint.otherDirection then
			degree  = AutoSteeringEngine.normalizeAngle( degree + math.pi )
		end
		angle     = AIVEUtils.clamp( degree / maxToolDegrees, -1, 1 )	
		ratio     = AIVEUtils.clamp( target + 1.5 * ( angle - ratio ), -1, 1 )
	end
	
	if AutoSteeringEngine.hasArticulatedAxis( self, true, true ) then 
		ratio = AIVEUtils.clamp( ratio, -0.5, 0.5 )
	end 
	
	angle = ratio * self.acDimensions.maxSteeringAngle
	
	if not self.acParameters.leftAreaActive then
		angle = -angle 
	end
	
	self:acDebugPrint( "gSBA: current: "..AutoSteeringEngine.radToString( yt ).." target: "..AutoSteeringEngine.radToString( yv ).." => angle: "..AutoSteeringEngine.radToString( angle ).." ("..tostring( self.acParameters.leftAreaActive ).." / "..AutoSteeringEngine.radToString( iTarget ).." / "..AutoSteeringEngine.radToString( self.aiveChain.trace.a )..")")
	
	return angle 
end
	
------------------------------------------------------------------------
-- AIVehicleExtension:getIsLowered
------------------------------------------------------------------------
function AIVehicleExtension:getIsLoweredServer()
	if self.acImplementsMoveDown == nil then
		if self.acImplMoveDownTimer < g_currentMission.time then
			self.acImplMoveDownTimer   = g_currentMission.time + 250
			self.acImplementsMoveDown2 = AutoSteeringEngine.areToolsLowered( self )
		end
		return self.acImplementsMoveDown2
	end
	return self.acImplementsMoveDown
end

function AIVehicleExtension:getIsLowered()
	if     self.acIsLowered == 1 then
		return false
	elseif self.acIsLowered == 2 then
		return true 
	end
	return false 
end
	
------------------------------------------------------------------------
-- AIVehicleExtension:onChangeLowered
------------------------------------------------------------------------
function AIVehicleExtension:onChangeLowered( isLowered )
	if self.aiveIsStarted and isLowered and AIVEGlobals.devFeatures > 0 then 
		AIVehicleExtension.printCallstack() 
	end
	if  not self.aiveIsStarted 
			and self.acImplementsMoveDown ~= nil
			and self.acImplementsMoveDown ~= isLowered then
		self.acImplementsMoveDown = nil
		self.acImplMoveDownTimer  = 0
	end
end
	
------------------------------------------------------------------------
-- AIVehicleExtension:getToolAngle
------------------------------------------------------------------------
function AIVehicleExtension:getStraighForwardsAngle( iTarget )

	local target = math.rad( AIVEUtils.getNoNil( iTarget, 0 ) )

	local toolAngle = AutoSteeringEngine.getToolAngle( self )
	local turnAngle = AutoSteeringEngine.getTurnAngle( self ) 
	if self.acParameters.leftAreaActive then
		turnAngle = -turnAngle
	else
		toolAngle = -toolAngle
	end
	turnAngle = turnAngle - target 
	
	angle = 0
	
	if      math.abs( toolAngle ) > math.abs( turnAngle ) then
		angle = -toolAngle 
	else
		angle = turnAngle 
	end
	
	self:acDebugPrint( "gSFA: "..AutoSteeringEngine.degToString( iTarget ).." "..AutoSteeringEngine.radToString( toolAngle ).." "..AutoSteeringEngine.radToString( turnAngle ).." => "..AutoSteeringEngine.radToString( angle ))
	
	angle = AIVEUtils.clamp( angle, -self.acDimensions.maxSteeringAngle, self.acDimensions.maxSteeringAngle )

	return angle 
end
	
------------------------------------------------------------------------
-- AIVehicleExtension:getLimitedToolAngle
------------------------------------------------------------------------
function AIVehicleExtension:getLimitedToolAngle( iLimit )

	local toolAngle = AIVehicleExtension.getToolAngle( self )
	local limit     = AIVEUtils.getNoNil( iLimit, 0.5 * self.acDimensions.maxSteeringAngle )
	
	if     toolAngle >=  limit then
		toolAngle =  limit
	elseif toolAngle <= -limit then
		toolAngle = -limit
	else
		local x   = toolAngle / limit
		toolAngle = toolAngle * 2 / ( 1 + x^2 )
	end
	
	return toolAngle
end

------------------------------------------------------------------------
-- AIVehicleExtension:onStopAiVehicle
------------------------------------------------------------------------
function AIVehicleExtension:onStopAiVehicle()
	if self.aiveMainStrategy then self.aiveMainStrategy:checkpointJob() end
	self.acImplementsMoveDown = nil
	self.acImplMoveDownTimer  = 0
	self.acTurnStage          = 0
	self.aiveIsStarted        = false
	AIVehicleExtension.setStatus( self, 0 )
end

function AIVehicleExtension:onSetLowered(lowered)
	AIVehicleExtension.onChangeLowered( self, lowered )
end
function AIVehicleExtension:onLowerAll(doLowering)
	AIVehicleExtension.onChangeLowered( self, doLowering )
end
function AIVehicleExtension:onTurnedOn()
	AIVehicleExtension.onChangeLowered( self, true )
end
function AIVehicleExtension:onTurnedOff()
	AIVehicleExtension.onChangeLowered( self, false )
end
function AIVehicleExtension:setFoldState(direction, moveToMiddle)
	AIVehicleExtension.onChangeLowered( self, not ( moveToMiddle ) )
end

------------------------------------------------------------------------
-- AIVehicleExtension:stopCoursePlayMode2
------------------------------------------------------------------------
function AIVehicleExtension:stopCoursePlayMode2( stopCP )
	if      ( stopCP or self.acStopCP ) 
			and self.courseplayers       ~= nil
			and self.courseplayers[1]    ~= nil
			and self.courseplayers[1].cp ~= nil then
		
		if stopCP then
			if not ( self.courseplayers[1].cp.forcedToStop ) then
				self.courseplayers[1].cp.forcedToStop = true
				self.acStopCP = true
			end
		elseif self.acStopCP then
			self.acStopCP = nil
			self.courseplayers[1].cp.forcedToStop = false
		end
	end
end

--==============================================================				
--==============================================================			
function AIVehicleExtension:afterUpdateAIDriveStrategies()
	local spec = self.spec_aiFieldWorker
	if spec == nil then
		return
	end
	if AIVehicleExtension.isNativeSteeringSelected(self) then
		self.aiveIsStarted=false
		return
	end

	-- Do not override if Courseplay or AutoDrive is controlling the vehicle
	if AIVEConflictGuard ~= nil then
		local extActive, extMod = AIVEConflictGuard.isExternalAIActive(self)
		if extActive then
			AIVELogger.info("DriveStrategy", "Skipping AIVE strategy injection on '%s' because %s is active.", tostring(self:getName()), tostring(extMod))
			self.aiveIsStarted = false
			return
		end
	end

	if self.acParameters ~= nil and self.acParameters.enabled and spec.driveStrategies ~= nil and #spec.driveStrategies > 0 then
		local replacedMainStrategy = false
		for i, d in pairs( spec.driveStrategies ) do
			local driveStrategyMogli = nil
			local isStraightStrategy = (AIDriveStrategyStraight ~= nil and d.isa ~= nil and d:isa(AIDriveStrategyStraight))
				or (AIDriveStrategyFieldCourse ~= nil and d.isa ~= nil and d:isa(AIDriveStrategyFieldCourse))
				or (AIDriveStrategyFieldWorkCourse ~= nil and d.isa ~= nil and d:isa(AIDriveStrategyFieldWorkCourse))
			local isCombineStrategy = (AIDriveStrategyCombine ~= nil and d.isa ~= nil and d:isa(AIDriveStrategyCombine))
				or (AIDriveStrategyCombineCourse ~= nil and d.isa ~= nil and d:isa(AIDriveStrategyCombineCourse))

			if isStraightStrategy then
				driveStrategyMogli = AIDriveStrategyMogli.new()
				replacedMainStrategy = true
			elseif isCombineStrategy then
				driveStrategyMogli = AIDriveStrategyCombine131.new()
			end

			if driveStrategyMogli ~= nil then
				driveStrategyMogli:setAIVehicle(self)
				if spec.driveStrategies[i].delete ~= nil then
					pcall(function() spec.driveStrategies[i]:delete() end)
				end
				spec.driveStrategies[i] = driveStrategyMogli
			end
		end

		-- Fallback for FS25 if a new field strategy class name was used by the engine
		if not replacedMainStrategy then
			local targetIdx = #spec.driveStrategies
			if spec.driveStrategies[targetIdx] ~= nil and spec.driveStrategies[targetIdx].delete ~= nil then
				pcall(function() spec.driveStrategies[targetIdx]:delete() end)
			end
			local driveStrategyMogli = AIDriveStrategyMogli.new()
			driveStrategyMogli:setAIVehicle(self)
			spec.driveStrategies[targetIdx] = driveStrategyMogli
			AIVELogger.info("DriveStrategy", "Injected AIDriveStrategyMogli into slot %d for FS25 vehicle '%s'.", targetIdx, tostring(self:getName()))
		else
			AIVELogger.info("DriveStrategy", "Replaced FS25 fieldwork strategy with AIDriveStrategyMogli on '%s'.", tostring(self:getName()))
		end

		if AIVEGlobals.otherAIColli > 0 then
			local driveStrategyOtherAI = AIDriveStrategyCollisionOtherAI.new()
			driveStrategyOtherAI:setAIVehicle(self)
			table.insert( spec.driveStrategies, 1, driveStrategyOtherAI )
		end

		if not (self.aiveMainStrategy and self.aiveMainStrategy.resumedJob) then
			AutoSteeringEngine.invalidateField( self, self.acParameters.useAIFieldFct )
		end
		AutoSteeringEngine.initFruitBuffer( self )
		AIVehicleExtension.setInt32Value( self, "autoSteer", 2 )
	else
		self.aiveIsStarted = false
	end
end

if AIFieldWorker ~= nil and AIFieldWorker.updateAIFieldWorkerDriveStrategies ~= nil then
	AIFieldWorker.updateAIFieldWorkerDriveStrategies = Utils.appendedFunction( AIFieldWorker.updateAIFieldWorkerDriveStrategies, AIVehicleExtension.afterUpdateAIDriveStrategies )
end

function AIVehicleExtension:newGetCanStartAIVehicle( superFunc, ... )
	if self.acParameters ~= nil
			and self.acParameters.enabled
			and AutoSteeringEngine.hasArticulatedAxis( self )
			and not ( self.aiveCanStartArtAxis ) then
		return false
	end

	local backup = self.isReverseDriving
	if self.acParameters ~= nil and self.acParameters.enabled then
		self.isReverseDriving = false
	end

	local res = { superFunc( self, ... ) }
	self.isReverseDriving = backup
	return unpack( res )
end

if AIFieldWorker ~= nil and AIFieldWorker.getCanStartFieldWork ~= nil then
	AIFieldWorker.getCanStartFieldWork = Utils.overwrittenFunction( AIFieldWorker.getCanStartFieldWork, AIVehicleExtension.newGetCanStartAIVehicle )
end

------------------------------------------------------------------------
-- onOtherAICollisionTrigger (Adapted for FS25 PlayerSystem & getNodeObject)
------------------------------------------------------------------------
function AIVehicleExtension:onOtherAICollisionTrigger(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	if self.acCollidingVehicles == nil or self.acCollidingVehicles[triggerId] == nil then
		return
	end

	local isPlayer = false
	if g_currentMission ~= nil then
		if g_currentMission.players ~= nil and g_currentMission.players[otherId] ~= nil then
			isPlayer = true
		elseif g_currentMission.playerSystem ~= nil and g_currentMission.playerSystem.playersByRootNode ~= nil and g_currentMission.playerSystem.playersByRootNode[otherId] ~= nil then
			isPlayer = true
		end
	end

	if not isPlayer and g_currentMission ~= nil then
		local vehicle = nil
		if type(g_currentMission.getNodeObject) == "function" then
			vehicle = g_currentMission:getNodeObject(otherId)
		elseif g_currentMission.nodeToObject ~= nil then
			vehicle = g_currentMission.nodeToObject[otherId]
		end
		local otherAI = nil

		if vehicle ~= nil and AIFieldWorker ~= nil then
			if vehicle.specializations ~= nil and SpecializationUtil.hasSpecialization( AIFieldWorker, vehicle.specializations ) then
				otherAI = vehicle
			elseif type( vehicle.getRootVehicle ) == "function" then
				otherAI = vehicle:getRootVehicle()
				if otherAI == nil or otherAI.specializations == nil or not SpecializationUtil.hasSpecialization( AIFieldWorker, otherAI.specializations ) then
					otherAI = nil
				end
			end
		end

		if otherAI ~= nil and otherAI ~= self then
			if not onLeave then
				self.acCollidingVehicles[triggerId][otherAI] = true
			elseif self.acCollidingVehicles[triggerId][otherAI] then
				self.acCollidingVehicles[triggerId][otherAI] = nil
			end
		end
	end
end

function AIVehicleExtension:getImplementObjectList()
	local obj = { self }
	if type(self.getAttachedAIImplements) == "function" then
		for _, implement in ipairs(self:getAttachedAIImplements()) do
			if implement.object ~= nil then
				table.insert( obj, implement.object )
			end
		end
	end
	return obj
end

function AIVehicleExtension:newCrabSteeringOnAIImplementStart( superFunc )
	local rootVehicle = self:getRootVehicle()
	if rootVehicle ~= nil and rootVehicle.acParameters ~= nil and rootVehicle.acParameters.enabled and self.spec_crabSteering ~= nil and self.spec_crabSteering.steeringModes ~= nil then
		rootVehicle.aiveSetCrabSteeringState = true
		rootVehicle.aiveSetCrabSteeringEnd   = nil
		self.aiveCrabSteeringState  = self.spec_crabSteering.state

		local spec = self.spec_crabSteering
		local crab = spec.steeringModes[self.aiveCrabSteeringState]
		if crab ~= nil and crab.wheels ~= nil then
			local test = {}
			for s, c in pairs( spec.steeringModes ) do
				if s ~= self.aiveCrabSteeringState and c.wheels ~= nil then
					test[s] = true
					for i, w in pairs( crab.wheels ) do
						local v = c.wheels[i]
						if v == nil then
							test[s] = false
						elseif w.locked and not ( v.locked ) then
							test[s] = false
						elseif v.locked and not ( w.locked ) then
							test[s] = false
						elseif w.offset ~= nil and v.offset ~= nil and math.abs( w.offset + v.offset ) > 0.01 then
							test[s] = false
						end
						if not ( test[s] ) then
							break
						end
					end

					if crab.articulatedAxis ~= nil then
						local w = crab.articulatedAxis
						local v = c.articulatedAxis
						if v == nil then
							test[s] = false
						elseif w.locked and not ( v.locked ) then
							test[s] = false
						elseif v.locked and not ( w.locked ) then
							test[s] = false
						elseif w.offset ~= nil and v.offset ~= nil and math.abs( w.offset + v.offset ) > 0.01 then
							test[s] = false
						end
					end
				end
			end

			self.aiveCrabSteeringState1 = self.aiveCrabSteeringState
			self.aiveCrabSteeringState2 = self.aiveCrabSteeringState
			for s, b in pairs( test ) do
				if b then
					self.aiveCrabSteeringState2 = s
				end
			end
			return
		end
	end
	return superFunc( self )
end

if CrabSteering ~= nil and CrabSteering.onAIImplementStart ~= nil then
	CrabSteering.onAIImplementStart = Utils.overwrittenFunction( CrabSteering.onAIImplementStart, AIVehicleExtension.newCrabSteeringOnAIImplementStart )
end

function AIVehicleExtension:onAIFieldWorkerTurnProgress( progress, left )
	if self.acParameters ~= nil
			and self.acParameters.enabled
			and self.aiveSetCrabSteeringState
			and progress ~= nil
			and progress > 0.05 then
		local target = progress > 0.95

		if self.aiveSetCrabSteeringEnd == nil or self.aiveSetCrabSteeringEnd ~= target then
			self.aiveSetCrabSteeringEnd = target

			for _, o in pairs( AIVehicleExtension.getImplementObjectList( self ) ) do
				if o.spec_crabSteering ~= nil
						and o.spec_crabSteering.stateMax ~= nil and o.spec_crabSteering.stateMax > 0
						and o.spec_crabSteering.aiSteeringModeIndex ~= nil and o.spec_crabSteering.aiSteeringModeIndex > 0 then
					local state = o.spec_crabSteering.state
					if not target then
						state = o.spec_crabSteering.aiSteeringModeIndex
					else
						state = o.aiveCrabSteeringState1
						if o.aiveCrabSteeringState1 ~= nil
								and o.aiveCrabSteeringState2 ~= nil
								and o.aiveCrabSteeringState2 ~= o.aiveCrabSteeringState1
								and self.aiveChain ~= nil
								and self.aiveChain.trace ~= nil
								and self.aiveChain.trace.isUTurn then
							state = o.aiveCrabSteeringState2
							o.aiveCrabSteeringState2 = o.aiveCrabSteeringState1
							o.aiveCrabSteeringState1 = state
						end
					end
					if state ~= nil and o.setCrabSteering ~= nil then
						o:setCrabSteering(state)
					end
				end
			end
		end
	end
end

function AIVehicleExtension:onAIFieldWorkerStart()
	if self.isServer and self.acParameters ~= nil then
		self.aiveIsStarted = self.acParameters.enabled and not AIVehicleExtension.isNativeSteeringSelected(self)
		self.aiveStartVerfied = false
		if self.aiveIsStarted and self.acParameters.straight then
			AIVehicleExtension.setAIDirection( self )
			self.acIsStraight = true
		else
			self.acIsStraight = false
		end
	end
end

function AIVehicleExtension:onAIFieldWorkerEnd()
	if self.aiveMainStrategy then self.aiveMainStrategy:checkpointJob() end
	if self.acParameters ~= nil
			and self.acParameters.enabled
			and self.aiveSetCrabSteeringState then
		for _, o in pairs( AIVehicleExtension.getImplementObjectList( self ) ) do
			if o.aiveCrabSteeringState ~= nil
					and o.spec_crabSteering ~= nil
					and o.spec_crabSteering.stateMax ~= nil and o.spec_crabSteering.stateMax > 0 then
				if o.setCrabSteering ~= nil then
					o:setCrabSteering(o.aiveCrabSteeringState)
				end
				o.aiveCrabSteeringState  = nil
				o.aiveCrabSteeringState1 = nil
				o.aiveCrabSteeringState2 = nil
			end
		end
	end
	self.aiveSetCrabSteeringState = nil
	self.aiveSetCrabSteeringEnd   = nil
	self.aiveIsStarted = false
	for _,object in ipairs(AIVehicleExtension.getImplementObjectList(self)) do
		AutoSteeringEngine.updateAIVEDirectPlanting(object)
	end
end

function AIVehicleExtension:afterCutterOnEndWorkAreaProcessing(dt, hasProcessed)
	local spec = self.spec_cutter
	local rootVehicle = self:getRootVehicle()
	if rootVehicle ~= nil and rootVehicle.aiveIsStarted and spec ~= nil and spec.aiNoValidGroundTimer ~= nil and spec.aiNoValidGroundTimer > 0 then
		spec.aiNoValidGroundTimer = 0
	end
end

if Cutter ~= nil and Cutter.onEndWorkAreaProcessing ~= nil then
	Cutter.onEndWorkAreaProcessing = Utils.appendedFunction( Cutter.onEndWorkAreaProcessing, AIVehicleExtension.afterCutterOnEndWorkAreaProcessing )
end

function AIVehicleExtension:processFertilizingSowingMachineArea(superFunc1, superFunc2, workArea, dt)
	-- Fertilizing seeders need the same cleanup before their native callback:
	-- it reads useDirectPlanting without calling the plain seeder callback.
	AutoSteeringEngine.updateAIVEDirectPlanting(self)
	local vehicle = self:getRootVehicle()
	if not ( vehicle ~= nil and vehicle.aiveIsStarted ) then
		return superFunc1( self, superFunc2, workArea, dt )
	end
	if vehicle.acParameters ~= nil and vehicle.acParameters.noSprayer and type(superFunc2) == "function" then
		return superFunc2( self, workArea, dt )
	end
	return superFunc1( self, superFunc2, workArea, dt )
end

if FertilizingSowingMachine ~= nil and FertilizingSowingMachine.processSowingMachineArea ~= nil then
	FertilizingSowingMachine.processSowingMachineArea = Utils.overwrittenFunction( FertilizingSowingMachine.processSowingMachineArea, AIVehicleExtension.processFertilizingSowingMachineArea )
end

function AIVehicleExtension:driveToPoint(superFunc, dt, acceleration, allowedToDrive, moveForwards, tX, tZ, maxSpeed, doNotSteer)
	-- AIDrivable's manual branch always passes allowedToDrive=true, even
	-- while our transport task holds speed at zero during route planning.
	-- GIANTS then evaluates 1/maxSpeed in its steering speed reduction.
	-- A zero limit is a brake request, not a request to steer/accelerate.
	if maxSpeed ~= nil and maxSpeed <= 0 then
		allowedToDrive, acceleration, doNotSteer = false, 0, true
	end
	if not self.aiveIsStarted then
		return superFunc( self, dt, acceleration, allowedToDrive, moveForwards, tX, tZ, maxSpeed, doNotSteer )
	end

	if self.finishedFirstUpdate then
		if allowedToDrive then
			local tX_2 = tX * 0.5
			local tZ_2 = tZ * 0.5
			local d1X = tZ_2
			local d1Z = -tX_2

			if tX > 0 then
				d1Z = tX_2
				d1X = -tZ_2
			end

			local hit, _, f2 = MathUtil.getLineLineIntersection2D(tX_2, tZ_2, d1X, d1Z, 0, 0, tX, 0)

			if doNotSteer == nil or not doNotSteer then
				local rotTime = 0

				if hit and math.abs(f2) < 100000 then
					local radius = tX * f2
					if type(self.getSteeringRotTimeByCurvature) == "function" then
						rotTime = self:getSteeringRotTimeByCurvature(1 / radius)
					elseif self.wheelSteeringDuration ~= nil and self.maxTurningRadius ~= nil and self.maxTurningRadius > 0 then
						rotTime = self.wheelSteeringDuration * ( math.atan(1 / radius) / math.atan(1 / self.maxTurningRadius) )
					end

					if type(self.getReverserDirection) == "function" and self:getReverserDirection() < 0 then
						rotTime = -rotTime
					end
				end

				local targetRotTime
				if rotTime >= 0 then
					targetRotTime = math.min(rotTime, self.maxRotTime or 1)
				else
					targetRotTime = math.max(rotTime, self.minRotTime or -1)
				end

				local steerSpeed = type(self.getAISteeringSpeed) == "function" and self:getAISteeringSpeed() or 0.001
				if self.rotatedTime < targetRotTime then
					self.rotatedTime = math.min(self.rotatedTime + dt * steerSpeed, targetRotTime)
				else
					self.rotatedTime = math.max(self.rotatedTime - dt * steerSpeed, targetRotTime)
				end
			end
		end

		local ccSpeed = type(self.getCruiseControlSpeed) == "function" and self:getCruiseControlSpeed() or maxSpeed
		AIVEWheelUtils.setMotorSpeedLimit(self, math.min(maxSpeed, ccSpeed))

		if Drivable ~= nil and type(self.getCruiseControlState) == "function" and self:getCruiseControlState() ~= Drivable.CRUISECONTROL_STATE_ACTIVE then
			self:setCruiseControlState(Drivable.CRUISECONTROL_STATE_ACTIVE)
		end

		if not allowedToDrive then
			acceleration = 0
		end

		if not moveForwards then
			acceleration = -acceleration
		end

		AIVEWheelUtils.updateWheelsPhysics(self, dt, (self.lastSpeedReal or 0) * (self.movingDirection or 1), acceleration, not allowedToDrive, true)
	end
end

if AIVehicleUtil ~= nil and AIVehicleUtil.driveToPoint ~= nil then
	AIVehicleUtil.driveToPoint = Utils.overwrittenFunction( AIVehicleUtil.driveToPoint, AIVehicleExtension.driveToPoint )
end
