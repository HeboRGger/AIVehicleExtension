-- FS25 swept-footprint protection and local, validated obstacle detours.
-- All physics queries are synchronous. A stopped/yielding vehicle never grants
-- another vehicle permission to drive through it: every detour is swept again.
AIVEObstacles={}
AIVEObstacles.__index=AIVEObstacles
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
			part.half,part.length,part.height,part.label=(b1-b0)/2+0.2,(a1-a0)/2+0.2,math.max(2.5,size.height or 3),label
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
	for i=#self.parts,partCount+1,-1 do self.parts[i]=nil end
	-- Compatibility for a work-width-only tool with no separate scene object.
	if #self.parts==1 and not next(c.tools or {}) and not next(v.childVehicles or {}) then
		local part=self.parts[1]
		part.half=math.max(part.half,(d.distance or 0)+0.35)
		self.half=math.max(self.half,part.half)
	end
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
	for _,corner in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
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
function AIVEObstacles:box(p,reverse,frontLimit,backLimit)
	local fx,fz=math.cos(p.h),math.sin(p.h)
	for _,part in ipairs(self.parts or {}) do
		local a,b,h,half,length=clippedPart(part,frontLimit,backLimit,reverse)
		if a then
			local hit=self:queryPart(p.x+a*fx-b*fz,p.z+a*fz+b*fx,p.h+h,half,length,part.height)
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
function AIVEObstacles:scan(p,target,forward,range)
	local h=p.h+(forward and 0 or math.pi)
	local dx,dz=target.x-p.x,target.z-p.z
	local cross=-math.sin(h)*dx+math.cos(h)*dz
	local k=2*cross/math.max(1,dx*dx+dz*dz)
	k=math.max(-1/self.radius,math.min(1/self.radius,k))
	local x,z=p.x,p.z
	-- Reverse corners approach fixed objects slowly; use a finer sweep so
	-- the last metre is not quantised into 40 cm jumps.
	local steps=math.max(1,math.ceil(range/(forward and 0.4 or 0.15)))
	for i=0,steps do
		local hit=self:box({x=x,z=z,h=h},not forward)
		if hit then hit.distance=i*range/steps;return hit end
		local step=range/steps
		local nextH=h+k*step
		x=x+step*math.cos((h+nextH)/2);z=z+step*math.sin((h+nextH)/2);h=nextH
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
	self.routeTarget={x=tx,z=tz};self.routeForward=true
	self.hit=hit;self.phase="planning";self.candidates={};self.blockedAt=self.clock
	local fx,fz=math.cos(p.h),math.sin(p.h)
	local objectAlong=(hit.x-p.x)*fx+(hit.z-p.z)*fz
	-- distance comes from a collision query, not from the object's scene origin.
	local approach=math.max(3,(hit.distance or 0)-0.8)
	local plateau=math.max(approach+2,objectAlong+self.back+1,self.front+self.back+(hit.distance or 0)+1)
	local finish=plateau+approach
	local grouped=1
	local maxOffset=math.min(12,math.max(4,2*self.half))
	-- Do not rejoin the border immediately in front of the NEXT bush. The
	-- previous planner swept the bypass itself, but never the road ahead of
	-- its rejoin; it discovered the third bush with only 2.7 m left to steer.
	-- Keep the lateral deviation across a cluster until a complete steering
	-- preview on the saved working line is clear after the return.
	local seen={[hit.node or 0]=true}
	local preview=math.max(14,2*self.radius+3)
	local u=0
	local waitForTraffic=false
	-- Sweep CONTINUOUSLY as the goal grows. Checking only the new endpoint
	-- skipped an entire header-length interval and missed a fourth bush
	-- between the old/new return positions on Vladimirovka's real boundary.
	while u<=math.min(180,finish+preview) do
		local q={x=p.x+fx*u,z=p.z+fz*u,h=p.h}
		if not self:isWorkingPoseOnField(q) then break end
		local nextHit=self:box(q,false)
		if nextHit then
			if nextHit.sensorFailed or AIVEObstacles.mustWait(nextHit) then waitForTraffic=true;break end
			if not seen[nextHit.node or 0] then seen[nextHit.node or 0]=true;grouped=grouped+1 end
			local nextPlateau=u+self.front+self.back+1
			if nextPlateau>plateau and nextPlateau+approach<=180 then plateau=nextPlateau;finish=plateau+approach end
		end
		u=u+0.4
	end
	self.goal={x=p.x+fx*finish,z=p.z+fz*finish,h=p.h}
	local preferred=self.vehicle.acParameters.rightAreaActive and -1 or 1
	for i=1,(waitForTraffic and 0 or math.ceil(maxOffset/0.25)) do
		for _,sign in ipairs({preferred,-preferred}) do
			local offset=i*0.25*sign
			-- A later, wider bush may require more shift than the first one.
			-- Give that shift enough length for the steering radius instead of
			-- rejecting it solely because the first bush is close. Full sweeping
			-- still verifies clearance on the incomplete approach to that bush.
			local ramp=math.max(approach,math.sqrt(6*self.radius*math.abs(offset)))
			local run=math.max(plateau,ramp+2)
			local total=run+ramp
			local path={length=0,working=true,offset=offset}
			path.goal={x=p.x+fx*total,z=p.z+fz*total,h=p.h}
			path.build={origin=p,fx=fx,fz=fz,ramp=ramp,run=run,total=total,steps=math.ceil(total/0.25),index=0,radius=self.radius}
			self.candidates[#self.candidates+1]=path
		end
	end
	-- Increasing lateral displacement, field side first. A harvested crop is
	-- desirable here; the raised-transfer crop penalty would choose the verge.
	self.candidateIndex=1;self.checkIndex=1;self.bestPath=nil;self.bestCost=nil;self.workCache={};self.candidateCrop=0
	self:log(string.format("working border bypass: %.1f m ahead; full-header padding=0.20 m; candidates=%d; grouped=%d; return=%.1f m",hit.distance or 0,#self.candidates,grouped,finish))
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
	if not self:tryBackout() then self:beginPlan(p,hit,tx,tz,forward) end
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
	self.workingBypass=nil;self.vehicle.aiveWorkingBypass=nil
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
        if u<b.ramp then t=u/b.ramp
        elseif u>b.run then t=(b.total-u)/b.ramp;reverse=true
        else t=1 end
        local lateral=path.offset*t*t*t*(10+t*(-15+6*t))
        local slope=path.offset*30*t*t*(1-t)*(1-t)/b.ramp*(reverse and -1 or 1)
        local bend=path.offset*60*t*(1-t)*(1-2*t)/(b.ramp*b.ramp)
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
			if not self.workingBypass and self:tryBackout() then return end
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
		if self:box(p,false) or (self.workingBypass and not self:isWorkingPoseOnField(p)) then
			self.candidateIndex=self.candidateIndex+1;self.checkIndex=1;self.candidateCrop=0
		else
			if self.workingBypass then
				self.checkIndex=self.checkIndex+1
				if self.checkIndex>#path then self:acceptPlan(path);return end
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
	local range=working and math.max(14,2*self.radius+3) or 3
	if not forward or self.clock>=self.nextProbe then
		self.lastHit=self:scan(p,{x=tx,z=tz},forward,range)
		self.nextProbe=self.clock+120
	end
	local hit=self.lastHit
	if hit==nil then self.waitSince=nil;self.waitNode=nil;return tx,tz,mf,maxSpeed,stopDistance end
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
	if working and (hit.distance or 0)>3 then
		local projected={x=p.x+math.cos(p.h)*hit.distance,z=p.z+math.sin(p.h)*hit.distance,h=p.h}
		-- Let the normal corner start before a tree BEYOND the field. The
		-- longer working preview must not freeze an otherwise clear headland.
		if not self:isWorkingPoseOnField(projected) then return tx,tz,mf,maxSpeed,stopDistance end
	end
	-- A working combine needs enough lead distance to bend around a tree
	-- without a reverse leg. Other vehicles/people retain the short wait zone.
	if working and forward then
		self:beginWorkingBypass(p,hit,tx,tz)
		return self:stop(p,mf)
	end
	if not forward and (hit.distance or 0)>0.75 then
		-- Keep the 3 m warning corridor, but creep towards a fixed obstacle
		-- rather than ending the reverse leg at its first distant detection.
		-- Clearance is from the padded full rig, not its reference node.
		local remaining=hit.distance-0.75
		self.waitSince=nil
		self.vehicle.aiRescueTimer=self.vehicle.acDeltaTimeoutStop
		-- Keep a nonzero rolling horizon; an almost-zero stop distance can
		-- make the engine brake before reaching the clearance threshold.
		return tx,tz,mf,math.min(maxSpeed,1.5),math.min(stopDistance or remaining,math.max(0.5,remaining))
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
		local allowed,stop,reason=v:getCanAIFieldWorkerContinueWork(true)
		if not allowed then
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
	if nearby and (nearby.sensorFailed or AIVEObstacles.mustWait(nearby)) then return self:stop(p) end
	if self.phase=="reverseBlocked" then
		if self.clock>=self.retryAt then
			self.retryAt=self.clock+2000
			local hit=self:scan(p,self.routeTarget,false,3)
			if not hit then self:release();return nil end
			if not hit.sensorFailed and not AIVEObstacles.mustWait(hit) then self:tryForwardRecovery() end
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
	if nearest>self.progressIndex then self.progressIndex=nearest;self.progressAt=self.clock end
	if self.clock-self.progressAt>20000 then self.phase="blocked";self.retryAt=self.clock+2000;return self:stop(p) end
	local targetIndex=math.min(#path,nearest+3)
	local target=path[targetIndex]
	local fx,fz=math.cos(self.goal.h),math.sin(self.goal.h)
	local along=(p.x-self.goal.x)*fx+(p.z-self.goal.z)*fz
	local side=-(p.x-self.goal.x)*fz+(p.z-self.goal.z)*fx
	if nearest>=#path-6 then target={x=self.goal.x+fx*5,z=self.goal.z+fz*5} end
	local finalSide=self.workingBypass and 0.45 or 1.2
	local finalHeading=self.workingBypass and 0.045 or 0.28
	if nearest>=#path-6 and along>=(self.workingBypass and -0.25 or -1) and math.abs(side)<finalSide and math.abs(wrap(p.h-self.goal.h))<finalHeading then
		self:log("detour completed; continuing the saved working route")
		self:release(true);return nil
	end
	if self.clock>=self.nextProbe then
		-- Follow the validated route through bends. Extrapolating one constant
		-- steering arc here can swing back into the very post we are passing.
		self.lastHit=self:scanPath(p,path,nearest,3)
		if not self.lastHit and nearest>=#path-6 then self.lastHit=self:scan(p,target,true,3) end
		self.nextProbe=self.clock+120
	end
	if self.lastHit then
		self.detourWaitSince=self.detourWaitSince or self.clock
		if self.workingBypass then
			if self.clock-self.detourWaitSince>45000 then v:stopCurrentAIJob(AIMessageErrorBlockedByObject.new()) end
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
	return tx,tz,mf,math.min(self.workingBypass and 8 or 5,AutoSteeringEngine.getMaxSpeed(v,dt,1,true,true,self.workingBypass and 2 or 4,false,1)),10
end
