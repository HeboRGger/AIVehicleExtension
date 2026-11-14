--
-- AIDriveStrategyMogli
--

-- AIDriveStrategy.new is a function
-- AIDriveStrategy.isa is a function
-- AIDriveStrategy.getDistanceToEndOfField is a function
-- AIDriveStrategy.getDriveData is a function
-- AIDriveStrategy.delete is a function
-- AIDriveStrategy.draw is a function
-- AIDriveStrategy.superClass is a function
-- AIDriveStrategy.updateDriving is a function
-- AIDriveStrategy.class is a function
-- AIDriveStrategy.setAIVehicle is a function
-- AIDriveStrategy.update is a function
-- AIDriveStrategy.copy is a function

source(Utils.getFilename("AITurnStrategyMogli.lua", g_currentModDirectory));
source(Utils.getFilename("AITurnStrategyMogliDefault.lua", g_currentModDirectory));
source(Utils.getFilename("AITurnStrategyMogli_C_R.lua", g_currentModDirectory));


AIDriveStrategyMogli = {}

AIDriveStrategyMogli.searchOutside = 4
AIDriveStrategyMogli.searchStart   = 3 
AIDriveStrategyMogli.searchUTurn   = 2
AIDriveStrategyMogli.searchCircle  = 1

local AIDriveStrategyMogli_mt = Class(AIDriveStrategyMogli, AIDriveStrategy)

-- Keep job progress on the vehicle while the engine destroys its drive
-- strategies after dismissal. Engine/base-class instances are never reused.
local jobFields={"mogliText","turnData","turnDataIsStable","turnDataIsStableCounter",
	"lastLookAheadDistance","aiveTurnTimer","lastAllowedToDrive","turnLeft",
	"turnStrategies","ts_C_R","currentTurnStrategy","search","lands","isAtEndTimer","lastDirection"}
