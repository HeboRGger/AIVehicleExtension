--
-- AIDriveStrategyCollisionOtherAI
--  drive strategy to stop vehicle on collision (aiTrafficCollision trigger)
--

AIDriveStrategyCollisionOtherAI = {}
local AIDriveStrategyCollisionOtherAI_mt = Class(AIDriveStrategyCollisionOtherAI, AIDriveStrategy)

function AIDriveStrategyCollisionOtherAI.new(reconstructionData, customMt)
	if customMt == nil then
		customMt = AIDriveStrategyCollisionOtherAI_mt
	end

	local self = AIDriveStrategy.new(reconstructionData, customMt)
	
	self.collisionTime = 0
	self.otherAIs      = {}
	
	return self
end

function AIDriveStrategyCollisionOtherAI:delete()
	AIDriveStrategyCollisionOtherAI:superClass().delete(self)
end

function AIDriveStrategyCollisionOtherAI:setAIVehicle(vehicle)
	self.mogliText = "AIDriveStrategyCollisionOtherAI"
	AIDriveStrategyCollisionOtherAI:superClass().setAIVehicle(self, vehicle)
end

function AIDriveStrategyCollisionOtherAI:addDebugText( s )
	if AIVELogger ~= nil and AIVELogger.currentLevel >= AIVELogger.LEVEL_DEBUG then
		AIVELogger.debug("CollisionOtherAI", "%s", tostring(s))
	elseif AIVEGlobals.devFeatures > 0 then
		print( s )
	end
end

function AIDriveStrategyCollisionOtherAI:getDriveData(dt, vX,vY,vZ)
	self.vehicle.aiveMaxCollisionSpeed = nil
	self.vehicle.aiveCollisionDistance = nil
	-- The FS25 controller protects all modes. Its coordinated yielding must
	-- not also be constrained by the legacy mutual-stop strategy.
	if self.vehicle.aiveObstacleController and self.vehicle.aiveObstacleController:isAvailable() then
		return nil,nil,nil,nil,nil
	end

	if self.vehicle.movingDirection < 0 and self.vehicle:getLastSpeed(true) > 2 then
		return nil, nil, nil, nil, nil
	end

	local triggerId
	if self.vehicle.acParameters == nil
			or self.vehicle.acParameters.upNDown
			or not self.vehicle.acParameters.collision
			or self.vehicle.acCollidingVehicles == nil then
		return nil, nil, nil, nil, nil
	elseif self.vehicle.acParameters.rightAreaActive then
		triggerId = self.vehicle.acOtherCombineCollisionTriggerR
	else
		triggerId = self.vehicle.acOtherCombineCollisionTriggerL
	end

	local tX, tZ, dirX, dirZ = nil, nil, nil, nil

	for otherAI,bool in pairs(self.otherAIs) do
		if bool
				and otherAI.acRefNode ~= nil
				and otherAI.aiveIsStarted
				and otherAI.acTurnStage ~= 0 then
			self.otherAIs[otherAI] = true
		else
			self.otherAIs[otherAI] = nil
		end
	end

	if triggerId ~= nil and self.vehicle.acCollidingVehicles[triggerId] ~= nil then
		for otherAI,bool in pairs(self.vehicle.acCollidingVehicles[triggerId]) do
			local isFieldWork = type(otherAI.getIsFieldWorkActive) == "function" and otherAI:getIsFieldWorkActive()
			local extActive = AIVEConflictGuard ~= nil and AIVEConflictGuard.isExternalAIActive(otherAI) or false
			if bool
					and isFieldWork
					and not extActive
					and ( otherAI.ad == nil or not ( otherAI.ad.isActive ) )
					and ( otherAI.cp == nil or not ( otherAI.cp.isDriving ) ) then
				self.otherAIs[otherAI] = true
			end
		end
	end

	for otherAI,bool in pairs(self.otherAIs) do
		if bool and self.vehicle.acRefNode ~= nil then
			local blocked = true

			if tX == nil or tZ == nil or dirX == nil or dirZ == nil then
				tX,_,tZ     = localToWorld(self.vehicle.acRefNode, 0,0,1)
				dirX,_,dirZ = localDirectionToWorld(self.vehicle.acRefNode, 0,0,1)
			end

			if g_currentMission ~= nil and g_currentMission.time < self.collisionTime + 2000 then
				self:addDebugText("AIDriveStrategyCollisionOtherAI :: STOP due to collision 1")
				return tX, tZ, true, 0, math.huge
			elseif otherAI.acRefNode ~= nil
					and otherAI.aiveIsStarted
					and otherAI.acTurnStage == 0 then
				local angle = AutoSteeringEngine.getRelativeYRotation( otherAI.acRefNode, self.vehicle.acRefNode )
				if math.abs( angle ) < 0.1667 * math.pi
						and otherAI.spec_motorized ~= nil
						and otherAI.spec_motorized.motor ~= nil then
					local speedLim = otherAI.spec_motorized.motor.speedLimit or (type(otherAI.spec_motorized.motor.getMaximumForwardSpeed) == "function" and otherAI.spec_motorized.motor:getMaximumForwardSpeed() or nil)
					if speedLim ~= nil then
						local s = speedLim * math.cos( angle )
						if self.vehicle.aiveMaxCollisionSpeed == nil
								or self.vehicle.aiveMaxCollisionSpeed > s then
							self.vehicle.aiveMaxCollisionSpeed = s
						end
					end
				end

				local wx1, _, wz1 = getWorldTranslation( otherAI.acRefNode )
				local wx2, _, wz2 = getWorldTranslation( self.vehicle.acRefNode )
				local dX = math.abs( ( wx1 - wx2 ) * dirZ - ( wz1 - wz2 ) * dirX )
				local dZ = math.abs( ( wx1 - wx2 ) * dirX + ( wz1 - wz2 ) * dirZ )
				local d2 = math.max( 20, dZ )
				if self.vehicle.aiveCollisionDistance == nil
						or self.vehicle.aiveCollisionDistance > d2 then
					self.vehicle.aiveCollisionDistance = d2
				end
				local acDist = (self.vehicle.acDimensions ~= nil and self.vehicle.acDimensions.distance ~= nil) and self.vehicle.acDimensions.distance or 2
				if dX > acDist + 1 or dZ > 30 then
					self:addDebugText(string.format("Not blocked: %5.2fm,  %5.2fm", dX, dZ))
					blocked = false
				end
			end

			if blocked then
				self:addDebugText("AIDriveStrategyCollisionOtherAI : STOP due to collision 2")
				self.collisionTime = g_currentMission ~= nil and g_currentMission.time or 0
				self:setHasCollision(true)
				return tX, tZ, true, 0, math.huge
			end
		end
	end

	self:setHasCollision(false)
	return nil, nil, nil, nil, nil
end

function AIDriveStrategyCollisionOtherAI:setHasCollision(state)
	if state ~= self.lastHasCollision then
		self.lastHasCollision = state

		if g_server ~= nil then
			g_server:broadcastEvent(AIVehicleIsBlockedEvent.new(self.vehicle, state), true, nil, self.vehicle)
		end
		
		self.vehicle:setBeaconLightsVisibility(state, false)
	end
end

function AIDriveStrategyCollisionOtherAI:updateDriving(dt)
end


