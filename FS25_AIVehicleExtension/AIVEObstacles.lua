-- FS25 swept-footprint protection and local, validated obstacle detours.
-- All physics queries are synchronous. A stopped/yielding vehicle never grants
-- another vehicle permission to drive through it: every detour is swept again.
AIVEObstacles={}
AIVEObstacles.__index=AIVEObstacles
AIVEObstacles.CLEARANCE=0.10
AIVEObstacles.REVERSE_CLEARANCE=0.35
AIVEObstacles.controllers=setmetatable({},{__mode="k"})
local atan2=math.atan2 or function(y,x)return math.atan(y,x)end
local pi2=2*math.pi
local function dist(a,b)return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)end
local function wrap(a)return (a+math.pi)%pi2-math.pi end
local footprintCorners={{-1,-1},{1,-1},{1,1},{-1,1}}
local function root(v)
	if v and type(v.getRootVehicle)=="function" then return v:getRootVehicle() or v end
	return v
end
local function identity(v)
	return v and (v.rootNode or (v.components and v.components[1] and v.components[1].node)) or 0
end
local function speed(v)return math.abs(v.lastSpeedReal or v.lastSpeed or 0)*1000 end
local function flagSet(value,flag)return type(value)=="number" and value%(2*flag)>=flag end
local function routeDistance(p,path,first,last)
	local best=math.huge
	for i=first,math.max(first,last-1) do
		local a,b=path[i],path[math.min(last,i+1)]
		local dx,dz=b.x-a.x,b.z-a.z
		local t=math.max(0,math.min(1,((p.x-a.x)*dx+(p.z-a.z)*dz)/math.max(0.000001,dx*dx+dz*dz)))
		best=math.min(best,(p.x-a.x-t*dx)^2+(p.z-a.z-t*dz)^2)
	end
	return math.sqrt(best)
end

function AIVEObstacles.mustWait(hit)
	if hit==nil then return false end
	if hit.player then return true end
	local other=hit.vehicle
	if not other then return false end
	if other.aiveIsStarted or other.aiveObstacleController or speed(other)>0.2 then return true end
	if other.spec_aiFieldWorker and other.spec_aiFieldWorker.isActive then return true end
	if other.spec_aiVehicle and other.spec_aiVehicle.isActive then return true end
	for _,name in ipairs({"getIsAIActive","getIsControlled"}) do
		if type(other[name])=="function" then
			local ok,active=pcall(other[name],other)
			if ok and active then return true end
		end
	end
	return false
end

function AIVEObstacles.new(vehicle,strategy)
	local self=setmetatable({vehicle=vehicle,strategy=strategy,clock=0,nextProbe=0,phase="clear",ignore={},lastLog=0},AIVEObstacles)
	AIVEObstacles.controllers[vehicle]=self
	return self
end
function AIVEObstacles:isAvailable()return type(overlapBox)=="function" end
function AIVEObstacles:isEnabled()return self:isAvailable() and self.vehicle.acParameters.collision==true end
function AIVEObstacles:hasControl()return self.phase~="clear" end
function AIVEObstacles:log(message)
	AIVELogger.info("Obstacles","%s: %s",type(self.vehicle.getName)=="function" and self.vehicle:getName() or "vehicle",message)
end
function AIVEObstacles:describeHit(hit)
	local node=hit and hit.node or 0
	local name,group="unknown","unknown"
	if node~=0 and type(getName)=="function" then name=tostring(getName(node)) end
	if node~=0 and type(getCollisionFilterGroup)=="function" then group=tostring(getCollisionFilterGroup(node)) end
	return string.format("node=%s name=%s group=%s clearance=%.2f m stage=%s part=%s box=%.2fx%.2f m",tostring(node),name,group,hit and hit.distance or 0,tostring(self.vehicle.acTurnStage),tostring(hit and hit.part or "unknown"),hit and hit.width or 0,hit and hit.length or 0)
end
function AIVEObstacles:pose()
	local node=self.refNode or (self.vehicle.aiveChain or {}).refNode or self.vehicle.rootNode
	local x,y,z=getWorldTranslation(node)
	local dx,_,dz=localDirectionToWorld(node,0,0,1)
	return {x=x,y=y,z=z,h=atan2(dz,dx)}