local vehicleJobFields={"acDimensions","aiveHas","acTurnMode","acDirectionBeforeTurn","acClearTraceAfterTurn"}
local function jobSignature(v)
	local p=v.acParameters or {}
	local keys={"circleLands","fieldGroup","upNDown","straight","inverted","widthOffset","turnOffset","turnModeIndex","turnModeIndexC","headland","bigHeadland","useAIFieldFct"}
	local values={}
	for _,key in ipairs(keys) do values[#values+1]=key.."="..tostring(p[key]) end
	local tools={}
	if type(v.getAttachedAIImplements)=="function" then
		for _,item in ipairs(v:getAttachedAIImplements() or {}) do
			local obj=item.object or item;tools[#tools+1]=tostring(obj.rootNode or obj)
		end
	else
		for _,item in ipairs((v.aiveChain or {}).tools or {}) do
			local obj=item.obj or item;tools[#tools+1]=tostring(obj.rootNode or obj)
		end
	end
	table.sort(tools)
	return table.concat(values,";")..";tools="..table.concat(tools,",")
end

function AIDriveStrategyMogli:checkpointJob()
	local v=self.vehicle
	if not v or self.jobFinished or not v.aiveChain or not self.obstacles then return end
	if v.aiveJobMemory and v.aiveJobMemory.owner==self then return end
	local memory={owner=self,mission=g_currentMission,signature=jobSignature(v),
		refNode=v.aiveChain.refNode,pose=self.obstacles:pose(),state={},vehicleState={},
		stage=v.acTurnStage,field=v.aiveCurrentField,
		lowered=v.acImplementsMoveDown~=false,wait=math.max(0,(v.waitForTurnTime or 0)-(g_currentMission.time or 0))}
	for _,key in ipairs(jobFields) do memory.state[key]=self[key] end
	for _,key in ipairs(vehicleJobFields) do memory.vehicleState[key]=v[key] end
	if v.aiveChain.trace then
		memory.trace={};for key,value in pairs(v.aiveChain.trace) do memory.trace[key]=value end
	end
	memory.obstacles={}
	for key,value in pairs(self.obstacles) do
		if key~="vehicle" and key~="strategy" and key~="ignore" then memory.obstacles[key]=value end
	end
	v.aiveJobMemory=memory
	AIVELogger.info("JobMemory","Saved '%s': phase=%s, pass=%s, nativeStage=%s.",v:getName(),
		tostring(self.lands and self.lands.phase or "edge"),tostring(self.lands and self.lands.laneIndex or "-"),tostring(memory.stage))
end

function AIDriveStrategyMogli:resumeJob()
	local v=self.vehicle
	local m=v.aiveJobMemory
	if not m then return false end
	v.aiveJobMemory=nil
	if m.mission~=g_currentMission or m.signature~=jobSignature(v) or not v.aiveChain or m.refNode~=v.aiveChain.refNode then
		AIVELogger.info("JobMemory","Discarded checkpoint on '%s': equipment or working settings changed.",v:getName());return false
	end
	local sensor=AIVEObstacles.new(v,self)
	local p=sensor:pose()
	if (p.x-m.pose.x)^2+(p.z-m.pose.z)^2>64 or math.cos(p.h-m.pose.h)<0.7 then
		sensor:delete()
		AIVELogger.info("JobMemory","Discarded checkpoint on '%s': moved away from the saved working position.",v:getName());return false
	end
	-- A paused obstacle plan is tied to its exact start pose. Even a small
	-- manual turn makes its encounter, goal and swept footprint stale.
	local obstacle=m.obstacles
	local moved=(p.x-m.pose.x)^2+(p.z-m.pose.z)^2>0.25 or math.cos(p.h-m.pose.h)<math.cos(math.rad(5))
	if moved and obstacle and obstacle.phase~="clear" and obstacle.phase~="waiting" then
		m.stage=obstacle.savedStage or 0
		m.lowered=obstacle.savedLowered~=false
		m.obstacles={phase="clear",clock=obstacle.clock or 0,nextProbe=0,coverageDebts=obstacle.coverageDebts,nextCoverageAt=obstacle.nextCoverageAt}
		AIVELogger.info("JobMemory","Discarded stale obstacle manoeuvre on '%s' after manual repositioning; preserving field route.",v:getName())
	end
	for _,key in ipairs(jobFields) do self[key]=m.state[key] end
	for _,key in ipairs(vehicleJobFields) do v[key]=m.vehicleState[key] end
	if m.trace then v.aiveChain.trace=m.trace end
	v.aiveCurrentField=m.field or v.aiveCurrentField
	if v.aiveCurrentField then v.aiveFieldIsInvalid=false end
	v.acTurnStage=m.stage;v.waitForTurnTime=(g_currentMission.time or 0)+m.wait
	v.aiRescueTimer=v.acDeltaTimeoutStop
	self.obstacles=sensor
	for key,value in pairs(m.obstacles) do sensor[key]=value end
	if sensor.maneuverSearch then sensor.maneuverSearch.controller=sensor end
	sensor.nextProbe=0;sensor.lastHit=nil;sensor.waitNode=nil;sensor.ignore={}
	v.aiveObstacleController=sensor
	v.aiveAvoidingObstacle=sensor.phase~="clear" and sensor.phase~="waiting" or nil
	v.aiveWorkingBypass=sensor.workingBypass and true or nil
	if self.lands then
		self.lands.vehicle=v;self.lands.lastPose=p;self.lands.lastProgress=p
		self.lands.progressTimer=0;self.lands.error=nil;self.lands.lowered=nil
		v.aiveLandsPhase=(self.lands.active or self.lands.waitingHandover or self.lands.finishingPass) and self.lands.phase or nil
	end
	self.resumeLowered=m.lowered;self.needsInitialPreparation=true
	self.resumedJob=true
	self.resumedTurn=self.currentTurnStrategy~=nil or (self.lands and self.lands.phase=="transfer") or (v.aiveAvoidingObstacle and not v.aiveWorkingBypass)
	v.aiveMainStrategy=self
	AIVehicleExtension.initMogliHud(v)
	AIVELogger.info("JobMemory","Resumed '%s': phase=%s, pass=%s; original field and route retained.",v:getName(),
		tostring(self.lands and self.lands.phase or "edge"),tostring(self.lands and self.lands.laneIndex or "-"))
	return true
end

function AIDriveStrategyMogli.new(reconstructionData, customMt)
	if customMt == nil then
		customMt = AIDriveStrategyMogli_mt
	end
	local self = AIDriveStrategy.new(reconstructionData, customMt)
	return self
end

function AIDriveStrategyMogli:setAIVehicle(vehicle)
	self.mogliText = "AIDriveStrategyMogli"
	
	AIDriveStrategyMogli:superClass().setAIVehicle(self, vehicle)
	if self:resumeJob() then return end
	vehicle.aiveMainStrategy=self
--==============================================================			
--==============================================================					
	AutoSteeringEngine.saveDirection( vehicle )

	vehicle.acClearTraceAfterTurn = true
	AIVehicleExtension.resetAIMarker( vehicle )	
	AIVehicleExtension.initMogliHud(vehicle)
	
	self.vehicle.aiToolReverserDirectionNode = (AIVehicleUtil ~= nil and type(AIVehicleUtil.getAIToolReverserDirectionNode) == "function") and AIVehicleUtil.getAIToolReverserDirectionNode(self.vehicle) or nil;
	
	AutoSteeringEngine.invalidateField( vehicle )
	
	AutoSteeringEngine.checkTools1( vehicle, true )
	
	vehicle.acDimensions	= nil;
	AIVehicleExtension.checkState( vehicle )
	
  self.turnDataIsStable = false;
  self.turnDataIsStableCounter = 0;

  self.lastLookAheadDistance = 5; -- 30;
	self:updateTurnData()
	self.turnData.stage = -3
	self.aiveTurnTimer		    = vehicle.acDeltaTimeoutWait;
	self.lastAllowedToDrive   = true
	
	vehicle.aiRescueTimer     = vehicle.acDeltaTimeoutStop;
	vehicle.waitForTurnTime   = 0;
	vehicle.acLastAcc			    = 0;
	vehicle.acLastWantedSpeed = 0;
	
	AIVehicleExtension.setInt32Value( vehicle, "speed2Level", 2 )
	
--if AIVehicleUtil.invertsMarkerOnTurn( vehicle, vehicle.acParameters.leftAreaActive ) then
--	if vehicle.acParameters.leftAreaActive then
--		AIVehicle.aiRotateLeft(vehicle);
--	else
--		AIVehicle.aiRotateRight(vehicle);
--	end			
--end
	
	AIVehicleExtension.sendParameters(vehicle);
	
	vehicle.acStat = nil		
--==============================================================				
--==============================================================				
		
	
	
	self.turnLeft = not ( self.vehicle.acParameters.rightAreaActive )
	self.turnStrategies = { }
	
	self.turnStrategies[1] = AITurnStrategyMogliDefault.new()
	
	self.ts_C_R = table.getn( self.turnStrategies ) + 1
	self.turnStrategies[self.ts_C_R] = AITurnStrategyMogli_C_R.new()
		
--self.ts_U_O = table.getn( self.turnStrategies ) + 1
--self.turnStrategies[self.ts_U_O] = AITurnStrategyMogli_U_O.new()
		
	for _,turnStrategy in pairs(self.turnStrategies) do
		turnStrategy:setAIVehicle(self.vehicle);
	end
	self.currentTurnStrategy = nil

	self.search     = AIDriveStrategyMogli.searchStart 
	-- FS25 raises onAIImplementStart after strategy construction, which lifts
	-- implements again. Prepare them on the first driving update instead.
	self.needsInitialPreparation = true
	self.lands = vehicle.acParameters.circleLands and AIVELands.new(vehicle) or nil
	self.obstacles=AIVEObstacles and AIVEObstacles.new(vehicle,self) or nil
	vehicle.aiveObstacleController=self.obstacles
	local geometry=vehicle.acDimensions or {}
	AIVELogger.info("DriveStrategy","Geometry on '%s': wheelbase=%.2f m; tractor radius=%.2f m; transfer radius=%.2f m; collision sensor=%s.",
		tostring(vehicle:getName()),geometry.wheelBase or 0,geometry.radius or 0,AIVELands and AIVELands.getTurnRadius and AIVELands.getTurnRadius(vehicle) or geometry.radius or 0,
		tostring(self.obstacles and self.obstacles:isEnabled() or false))
	if self.lands~=nil then
		AIVELogger.info("Lands","Perimeter phase started on '%s'; corner=%s; one complete contour required before switching near 80 m.",
			tostring(vehicle:getName()),tostring(vehicle.acTurnMode))
	end
	self.isAtEndTimer = self.vehicle.acDeltaTimeoutWait
	AIVELogger.info("DriveStrategy", "AIVE strategy initialized on '%s'; tools=%s; fieldScan=%s.",
		tostring(type(vehicle.getName) == "function" and vehicle:getName() or "vehicle"),
		tostring(vehicle.aiveChain ~= nil and vehicle.aiveChain.toolCount or 0),
		tostring(vehicle.aiveCurrentFieldCo ~= nil))
end

function AIDriveStrategyMogli:delete()
		
--==============================================================				
--==============================================================				
	local veh = self.vehicle 
	self:checkpointJob()
	if self.lands and self.lands.groupSession then AIVEFieldDispatcher.leave(self.lands) end
	
	veh.aiveIsStarted = false
	if self.obstacles then self.obstacles:delete() end
	veh.aiveLandsPhase = nil
	if veh.aiveMainStrategy==self then veh.aiveMainStrategy=nil end
	
	if veh.acStat ~= nil then
		for n,s in pairs(veh.acStat) do 
			print(string.format("%s: %.0f (%.0f / %.0f)", n, s.t/s.n, s.t, s.n))
		end
	end
	AutoSteeringEngine.invalidateField( veh )		
	AIVehicleExtension.resetAIMarker( veh )
	veh.acImplementsMoveDown = false
	AIVehicleExtension.setStatus( veh, 0 )
	veh.acTurnStage = 0
--==============================================================				
--==============================================================				
		
	AIDriveStrategyMogli:superClass().delete(self);

  if self.vehicle ~= nil and type(self.vehicle.getAttachedAIImplements) == "function" then
		for _, implement in ipairs(self.vehicle:getAttachedAIImplements()) do
			if implement.object ~= nil and type(implement.object.aiImplementEndLine) == "function" then
				implement.object:aiImplementEndLine()
			end
			if implement.object ~= nil and type(implement.object.getRootVehicle) == "function" then
				local rootVehicle = implement.object:getRootVehicle()
				if rootVehicle ~= nil and VehicleStateChange ~= nil and type(rootVehicle.raiseStateChange) == "function" then
					rootVehicle:raiseStateChange(VehicleStateChange.AI_END_LINE)
				end
			end
		end
	end
end

function AIDriveStrategyMogli:update(dt)
	if self.obstacles and self.obstacles:hasControl() then return end
	for _,turnStrategy in pairs(self.turnStrategies) do
		turnStrategy:update(dt)
	end
	self.turnLeft = not ( self.vehicle.acParameters.rightAreaActive )
	-- Keep measurement independent of corner/search returns and combine waits.
	-- Use the existing strategy update; never add another native driving update.
	local chain=self.vehicle.aiveChain
	if self.vehicle.acParameters.fieldGroup and AIVEFieldDispatcher.enabled(self.vehicle) and self.lands and chain and (chain.toolCount or 0)>0
		and not self.vehicle.aiveCurrentField and type(AutoSteeringEngine.checkFieldIsValid)=="function" then
		local shared=AIVEFieldDispatcher and AIVEFieldDispatcher.findField(self.vehicle)
		if shared then
			self.vehicle.aiveCurrentField=shared;self.vehicle.aiveCurrentFieldCo=nil;self.vehicle.aiveFieldIsInvalid=false
		else AutoSteeringEngine.checkFieldIsValid(self.vehicle) end
	end
	if self.lands~=nil and not self.vehicle.acPause and not self.vehicle.acIsCPStopped
		and chain~=nil and chain.refNode~=nil and (chain.toolCount or 0)>0 then
		self.lands:observe(dt)
	end
end

function AIDriveStrategyMogli:draw()
	if self.vehicle ~= nil and self.vehicle.aiveIsStarted then
		self.vehicle.aiveToolAngleInfo = AutoSteeringEngine.radToString(AutoSteeringEngine.getToolAngle(self.vehicle))
	end
end

function AIDriveStrategyMogli:addDebugText( s )
	if self.vehicle ~= nil and type( self.vehicle.aiveAddDebugText ) == "function" then
		self.vehicle:aiveAddDebugText( s ) 
	end
end

function AIDriveStrategyMogli:printReturnInfo( tX, vY, tZ, moveForwards, maxSpeed, distanceToStop )
	local vehicle = self.vehicle
	local x,y,z
	if tX ~= nil and vY ~= nil and tZ ~= nil and vehicle.aiVehicleDirectionNode ~= nil then
		x,y,z = worldToLocal( vehicle.aiVehicleDirectionNode, tX, vY, tZ )
	end
	
	local turnStage = "???"
	if self.currentTurnStrategy ~= nil then
		turnStage = tostring(self.turnData.stage)
	elseif self.search == nil then
		turnStage = " 0"
	else
		turnStage = "-"..self.search
	end
	
	vehicle.aiveReturnInfo = turnStage..": "..AutoSteeringEngine.posToString(x).." "..AutoSteeringEngine.posToString(z).." "..tostring(moveForwards).." "..AutoSteeringEngine.posToString(maxSpeed).." "..AutoSteeringEngine.posToString(distanceToStop)
end

function AIDriveStrategyMogli:updateTurnData()
	if AIDriveStrategyStraight ~= nil and type(AIDriveStrategyStraight.updateTurnData) == "function" then
		pcall(AIDriveStrategyStraight.updateTurnData, self)
	end
	if type(self.turnData) ~= "table" then
		self.turnData = {
			stage = 0,
			useExtraStraight = false,
			sideOffset = 0,
			headlandTurn = false
		}
	end
	self.turnData.driveStrategy = self
end

function AIDriveStrategyMogli:adjustPosition( eX, eZ, moveForwards, distanceToStop, inverse )
	local vehicle = self.vehicle
	local mF2     = moveForwards
	if vehicle.acParameters.inverted then
		mF2 = not moveForwards
	end
	
	if vehicle.aiveChain == nil or vehicle.aiveChain.refNode == nil then
		return eX, eZ, mF2
	end
	
--local refNode = vehicle.aiveChain.refNode
--
--if      not ( moveForwards ) 
--		and AutoSteeringEngine.hasArticulatedAxis( vehicle )
--    and vehicle.spec_articulatedAxis.aiRevereserNode ~= nil then
--	refNode = vehicle.aiVehicleDirectionNode
--elseif  vehicle.aiVehicleDirectionNode ~= nil then
--	refNode = vehicle.aiVehicleDirectionNode
--end

	local refNode = vehicle:getAIDirectionNode()
	
	local nIn  = vehicle.aiveChain.refNode
	local nOut = refNode
	
	if inverse then
		nIn  = refNode
		nOut = vehicle.aiveChain.refNode
	end
	
	local eY       = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, eX, 1, eZ) 
	
	local lX,lY,lZ = worldToLocal( nIn,  eX, eY, eZ )
	
--if not inverse and distanceToStop ~= nil then
--	local d = math.max( 1, math.min( 6, distanceToStop ) )
--	local l = AIVEUtils.vector3Length( lX,lY,lZ )
--	
--	
--	if 0.1 < math.abs( l ) and math.abs( 1.2 * l ) < d then
--		local f = d / l
--		lX = lX * f
--		lY = lY * f
--		lZ = lZ * f
--	end
--end
	
	if vehicle.acParameters.inverted then
		lX = -lX
	end
	
	local tX,_,tZ  = localToWorld( nOut, lX, lY, lZ )
	
--print(string.format("%5.2f %5.2f => %5.2f %5.2f => %5.2f %5.2f", eX, eZ, lX, lZ, tX, tZ ))
	
	return tX, tZ, mF2
end

function AIDriveStrategyMogli:gotoNextStage()
	if self.currentTurnStrategy ~= nil then
		self.currentTurnStrategy:gotoNextStage(self.turnData)
	else
		self.search = nil
	end
end

local function safeStopAIJob(vehicle, msgClass, reason)
	if vehicle == nil or type(vehicle.stopCurrentAIJob) ~= "function" then
		return
	end
	if msgClass~=nil and msgClass==AIMessageSuccessFinishedJob then
		vehicle.aiveJobMemory=nil
		if vehicle.aiveMainStrategy then vehicle.aiveMainStrategy.jobFinished=true end
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
	if AIVELogger ~= nil then
		AIVELogger.info("DriveStrategy", "Stopping AI job on '%s'; reason=%s; messageClass=%s", tostring(type(vehicle.getName) == "function" and vehicle:getName() or "vehicle"), tostring(reason or "unspecified"), tostring(msgClass))
	end
	pcall(vehicle.stopCurrentAIJob, vehicle, msg)
end

function AIDriveStrategyMogli:getLandsDriveData(dt,vX,vY,vZ)
	local x,z,forward,speed,stop,result=self.lands:getDriveData(dt)
	if self.lands.groupSession and result~="finished" and type(self.vehicle.getCanAIFieldWorkerContinueWork)=="function" then
		local allowed,stopJob,reason=self.vehicle:getCanAIFieldWorkerContinueWork(true)
		if not allowed then
			self.lands.progressTimer=0
			self.lands.groupRouteBlockedAt=nil
			if stopJob then self.vehicle:stopCurrentAIJob(reason or AIMessageErrorUnknown.new()) end
			return x,z,forward,0,0
		end
		if self.vehicle.aiveMaxCollisionSpeed~=nil then
			speed=math.min(speed,math.max(0,self.vehicle.aiveMaxCollisionSpeed-0.2))
			if speed<=0 then self.lands.progressTimer=0 end
		end
	end
	if result=="finished" then
		safeStopAIJob(self.vehicle,AIMessageSuccessFinishedJob,"lands: remaining work verified empty")
	elseif result=="blocked" then
		safeStopAIJob(self.vehicle,AIMessageErrorBlockedByObject,"lands: "..tostring(self.lands.error))
	elseif result=="perimeter" then
		self.search=AIDriveStrategyMogli.searchCircle
		AutoSteeringEngine.clearTrace(self.vehicle)
		AutoSteeringEngine.saveDirection(self.vehicle,false)
	end
	local tx,tz,mf=self:adjustPosition(x,z,forward,stop)
	self.lastDirection={tx,tz}
	return tx,tz,mf,speed,stop
end

function AIDriveStrategyMogli:getDriveData(dt,vX,vY,vZ)
	if not self.vehicle.acPause and not self.vehicle.acIsCPStopped then self:prepareInitialWork() end
	local lands,sensor=self.lands,self.obstacles
	local session=lands and lands.groupSession
	local groupTime=g_currentMission and g_currentMission.time or (lands and lands.clock) or 0
	if session and session.headlandReady and sensor and sensor.phase=="waiting"
		and sensor.lastHit and session.members[sensor.lastHit.vehicle]
		and not self.vehicle.acPause and not self.vehicle.acIsCPStopped then
		local changed=false
		if not lands.active then
			if self.currentTurnStrategy then
				for _,turn in pairs(self.turnStrategies) do turn:onEndTurn(self.turnLeft) end
				self.currentTurnStrategy=nil;self.vehicle:aiFieldWorkerEndTurn(self.turnLeft)
			end
			changed=lands:requestHandover("shared core ready; yielding to another field worker")
		elseif lands.phase=="transfer" and groupTime>=(lands.nextPeerReplan or 0) then
			AIVEFieldDispatcher.finishTurn(lands)
			lands.path=nil;lands.phase="groupTurnWait";lands.nextPeerReplan=groupTime+2000
			lands.progressTimer=0;changed=true
		elseif lands.phase=="groupTurnWait" or lands.phase=="groupWait" then
			changed=true
		end
		if changed then
			sensor.phase="clear";sensor.lastHit=nil;sensor.waitNode=nil;sensor.waitSince=nil;sensor.nextProbe=0
		end
	end
	if self.obstacles and self.obstacles:hasControl() then
		local x,z,mf,speed,stop=self.obstacles:drive(dt)
		if x~=nil then return x,z,mf,speed,stop end
	end
	local x,z,mf,speed,stop=self:getDriveDataRaw(dt,vX,vY,vZ)
	if self.obstacles and x~=nil and not self.vehicle.acPause and not self.vehicle.acIsCPStopped then
		return self.obstacles:filter(dt,x,z,mf,speed,stop)
	end
	return x,z,mf,speed,stop
end

function AIDriveStrategyMogli:prepareInitialWork()
	if not self.needsInitialPreparation then return end
	local veh=self.vehicle
	local lowered=self.resumeLowered~=false
	if self.lands and (self.lands.active or self.lands.waitingHandover) then lowered=self.lands.phase=="work" end
	if veh.aiveAvoidingObstacle and not veh.aiveWorkingBypass then lowered=false end
	AutoSteeringEngine.setToolsAreTurnedOn(veh,true,false)
	AIVehicleExtension.setAIImplementsMoveDown(veh,lowered,true)
	self.needsInitialPreparation=false;self.resumeLowered=nil
	if self.resumedTurn then
		veh:aiFieldWorkerStartTurn(self.turnLeft)
		self.resumedTurn=nil
	end
end

function AIDriveStrategyMogli:getDriveDataRaw(dt, vX,vY,vZ)
	local veh = self.vehicle 
		
	if veh.acIsCPStopped then
		veh.acIsCPStopped = false
		veh.isHirableBlocked = true		
		AIVehicleExtension.setStatus( veh, 0 )
		return vX, vZ, not veh.acParameters.inverted, 0, 0
	end
	
	if veh.acPause then
		veh.isHirableBlocked = true		
		AIVehicleExtension.setStatus( veh, 0 )
		return vX, vZ, not veh.acParameters.inverted, 0, 0
	end
	self:prepareInitialWork()
	if veh.acParameters.fieldGroup and AIVEFieldDispatcher.enabled(veh) and self.lands
		and (self.lands.error or self.lands.active or (self.lands.groupSession and self.lands.groupSession.headlandReady
			and self.search==AIDriveStrategyMogli.searchStart and not self.currentTurnStrategy)) then
		local l=self.lands
		veh.aiRescueTimer=veh.acDeltaTimeoutStop
		if l.error then return self:getLandsDriveData(dt,vX,vY,vZ) end
		if not l.groupSession or not l.snapshot then l:setLowered(false);return vX,vZ,true,0,0 end
		if not l.active then
			if #l.snapshot.cells==0 then safeStopAIJob(veh,AIMessageSuccessFinishedJob,"field group: no remaining work");return vX,vZ,true,0,0 end
			l:tryStart()
		end
		return self:getLandsDriveData(dt,vX,vY,vZ)
	end

--veh.acAiPos = { vX, vY, vZ }
	AutoSteeringEngine.setAiWorldPosition( veh, vX, vY, vZ )
	
	if self.aiveTurnTimer == nil then 
		veh:acDebugPrint("turnTimer is nil: "..tostring(self.search).." / "..tostring(self.turnData.stage))
		self.aiveTurnTimer = 0
	end
		
	if veh.spec_aiVehicle ~= nil then veh.spec_aiVehicle.aiSteeringSpeed = veh.acSteeringSpeed end
	self.activeTurnStrategy = nil
	
	local resetState = false 
	if self.currentTurnStrategy ~= nil then
		local tX, tZ, moveForwards, maxSpeed, distanceToStop = self.currentTurnStrategy:getDriveData(dt, vX,vY,vZ, self.turnData)
		
	--if AIVEGlobals.devFeatures > 0 then
	--	self:addDebugText("truning: "..tostring(tX)
	--												..", "..tostring(tZ)
	--												..", "..tostring(moveForwards)
	--												..", "..tostring(maxSpeed)
	--												..", "..tostring(distanceToStop)
	--												..", "..tostring(self.turnData)) 
	--end
		
		if tX == nil then
			veh:aiFieldWorkerTurnProgress( 1, veh.acParameters.leftAreaActive )
			for _,turnStrategy in pairs(self.turnStrategies) do
				turnStrategy:onEndTurn(self.turnLeft)
			end
			self.currentTurnStrategy = nil
			self.aiveTurnTimer		   = veh.acDeltaTimeoutRun
			veh.aiRescueTimer  = math.max( veh.aiRescueTimer, veh.acDeltaTimeoutStop )
			
			if self.search == nil then
				self.search = AIDriveStrategyMogli.searchCircle
			end			
			veh.acLastAbsAngle = nil
			resetState         = true
			veh:aiFieldWorkerEndTurn( veh.acParameters.leftAreaActive )
			if self.lands~=nil then
				self.lands:requestHandover("perimeter corner completed")
			end
		else
			local tX2, tZ2, mF2 = self:adjustPosition( tX, tZ, moveForwards, distanceToStop )
			self.lastDirection = { tX2, tZ2 }
			self:printReturnInfo( tX2, vY, tZ2, mF2, maxSpeed, distanceToStop )
			
			if maxSpeed == 0 then
				veh.acLastWantedSpeed = nil
			end
			
			if veh.acTurnStage > 0 then
				self.activeTurnStrategy = self.currentTurnStrategy
				AIVehicleExtension.stopCoursePlayMode2( veh, false )
			end
			
			AIVehicleExtension.statEvent( veh, "tT", dt )
			return tX2, tZ2, mF2, maxSpeed, distanceToStop
		end		
	end

--if AIVEGlobals.devFeatures > 0 then
--	self:addDebugText("driving: "..tostring(self.search))
--end

	if self.search == nil then
		veh.acTurnStage = 0
	else
		veh.acTurnStage = -self.search 
	end
		
	local tX, tZ, maxSpeed, distanceToStop = nil, nil, 0, 0			

	AIVehicleExtension.statEvent( veh, "t0", dt )

	AIVehicleExtension.checkState( veh, resetState )
	if not AutoSteeringEngine.hasTools( veh ) then
		safeStopAIJob(veh, AIMessageErrorUnknown, "hasTools=false; toolCount=" .. tostring(veh.aiveChain ~= nil and veh.aiveChain.toolCount or "nil"))
		return;
	end
	
	local allowedToDrive =  AutoSteeringEngine.checkAllowedToDrive( veh, false, self.search == AIDriveStrategyMogli.searchStart ) --not ( veh.acParameters.isHired  ) )

	if type(veh.getCanAIFieldWorkerContinueWork) == "function" then
		local landsTurning=self.lands~=nil and (self.lands.active or self.lands.waitingHandover) and self.lands.phase~="work"
		local canContinueWork, stopAI, stopReason = veh:getCanAIFieldWorkerContinueWork(landsTurning)
		if not canContinueWork then
			allowedToDrive = false
			if stopAI then
				AIVELogger.info("DriveStrategy", "Stopping fieldwork on '%s': %s", tostring(veh:getName()), tostring(stopReason))
				veh:stopCurrentAIJob(stopReason or AIMessageErrorUnknown.new())
				return vX, vZ, not veh.acParameters.inverted, 0, 0
			end
		end
	end

	self.lastAllowedToDrive = allowedToDrive
		
	self.noSneak	   = false
	self.isAnimPlaying = false
	if self.search ~= nil or AIVEGlobals.raiseNoFruits > 0 then
		local isPlaying, noSneak = AutoSteeringEngine.checkIsAnimPlaying( veh, veh.acImplementsMoveDown )
		
		if isPlaying then
			if	self.animWaitTimer == nil then
				self.animWaitTimer = veh.acDeltaTimeoutWait
				self.isAnimPlaying = true
			elseif self.animWaitTimer > 0 then
				self.animWaitTimer = self.animWaitTimer - dt
				self.isAnimPlaying = true
			end
		else
			self.animWaitTimer = nil
			noSneak			= false
		end
		
		if noSneak then
			if	self.noSneakTimer == nil then
				self.noSneakTimer = veh.acDeltaTimeoutWait
				self.noSneak = true
			elseif self.noSneakTimer > 0 then
				self.noSneakTimer = self.noSneakTimer - dt
				self.noSneak = true
			end
		else
			self.noSneakTimer = nil
		end
		
		if	  allowedToDrive 
				and self.noSneak then
			AIVehicleExtension.setStatus( veh, 3 )
			allowedToDrive = false
		end
	else
		self.animWaitTimer = nil
		self.noSneakTimer  = nil
	end
	
	local fruitsDetected, fruitsAll = AutoSteeringEngine.hasFruits( veh )
	
	local speedLevel = 4
	if self.search == nil then
		speedLevel = 2
	end
--if veh.speed2Level ~= nil and 0 <= veh.speed2Level and veh.speed2Level <= 4 then
--	speedLevel = veh.speed2Level;
--end
	-- 20 km/h => lastSpeed = 5.555E-3 => speedLevelFactor = 234 * 5.555E-3 = 1.3
	-- 10 km/h =>						 speedLevelFactor				  = 0.7
	local speedLevelFactor = math.min( veh.lastSpeed * 234, 0.5 ) 
	
	if not allowedToDrive or speedLevel == 0 then
		AIVehicleExtension.statEvent( veh, "tS", dt )
		
		if self.lastDirection == nil then
			self.lastDirection = { AutoSteeringEngine.getWorldTargetFromSteeringAngle( veh, 0 ) }
		end
		
		return self.lastDirection[1], self.lastDirection[2], not veh.acParameters.inverted, AutoSteeringEngine.getMaxSpeed( veh, dt, 1, false, true, 0, false, 0.7 ), 0
	end
	
	
	
	if not self.lastAllowedToDrive then
		AIVehicleExtension.setAIImplementsMoveDown(veh,true,true)
	end
	if self.lands~=nil and (self.lands.active or self.lands.waitingHandover or self.lands.finishingPass) then
		return self:getLandsDriveData(dt,vX,vY,vZ)
	end
	if self.lands~=nil and self.search==AIDriveStrategyMogli.searchCircle
		and self.lands:requestHandover("perimeter edge reacquisition") then
		return self:getLandsDriveData(dt,vX,vY,vZ)
	end
	if self.lands~=nil and self.search==nil and self.lands:finishPerimeterPass() then
		return self:getLandsDriveData(dt,vX,vY,vZ)
	end
	
	local offsetOutside = 0;
	if	 veh.acParameters.rightAreaActive then
		offsetOutside = -1;
	elseif veh.acParameters.leftAreaActive then
		offsetOutside = 1;
	end;
	
	self.aiveTurnTimer		  = self.aiveTurnTimer - dt;
	veh.acTurnOutsideTimer = veh.acTurnOutsideTimer - dt;

--==============================================================				
	
	if	 self.search ~= nil then
		veh.aiRescueTimer = veh.aiRescueTimer - dt;
	else
		veh.aiRescueTimer = math.max( veh.aiRescueTimer, veh.acDeltaTimeoutStop )
	end
	
	if veh.aiRescueTimer < 0 then
		safeStopAIJob(veh, AIMessageErrorBlockedByObject, "aiRescueTimer expired; search=" .. tostring(self.search) .. "; turnStage=" .. tostring(self.turnData ~= nil and self.turnData.stage or "nil"))
		return
	end
		
--==============================================================				
	local angle, angle2 = nil, nil
	local angleMax = veh.acDimensions.maxSteeringAngle;
	local detected = false;
	local border   = 0;
	local angleFactor;
	local offsetOutside;
	local noReverseIndex = 0;
	local angleOffset = 6;
	local angleOffsetStrict = 4;
	local stoppingDist = 0.5;
	local turn2Outside = false
--==============================================================		
--==============================================================		
	local turnAngle2 = AutoSteeringEngine.getTurnAngle(veh)
	local turnAngle  = math.deg(turnAngle2)

	if veh.acParameters.leftAreaActive then
		turnAngle = -turnAngle;
	end;

	if fruitsDetected and self.search ~= nil then
		if veh.acFruitAllTimer == nil then
			veh.acFruitAllTimer = veh.acDeltaTimeoutStart
		elseif veh.acFruitAllTimer > 0 then
			veh.acFruitAllTimer = veh.acFruitAllTimer - dt
		else
			fruitsAll = true
		end
	else
		veh.acFruitAllTimer = nil
	end	
	
	noReverseIndex  = AutoSteeringEngine.getNoReverseIndex( veh );
	
--==============================================================				
	if self.search == AIDriveStrategyMogli.searchOutside and AutoSteeringEngine.getIsAtEnd( veh ) then
		AutoSteeringEngine.ensureToolIsLowered( veh, true )	
		self.search            = nil
		self.aiveTurnTimer		       = veh.acDeltaTimeoutNoTurn;
		veh.acTurnOutsideTimer = math.max( self.aiveTurnTimer, veh.acDeltaTimeoutNoTurn );
		veh.aiRescueTimer	     = veh.acDeltaTimeoutStop;		
	end
	
	local isInField = false
	if self.search == nil or veh.acParameters.straight then
		isInField = true
	end
	
	local straightAbsAngle = math.min( math.max( math.rad( 0.5 * turnAngle ), -veh.acDimensions.maxSteeringAngle ), veh.acDimensions.maxSteeringAngle )
	
	if math.abs( veh.acAxisSide ) > 0.1 then
		detected   = false
		border     = 0
		angle2     = 0
		tX         = nil
		tZ         = nil
		dist       = math.huge
		speedLevel = 1
		
		self.aiveTurnTimer = self.aiveTurnTimer + dt;
		veh.waitForTurnTime = veh.waitForTurnTime + dt;
		if veh.acTurnStage <= 0 then
			veh.aiRescueTimer = veh.aiRescueTimer + dt;
		end			
	else
		local ta, af, na
		
		if	    self.search    == nil
				and ( self.aiveTurnTimer < 0 
					 or AutoSteeringEngine.processIsAtEnd( veh ) )
				then
			ta = straightAbsAngle
		
			if noReverseIndex <= 0 and veh.acDimensions.zBack < 0 then
				ta = math.max( ta, 0 )
			end
			if not veh.acParameters.leftAreaActive then
				ta = -ta
			end
		end
		
		if     self.search == nil then
			af = veh.acParameters.angleFactor 
			na = "L"
		elseif self.search == AIDriveStrategyMogli.searchStart  then
			na = "M"
		elseif self.search == AIDriveStrategyMogli.searchUTurn  then
			na = "M"
		else
			na = "I"
		end
		
	--if      not AutoSteeringEngine.hasArticulatedAxis( vehicle ) and AIVEGlobals.staticRoot > 0
	--		and self.search == nil
	--		and ta == nil
	--		and self.lastChainResult ~= nil
	--		and g_currentMission.time - self.lastChainResult[1] < 500
	--		and self.lastChainResult[2]
	--		and self.lastChainResult[4] <= 0 then 
	--	detected = self.lastChainResult[2]
	--	angle2   = self.lastChainResult[3]
	--	border   = self.lastChainResult[4]
	--	tX       = self.lastChainResult[5]
	--	tZ       = self.lastChainResult[6]
	--	dist     = self.lastChainResult[7]
	--else 
			detected, angle2, border, tX, _, tZ, dist = AutoSteeringEngine.processChain( veh, isInField, ta, af, na )
	--	--                       1                      2         3       4       5   6   7
	--	self.lastChainResult = { g_currentMission.time, detected, angle2, border, tX, tZ, dist }
	--end 
	end
	
	local absAngle = angle2 
	if not veh.acParameters.leftAreaActive then
		absAngle = -angle2 
	end
	
	if dist == nil then
		dist = math.huge
	end
		
--==============================================================		
	local isAtEnd = false
	if self.search == nil then
		if self.isAtEndTimer < 0 then
			isAtEnd = true
		elseif AutoSteeringEngine.getIsAtEnd( veh ) then
			self.isAtEndTimer = self.isAtEndTimer - dt
			isAtEnd = true
		else 
			self.isAtEndTimer = veh.acDeltaTimeoutWait
		end
	else
		self.isAtEndTimer = veh.acDeltaTimeoutWait
	end
	
	local stopCP = false
		
	if self.search == nil and isAtEnd then
		veh.acMinDistanceToStop = math.max( 0.5, veh.acMinDistanceToStop - dt * veh.lastSpeed )
		distanceToStop = veh.acMinDistanceToStop
		
		if veh.acTurnMode == "7" and veh.acChopperWithCourseplay then
			AIVehicleExtension.stopCoursePlayMode2( veh, true )
		end
		
		if      not fruitsDetected	
				and not ( veh.acParameters.upNDown and veh.acParameters.headland and veh.acParameters.bigHeadland ) then 
		-- raise as early as possible but not with bigHeadland
			detected = false 
		end 
	else
		veh.acMinDistanceToStop = math.max( 1, veh.acDimensions.toolDistance - veh.acDimensions.zBack ) + AIVEGlobals.fruitsInFront
		if self.search ~= nil then
			distanceToStop = math.huge 
		else
			distanceToStop = math.max( veh.acMinDistanceToStop, dist )
		end
	end		
	
	if not ( detected or isAtEnd ) then
		speedLevel = 4
	end
	
	if veh.acDebugRetry and fruitsDetected then
		print("Starting debug 1xx...: "..tostring(self.search))
		veh.acDebugRetry = nil
		self.aiveTurnTimer    = -1
		border           = 99
		detected         = false
		AutoSteeringEngine.shiftTurnVector( veh, -1 )
	end
	
--==============================================================				
	turn2Outside = false
	
	if	    self.search    == nil
			and border         <= 0
			and ( self.aiveTurnTimer < 0 
				 or isAtEnd 
				 or ( AutoSteeringEngine.getTraceLength(veh) > AIVEGlobals.minTraceLen and not detected ) )
			then
		
		local ta = straightAbsAngle
		
	--if noReverseIndex <= 0 and veh.acDimensions.zBack < 0 then
	--	ta = 0 
	--end
	--print( AutoSteeringEngine.degToString( turnAngle )..", "..AutoSteeringEngine.radToString( ta )..", "..AutoSteeringEngine.radToString( absAngle ))
		
		if detected then
			if absAngle < ta - 0.01 then 
				angle = ta 
			end 
		else
			if math.abs( ta - absAngle ) > 0.01 then 
				angle = ta
			end 
		end
	elseif  detected then
	-- everything is ok
	elseif  border > 0 then
	-- border !!!
		turn2Outside = AutoSteeringEngine.hasLeftFruits( veh )	
		detected     = false
		speedLevel   = 4
		
		if     self.search == nil then
			local f = 1
			if veh.acDimensions.zBack < 0 then
			-- keep calm and don't move!!! Going to outside would just make it worse
				if AutoSteeringEngine.hasArticulatedAxis( vehicle ) then
					f = 0
				elseif noReverseIndex <= 0 then
					f = 0.1
				else
					f = 0.25
				end
			end
			angle  = math.min( math.min( 0, straightAbsAngle ) + f * veh.acDimensions.maxSteeringAngle, absAngle )
		elseif self.search == AIDriveStrategyMogli.searchStart then
			angle = veh.acDimensions.maxSteeringAngle
		elseif turn2Outside and fruitsDetected then
			if	   veh.acTurnMode == "C" 
					or veh.acTurnMode == "8" 
					or veh.acTurnMode == "O" then
				if self.search == AIDriveStrategyMogli.searchUTurn then
					AutoSteeringEngine.shiftTurnVector( veh, 0.5 )
					self.turnData.stage = 105
					self.currentTurnStrategy = self.turnStrategies[1]		
					self.currentTurnStrategy:startTurn( self.turnData )			
					return self.currentTurnStrategy:getDriveData( dt, vX,vY,vZ, self.turnData )
				end
			else
				if self.search == AIDriveStrategyMogli.searchUTurn then
					AutoSteeringEngine.shiftTurnVector( veh, 0.5 )
					self.turnData.stage = 110
					self.currentTurnStrategy = self.turnStrategies[1]		
					self.currentTurnStrategy:startTurn( self.turnData )			
					return self.currentTurnStrategy:getDriveData( dt, vX,vY,vZ, self.turnData )
				else
					AutoSteeringEngine.shiftTurnVector( veh, 0.5 )
					self.turnData.stage = 115
					self.currentTurnStrategy = self.turnStrategies[1]		
					self.currentTurnStrategy:startTurn( self.turnData )			
					return self.currentTurnStrategy:getDriveData( dt, vX,vY,vZ, self.turnData )
				end
			end
			self.aiveTurnTimer = veh.acDeltaTimeoutWait
		else
			angle = veh.acDimensions.maxSteeringAngle
		end
	elseif  self.search == AIDriveStrategyMogli.searchStart then
	-- start of hired worker
		angle = 0
	elseif     self.search == AIDriveStrategyMogli.searchUTurn then
	-- after U-turn
		local a, o, tX, tZ = AutoSteeringEngine.navigateToSavePoint( veh, 3, AIVehicleExtension.navigationFallbackRetry )
		if not o then
			angle = -veh.acDimensions.maxSteeringAngle 
		end
	elseif self.search == AIDriveStrategyMogli.searchOutside then
	-- after turn 2 outside 
		local a, o, tX, tZ = AutoSteeringEngine.navigateToSavePoint( veh, 3, AIVehicleExtension.navigationFallbackRetry )
		if not o then
			angle = veh.acDimensions.maxSteeringAngle
		end
	elseif self.search == AIDriveStrategyMogli.searchCircle then
	-- after 90° turn
		a, o, tX, tZ = AutoSteeringEngine.navigateToSavePoint( veh, 4, AIVehicleExtension.navigationFallbackRotateMinus )
		if not o then
			angle = -veh.acDimensions.maxSteeringAngle
		end
	else
		angle = -veh.acDimensions.maxSteeringAngle
	end
		
--==============================================================				
--==============================================================				
-- threshing...					
	if	 self.search == nil then		
		
		local doTurn = false;
		local uTurn  = false;
		
		if turn2Outside and not isAtEnd then
			if fruitsDetected and self.aiveTurnTimer < 0 then
				doTurn = true
				
				if AutoSteeringEngine.getTraceLength(veh) < AIVEGlobals.minTraceLen and veh.acParameters.upNDown then		
					uTurn = false
					veh.acClearTraceAfterTurn = false
				elseif veh.acParameters.upNDown then
					uTurn = true
					veh.acClearTraceAfterTurn = false
				else
					uTurn = false
					veh.acClearTraceAfterTurn = true
				end
			end
		elseif fruitsDetected or detected or not isAtEnd then		
			self.aiveTurnTimer   		   = math.max(self.aiveTurnTimer,veh.acDeltaTimeoutRun);
			veh.acTurnOutsideTimer = math.max( veh.acTurnOutsideTimer, veh.acDeltaTimeoutNoTurn );
		elseif self.aiveTurnTimer < 0 then 
			doTurn = true
			turn2Outside = false
			if veh.acParameters.straight then 
				uTurn = true 
				veh.acClearTraceAfterTurn = true
			elseif AutoSteeringEngine.getTraceLength(veh) < AIVEGlobals.minTraceLen and veh.acParameters.upNDown then		
				uTurn = false
				veh.acClearTraceAfterTurn = false
			else
				uTurn = veh.acParameters.upNDown
				veh.acClearTraceAfterTurn = true
			end
		end
		
		if doTurn then
			if self.lands~=nil and not turn2Outside and self.lands:requestHandover("selected perimeter corner") then
				return self:getLandsDriveData(dt,vX,vY,vZ)
			end
			
			AutoSteeringEngine.initTurnVector( veh, uTurn, turn2Outside )

			if not turn2Outside then 
				if veh.aiveChain ~= nil and veh.aiveChain.trace ~= nil and veh.aiveChain.trace.isUTurn ~= nil then 
					veh.aiDriveTarget = { veh.aiveChain.trace.ux, veh.aiveChain.trace.uz }
				end 
				
				veh.aiDriveDirection[1] = - veh.aiDriveDirection[1]
				veh.aiDriveDirection[2] = - veh.aiDriveDirection[2]
				
			--local dist	= math.floor( 4 * math.max( 10, veh.acDimensions.distance ) )
			--local wx,_,wz = AutoSteeringEngine.getAiWorldPosition( veh )
			--local stop	= true
			--local lx,lz
			--for i=0,dist do
			--	for j=0,dist do
			--		for k=1,4 do
			--			if     k==1 then 
			--				lx = wx + i
			--				lz = wz + j
			--			elseif k==2 then
			--				lx = wx - i
			--				lz = wz + j
			--			elseif k==3 then
			--				lx = wx + i
			--				lz = wz - j
			--			else
			--				lx = wx - i
			--				lz = wz - j
			--			end
			--			if	    AutoSteeringEngine.isChainPointOnField( veh, lx-0.5, lz-0.5 ) 
			--					and AutoSteeringEngine.isChainPointOnField( veh, lx-0.5, lz+0.5 ) 
			--					and AutoSteeringEngine.isChainPointOnField( veh, lx+0.5, lz-0.5 ) 
			--					and AutoSteeringEngine.isChainPointOnField( veh, lx+0.5, lz+0.5 ) 
			--					then
			--				local x = lx - 0.5
			--				local z1= lz - 0.5
			--				local z2= lz + 0.5
			--				if AutoSteeringEngine.hasFruitsSimple( veh, x,z1,x,z2, 1 ) then
			--					stop = false
			--					break
			--				end
			--			end
			--		end
			--	end
			--end
			--		
			--if stop then
				if not ( AutoSteeringEngine.hasFoundNext( veh ) ) then
					safeStopAIJob(veh, AIMessageSuccessFinishedJob, "AIMessageSuccessFinishedJob")
					return
				end
			end
			
			self:updateTurnData()
			
			veh.aiRescueTimer  = 3 * veh.acDeltaTimeoutStop;
			angle			   = 0
			
			self.search = AIDriveStrategyMogli.searchCircle
			
			if     turn2Outside then
				self.search = AIDriveStrategyMogli.searchOutside
		-- turn to outside because we are in the middle of the field
				if	   veh.acTurnMode == "C" 
						or veh.acTurnMode == "8" 
						or veh.acTurnMode == "O" then
					self.turnData.stage = 100
				else	
					self.turnData.stage = 120
				end
				self.aiveTurnTimer = veh.acDeltaTimeoutWait;
			elseif uTurn			   then
		-- the U turn
				--invert turn angle because we will swap left/right in about 10 lines
				self.search = AIDriveStrategyMogli.searchUTurn
				
				
				turnAngle = -turnAngle;
				if	 veh.acTurnMode == "O" then				
					self.turnData.stage = 70				
				elseif veh.acTurnMode == "8" then
					self.turnData.stage = 80				
				elseif veh.acTurnMode == "A" then
					self.turnData.stage = 50;
				elseif veh.acTurnMode == "Y" then
					self.turnData.stage = 40;
				else--if veh.acTurnMode == "T" then
					self.turnData.stage = 20;
				end
				self.aiveTurnTimer = veh.acDeltaTimeoutWait;
				veh.waitForTurnTime = g_currentMission.time + self.aiveTurnTimer;
				veh.acParameters.leftAreaActive  = not veh.acParameters.leftAreaActive;
				veh.acParameters.rightAreaActive = not veh.acParameters.rightAreaActive;
				AIVehicleExtension.sendParameters(veh);
				AutoSteeringEngine.setChainStraight( veh );	
				
			--if veh.acTurnMode == "O" then
			--	self.currentTurnStrategy = self.turnStrategies[self.ts_U_O]
			--end
			elseif veh.acTurnMode == "C" 
					or veh.acTurnMode == "8" 
					or veh.acTurnMode == "O" then
		-- 90° turn w/o reverse
				self.turnData.stage = 10
				self.aiveTurnTimer = veh.acDeltaTimeoutWait;
				veh.waitForTurnTime = g_currentMission.time + self.aiveTurnTimer;
			elseif veh.acTurnMode == "L" 
					or veh.acTurnMode == "A" 
					or veh.acTurnMode == "Y" then
		-- 90° turn with reverse
			--self.turnData.stage = 1;
			--self.aiveTurnTimer = veh.acDeltaTimeoutWait;
				self.currentTurnStrategy = self.turnStrategies[self.ts_C_R]
			elseif veh.acTurnMode == "7" then 
		-- 90° new turn with reverse
				self.turnData.stage = 90;
				self.aiveTurnTimer = veh.acDeltaTimeoutWait;
			else
		-- 90° turn with reverse
				self.turnData.stage = 30;
				self.aiveTurnTimer = veh.acDeltaTimeoutWait;
			end
			
			if self.currentTurnStrategy == nil then
				self.currentTurnStrategy = self.turnStrategies[1]
			end
			
			veh:aiFieldWorkerStartTurn( veh.acParameters.leftAreaActive ) --, self.currentTurnStrategy )
			veh:aiFieldWorkerTurnProgress( 0, veh.acParameters.leftAreaActive )
	
			self.currentTurnStrategy:startTurn( self.turnData )
			
			return self.currentTurnStrategy:getDriveData( dt, vX,vY,vZ, self.turnData )
			
	--elseif detected or fruitsDetected then
		else
			AutoSteeringEngine.saveDirection( veh, true, border > 0, true );
		end
		
--==============================================================				
-- searching...
	else
			
		if not detected then
			self.aiveTurnTimer = math.max( self.aiveTurnTimer, veh.acDeltaTimeoutRun )
		elseif isAtEnd then
			self.aiveTurnTimer = math.max( self.aiveTurnTimer, veh.acDeltaTimeoutRun )
	--elseif not fruitsAll then
		elseif not fruitsDetected then
			self.aiveTurnTimer = math.max( self.aiveTurnTimer, veh.acDeltaTimeoutRun )
		elseif AutoSteeringEngine.isBeforeStartNode( veh ) then
			self.aiveTurnTimer = math.max( self.aiveTurnTimer, veh.acDeltaTimeoutRun )
		elseif self.aiveTurnTimer < 0 then
			if veh.acClearTraceAfterTurn then
				AutoSteeringEngine.clearTrace( veh );
				AutoSteeringEngine.saveDirection( veh, false );
			end
			AutoSteeringEngine.ensureToolIsLowered( veh, true )	
			self.search            = nil
			self.aiveTurnTimer		 = veh.acDeltaTimeoutNoTurn;
			veh.acTurnOutsideTimer = math.max( self.aiveTurnTimer, veh.acDeltaTimeoutNoTurn );
			veh.aiRescueTimer	     = veh.acDeltaTimeoutStop;
		end		
		