end
function AIVEObstacles:dimensions()
	local v,c,d=self.vehicle,self.vehicle.aiveChain or {},self.vehicle.acDimensions or {}
	local pose=self:pose()
	local fx,fz=math.cos(pose.h),math.sin(pose.h)
	self.half=0;self.front=0;self.back=0;self.height=0
	self.radius=math.max(3.5,AIVELands.getTurnRadius(v))
	-- Raised asphalt/yard meshes are not represented by the terrain height
	-- map. Use the actual wheel support plane as well, otherwise their FLOOR
	-- is reported as a wall in front of the machine. Do not ignore the mesh:
	-- it can also contain real walls/posts, which must still be detected.
	local offsets=self.wheelOffsets or {};self.wheelOffsets=offsets
	for i=#offsets,1,-1 do offsets[i]=nil end
	for _,wheel in pairs((v.spec_wheels or {}).wheels or {}) do
		local f=wheel.physics
		if f and f.hasGroundContact and f.lastContactX and f.lastContactY and f.lastContactZ then
			local ground=getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,f.lastContactX,0,f.lastContactZ)
			local delta=f.lastContactY-ground
			if delta>=-0.5 and delta<=10 then offsets[#offsets+1]=math.max(0,delta) end
		end
	end
	table.sort(offsets)
	self.groundOffset=#offsets>0 and (offsets[math.ceil(#offsets/2)]+offsets[math.floor(#offsets/2)+1])/2 or 0
	self.ignore=self.ignore or {};self.parts=self.parts or {}
	for node in pairs(self.ignore) do self.ignore[node]=nil end
	local seen=self.dimensionSeen or {};self.dimensionSeen=seen
	for object in pairs(seen) do seen[object]=nil end
	local partCount=0
	local function add(obj)
		if not obj or seen[obj] or obj.isDeleted or obj.isDeleting then return end
		seen[obj]=true
		if obj.rootNode then self.ignore[obj.rootNode]=true end
		for _,component in pairs(obj.components or {}) do self.ignore[component.node]=true end
		local node=obj.rootNode or (obj.components and obj.components[1] and obj.components[1].node)
		if not node then return end
		local size=obj.size or {}
		local x,_,z=getWorldTranslation(node)
		local dx,_,dz=localDirectionToWorld(node,0,0,1)
		local h=atan2(dz,dx)
		local offset=size.lengthOffset or 0
		local lo,hi=offset-(size.length or 6)/2,offset+(size.length or 6)/2
		local left,right=(size.widthOffset or 0)-(size.width or 2.8)/2,(size.widthOffset or 0)+(size.width or 2.8)/2
		local function appendPart(a0,a1,b0,b1,label)
			local along,side=(a0+a1)/2,(b0+b1)/2
			local cx,cz=x+along*dx-side*dz,z+along*dz+side*dx
			local a,b=(cx-pose.x)*fx+(cz-pose.z)*fz,-(cx-pose.x)*fz+(cz-pose.z)*fx
			partCount=partCount+1
			local part=self.parts[partCount] or {};self.parts[partCount]=part
			part.along,part.side,part.h=a,b,wrap(h-pose.h)
			part.half,part.length,part.height,part.label=(b1-b0)/2+AIVEObstacles.CLEARANCE,(a1-a0)/2+AIVEObstacles.CLEARANCE,math.max(2.5,size.height or 3),label
			local ca,sa=math.cos(part.h),math.sin(part.h)
			local ex=math.abs(ca)*part.length+math.abs(sa)*part.half
			local ez=math.abs(sa)*part.length+math.abs(ca)*part.half
			self.front=math.max(self.front,a+ex);self.back=math.max(self.back,-a+ex)
			self.half=math.max(self.half,math.abs(b)+ez);self.height=math.max(self.height,part.height)
		end
		appendPart(lo,hi,left,right,"body")
		-- Unfolded tools can be wider than their transport size. Transform
		-- THEIR markers into THEIR frame, never inflate the entire combination.
		if type(obj.getAIMarkers)=="function" then
			local ml,mr,mb=obj:getAIMarkers()
			local a0,a1,b0,b1=math.huge,-math.huge,math.huge,-math.huge
			for _,marker in pairs({ml,mr,mb}) do
				if marker and marker~=0 then
					local mx,_,mz=getWorldTranslation(marker)
					local along=(mx-x)*dx+(mz-z)*dz
					local side=-(mx-x)*dz+(mz-z)*dx
					a0=math.min(a0,along);a1=math.max(a1,along)
					b0=math.min(b0,side);b1=math.max(b1,side)
				end
			end
			if a0<math.huge then
				-- A wide rear toolbar is not a 6 m-wide hopper all the way to
				-- the tractor. Protect its work rectangle separately from body.
				appendPart(a0,a1,b0,b1,"workbar")
			end
		end
	end
	add(v)
	for _,child in pairs(v.childVehicles or {}) do add(child) end
	if type(v.getAttachedAIImplements)=="function" then for _,item in ipairs(v:getAttachedAIImplements()) do add(item.object) end end
	for _,tool in pairs(c.tools or {}) do add(tool.obj) end
	-- Only a rigid combine/cutter may use close rear approaches. Articulated
	-- implements require their own kinematic model, not a smaller safety box.
	self.precisionCombine=v.spec_combine~=nil
	for object in pairs(seen) do
		if object~=v and (object.spec_trailer or object.spec_articulatedAxis or object.spec_attachable and object.spec_attachable.isTrailer) then self.precisionCombine=false end
	end
	for i=#self.parts,partCount+1,-1 do self.parts[i]=nil end
	-- Compatibility for a work-width-only tool with no separate scene object.
	if #self.parts==1 and not next(c.tools or {}) and not next(v.childVehicles or {}) then
		local part=self.parts[1]
		part.half=math.max(part.half,(d.distance or 0)+AIVEObstacles.CLEARANCE+0.15)
		self.half=math.max(self.half,part.half)
	end
end
function AIVEObstacles:reverseClearance()
	if not self.precisionCombine then return AIVEObstacles.REVERSE_CLEARANCE end
	-- CLEARANCE is already on the physical hull. Add braking distance and a
	-- small latency allowance; at rest this is 15 cm from the measured body.
	local s=speed(self.vehicle)
	return .05+s*.12+s*s/(2*1.5)
end
function AIVEObstacles:onOverlap(node)
	local ok,err=pcall(self.classifyNode,self,node)
	if not ok then
		if not self.sensorError then AIVELogger.errorOnce("obstacleSensor","Obstacles","Collision callback failed; stopping: %s",tostring(err)) end
		self.sensorError=true
		self.probeHit={sensorFailed=true,node=0,x=self.probeCenter.x,z=self.probeCenter.z,distance=0}
	end
	-- FS25 1.25 stops enumeration on false (verified in the live engine).
	-- Own components/triggers often arrive first; continue past ignored hits.
	return self.probeHit==nil
end
function AIVEObstacles:classifyNode(node)
	if node==nil or node==0 or node==g_currentMission.terrainRootNode then return false end
	if type(getHasTrigger)=="function" and getHasTrigger(node) then return false end
	-- Navigation-only volumes are not physical posts/trees. Real solids also
	-- carry STATIC_OBJECT/TREE/BUILDING/VEHICLE/etc. on the returned shape.
	if type(getCollisionFilterGroup)=="function" then
		local group=getCollisionFilterGroup(node)
		if flagSet(group,32) then
			local solid=false
			for _,flag in ipairs({2,2048,4096,65536,262144,524288,1048576}) do solid=solid or flagSet(group,flag) end
			if not solid then return false end
		end
	end
	local id,obj,player=node,nil,false
	for _=1,24 do
		if id==nil or id==0 then break end
		if self.ignore[id] or (self.vehicle.trafficCollisionIgnoreList or {})[id] then return false end
		if type(getCollisionFilterGroup)=="function" then
			player=player or flagSet(getCollisionFilterGroup(id),(CollisionFlag or {}).PLAYER or 1048576)
		end
		if obj==nil then
			if type(g_currentMission.getNodeObject)=="function" then obj=g_currentMission:getNodeObject(id)
			else obj=(g_currentMission.nodeToObject or {})[id] end
		end
		if type(getParent)~="function" then break end
		id=getParent(id)
	end
	obj=root(obj)
	if obj==root(self.vehicle) then return false end
	local x,z=self.probeCenter.x,self.probeCenter.z
	if type(getWorldTranslation)=="function" then
		local px,_,pz=getWorldTranslation(node)
		if type(px)=="number" and type(pz)=="number" and (px-x)^2+(pz-z)^2<900 then x,z=px,pz end
	end
	local vehicle=obj and (obj.spec_wheels~=nil or type(obj.getAIDirectionNode)=="function" or type(obj.getIsFieldWorkActive)=="function") and obj or nil
	self.probeHit=self.probeHit or {node=node,x=x,z=z,vehicle=vehicle,player=player or (obj and (obj.isPlayer==true or obj.spec_player~=nil))}
	return false
end
-- Clip an individual tool rectangle to the rear/front corridor when
-- reversing. Keeping the union avoids phantom collisions in the hitch gap.
local function clippedPart(part,front,back,reverse)
	local a,b,h=part.along,part.side,part.h
	if reverse then a,b,h=-a,-b,h+math.pi end
	-- A full part needs no polygon clipping or projection back into itself.
	if front==nil and back==nil and part.half>=0.01 and part.length>=0.01 then
		return a,b,h,part.half,part.length
	end
	local ca,sa=math.cos(h),math.sin(h)
	local polygon={}
	for _,corner in ipairs(footprintCorners) do
		local u,w=corner[1]*part.length,corner[2]*part.half
		polygon[#polygon+1]={x=a+u*ca-w*sa,z=b+u*sa+w*ca}
	end
	local function clip(limit,sign)
		local output={}
		local prev=polygon[#polygon]
		if not prev then return end
		for _,q in ipairs(polygon) do
			local pin,qin=sign*(prev.x-limit)<=0,sign*(q.x-limit)<=0
			if pin~=qin then
				local t=(limit-prev.x)/(q.x-prev.x)
				output[#output+1]={x=limit,z=prev.z+t*(q.z-prev.z)}
			end
			if qin then output[#output+1]=q end
			prev=q
		end
		polygon=output
	end
	if front~=nil then clip(front,1) end
	if back~=nil then clip(-back,-1) end
	if #polygon<3 then return end
	local u0,u1,w0,w1=math.huge,-math.huge,math.huge,-math.huge
	for _,q in ipairs(polygon) do
		local u,w=q.x*ca+q.z*sa,-q.x*sa+q.z*ca
		u0=math.min(u0,u);u1=math.max(u1,u);w0=math.min(w0,w);w1=math.max(w1,w)
	end
	if u1-u0<0.01 or w1-w0<0.01 then return end
	local u,w=(u0+u1)/2,(w0+w1)/2
	return u*ca-w*sa,u*sa+w*ca,h,(w1-w0)/2,(u1-u0)/2
end
function AIVEObstacles:onRoadSurfaceRay(node,x,y,z,distance,nx,ny,nz)
	if node==self.roadRayNode and ny>0.75 and y>self.roadRayFloor+0.02 and y<=self.roadRayFloor+0.75 then
		self.roadRayHeight=math.max(self.roadRayHeight or y,y)
	end
	-- raycastAll continues on false (unlike overlapBox enumeration).
	return false
end
function AIVEObstacles:roadSurfaceHeight(node,x,z,h,half,length,floor)
	if type(raycastAll)~="function" or type(getCollisionFilterGroup)~="function" then return nil end
	local group=getCollisionFilterGroup(node)
	if flagSet(group,(CollisionFlag or {}).TREE or 2048) then return nil end
	local road=((CollisionFlag or {}).STATIC_OBJECT or 2)+((CollisionFlag or {}).ROAD or 8192)+((CollisionFlag or {}).AI_DRIVABLE or 16384)
	self.roadRayNode=node;self.roadRayFloor=floor
	local ca,sa=math.cos(h),math.sin(h)
	local samples={}
	for _,corner in ipairs({{0,0},{-1,-1},{1,-1},{1,1},{-1,1}}) do
		local u,w=corner[1]*length,corner[2]*half
		local gx,gz=x+u*ca-w*sa,z+u*sa+w*ca
		self.roadRayHeight=nil
		local ok=pcall(raycastAll,gx,floor+1,gz,0,-1,0,1.5,"onRoadSurfaceRay",self,road)
		if ok and self.roadRayHeight then samples[#samples+1]={x=gx,z=gz,y=self.roadRayHeight} end
	end
	-- A broad upward-facing road surface needs two separated samples. A
	-- single pole top is never accepted as a new floor. Re-query the raised
	-- box afterwards, so vertical walls in the SAME merged mesh still block.
	for i=1,#samples do for j=i+1,#samples do
		local a,b=samples[i],samples[j]
		local dx,dz=b.x-a.x,b.z-a.z
		local length=math.sqrt(dx*dx+dz*dz)
		if length>=2 and math.abs(a.y-b.y)<0.35 then
			-- Verify area, not just a line: two points on the top of a low
			-- narrow fence are not a road. A third point 1 m to either side
			-- must belong to the same broad upward-facing surface.
			for _,sign in ipairs({-1,1}) do
				local gx,gz=(a.x+b.x)/2-sign*dz/length,(a.z+b.z)/2+sign*dx/length
				self.roadRayHeight=nil
				local ok=pcall(raycastAll,gx,floor+1,gz,0,-1,0,1.5,"onRoadSurfaceRay",self,road)
				if ok and self.roadRayHeight and math.abs(self.roadRayHeight-(a.y+b.y)/2)<0.35 then return math.max(a.y,b.y,self.roadRayHeight) end
			end
		end
	end end
	return nil
end
function AIVEObstacles:queryPart(x,z,h,half,length,height)
	local ca,sa=math.cos(h),math.sin(h)
	-- A long flat query at its centre's ground height cuts into rising roads.
	-- Follow the highest sampled ground under THIS part, not the whole rig.
	local y=getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,x,0,z)
	for _,corner in ipairs(footprintCorners) do
		local u,w=corner[1]*length,corner[2]*half
		local gx,gz=x+u*ca-w*sa,z+u*sa+w*ca
		y=math.max(y,getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,gx,0,gz))
	end
	self.probeCenter=self.probeCenter or {};self.probeCenter.x,self.probeCenter.z=x,z;self.probeHit=nil
	local flags=CollisionFlag or {}
	local mask=(flags.STATIC_OBJECT or 2)+(flags.AI_BLOCKING or 32)
		+(flags.TREE or 2048)+(flags.BUILDING or 4096)+(flags.VEHICLE or 65536)
		+(flags.DYNAMIC_OBJECT or 262144)+(flags.TRAFFIC_VEHICLE or 524288)+(flags.PLAYER or 1048576)
	-- FS25: dynamics, kinematics, statics, exactTest. Extents are HALF sizes.
	local ok,err=pcall(overlapBox,x,y+(self.groundOffset or 0)+0.25+height/2,z,0,math.pi/2-h,0,half,height/2,length,"onOverlap",self,mask,true,true,true,true)
	if ok and self.probeHit and not self.probeHit.vehicle and not self.probeHit.player and not self.probeHit.sensorFailed then
		local surface=self:roadSurfaceHeight(self.probeHit.node,x,z,h,half,length,y+(self.groundOffset or 0))
		if surface then
			self.probeHit=nil
			ok,err=pcall(overlapBox,x,surface+0.25+height/2,z,0,math.pi/2-h,0,half,height/2,length,"onOverlap",self,mask,true,true,true,true)
		end
	end
	if not ok then
		if not self.sensorError then
			AIVELogger.errorOnce("obstacleSensor","Obstacles","Physics query failed; stopping before continuing: %s",tostring(err))
		end
		self.sensorError=true
		self.probeHit={sensorFailed=true,node=0,x=x,z=z,distance=0}
	end
	return self.probeHit
end
function AIVEObstacles:box(p,reverse,frontLimit,backLimit,extra)
	local fx,fz=math.cos(p.h),math.sin(p.h)
	for _,part in ipairs(self.parts or {}) do
		local a,b,h,half,length=clippedPart(part,frontLimit,backLimit,reverse)
		if a then
			local hit=self:queryPart(p.x+a*fx-b*fz,p.z+a*fz+b*fx,p.h+h,half+(extra or 0),length+(extra or 0),part.height)
			if hit then
				hit.part=part.label or "body";hit.width=2*half;hit.length=2*length
				return hit
			end
		end
	end
end
function AIVEObstacles:rearSweep(p,distance)
	local steps=math.max(1,math.ceil(distance/0.4))
	local fx,fz=math.cos(p.h),math.sin(p.h)
	for i=0,steps do
		local moved=distance*i/steps
		-- Sweep each actual part through NEW space behind the machine.
		-- Merely raising backLimit clips the existing shapes; it never grows
		-- them into the retreat corridor. Leave the occupied front half out.
		local hit=self:box({x=p.x-moved*fx,z=p.z-moved*fz,h=p.h},false,moved)
		if hit then return hit end
	end
end
function AIVEObstacles:frontSweep(p,distance)
	local steps=math.max(1,math.ceil(distance/0.4))
	local fx,fz=math.cos(p.h),math.sin(p.h)
	for i=0,steps do
		local moved=distance*i/steps
		local hit=self:box({x=p.x+moved*fx,z=p.z+moved*fz,h=p.h},false,nil,moved)
		if hit then return hit end
	end
end
function AIVEObstacles:scan(p,target,forward,range,options)
	local h=p.h+(forward and 0 or math.pi)
	-- A recovered old checkpoint may predate the saved route target. A
	-- straight safety probe is still valid; never dereference a missing goal.
	target=target or {x=p.x+math.cos(h)*5,z=p.z+math.sin(h)*5}
	local dx,dz=target.x-p.x,target.z-p.z
	local cross=-math.sin(h)*dx+math.cos(h)*dz
	local k=2*cross/math.max(1,dx*dx+dz*dz)
	k=math.max(-1/self.radius,math.min(1/self.radius,k))
	-- The edge controller updates its steering point every frame. Extending
	-- a tight instantaneous curve for 14m predicts a circle the helper never
	-- intends to drive. Keep long straight previews, but only the near arc
	-- of a changing working turn. Physical braking and moving-object waits
	-- still sweep the complete rig through that near corridor.
	if options and options.maxYaw and math.abs(k)>1e-6 then range=math.min(range,options.maxYaw/math.abs(k)) end
	local x,z=p.x,p.z
	-- Reverse corners approach fixed objects slowly; use a finer sweep so
	-- the last metre is not quantised into 40 cm jumps.
	local steps=math.max(1,math.ceil(range/(forward and 0.4 or 0.15)))
	for i=0,steps do
		local hit=self:box({x=x,z=z,h=h},not forward,nil,nil,options and options.reserve)
		if hit then
			hit.distance=i*range/steps
			hit.pose={x=x,z=z,h=h}
			return hit
		end
		local step=range/steps
		local nextH=h+k*step
		if math.abs(k)>1e-8 then
			x=x+(math.sin(nextH)-math.sin(h))/k;z=z-(math.cos(nextH)-math.cos(h))/k
		else x=x+step*math.cos(h);z=z+step*math.sin(h) end
		h=nextH
	end
	return nil
end
function AIVEObstacles:scanPath(p,path,index,range)
	local hit=self:box(p,false)
	if hit then hit.distance=0;return hit end
	local walked=0
	local previous=p
	for i=index,#path do
		local q=path[i]
		walked=walked+dist(previous,q)
		if walked>range then break end
		hit=self:box(q,false)
		if hit then hit.distance=walked;return hit end
		previous=q
	end
end
function AIVEObstacles:stop(p,mf)
	if mf==nil then mf=not self.vehicle.acParameters.inverted end
	return p.x+math.cos(p.h),p.z+math.sin(p.h),mf,0,0
end

-- Harvesting along a border is not a headland transfer. Keep the cutter on,
-- move only as far sideways as the measured full footprint requires, and
-- return to the original line after the REAR has passed the obstacle.
function AIVEObstacles:canWorkAround(forward)
	local v=self.vehicle
	if not forward or v.acParameters.inverted or v.acImplementsMoveDown==false or (v.acTurnStage or 0)~=0 then return false end
	if self.strategy.currentTurnStrategy or (self.strategy.lands and self.strategy.lands.phase=="transfer") then return false end
	if not v.spec_combine then return false end
	return true
end
function AIVEObstacles:escalateWorkingBypass()
	if self.coverageTask and AIVECoverage then
		AIVECoverage.defer(self,self.coverageTask,"working approach became obstructed")
		return true
	end
	if not self.precisionCombine then return false end
	local p=self.encounterPose or self:pose()
	if AIVECoverage then AIVECoverage.record(self,p,6) end
	self.workingBypass=nil;self.vehicle.aiveWorkingBypass=nil
	self.savedTurning=false
	self.vehicle:aiFieldWorkerStartTurn(true)
	AIVehicleExtension.setAIImplementsMoveDown(self.vehicle,false,true)
	self:log("working deviation does not fit; retaining crop entry and trying a short multi-point turn")
	if self:beginManeuver() then return true end
	self:beginPlan(self:pose(),self.hit,self.routeTarget.x,self.routeTarget.z,true)
	return true
end
function AIVEObstacles:resetFieldSearch()
	local s,v=self.strategy,self.vehicle
	for _,turn in pairs(s.turnStrategies or {}) do if turn.onEndTurn then turn:onEndTurn(s.turnLeft) end end
	s.currentTurnStrategy=nil;s.search=AIDriveStrategyMogli.searchStart
	s.lastDirection=nil;s.aiveTurnTimer=v.acDeltaTimeoutRun
	v:aiFieldWorkerEndTurn(s.turnLeft);v.acTurnStage=-(s.search or 3)
end
function AIVEObstacles:beginWorkingBypass(p,hit,tx,tz)
	if not self.workingBypass then
		self.savedLowered=self.vehicle.acImplementsMoveDown~=false
		self.savedStage=self.vehicle.acTurnStage
	end
	self.workingBypass=true
	self.savedTurning=true -- no turn events were raised for a working deviation
	self.vehicle.aiveAvoidingObstacle=true;self.vehicle.aiveWorkingBypass=true
	self.vehicle.acTurnStage=202
	self.encounterPose={x=p.x,z=p.z,h=p.h}
	-- Retain the original working line through replans. Using the currently
	-- steered heading here makes every retry adopt a different field edge.
	self.workingLine=self.workingLine or {x=p.x,z=p.z,h=p.h}
	local line=self.workingLine
	local lineFx,lineFz=math.cos(line.h),math.sin(line.h)
	local startSide=-(p.x-line.x)*lineFz+(p.z-line.z)*lineFx
	local origin={x=p.x+startSide*lineFz,z=p.z-startSide*lineFx,h=line.h}
	local headingDelta=wrap(p.h-line.h)
	local startSlope=math.tan(headingDelta)
	self.routeTarget={x=tx,z=tz};self.routeForward=true
	self.hit=hit;self.phase="planning";self.candidates={};self.blockedAt=self.clock
	local fx,fz=lineFx,lineFz
	-- The line scan already sweeps front, rear and cutter. Adding their
	-- lengths a second time was responsible for very long working detours.
	local intervals={};local current;local u=0;local grouped=0
	local seen={};local waitForTraffic=false
	local scanLimit=math.min(180,math.max(50,(hit.distance or 0)+40))
	while u<=scanLimit do
		local q={x=origin.x+fx*u,z=origin.z+fz*u,h=line.h}
		if not self:isWorkingPoseOnField(q) then break end
		local nextHit=self:box(q,false)
		if nextHit then
			if nextHit.sensorFailed or AIVEObstacles.mustWait(nextHit) then waitForTraffic=true;break end
			if not seen[nextHit.node or 0] then seen[nextHit.node or 0]=true;grouped=grouped+1 end
			if not current then current={first=u,last=u};intervals[#intervals+1]=current end
			current.last=u+.4
		else current=nil end
		u=u+.4
	end
	if #intervals==0 then intervals[1]={first=hit.distance or 0,last=(hit.distance or 0)+1} end
	local maxOffset=math.min(12,math.max(4,2*self.half))
	local preferred=self.vehicle.acParameters.rightAreaActive and -1 or 1
	local field=(self.strategy.lands or {}).field or self.vehicle.aiveCurrentField
	local allowOther=true
	if field and field.getBit then
		-- At an exposed border the alternative side is the verge. Swinging
		-- cutter tips may leave the mask, but the bypass itself stays inward.
		for _,part in ipairs(self.parts or {}) do
			if part.label=="workbar" then
				local b=part.side-preferred*(part.half+.3)
				if not field.getBit(p.x+part.along*fx-b*fz,p.z+part.along*fz+b*fx) then allowOther=false end
			end
		end
	end
	for i=1,(waitForTraffic and 0 or math.ceil(maxOffset/.25)) do
		for _,sign in ipairs({preferred,-preferred}) do
			local offset=i*.25*sign
			local minimum=math.max(3,math.sqrt(6*self.radius*math.max(math.abs(offset),math.abs(offset-startSide))))
			for _,scale in ipairs({1,1.3,1.7}) do
				local ramp=minimum*scale
				local lead=math.max(0,intervals[1].first-ramp-1)
				if math.abs(startSide)>.01 or math.abs(startSlope)>.01 then lead=0 end
				local last=intervals[1].last
				for j=2,#intervals do
					-- Rejoin between distant bushes only when a complete second
					-- departure fits. Nearby bushes retain one continuous deviation.
					if intervals[j].first>last+2*ramp+4 then break end
					last=intervals[j].last
				end
				local run=math.max(lead+ramp+.5,last+.5)
				local returnEnd=run+ramp
				local total=returnEnd+3 -- finish steering before handing back control
				local path={length=0,working=true,offset=offset}
				if sign~=preferred and not allowOther then path.invalid=true end
				path.rank=total+math.abs(offset)*2+(sign~=preferred and .5 or 0)
				path.goal={x=origin.x+fx*total,z=origin.z+fz*total,h=line.h}
				path.build={origin=origin,startSide=startSide,startSlope=startSlope,fx=fx,fz=fz,lead=lead,ramp=ramp,run=run,returnEnd=returnEnd,total=total,steps=math.ceil(total/.25),index=0,radius=self.radius}
				if math.abs(headingDelta)>=1.4 then path.invalid=true;path.build=nil end
				self.candidates[#self.candidates+1]=path
			end
		end
	end
	table.sort(self.candidates,function(a,b)return a.rank<b.rank end)
	local finish=self.candidates[1] and self.candidates[1].build and self.candidates[1].build.total or 0
	self.goal=self.candidates[1] and self.candidates[1].goal or {x=tx,z=tz,h=line.h}
	self.candidateIndex=1;self.checkIndex=1;self.bestPath=nil;self.bestCost=nil;self.workCache={};self.candidateCrop=0
	self:log(string.format("working border bypass: %.1f m ahead; full-header padding=%.2f m; candidates=%d; grouped=%d; return=%.1f m; %s",hit.distance or 0,AIVEObstacles.CLEARANCE,#self.candidates,grouped,finish,self:describeHit(hit)))
end
function AIVEObstacles:isWorkingPoseOnField(p)
	local field=(self.strategy.lands or {}).field or self.vehicle.aiveCurrentField
	local function inside(x,z)
		if field and field.getBit then return field.getBit(x,z) end
		return AutoSteeringEngine.checkFieldNoBuffer(x,z,FieldBitmap.isFieldFast)
	end
	if not inside(p.x,p.z) then return false end
	local fx,fz=math.cos(p.h),math.sin(p.h)
	for _,part in ipairs(self.parts) do
		if part.label=="workbar" and not inside(p.x+part.along*fx-part.side*fz,p.z+part.along*fz+part.side*fx) then return false end
	end
	return true
end
function AIVEObstacles:captureRoute(p,hit,forward)
	if not self.vehicle.aiveAvoidingObstacle then
	self.savedLowered=self.vehicle.acImplementsMoveDown~=false
	self.savedTurning=type(self.vehicle.getAIFieldWorkerIsTurning)=="function" and self.vehicle:getAIFieldWorkerIsTurning() or false
	self.vehicle.aiveAvoidingObstacle=true
	self.savedStage=self.vehicle.acTurnStage
	self.vehicle.acTurnStage=202
	if not self.savedTurning then self.vehicle:aiFieldWorkerStartTurn(true) end
	AIVehicleExtension.setAIImplementsMoveDown(self.vehicle,false,true)
	self.backAttempts=0
	self.encounterPose={x=p.x,z=p.z,h=p.h}
	if AIVECoverage and not self.coverageTask and self.savedLowered then AIVECoverage.record(self,p,6) end
	end
	self.hit=hit;self.savedForward=forward
end
function AIVEObstacles:startAvoidance(p,hit,tx,tz,forward)
	if not self.vehicle.aiveAvoidingObstacle then
		self.routeTarget={x=tx,z=tz};self.routeForward=forward
		self:log("physical obstacle confirmed; "..self:describeHit(hit))
	end
	self:captureRoute(p,hit,forward)
	self.goal=self.goal or {x=tx,z=tz,h=p.h}
	if self:beginCorner() then return end
	if self.precisionCombine or not self:tryBackout() then self:beginPlan(p,hit,tx,tz,forward) end
end
function AIVEObstacles:tryForwardRecovery()
	local turn=self.strategy.currentTurnStrategy
	local data=self.strategy.turnData
	if not turn or not turn.canRecoverBlockedReverse or not turn:canRecoverBlockedReverse(data) then
		self.reverseRefusal="native turn has no reverse recovery handler";return false
	end
	local p=self:pose()
	-- This only clears the rear obstacle before the native FORWARD stage.
	-- A radius-based 2-4 m run needlessly enters unworked crop.
	for _,distance in ipairs({0.8,0.5}) do
		if not self:frontSweep(p,distance) then
			self.phase="forwardRecovery";self.forwardStart=p;self.forwardDistance=distance
			self.forwardAt=self.clock;self.recoveryTurn=turn
			self:log(string.format("rear obstacle; advancing %.1f m along checked front corridor before continuing the native corner",distance))
			return true
		end
	end
	self.reverseRefusal="front swept corridor occupied";return false
end
function AIVEObstacles:startReverseRecovery(p,hit,tx,tz,mf)
	self.routeTarget={x=tx,z=tz};self.routeForward=mf
	self:log("reverse manoeuvre blocked; "..self:describeHit(hit))
	self:captureRoute(p,hit,mf)
	if not self:tryForwardRecovery() then
		if self.precisionCombine and self:beginManeuver() then return end
		self.phase="reverseBlocked";self.retryAt=self.clock+2000
		self:log("reverse recovery waiting: "..tostring(self.reverseRefusal))
	end
end

-- Mogli's border steering checks actual remaining work, not just physical
-- clearance. Apply the same distinction when ranking local detours. Sample
-- every component, so a narrow tractor path cannot hide crop under a header.
function AIVEObstacles:workAt(x,z)
	local ix,iz=math.floor(x),math.floor(z)
	local key=ix..":"..iz
	local cache=self.workCache
	if cache[key]~=nil then return cache[key] end
	local lands=self.strategy.lands
	local field=lands and lands.field or self.vehicle.aiveCurrentField
	local value=0
	if not field or not field.getBit or field.getBit(ix+0.5,iz+0.5) then
		if type(AutoSteeringEngine.getAIAreaOfVehicle)=="function" then
			for i=1,(self.vehicle.aiveChain.toolCount or 0) do
				local area=AutoSteeringEngine.getAIAreaOfVehicle(self.vehicle,i,ix,iz,ix+1,iz,ix,iz+1,true)
				if area and area>0 then value=1;break end
			end
		end
	end
	cache[key]=value
	return value
end
function AIVEObstacles:cropAtPose(p)
	local fx,fz=math.cos(p.h),math.sin(p.h)
	local hits,samples=0,0
	for _,part in ipairs(self.parts or {}) do
		local ca,sa=math.cos(part.h),math.sin(part.h)
		for _,u in ipairs({-part.length,0,part.length}) do
			for _,w in ipairs({-part.half,0,part.half}) do
				local a=part.along+u*ca-w*sa
				local b=part.side+u*sa+w*ca
				hits=hits+self:workAt(p.x+a*fx-b*fz,p.z+a*fz+b*fx)
				samples=samples+1
			end
		end
	end
	return hits/math.max(1,samples)
end
function AIVEObstacles:acceptPlan(path)
	self.path=path;self.pathIndex=1;self.phase="detour";self.nextProbe=0
	if path.goal then self.goal=path.goal end
	self.progressIndex=1;self.progressAt=self.clock
	self.candidates=nil;self.bestPath=nil;self.bestCost=nil;self.workCache=nil
	if self.workingBypass then
		self:log(string.format("working bypass found: %.1f m; lateral shift=%+.2f m; cutter remains working",path.length,path.offset))
	else
		self:log(string.format("clear detour found: %.1f m; crop exposure=%.2f; rejoining the saved route without advancing its work entry",path.length,path.crop or 0))
	end
end

-- Forward-only connectors cannot solve a boxed-in corner. Search the vehicle
-- pose (including heading and gear) only after those cheap connectors fail.
function AIVEObstacles:beginCorner()
	if not AIVECorner or not self.precisionCombine or self.cornerTried or self.coverageTask then return false end
	local parameters=self.vehicle.acParameters
	if parameters.inverted or (parameters.upNDown and not parameters.circleLands) then return false end
	local lands=self.strategy.lands
	if lands and (lands.active or lands.waitingHandover or lands.finishingPass) then return false end
	self.cornerTried=true;self.workCache={}
	self.cornerAnchor=self.cornerAnchor or self:pose()
	self.maneuverSearch=AIVECorner.new(self,self:pose(),self.hit)
	self.phase="maneuverPlanning"
	self:log("checking tight corner: reverse on the cut strip, harvest the wedge, continue along the next edge")
	return true
end
function AIVEObstacles:prepareCornerLeg()
	local path=self.maneuverPath
	if not path or not path.corner then return end
	local q=path[self.maneuverIndex]
	if not q or self.cornerWork==q.work then return end
	self.cornerWork=q.work
	local v=self.vehicle
	if q.work then
		v:aiFieldWorkerEndTurn(true)
		self.workingBypass=true;v.aiveWorkingBypass=true
		AIVehicleExtension.setAIImplementsMoveDown(v,true,true)
		self:log("tight corner: cutter down; harvesting the corner wedge")
	else
		self.workingBypass=nil;v.aiveWorkingBypass=nil
		v:aiFieldWorkerStartTurn(true)
		AIVehicleExtension.setAIImplementsMoveDown(v,false,true)
		self:log("tight corner: cutter up; checked reverse section")
	end
end
function AIVEObstacles:beginManeuver()
	if self:beginCorner() then return true end
	if not AIVEManeuver or not self.vehicle.spec_combine or self.maneuverTried then return false end
	for _,child in pairs(self.vehicle.childVehicles or {}) do
		if child~=self.vehicle and child.spec_trailer then return false end
	end
	self.maneuverTried=true
	local p=self:pose()
	local goals={}
	local function add(q,escape)
		for _,failed in ipairs(self.failedManeuverGoals or {}) do
			if dist(q,failed)<1.5 and math.abs(wrap(q.h-failed.h))<.4 then return end
		end
		if not self:isWorkingPoseOnField(q) or self:box(q,false,nil,nil,self.precisionCombine and .04 or .15) then return end
		if self:frontSweep(q,3) then return end
		local ahead={x=q.x+3*math.cos(q.h),z=q.z+3*math.sin(q.h),h=q.h}
		if escape and not self:isWorkingPoseOnField(ahead) then return end
		q.escape=escape;goals[#goals+1]=q
	end
	local lands=self.strategy.lands
	local fixed=lands and (lands.active or lands.waitingHandover or lands.finishingPass)
	if self.goal then add({x=self.goal.x,z=self.goal.z,h=self.goal.h},false) end
	if not fixed then
		local anchor=self.encounterPose or p
		for _,r in ipairs({2.5,4,6,math.max(10,self.radius*2),math.max(16,self.radius*3)}) do
			for i=0,7 do
				local h=anchor.h+i*math.pi/4
				for _,yaw in ipairs({h,h+math.pi/2,h-math.pi/2}) do
					-- Prefer a nearby continuation; large escape rings remain a
					-- fallback. Remaining crop is explicitly recovered afterwards.
					add({x=anchor.x+r*math.cos(h),z=anchor.z+r*math.sin(h),h=yaw,penalty=math.max(0,r-4)*2},true)
				end
			end
		end
	end
	if #goals==0 then return false end
	self.maneuverSearch=AIVEManeuver.new(self,p,goals)
	self.phase="maneuverPlanning"
	self:log(string.format("searching forward/reverse manoeuvre; reachable field goals=%d",#goals))
	return true
end

function AIVEObstacles:retryManeuver(p,reason)
	if self.coverageTask and AIVECoverage then AIVECoverage.defer(self,self.coverageTask,reason);return end
	local path=self.maneuverPath
	if path and path.corner and (self.cornerRetries or 0)<2 then
		self:log("tight corner: rechecking after "..reason)
		self.cornerExitHeading=path.goal.h
		self.cornerRetries=(self.cornerRetries or 0)+1;self.cornerTried=nil
		self.workingBypass=nil;self.vehicle.aiveWorkingBypass=nil
		AIVehicleExtension.setAIImplementsMoveDown(self.vehicle,false,true)
		self.vehicle:aiFieldWorkerStartTurn(true)
		if self:beginCorner() then return end
	end
	self.maneuverRetries=(self.maneuverRetries or 0)+1
	if path and path.recoveryGoal then
		self.failedManeuverGoals=self.failedManeuverGoals or {}
		self.failedManeuverGoals[#self.failedManeuverGoals+1]=path.recoveryGoal
	end
	self.maneuverTried=nil;self.maneuverBlockedAt=nil
	self:log("rechecking a multi-point turn from the actual pose: "..reason)
	if self.maneuverRetries<=4 and self:beginManeuver() then return end
	self.phase="blocked";self.retryAt=self.clock+2000
	self.routeTarget=self.routeTarget or self.goal or {x=p.x+math.cos(p.h)*3,z=p.z+math.sin(p.h)*3,h=p.h}
	self.goal=self.goal or self.routeTarget
end

function AIVEObstacles:driveManeuver(p)
	local v=self.vehicle
	if self.phase=="maneuverPlanning" then
		v.aiRescueTimer=v.acDeltaTimeoutStop
		local path,status=self.maneuverSearch:update()
		if path then
			if self.coverageTask and (self.coverageTask.remainingCells or 3)<=2 and (path.length or 0)>4 then
				AIVECoverage.defer(self,self.coverageTask,"small remnant needs a closer approach");return self:stop(p)
			end
			self.maneuverPath=path;self.maneuverIndex=math.min(2,#path);self.maneuverAt=self.clock
			self.goal=path.goal;self.routeTarget=self.routeTarget or path.goal
			if self.routeForward==nil then self.routeForward=true end
			self.phase="maneuver";self.maneuverSearch=nil
			self:log(string.format("forward/reverse manoeuvre found; points=%d; initial reverse=%.2f m; exit yaw=%.1f deg",#path,path.reverseDistance or 0,math.deg(wrap(path.goal.h-path[1].h))))
		elseif status then
			if self.cornerTried and not self.maneuverTried and not self.coverageTask then
				self:log("corner templates do not fit; trying the general checked manoeuvre search")
				self.maneuverSearch=nil
				if self:beginManeuver() then return self:stop(p) end
			end
			if self.coverageTask and AIVECoverage then AIVECoverage.defer(self,self.coverageTask,tostring(status));return self:stop(p) end
			self.maneuverSearch=nil;self.phase="blocked";self.retryAt=self.clock+5000
			self:log("no collision-free forward/reverse manoeuvre in the local search area: "..tostring(status))
		end
		return self:stop(p)
	end
	local path=self.maneuverPath
	local i=self.maneuverIndex
	local gear=path[i].forward
	local ending=i
	while ending<#path and path[ending+1].forward==gear and (not path.corner or path[ending+1].work==path[i].work) do ending=ending+1 end
	local nearest=i;local best=dist(p,path[i])
	for j=i+1,math.min(ending,i+14) do
		local d=dist(p,path[j]);if d<best then nearest=j;best=d end
	end
	if nearest>i then self.maneuverIndex=nearest;self.maneuverAt=self.clock;i=nearest end
	local endDistance=dist(p,path[ending])
	local endPoint,previous=path[ending],path[math.max(1,ending-1)]
	local ex,ez=endPoint.x-previous.x,endPoint.z-previous.z
	local el=math.max(1e-5,math.sqrt(ex*ex+ez*ez))
	local remaining=((endPoint.x-p.x)*ex+(endPoint.z-p.z)*ez)/el
	local cross=math.abs(-(p.x-endPoint.x)*ez+(p.z-endPoint.z)*ex)/el
	local reached=endDistance<.4 or (nearest>=ending-2 and remaining<=.1 and cross<.65)
	if path.corner then reached=endDistance<.25 or (nearest>=ending-5 and remaining<=.1 and cross<.9) end
	if path.corner and not gear then
		-- Finish the checked reverse, rather than consuming its last waypoint
		-- inside the much wider forward-turn arrival tolerance.
		reached=remaining<=.12 and cross<.45
	end
	if #path==1 then reached=endDistance<.4 end
	if reached and speed(v)<0.07 then
		if path.corner and not gear then
			local first=ending
			while first>1 and not path[first-1].forward and not path[first-1].work do first=first-1 end
			self:log(string.format("tight corner: reverse section completed; travelled=%.2f m; remaining=%.2f m",dist(p,path[first]),remaining))
		end
		self.maneuverIndex=ending+1;self.maneuverAt=self.clock
		if ending==#path then
			if path.corner then
				self.savedLowered=true;self.workingBypass=nil;v.aiveWorkingBypass=nil
				self:release(true);self:resetFieldSearch()
				for _,debt in ipairs(self.coverageDebts or {}) do debt.nextAt=self.clock+15000 end
				self.nextCoverageAt=self.clock+15000
				self:log("tight corner completed: wedge harvested, following the next edge")
				return nil
			end
			if path.recoveryGoal and path.recoveryGoal.workPath and AIVECoverage then
				AIVECoverage.startWork(self,path.recoveryGoal.workPath);return self:stop(p)
			end
			local escape=path.escape
			if AIVECoverage and self.encounterPose then
				local a=self.encounterPose
				AIVECoverage.record(self,a,math.max(6,(p.x-a.x)*math.cos(a.h)+(p.z-a.z)*math.sin(a.h)+2))
			end
			self:release(not escape)
			if escape then
				self:resetFieldSearch()
			end
			self:log("forward/reverse manoeuvre completed; resuming fieldwork")
			if AIVECoverage and AIVECoverage.begin(self) then return self:stop(p) end
			return nil
		end
		return self:stop(p)
	end
	local target=path[math.min(ending,i+(path.corner and 16 or 5))]
	if path.corner and dist(p,target)<3 then
		local direction=gear and 1 or -1
		target={x=endPoint.x+direction*4*math.cos(endPoint.h),z=endPoint.z+direction*4*math.sin(endPoint.h),h=endPoint.h}
	end
	if self.clock-self.maneuverAt>15000 or best>3 then
		self:retryManeuver(p,"tracking progress stopped");return self:stop(p)
	end
	-- Check the actual off-path pose and the entire next short motion, in
	-- either gear. A wide front cutter remains at the FRONT while reversing.
	local checkTarget=target
	local walked=dist(p,checkTarget)
	local samples=math.max(1,math.ceil(walked/0.2))
	if path.corner then samples=0 end
	local hit
	if path.corner then
		-- Follow the same commanded curvature as the native driver. Blending
		-- position and heading independently toward an ideal waypoint can
		-- rotate a wide cutter into a tree in the preview although the actual
		-- arc clears it. Continue checking the full real hull, in both gears.
		local command={x=target.x,z=target.z}
		if not gear then
			local along=(command.x-p.x)*math.cos(p.h)+(command.z-p.z)*math.sin(p.h)
			command.x=command.x-2*along*math.cos(p.h);command.z=command.z-2*along*math.sin(p.h)
		end
		local reserve=(path.initialReserve or 0)*math.max(0,1-dist(p,path[1])/2)
		hit=self:scan(p,command,gear,math.min(1.5,math.max(.15,endDistance)),{reserve=reserve})
	end
	for j=0,samples do
		local t=samples>0 and j/samples or 0
		local q={x=p.x+(checkTarget.x-p.x)*t,z=p.z+(checkTarget.z-p.z)*t,h=p.h+wrap(checkTarget.h-p.h)*t}
		local initial=path.initialReserve or 0
		local reserve=initial*math.max(0,1-dist(q,path[1])/2)
		if not path.corner then hit=self:box(q,false,nil,nil,reserve) end
		if hit then
			v.aiRescueTimer=v.acDeltaTimeoutStop
			if not hit.sensorFailed and not AIVEObstacles.mustWait(hit) then
				self.maneuverBlockedAt=self.maneuverBlockedAt or self.clock
				if self.clock-self.maneuverBlockedAt>=750 then self:retryManeuver(p,"actual swept clearance changed") end
			end
			return self:stop(p)
		end
	end
	self.maneuverBlockedAt=nil
	v.aiRescueTimer=v.acDeltaTimeoutStop
	if reached then return self:stop(p) end
	local tx,tz=target.x,target.z
	if not gear then
		local fx,fz=math.cos(p.h),math.sin(p.h)
		local along=(tx-p.x)*fx+(tz-p.z)*fz
		tx,tz=tx-2*along*fx,tz-2*along*fz
	end
	local x,z,mf=self.strategy:adjustPosition(tx,tz,gear,math.max(.15,endDistance))
	local limit=path.corner and (gear and 4 or 3) or (gear and 2 or 1.5)
	return x,z,mf,math.min(limit,math.max(.35,endDistance*1.2)),math.max(path.corner and .35 or .1,endDistance)
end
function AIVEObstacles:beginPlan(p,hit,tx,tz,forward)
	self:captureRoute(p,hit,forward)
	self.phase="planning";self.hit=hit;self.savedForward=forward;self.blockedAt=self.clock
	self.detourWaitSince=nil
	local anchor=self.encounterPose or p
	local fx,fz=math.cos(anchor.h),math.sin(anchor.h)
	local along=math.max(0,(hit.x-anchor.x)*fx+(hit.z-anchor.z)*fz)
	local beyond=math.max(6,along+math.max(self.back+2,2*self.radius))
	local goal={x=anchor.x+fx*beyond,z=anchor.z+fz*beyond,h=anchor.h}
	self.resumeLandIndex=nil
	local lands=self.strategy.lands
	local corridorFirst,corridorLast
	if lands and lands.phase=="transfer" and lands.path then
		corridorFirst=math.max(1,lands.pathIndex-2)
		local index=lands.pathIndex
		local walked=0
		while index<#lands.path and walked<beyond do
			walked=walked+dist(lands.path[index],lands.path[index+1]);index=index+1
		end
		local q=lands.path[index]
		goal={x=q.x,z=q.z,h=q.h};self.resumeLandIndex=index
		corridorLast=math.min(#lands.path,index+2)
		if index>=#lands.path-math.ceil(self.radius/0.8) and lands.workStart and lands.workEnd then
			-- Never advance the raised machine several metres INTO the next
			-- working pass. That loses the entry crop before lowering. Return
			-- to its original entry, even if a longer headland loop is needed.
			local last=lands.workStart
			goal={x=last.x,z=last.z,h=last.h}
			self.resumeLandIndex=#lands.path;corridorLast=#lands.path
		end
	elseif lands and lands.phase=="work" and lands.workStart and lands.workEnd then
		local h=lands.workStart.h
		local ux,uz=math.cos(h),math.sin(h)
		local onLine=(anchor.x-lands.workStart.x)*ux+(anchor.z-lands.workStart.z)*uz
		local hitAlong=(hit.x-lands.workStart.x)*ux+(hit.z-lands.workStart.z)*uz
		-- The rear attachment must clear the object before rejoining, even
		-- when that point lies just beyond the last metre of the working pass.
		local rejoin=math.max(onLine+beyond,hitAlong+self.back+2)
		goal={x=lands.workStart.x+ux*rejoin,z=lands.workStart.z+uz*rejoin,h=h}
	elseif lands and lands.finishingPass then
		goal=lands.finishingPass.finish
	end
	self.goal=goal;self.candidates={}
	local otherHalf=hit.vehicle and ((hit.vehicle.size or {}).width or 3)/2 or 0.5
	local lateralLimit=math.max(self.half+otherHalf+3,self.backDistance or 0,2*self.radius+self.half)
	local maxLength=dist(p,goal)*2+4*self.radius+6
	local retreatCorridor={p,anchor}
	local rejectedLength,rejectedCorridor=0,0
	local function add(path)
		if path.length>maxLength then rejectedLength=rejectedLength+1;return end
		for _,q in ipairs(path) do
			local side
			if corridorFirst then
				-- A U-turn's legitimate rejoin point is outside the initial
				-- straight strip. Bound deviation from the SAVED CURVE instead.
				side=math.min(routeDistance(q,lands.path,corridorFirst,corridorLast),routeDistance(q,retreatCorridor,1,2))
			else side=math.abs(-(q.x-anchor.x)*fz+(q.z-anchor.z)*fx) end
			if side>lateralLimit then rejectedCorridor=rejectedCorridor+1;return end
		end
		self.candidates[#self.candidates+1]=path
	end
	for _,path in ipairs(AIVELands.connectors(p,goal,self.radius)) do add(path) end
	for _,side in ipairs({-1,1}) do
		for _,extra in ipairs({0,1.5,4,8}) do
			local offset=self.half+otherHalf+0.8+extra
			local via={x=anchor.x+fx*along-fz*side*offset,z=anchor.z+fz*along+fx*side*offset,h=anchor.h}
			for _,a in ipairs(AIVELands.connectors(p,via,self.radius)) do
				for _,b in ipairs(AIVELands.connectors(via,goal,self.radius)) do
					local path={length=a.length+b.length}
					for _,q in ipairs(a) do path[#path+1]=q end
					for i=2,#b do path[#path+1]=b[i] end
					add(path)
				end
			end
		end
	end
	table.sort(self.candidates,function(a,b)return a.length<b.length end)
	self.candidateIndex=1;self.checkIndex=1
	self.workCache={};self.bestPath=nil;self.bestCost=nil;self.candidateCrop=0
	if self.clock>=(self.nextPlanLog or 0) then
		self.nextPlanLog=self.clock+15000
		self:log(string.format("checking crop-aware local bypass; object=%s; clearance=%.1f m; candidates=%d; rejectedLength=%d; rejectedCorridor=%d; curve=%s; reverse=%s",tostring(hit.node),hit.distance or 0,#self.candidates,rejectedLength,rejectedCorridor,tostring(corridorFirst~=nil),tostring(self.backRefusal or "checked")))
	end
end
function AIVEObstacles:release(completed)
	if self.vehicle.aiveAvoidingObstacle then
		if completed and self.resumeLandIndex and self.strategy.lands then
			self.strategy.lands.pathIndex=self.resumeLandIndex
		end
		self.vehicle.aiveAvoidingObstacle=nil
		self.vehicle.acTurnStage=self.savedStage or 0
		if not self.savedTurning then
			self.vehicle:aiFieldWorkerTurnProgress(1,true)
			self.vehicle:aiFieldWorkerEndTurn(true)
		end
		if not self.workingBypass then AIVehicleExtension.setAIImplementsMoveDown(self.vehicle,self.savedLowered,true) end
	end
	self.phase="clear";self.path=nil;self.candidates=nil;self.nextProbe=0;self.lastHit=nil;self.resumeLandIndex=nil
	self.backStart=nil;self.backAttempts=0
	self.detourWaitSince=nil
	self.encounterPose=nil;self.nextPlanLog=nil
	self.goal=nil;self.nextBlockedLog=nil;self.waitNode=nil
	self.waitTarget=nil;self.waitForward=nil
	self.routeTarget=nil;self.routeForward=nil
	self.backRefusal=nil
	self.forwardStart=nil;self.recoveryTurn=nil;self.reverseRefusal=nil
	self.workingBypass=nil;self.vehicle.aiveWorkingBypass=nil;self.workingLine=nil
	self.maneuverSearch=nil;self.maneuverPath=nil;self.maneuverTried=nil
	self.maneuverRetries=nil;self.failedManeuverGoals=nil;self.maneuverBlockedAt=nil
	self.cornerTried=nil;self.cornerRetries=nil;self.cornerWork=nil
	self.cornerAnchor=nil;self.cornerExitHeading=nil
end
function AIVEObstacles:delete()
	AIVEObstacles.controllers[self.vehicle]=nil
	self.vehicle.aiveAvoidingObstacle=nil
	self.vehicle.aiveWorkingBypass=nil
	if self.vehicle.aiveObstacleController==self then self.vehicle.aiveObstacleController=nil end
	self.phase="clear";self.path=nil;self.candidates=nil
end
function AIVEObstacles:tryBackout()
	local p=self:pose()
	local hit=self.hit
	if (self.backAttempts or 0)>0 or not hit or hit.sensorFailed or AIVEObstacles.mustWait(hit) then return false end
	-- A sharply folded trailer cannot be reversed as one rigid rectangle.
	if AutoSteeringEngine.getToolAngle and math.abs(AutoSteeringEngine.getToolAngle(self.vehicle))>0.35 then self.backRefusal="implement angle exceeds 20 degrees";return false end
	local retreat=math.min(8,math.max(4,self.radius+0.5))
	-- Validate the entire rear half plus the NEW swept area behind it. The
	-- already occupied front half is deliberately excluded: the obstacle we
	-- are touching is there, and straight reverse moves away from that half.
	if self:rearSweep(p,retreat) then self.backRefusal="rear swept corridor occupied";return false end
	self.backRefusal=nil
	self.backAttempts=(self.backAttempts or 0)+1
	self.backStart=p;self.backDistance=retreat;self.phase="backing";self.backAt=self.clock
	self:log(string.format("front is obstructed; reversing %.1f m along the checked rear corridor",retreat))
	return true
end

-- Generate only the currently considered curve, with bounded work per tick.
-- Coordinates and curvature limits are identical to the eager planner.
function AIVEObstacles:buildWorkingCandidate(path)
    local b=path.build
    if not b then return true end
    for _=1,64 do
        if b.index>b.steps then path.build=nil;return true end
        local u=b.total*b.index/b.steps
        local t,reverse
        if u<(b.lead or 0) then t=0
        elseif u<(b.lead or 0)+b.ramp then t=(u-(b.lead or 0))/b.ramp
        elseif u>(b.returnEnd or b.total) then t=0
        elseif u>b.run then t=((b.returnEnd or b.total)-u)/b.ramp;reverse=true
        else t=1 end
        local lateral=path.offset*t*t*t*(10+t*(-15+6*t))
        local slope=path.offset*30*t*t*(1-t)*(1-t)/b.ramp*(reverse and -1 or 1)
        local bend=path.offset*60*t*(1-t)*(1-2*t)/(b.ramp*b.ramp)
        if u<(b.lead or 0)+b.ramp and ((b.startSide or 0)~=0 or (b.startSlope or 0)~=0) then
            local y0,m0=b.startSide or 0,(b.startSlope or 0)*b.ramp
            local delta=path.offset-y0
            local c3,c4,c5=10*delta-6*m0,-15*delta+8*m0,6*delta-3*m0
            lateral=y0+m0*t+c3*t^3+c4*t^4+c5*t^5
            slope=(m0+3*c3*t*t+4*c4*t^3+5*c5*t^4)/b.ramp
            bend=(6*c3*t+12*c4*t*t+20*c5*t^3)/(b.ramp*b.ramp)
        end
        if math.abs(bend)/(1+slope*slope)^1.5>1/b.radius then path.invalid=true;path.build=nil;return true end
        local p=b.origin
        local q={x=p.x+b.fx*u-b.fz*lateral,z=p.z+b.fz*u+b.fx*lateral,h=p.h+math.atan(slope)}
        if #path>0 then path.length=path.length+dist(path[#path],q) end
        path[#path+1]=q;b.index=b.index+1
    end
    return false
end
function AIVEObstacles:checkPlan()
	for _=1,(self.workingBypass and 96 or 8) do
		local path=self.candidates[self.candidateIndex]
		if path==nil then
			if self.bestPath then self:acceptPlan(self.bestPath);return end
			if self.workingBypass and self:escalateWorkingBypass() then return end
			if self.precisionCombine and self:beginManeuver() then return end
			if not self.workingBypass and self:tryBackout() then return end
			if not self.workingBypass and self:beginManeuver() then return end
			self.phase="blocked";self.retryAt=self.clock+2000
			if self.clock>=(self.nextBlockedLog or 0) then
				self.nextBlockedLog=self.clock+15000
				self:log("neither local side is clear; waiting and rechecking")
			end
			return
		end
		if path.build and not self:buildWorkingCandidate(path) then return end
		if path.invalid then
			self.candidateIndex=self.candidateIndex+1;self.checkIndex=1;self.candidateCrop=0
			return
		end
		local p=path[self.checkIndex]
		-- Leave room for tracking error along the planned path, while allowing
		-- a machine already in a tight gap to start at the actual clearance.
		local reserve=AIVEObstacles.CLEARANCE*math.min(1,dist(path[1],p)/2)
		if self:box(p,false,nil,nil,reserve) or (self.workingBypass and not self:isWorkingPoseOnField(p)) then
			self.candidateIndex=self.candidateIndex+1;self.checkIndex=1;self.candidateCrop=0
		else
			if self.workingBypass then
				self.checkIndex=self.checkIndex+1
				if self.checkIndex>#path then
					local cost=path.length+math.abs(path.offset)*2
					if not self.bestCost or cost<self.bestCost then self.bestPath=path;self.bestCost=cost end
					self.candidateIndex=self.candidateIndex+1;self.checkIndex=1
					local nextPath=self.candidates[self.candidateIndex]
					if not nextPath or nextPath.rank>self.bestCost+1 then self:acceptPlan(self.bestPath);return end
				end
			else
			local previous=path[math.max(1,self.checkIndex-1)]
			self.candidateCrop=self.candidateCrop+self:cropAtPose(p)*dist(previous,p)
			self.checkIndex=self.checkIndex+1
			if self.checkIndex>#path then
				path.crop=self.candidateCrop
				local cost=path.length+1000*path.crop
				if not self.bestCost or cost<self.bestCost then self.bestPath=path;self.bestCost=cost end
				if path.crop==0 then self:acceptPlan(path);return end
				self.candidateIndex=self.candidateIndex+1;self.checkIndex=1;self.candidateCrop=0
			end
			end
		end
	end
end
function AIVEObstacles:mayPass(hit)
	return not AIVEObstacles.mustWait(hit)
end

function AIVEObstacles:filter(dt,tx,tz,mf,maxSpeed,stopDistance)
	if not self:isEnabled() or tx==nil or maxSpeed==nil then return tx,tz,mf,maxSpeed,stopDistance end
	self.clock=self.clock+dt;self:dimensions()
	local p=self:pose()
	if maxSpeed<=0 then
		local key=tostring(self.vehicle.acTurnStage)..":"..tostring(self.strategy.lastAllowedToDrive)
		if self.nativeStopKey~=key then
			self.nativeStopKey=key
			self:log("native strategy requested stop; stage="..tostring(self.vehicle.acTurnStage).." allowed="..tostring(self.strategy.lastAllowedToDrive))
		end
		return tx,tz,mf,maxSpeed,stopDistance
	end
	self.nativeStopKey=nil
	local forward=mf~=self.vehicle.acParameters.inverted
	-- Distance is measured from the inflated FULL implement footprint.
	-- Do not intercept a normal headland turn for objects 20-40 m away.
	local working=self:canWorkAround(forward)
	if working and AIVECoverage and self.clock>=(self.nextCoverageAt or 0) then
		self.nextCoverageAt=self.clock+5000
		if AIVECoverage.begin(self) then return self:stop(p,mf) end
	end
	local range=working and math.max(14,2*self.radius+3) or 3
	if not forward or self.clock>=self.nextProbe then
		-- The drive target is expressed from the game's AI steering node;
		-- all collision parts use AIVE's reference node. Undo that conversion
		-- before deriving curvature, especially for rear-steered combines.
		local sx,sz=tx,tz
		if self.strategy.adjustPosition then sx,sz=self.strategy:adjustPosition(tx,tz,forward,stopDistance,true) end
		local options=working and self.precisionCombine and {maxYaw=math.rad(45)} or nil
		self.lastHit=self:scan(p,{x=sx,z=sz},forward,range,options)
		self.nextProbe=self.clock+120
	end
	local hit=self.lastHit
	if hit==nil then self.waitSince=nil;self.waitNode=nil;self.cornerWaitAt=nil;return tx,tz,mf,maxSpeed,stopDistance end
	if hit.sensorFailed or AIVEObstacles.mustWait(hit) then
		self.vehicle.aiRescueTimer=self.vehicle.acDeltaTimeoutStop
		if not hit.sensorFailed then
			self.phase="waiting";self.waitTarget={x=tx,z=tz};self.waitForward=mf
		end
		self.waitNode=hit.node
		if self.clock>=(self.nextWaitLog or 0) then
			self.nextWaitLog=self.clock+5000
			self:log("player or helper within 3 m; waiting without reversing or bypassing; "..self:describeHit(hit))
		end
		return self:stop(p,mf)
	end
	self.waitNode=nil
	if working then
		local projected=hit.pose or {x=p.x+math.cos(p.h)*(hit.distance or 0),z=p.z+math.sin(p.h)*(hit.distance or 0),h=p.h}
		-- Let the normal corner start before a tree BEYOND the field. The
		-- collision pose follows the scanned CURVE, not the initial heading.
		-- Taking obstacle control here freezes the native end-of-field timer
		-- and searches for a working bypass whose rejoin is outside the field.
		if not self:isWorkingPoseOnField(projected) then
			if (hit.distance or 0)>3 then self.cornerWaitAt=nil;return tx,tz,mf,maxSpeed,stopDistance end
			-- Keep physical braking, but let the native corner/search state tick.
			-- If it cannot produce a turn while stopped, explicitly recover;
			-- otherwise this "clear" phase can brake forever without replanning.
			self.cornerWaitAt=self.cornerWaitAt or self.clock
			if self.clock-self.cornerWaitAt>=750 then
				self.routeTarget={x=tx,z=tz};self.routeForward=mf
				self:captureRoute(p,hit,mf);self.goal=nil
				if not self:beginManeuver() then self:beginPlan(p,hit,tx,tz,mf) end
				self.cornerWaitAt=nil
			end
			return self:stop(p,mf)
		end
	end
	-- A working combine needs enough lead distance to bend around a tree
	-- without a reverse leg. Other vehicles/people retain the short wait zone.
	if working and forward then
		local distantTree=false
		local warning=math.max(3,self:reverseClearance()+.5)
		if (hit.distance or 0)>warning and hit.x and hit.z and type(getCollisionFilterGroup)=="function" then
			local side=math.abs(-(hit.x-p.x)*math.sin(p.h)+(hit.z-p.z)*math.cos(p.h))
			local turning=hit.pose~=nil and math.abs(wrap(hit.pose.h-p.h))>math.rad(10)
			-- Edge steering can change before a distant side or curved tree prediction.
			distantTree=(side>self.half or turning) and flagSet(getCollisionFilterGroup(hit.node),(CollisionFlag or {}).TREE or 2048)
		end
		-- A long curved preview is advisory when the interrupted work strip
		-- itself is clear. Freezing the native steering here would manufacture
		-- a straight bypass of a tree that was never on that straight strip
		-- (grouped=0), replacing a perfectly usable field-edge turn. A near
		-- collision still takes control; straight-row bushes retain early
		-- detection so the working S-curve has room to fit.
		if self.precisionCombine and (hit.distance or 0)>3 and (distantTree or not self:frontSweep(p,range)) then
			self.waitSince=nil
			if self.clock>=(self.nextCurveLog or 0) then
				self.nextCurveLog=self.clock+15000
				self:log("distant edge forecast is advisory; keeping native edge steering")
			end
			return tx,tz,mf,math.min(maxSpeed,8),stopDistance
		end
		self:beginWorkingBypass(p,hit,tx,tz)
		return self:stop(p,mf)
	end
	local reverseClearance=self:reverseClearance()
	if not forward and (hit.distance or 0)>reverseClearance then
		-- Keep the 3 m warning corridor, but creep towards a fixed obstacle
		-- rather than ending the reverse leg at its first distant detection.
		-- Clearance is from the padded full rig, not its reference node.
		local remaining=hit.distance-reverseClearance
		self.waitSince=nil
		self.vehicle.aiRescueTimer=self.vehicle.acDeltaTimeoutStop
		-- Keep a nonzero rolling horizon; an almost-zero stop distance can
		-- make the engine brake before reaching the clearance threshold.
		local creep=self.precisionCombine and math.min(1.5,math.max(.45,remaining*2)) or 1.5
		return tx,tz,mf,math.min(maxSpeed,creep),math.min(stopDistance or remaining,math.max(0.2,remaining))
	end
	self.waitSince=self.waitSince or self.clock
	if forward and self:mayPass(hit) and self.clock-self.waitSince>=400 then
		self:startAvoidance(p,hit,tx,tz,mf)
	elseif not forward and self:mayPass(hit) and self.clock-self.waitSince>=400 then
		self:startReverseRecovery(p,hit,tx,tz,mf)
	end
	-- Detection is ahead of the full implement footprint, so braking starts
	-- before the tractor, header or rear attachment contacts the object.
	return self:stop(p,mf)
end
function AIVEObstacles:drive(dt)
	local v=self.vehicle
	local p=self:pose()
	if v.acPause or v.acIsCPStopped then return self:stop(p) end
	self.clock=self.clock+dt
	if not self:isEnabled() then self:release();return nil end
	self:dimensions()
	if self.phase=="coverageScan" then
		v.aiRescueTimer=v.acDeltaTimeoutStop
		AIVECoverage.update(self);return self:stop(p)
	end
	if self.phase=="maneuver" then self:prepareCornerLeg() end
	if self.phase=="waiting" then
		v.aiRescueTimer=v.acDeltaTimeoutStop
		local forward=self.waitForward~=v.acParameters.inverted
		local hit=self:scan(p,self.waitTarget,forward,3)
		self.lastHit=hit
		if hit and (hit.sensorFailed or AIVEObstacles.mustWait(hit)) then return self:stop(p,self.waitForward) end
		self.phase="clear";self.waitNode=nil;self.lastHit=nil;self.waitSince=nil;self.nextProbe=0
		return nil
	end
	if type(v.getCanAIFieldWorkerContinueWork)=="function" then
		-- A working deviation keeps the cutter down and has not raised turn
		-- events. Ask the native implement check about WORK, not a headland turn.
		local allowed,stop,reason=v:getCanAIFieldWorkerContinueWork(not self.workingBypass)
		if not allowed then
			-- Unloading/implement preparation is not an obstacle timeout.
			self.clock=self.clock-dt
			local key=tostring(stop)..":"..tostring(reason)
			if self.continueBlock~=key then
				self.continueBlock=key
				self:log("manoeuvre held by native continuation check; phase="..tostring(self.phase).." stopJob="..tostring(stop).." reason="..tostring(reason))
			end
			if stop then v:stopCurrentAIJob(reason or AIMessageErrorUnknown.new()) end
			return self:stop(p)
		end
		self.continueBlock=nil
	end
	-- A person/helper entering a manoeuvre corridor always has waiting
	-- priority. Never convert that encounter into another reverse or bypass.
	local nearby=self:scan(p,{x=p.x+5*math.cos(p.h),z=p.z+5*math.sin(p.h)},true,3)
	if nearby and (nearby.sensorFailed or AIVEObstacles.mustWait(nearby)) then
		self.clock=self.clock-dt
		return self:stop(p)
	end
	if self.phase=="reverseBlocked" then
		if self.clock>=self.retryAt then
			self.retryAt=self.clock+2000
			local hit=self:scan(p,self.routeTarget,false,3)
			if not hit then self:release();return nil end
			if not hit.sensorFailed and not AIVEObstacles.mustWait(hit) then
				if not self:tryForwardRecovery() and self.precisionCombine then self:beginManeuver() end
			end
		end
		return self:stop(p)
	end
	if self.phase=="forwardRecovery" then
		local b=self.forwardStart
		local fx,fz=math.cos(b.h),math.sin(b.h)
		local moved=(p.x-b.x)*fx+(p.z-b.z)*fz
		local remaining=self.forwardDistance-moved
		if remaining<=0.1 then
			local turn=self.recoveryTurn
			self:release()
			if turn and turn:resumeAfterBlockedReverse(self.strategy.turnData) then
				self:log("forward clearance completed; native corner resumed at stage "..tostring(self.strategy.turnData.stage))
			end
			return nil
		end
		if self.clock-self.forwardAt>15000 or math.abs(wrap(p.h-b.h))>0.15 then
			self.phase="reverseBlocked";self.retryAt=self.clock+2000
			self:log("forward clearance interrupted by timeout or heading drift; rechecking")
			return self:stop(p)
		end
		if self:frontSweep(p,math.min(2,remaining)) then return self:stop(p) end
		v.aiRescueTimer=v.acDeltaTimeoutStop
		local tx,tz,mf=self.strategy:adjustPosition(b.x+fx*(self.forwardDistance+4),b.z+fz*(self.forwardDistance+4),true,remaining)
		return tx,tz,mf,3,math.max(0.3,remaining)
	end
	if self.phase=="maneuverPlanning" or self.phase=="maneuver" then return self:driveManeuver(p) end
	if self.phase=="planning" then self:checkPlan();return self:stop(p) end
	if self.phase=="backing" then
		local b=self.backStart
		local fx,fz=math.cos(b.h),math.sin(b.h)
		local backed=(b.x-p.x)*fx+(b.z-p.z)*fz
		local remaining=self.backDistance-backed
		if remaining<=0.3 then
			self:beginPlan(p,self.hit,self.goal.x,self.goal.z,true)
			return self:stop(p)
		end
		local folded=AutoSteeringEngine.getToolAngle and math.abs(AutoSteeringEngine.getToolAngle(v))>0.5
		if self.clock-self.backAt>20000 or math.abs(wrap(p.h-b.h))>0.15 or folded then
			self:beginPlan(p,self.hit,self.goal.x,self.goal.z,true)
			return self:stop(p)
		end
		if self:rearSweep(p,math.min(3,remaining)) then return self:stop(p,false) end
		v.aiRescueTimer=v.acDeltaTimeoutStop
		local tx,tz,mf=self.strategy:adjustPosition(p.x+fx*5,p.z+fz*5,false,math.min(5,remaining))
		return tx,tz,mf,math.min(3,AutoSteeringEngine.getMaxSpeed(v,dt,1,true,false,4,false,1)),math.max(0.5,remaining)
	end
	if self.phase=="blocked" then
		if self.coverageTask and AIVECoverage then
			AIVECoverage.defer(self,self.coverageTask,"cleanup needs a different approach");return self:stop(p)
		end
		if self.workingBypass then
			if self.clock-self.blockedAt>45000 then v:stopCurrentAIJob(AIMessageErrorBlockedByObject.new());return self:stop(p) end
			if self.clock>=self.retryAt then
				self.retryAt=self.clock+2000
				local hit=self:scan(p,self.routeTarget,true,math.max(14,2*self.radius+3))
				if not hit then self:release();return nil end
				if not hit.sensorFailed and not AIVEObstacles.mustWait(hit) then
					local since=self.blockedAt
					self:beginWorkingBypass(p,hit,self.routeTarget.x,self.routeTarget.z);self.blockedAt=since
				end
			end
			return self:stop(p)
		end
		if self.clock>=self.retryAt then
			self.retryAt=self.clock+2000
			v.aiRescueTimer=v.acDeltaTimeoutStop
			local recoveryGoal=self.goal or (self.maneuverPath and self.maneuverPath.goal) or self.routeTarget
			if not recoveryGoal then self:release(false);self:resetFieldSearch();return nil end
			self.goal=recoveryGoal;self.routeTarget=self.routeTarget or recoveryGoal
			local forward=self.routeForward~=self.vehicle.acParameters.inverted
			local hit=self:scan(p,self.routeTarget or self.goal,forward,3)
			if hit==nil then
				-- Backing deliberately moves the original wall/post out of the
				-- short sensor. Revalidate THAT object at the encounter pose;
				-- otherwise release/reverse would repeat forever. Never adopt a
				-- different distant object from an extended 12 m retry corridor.
				local held=self.encounterPose and self:scan(self.encounterPose,self.routeTarget or self.goal,forward,3)
				if held and self.hit and held.node==self.hit.node then
					self:beginPlan(p,self.hit,self.goal.x,self.goal.z,true)
					return self:stop(p)
				end
				self:log("saved driving direction is clear within 3 m; releasing obstacle hold")
				self:release();return nil
			end
			if hit.sensorFailed or AIVEObstacles.mustWait(hit) then return self:stop(p) end
			self:beginPlan(p,hit,self.goal.x,self.goal.z,true)
		end
		return self:stop(p)
	end
	local path=self.path
	local best,nearest=math.huge,self.pathIndex
	for i=self.pathIndex,math.min(#path,self.pathIndex+14) do
		local d=dist(p,path[i]);if d<best then nearest,best=i,d end
	end
	self.pathIndex=nearest
	if nearest>self.progressIndex then
		self.progressIndex=nearest;self.progressAt=self.clock
		if self.workingBypass then self.blockedAt=self.clock end
	end
	if self.clock-self.progressAt>20000 then self.phase="blocked";self.retryAt=self.clock+2000;return self:stop(p) end
	local targetIndex=math.min(#path,nearest+3)
	local target=path[targetIndex]
	local fx,fz=math.cos(self.goal.h),math.sin(self.goal.h)
	local along=(p.x-self.goal.x)*fx+(p.z-self.goal.z)*fz
	local side=-(p.x-self.goal.x)*fz+(p.z-self.goal.z)*fx
	if self.coverageTask then
		-- A target less than a metre ahead can sit behind the native steering
		-- node on a combine. Track the line with a proper lookahead, but STOP
		-- at its end: the steering target is not a permission to drive past it.
		target={x=self.goal.x+fx*(along+4),z=self.goal.z+fz*(along+4)}
		if along>=-.2 then
			AIVECoverage.finished(self);self:release(true);self:resetFieldSearch()
			self:log("cleanup strip ended; checking remaining crop before any further approach")
			return self:stop(p)
		end
	elseif nearest>=#path-6 then
		target={x=self.goal.x+fx*5,z=self.goal.z+fz*5}
	end
	if self.workingBypass and not self.coverageTask and along>=0 then
		-- Native steering cannot chase a waypoint that has already passed
		-- behind the steering node. Hand the end plane back to border search;
		-- any real missed crop is checked separately, never by driving a loop.
		if AIVECoverage and self.encounterPose then
			local a=self.encounterPose
			AIVECoverage.record(self,a,math.max(6,(p.x-a.x)*math.cos(a.h)+(p.z-a.z)*math.sin(a.h)))
		end
		self:release(true);self:resetFieldSearch();self.nextCoverageAt=self.clock+15000
		self:log("working bypass end reached; continuing along the actual crop edge")
		return self:stop(p)
	end
	local finalSide=self.workingBypass and 0.45 or 1.2
	local finalHeading=self.coverageTask and .12 or (self.workingBypass and 0.045 or 0.28)
	if nearest>=#path-6 and along>=(self.workingBypass and -0.25 or -1) and math.abs(side)<finalSide and math.abs(wrap(p.h-self.goal.h))<finalHeading then
		self:log("detour completed; continuing the saved working route")
		local cleanup=self.coverageTask~=nil
		if cleanup and AIVECoverage then AIVECoverage.finished(self) end
		if not cleanup and AIVECoverage and self.encounterPose then
			local a=self.encounterPose
			AIVECoverage.record(self,a,math.max(6,(p.x-a.x)*math.cos(a.h)+(p.z-a.z)*math.sin(a.h)+(self.workingBypass and 0 or 2)))
		end
		self:release(true)
		if cleanup then self:resetFieldSearch() end
		return nil
	end
	if self.clock>=self.nextProbe then
		-- Follow the validated route through bends. Extrapolating one constant
		-- steering arc here can swing back into the very post we are passing.
		self.lastHit=self:scanPath(p,path,nearest,3)
		if not self.lastHit and self.coverageTask then self.lastHit=self:scan(p,target,true,math.min(3,math.max(0,-along))) end
		if not self.lastHit and nearest>=#path-6 and not self.coverageTask then self.lastHit=self:scan(p,target,true,3) end
		self.nextProbe=self.clock+120
	end
	if self.lastHit then
		self.detourWaitSince=self.detourWaitSince or self.clock
		if self.workingBypass then
			if self.clock-(self.blockedAt or self.detourWaitSince)>45000 then
				v:stopCurrentAIJob(AIMessageErrorBlockedByObject.new());return self:stop(p)
			end
			if not self.lastHit.sensorFailed and self.clock-self.detourWaitSince>=400 and self:mayPass(self.lastHit) then
				if self.coverageTask and AIVECoverage then
					AIVECoverage.defer(self,self.coverageTask,"new obstacle on cleanup strip");return self:stop(p)
				end
				local since=self.blockedAt
				local destination=self.routeTarget or self.goal
				self:beginWorkingBypass(p,self.lastHit,destination.x,destination.z)
				self.blockedAt=since;self.detourWaitSince=nil
			end
		elseif not self.lastHit.sensorFailed and self.clock-self.detourWaitSince>=400 and self:mayPass(self.lastHit) then
			self:startAvoidance(p,self.lastHit,self.goal.x,self.goal.z,true)
			self.detourWaitSince=nil
		end
		return self:stop(p)
	end
	self.detourWaitSince=nil
	v.aiRescueTimer=v.acDeltaTimeoutStop
	if not self.workingBypass then v:aiFieldWorkerTurnProgress(nearest/math.max(1,#path),true) end
	local tx,tz,mf=self.strategy:adjustPosition(target.x,target.z,true,10)
	local limit=self.coverageTask and 3 or (self.workingBypass and 8 or 5)
	return tx,tz,mf,math.min(limit,AutoSteeringEngine.getMaxSpeed(v,dt,1,true,true,self.workingBypass and 2 or 4,false,1)),10
end