--==============================================================				
--==============================================================				
	end
	
	local smooth = nil
	
	if veh.acAxisSideFactor == nil or veh.acLastAbsAngle == nil then
		veh.acAxisSideFactor = 1000
	elseif math.abs( veh.acAxisSide ) >= 0.1 then
		veh.acAxisSideFactor = math.max( veh.acAxisSideFactor - dt, 0 )
	elseif veh.acAxisSideFactor < 1000  then
		veh.acAxisSideFactor = math.min( veh.acAxisSideFactor + dt, 1000 )
	end
	
	local f = 0.001 * veh.acAxisSideFactor
	
	if f <= 0.999 then
		absAngle = veh.acLastAbsAngle
		local a  = 0
		
		if     veh.acAxisSide <= -0.999 then
			a =  veh.acDimensions.maxSteeringAngle
  		smooth = 0.03
		elseif veh.acAxisSide >=  0.999 then
			a = -veh.acDimensions.maxSteeringAngle
  		smooth = 0.03
		else
			local midAngle = veh.acLastAbsAngle
			if not veh.acParameters.leftAreaActive then
				midAngle = -midAngle
			end
			
			local g = (f-1)*veh.acAxisSide
			local a = f*midAngle 
			
			if f < 0 then
				a = midAngle + g * ( veh.acDimensions.maxSteeringAngle + midAngle )
			else
				a = midAngle + g * ( veh.acDimensions.maxSteeringAngle - midAngle )
			end
			smooth = 0.05
		end
		
		tX,tZ  = AutoSteeringEngine.getWorldTargetFromSteeringAngle( veh, a )

	elseif angle ~= nil then
		if not veh.acParameters.leftAreaActive then
			angle = -angle 
		end
		tX,tZ  = AutoSteeringEngine.getWorldTargetFromSteeringAngle( veh, angle )
	elseif tX == nil and angle2 ~= nil then
		tX,tZ  = AutoSteeringEngine.getWorldTargetFromSteeringAngle( veh, angle2 )
--elseif border > 0 then
--	veh.spec_aiVehicle.aiSteeringSpeed = 1
--elseif not detected then 
--	veh.spec_aiVehicle.aiSteeringSpeed = 2 * veh.acSteeringSpeed
--elseif veh.acLastAbsAngle == nil then
--	veh.spec_aiVehicle.aiSteeringSpeed = veh.acSteeringSpeed
--else
--	if     absAngle > veh.acLastAbsAngle then
--		veh.spec_aiVehicle.aiSteeringSpeed = 2.0 * veh.acSteeringSpeed
--	elseif absAngle < veh.acLastAbsAngle then
--		veh.spec_aiVehicle.aiSteeringSpeed = 0.5 * veh.acSteeringSpeed
--	else
--		veh.spec_aiVehicle.aiSteeringSpeed =       veh.acSteeringSpeed
--	end
--	if     absAngle > 0 then
--		veh.spec_aiVehicle.aiSteeringSpeed = 2.0 * veh.spec_aiVehicle.aiSteeringSpeed
--	elseif absAngle < 0 then
--		veh.spec_aiVehicle.aiSteeringSpeed = 0.5 * veh.spec_aiVehicle.aiSteeringSpeed
--	end
	end	
	
--veh.spec_aiVehicle.aiSteeringSpeed = veh.spec_aiVehicle.aiSteeringSpeed * math.max( 1, veh.lastSpeed * 360 ) 
--veh.spec_aiVehicle.aiSteeringSpeed = math.min( veh.spec_aiVehicle.aiSteeringSpeed, ( veh.maxRotTime - veh.minRotTime ) / 100 )
	veh.acLastAbsAngle  = absAngle
	
	local tX2 = tX
	local tZ2 = tZ
	
	tX, tZ = self:adjustPosition( tX2, tZ2, moveForwards, distanceToStop )

	if smooth ~= nil and self.lastDirection ~= nil then
		tX = self.lastDirection[1] + smooth * ( tX - self.lastDirection[1] )
		tZ = self.lastDirection[2] + smooth * ( tZ - self.lastDirection[2] )
	end
	
	local useReduceSpeed = false
	local slowFactor     = 1
	
	if      self.search == nil 
			and angle2 ~= nil 
			and math.abs( angle2+angle2 ) > veh.acDimensions.maxSteeringAngle then
		slowFactor = math.min( 1, AutoSteeringEngine.getWantedSpeed( veh, 4 ) / AutoSteeringEngine.getWantedSpeed( veh, 2 ) )
		if slowFactor < 1 and math.abs( angle2 ) < veh.acDimensions.maxSteeringAngle then
			slowFactor = slowFactor + ( 1 - slowFactor ) * 2 * ( 1 - math.abs( angle2 ) / veh.acDimensions.maxSteeringAngle ) 
		end
		speedLevel     = 2
		useReduceSpeed = true
	end

	maxSpeed = AutoSteeringEngine.getMaxSpeed( veh, dt, 1, true, true, speedLevel, useReduceSpeed, slowFactor )
			
--if self.search == nil and ( distanceToStop < 5 or maxSpeed < 8 ) then
--	veh:acDebugPrint("Slow...: "..tostring(speedLevel).."; "..tostring(useReduceSpeed).."; "..tostring(distanceToStop).."; "..tostring(dist).."; "..tostring(slowFactor).."; "..tostring(border).."; "..tostring(detected).."; "..tostring(maxSpeed))
--end
	
	if math.abs( veh.acAxisSide ) > 0.1 then
		AIVehicleExtension.setStatus( veh, 2 )
	elseif self.search ~= nil and self.search == AIDriveStrategyMogli.searchStart then
		if detected then
			AIVehicleExtension.setStatus( veh, 2 ) 
		else
			AIVehicleExtension.setStatus( veh, 0 )
		end
	elseif detected then
		if veh.atHud ~= nil then 
			veh.atHud.InfoText = "" 
		end 
		AIVehicleExtension.setStatus( veh, 1 )
	else
		AIVehicleExtension.setStatus( veh, 2 )
	end	
	
	self.lastDirection = { tX, tZ }
	
	self:printReturnInfo( tX, vY, tZ, true, maxSpeed, distanceToStop )

	if distanceToStop < 0 then 
		distanceToStop = 0
	elseif distanceToStop > 10 then 
		distanceToStop = 10 
	end 

	return tX, tZ, not veh.acParameters.inverted, maxSpeed, distanceToStop
end


