-- Perimeter with lands. The existing Mogli strategy owns all perimeter turns.
-- This controller takes over at a pass end only after measuring the work left.
-- Coordinates u/v are metres along/across the first working direction.
AIVELands = {}
AIVELands.__index = AIVELands
AIVELands.switchWidth = 80
AIVELands.scanStep = 4
AIVELands.scanBudget = 24

local pi2 = 2 * math.pi
local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
local function norm(a) return a % pi2 end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end
local function point(x,z,h) return {x=x,z=z,h=h} end
local scanOffsets={{0.5,0.5},{0.15,0.15},{0.85,0.15},{0.15,0.85},{0.85,0.85}}
local costOffsets={{0,0},{-1.5,0},{1.5,0},{0,-1.5},{0,1.5}}
local peerMaskBits={1,2,4}

function AIVELands.new(vehicle)
	return setmetatable({vehicle=vehicle,phase="perimeter",clock=0,nextScan=0,travelled=0,perimeterPoints={},perimeterAngle=0},AIVELands)
end

function AIVELands.getTurnRadius(vehicle)
	local d,c=vehicle.acDimensions or {},vehicle.aiveChain or {}
	local r=math.max(2,d.radius or c.radius or 6,d.radius75 or 0)
	if AutoSteeringEngine.getMaxSteeringAngle75 and c.toolCount and c.toolCount>0 then
		local turn=AutoSteeringEngine.getMaxSteeringAngle75(vehicle)
		-- radiusT is the implement's inner wheel track; the tractor must follow
		-- the larger hitch-compatible radius, otherwise the trailer jackknifes.
		r=math.max(r,turn and turn.radius or 0)
	end
	return r+0.5
end

function AIVELands:world(u,v)
	return self.ox+self.dx*u-self.dz*v, self.oz+self.dz*u+self.dx*v
end

function AIVELands:localPoint(x,z)
	local x1,z1=x-self.ox,z-self.oz
	return x1*self.dx+z1*self.dz, -x1*self.dz+z1*self.dx
end

-- Four forward-only circle/straight/circle candidates. The tangent construction
-- is analytic, so every arc has the implement-compatible minimum turn radius.
function AIVELands.connectors(a,b,r)
	local result={}
	for _,s1 in ipairs({-1,1}) do
		for _,s2 in ipairs({-1,1}) do
			local c1=point(a.x-s1*r*math.sin(a.h), a.z+s1*r*math.cos(a.h))
			local c2=point(b.x-s2*r*math.sin(b.h), b.z+s2*r*math.cos(b.h))
			local dx,dz=c2.x-c1.x,c2.z-c1.z
			local d=math.sqrt(dx*dx+dz*dz)
			if d>1e-6 and d+1e-6>=math.abs((s1-s2)*r) then
				local h=atan2(dz,dx)+math.asin(math.max(-1,math.min(1,(s1-s2)*r/d)))
				local p1=point(c1.x+s1*r*math.sin(h), c1.z-s1*r*math.cos(h),h)
				local p2=point(c2.x+s2*r*math.sin(h), c2.z-s2*r*math.cos(h),h)
				local straight=(p2.x-p1.x)*math.cos(h)+(p2.z-p1.z)*math.sin(h)
				if straight>=-1e-5 then
					local a1,a2=norm(s1*(h-a.h)),norm(s2*(b.h-h))
					local path={point(a.x,a.z,a.h)}
					local function arc(c,from,angle,s)
						local n=math.max(1,math.ceil(angle*r/0.8))
						for i=1,n do
							local hh=from+s*angle*i/n
							path[#path+1]=point(c.x+s*r*math.sin(hh),c.z-s*r*math.cos(hh),hh)
						end
					end
					arc(c1,a.h,a1,s1)
					local n=math.max(1,math.ceil(math.max(0,straight)/0.8))
					for i=1,n do path[#path+1]=point(p1.x+(p2.x-p1.x)*i/n,p1.z+(p2.z-p1.z)*i/n,h) end
					arc(c2,h,a2,s2)
					path[#path]=point(b.x,b.z,b.h)
					path.length=r*(a1+a2)+math.max(0,straight)
					result[#result+1]=path
				end
			elseif d<=1e-6 and s1==s2 then
				local angle=norm(s1*(b.h-a.h))
				local path={point(a.x,a.z,a.h)}
				for i=1,math.max(1,math.ceil(angle*r/0.8)) do
					local h=a.h+s1*angle*i/math.max(1,math.ceil(angle*r/0.8))
					path[#path+1]=point(c1.x+s1*r*math.sin(h),c1.z-s1*r*math.cos(h),h)
				end
				path.length=angle*r
				result[#result+1]=path
			end
		end
	end
	-- Three-circle connectors handle the final close rows without a detour
	-- around the long side of the field (LRL / RLR).
	for _,s in ipairs({-1,1}) do
		local c1=point(a.x-s*r*math.sin(a.h),a.z+s*r*math.cos(a.h))
		local c3=point(b.x-s*r*math.sin(b.h),b.z+s*r*math.cos(b.h))
		local dx,dz=c3.x-c1.x,c3.z-c1.z
		local d=math.sqrt(dx*dx+dz*dz)
		if d>1e-6 and d<=4*r then
			for _,side in ipairs({-1,1}) do
				local offset=math.sqrt(math.max(0,4*r*r-d*d/4))
				local c2=point((c1.x+c3.x)/2-side*dz/d*offset,(c1.z+c3.z)/2+side*dx/d*offset)
				local h1=atan2(c2.z-c1.z,c2.x-c1.x)+s*math.pi/2
				local h2=atan2(c3.z-c2.z,c3.x-c2.x)-s*math.pi/2
				local a1,a2,a3=norm(s*(h1-a.h)),norm(-s*(h2-h1)),norm(s*(b.h-h2))
				local path={point(a.x,a.z,a.h)}
				local function arc(center,from,angle,turn)
					local n=math.max(1,math.ceil(angle*r/0.8))
					for i=1,n do
						local h=from+turn*angle*i/n
						path[#path+1]=point(center.x+turn*r*math.sin(h),center.z-turn*r*math.cos(h),h)
					end
				end
				arc(c1,a.h,a1,s);arc(c2,h1,a2,-s);arc(c3,h2,a3,s)
				path[#path]=point(b.x,b.z,b.h);path.length=(a1+a2+a3)*r
				result[#result+1]=path
			end
		end
	end
	return result
end

-- Work the two opposite edges inwards: 1, N, 2, N-1, ... .
-- These are the green passes in the user's revised sketch.
function AIVELands.laneOrder(count,spacing,radius)
	local result={}
	local low,high=1,count
	while low<=high do
		result[#result+1]=low
		if high~=low then result[#result+1]=high end
		low=low+1;high=high-1
	end
	return result
end

function AIVELands:pose()
	local node=self.vehicle.aiveChain.refNode
	local x,_,z=getWorldTranslation(node)
	local dx,_,dz=localDirectionToWorld(node,0,0,1)
	return point(x,z,atan2(dz,dx))
end

function AIVELands:beginScan()
	-- Engine field caches can be replaced while a corner is being searched.
	-- Keep the connected mask belonging to this job; query live work inside it.
	if self.field==nil and (self.vehicle.aiveFieldIsInvalid or self.vehicle.aiveCurrentFieldCo~=nil) then return false end
	local field=self.field or self.vehicle.aiveCurrentField
	if field==nil or field.getBounds==nil then return false end
	local x0,z0,x1,z1=field.getBounds()
	if x0==nil then return false end
	if self.dx==nil then
		local p=self:pose()
		-- A tractor may still be aligning with the edge here. Its instantaneous
		-- heading must not decide the measured width of the whole field.
		self.ox,self.oz,self.dx,self.dz=p.x,p.z,1,0
	end
	self.field=field
	local u0,v0,u1,v1
	for _,p in ipairs({{x0,z0},{x0,z1},{x1,z0},{x1,z1}}) do
		local u,v=self:localPoint(p[1],p[2])
		u0=math.min(u0 or u,u);v0=math.min(v0 or v,v)
		u1=math.max(u1 or u,u);v1=math.max(v1 or v,v)
	end
	local step=self.scanStep
	-- Work only decreases during this job. A fresh handover must not rescan
	-- hectares of already completed perimeter while the vehicle waits lifted.
	if self.workBounds then
		u0=math.max(u0,self.workBounds[1]-step);v0=math.max(v0,self.workBounds[2]-step)
		u1=math.min(u1,self.workBounds[3]+step);v1=math.min(v1,self.workBounds[4]+step)
	end
	self.scan={field=field,step=step,u0=math.floor(u0/step)*step,v0=math.floor(v0/step)*step,
		u1=math.ceil(u1/step)*step,v1=math.ceil(v1/step)*step,iu=0,iv=0,cells={},rows={}}
	return true
end

function AIVELands:hasWork(u0,v0,u1,v1)
	local x1,z1=self:world(u0,v0)
	local x2,z2=self:world(u1,v0)
	local x3,z3=self:world(u0,v1)
	for i=1,self.vehicle.aiveChain.toolCount do
		local area,total=AutoSteeringEngine.getAIAreaOfVehicle(self.vehicle,i,x1,z1,x2,z2,x3,z3,true)
		if area~=nil and area>0 then return true,type(total)=="number" and total>0 and math.min(1,area/total) or nil end
	end
	return false
end

function AIVELands:observe(dt)
	self.clock=self.clock+dt
	if not self.dispatchScanner and AIVEFieldDispatcher and AIVEFieldDispatcher.enabled(self.vehicle) then
		if not self.groupSession then
			AIVEFieldDispatcher.join(self,self.field or self.vehicle.aiveCurrentField)
		end
		if self.groupSession then
			AIVEFieldDispatcher.tick(self,dt)
			AIVEFieldDispatcher.adopt(self)
			local session=self.groupSession
			if not self.active and not session.headlandReady and self.perimeterCenter then
				local p=self:pose()
				if self.lastPose then local moved=distance(self.lastPose,p);if moved<10 then self.travelled=self.travelled+moved end end
				self.lastPose=p;self:observePerimeter(p)
				AIVEFieldDispatcher.perimeterProgress(self)
			end
		end
		return
	end
	if not self.active then
		local p=self:pose()
		if self.lastPose then
			local d=distance(self.lastPose,p)
			if d<10 then self.travelled=self.travelled+d end
		end
		self.lastPose=p
		if not self.dispatchScanner and not self.perimeterComplete then self:observePerimeter(p) end
	end
	if self.active and self.phase~="verify" then return end
	if self.scan==nil then
		if self.clock<self.nextScan or not self:beginScan() then return end
	end
	local scan=self.scan
	local step=scan.step
	if scan.refineSide then
		-- Refine only the four boundary bands, not every field cell. Coarse
		-- cells touching the just-worked swath must not create a return pass on it.
		for _=1,self.scanBudget do
			local side,offset=scan.refineSide,scan.refineOffset
			local a,b,c,d=scan.minU,scan.minV,scan.maxU,scan.maxV
			local band=math.min(1,step-offset)
			if side==1 then a=scan.refineBase[1]+offset;c=a+band
			elseif side==2 then c=scan.refineBase[3]-offset;a=c-band
			elseif side==3 then b=scan.refineBase[2]+offset;d=b+band
			else d=scan.refineBase[4]-offset;b=d-band end
			local found=self:hasWork(a,b,c,d)
			if found or offset+band>=step then
				if side==1 then scan.minU=a elseif side==2 then scan.maxU=c
				elseif side==3 then scan.minV=b else scan.maxV=d end
				scan.refineSide=side+1;scan.refineOffset=0
			else scan.refineOffset=offset+band end
			if scan.refineSide>4 then scan.refined=true;scan.refineSide=nil;self:completeScan(scan);return end
		end
		return
	end
	for _=1,self.scanBudget do
		local u,v=scan.u0+scan.iu*step,scan.v0+scan.iv*step
		local inside=false
		-- Check the connected field mask before querying work; neighbouring fields
		-- and islands outside this bitmap cannot expand the remaining core.
		for _,o in ipairs(scanOffsets) do
			local x,z=self:world(u+o[1]*step,v+o[2]*step)
			if scan.field.getBit(x,z) then inside=true;break end
		end
		local work,fraction
		if inside then work,fraction=self:hasWork(u,v,u+step,v+step) end
		if work then
			scan.workArea=(scan.workArea or 0)+step*step*(fraction or 1)
			scan.cells[#scan.cells+1]={u=u,v=v}
			scan.rows[scan.iv]=scan.rows[scan.iv] or {}
			scan.rows[scan.iv][scan.iu]=true
			scan.minU=math.min(scan.minU or u,u);scan.maxU=math.max(scan.maxU or u+step,u+step)
			scan.minV=math.min(scan.minV or v,v);scan.maxV=math.max(scan.maxV or v+step,v+step)
		end
		scan.iu=scan.iu+1
		if scan.u0+scan.iu*step>=scan.u1 then scan.iu=0;scan.iv=scan.iv+1 end
		if scan.v0+scan.iv*step>=scan.v1 then
			self:completeScan(scan)
			break
		end
	end
end

function AIVELands:observePerimeter(p)
	local points=self.perimeterPoints
	local last=points[#points]
	if last==nil or distance(last,p)>=1 then
		points[#points+1]=point(p.x,p.z,p.h)
		if self.perimeterCenter then self:countPerimeterPoint(p) end
	end
end

function AIVELands:countPerimeterPoint(p)
	if self.perimeterComplete then return end
	local center=self.perimeterCenter
	local angle=atan2(p.z-center.z,p.x-center.x)
	if self.lastPerimeterAngle~=nil then
		local delta=(angle-self.lastPerimeterAngle+math.pi)%pi2-math.pi
		-- A teleport or an across-field jump is not a completed contour.
		if math.abs(delta)<math.pi/2 then self.perimeterAngle=self.perimeterAngle+delta end
	end
	self.lastPerimeterAngle=angle
	local progress=math.abs(self.perimeterAngle)
	if progress>=pi2-0.06 and self.travelled>=self.minimumPerimeterDistance then
		self.perimeterComplete=true
		AIVELogger.info("Lands","Initial perimeter completed on '%s'; distance=%.1f m; waiting for a core near 80 m.",self:name(),self.travelled)
	end
end

function AIVELands:completeScan(scan)
	local step=scan.step
	-- Align from the shape of the work, independently of heading at hire/restart.
	if not self.axesChosen and #scan.cells>=3 then
		local n,su,sv,suu,svv,suv=#scan.cells,0,0,0,0,0
		for _,c in ipairs(scan.cells) do
			local u,v=c.u+step/2,c.v+step/2
			su=su+u;sv=sv+v;suu=suu+u*u;svv=svv+v*v;suv=suv+u*v
		end
		local xx,zz,xz=suu/n-(su/n)^2,svv/n-(sv/n)^2,suv/n-su*sv/(n*n)
		local angle=0.5*atan2(2*xz,xx-zz)
		self.axesChosen=true
		if math.abs(math.sin(angle))>0.01 then
			self.dx,self.dz=math.cos(angle),math.sin(angle)
			self.scan=nil;self.snapshot=nil;self.nextScan=0
			return
		end
	end
	if self.waitingHandover and scan.minU~=nil and not scan.refined then
		scan.refineSide=1;scan.refineOffset=0
		scan.refineBase={scan.minU,scan.minV,scan.maxU,scan.maxV}
		return
	end
	scan.completedAt=self.clock
	self.snapshot=scan;self.scan=nil;self.nextScan=self.clock+3000
	if scan.minU~=nil then
		if self.perimeterCenter==nil then
			local x,z=self:world((scan.minU+scan.maxU)/2,(scan.minV+scan.maxV)/2)
			self.perimeterCenter=point(x,z)
			self.minimumPerimeterDistance=0.65*2*(scan.maxU-scan.minU+scan.maxV-scan.minV)
			for _,p in ipairs(self.perimeterPoints) do self:countPerimeterPoint(p) end
		end
		self.workBounds={scan.minU,scan.minV,scan.maxU,scan.maxV}
		self.remainingWidth=math.min(scan.maxU-scan.minU,scan.maxV-scan.minV)
		local ready=self.perimeterComplete==true and self.remainingWidth<=self.switchWidth+self.scanStep
		if self.loggedReady~=ready or self.loggedWidth==nil or (math.abs(self.loggedWidth-self.remainingWidth)>=4 and self.clock-(self.loggedAt or 0)>=5000) then
			AIVELogger.info("Lands","Scan on '%s': remaining %.1f x %.1f m; perimeterComplete=%s; ready=%s.",self:name(),scan.maxU-scan.minU,scan.maxV-scan.minV,tostring(self.perimeterComplete==true),tostring(ready))
			self.loggedReady,self.loggedWidth,self.loggedAt=ready,self.remainingWidth,self.clock
		end
	end
end

function AIVELands:name()
	return type(self.vehicle.getName)=="function" and self.vehicle:getName() or "vehicle"
end

function AIVELands:isReady()
	local s=self.snapshot
	if self.groupSession then
		if not self.groupSession.headlandReady then return false end
		return s~=nil and s.minU~=nil
	end
	return self.perimeterComplete==true and s~=nil and s.minU~=nil and math.min(s.maxU-s.minU,s.maxV-s.minV)<=self.switchWidth+self.scanStep
end

-- Take ownership of the last metres of a straight perimeter pass BEFORE the
-- edge follower starts its corner. A corner can be followed continuously and
-- need never produce the legacy doTurn/isAtEnd event.
function AIVELands:finishPerimeterPass()
	if self.active or self.waitingHandover or self.finishingPass or not self:isReady() then return false end
	local veh=self.vehicle
	local width=math.max(0.5,2*veh.acDimensions.distance)
	if self.travelled<math.max(4,width) then return false end
	local p=self:pose()
	local u,v=self:localPoint(p.x,p.z)
	local du,dv=math.cos(p.h)*self.dx+math.sin(p.h)*self.dz,-math.cos(p.h)*self.dz+math.sin(p.h)*self.dx
	local s=self.snapshot
	local along,edge,h
	if math.abs(du)>=math.abs(dv) then
		if math.abs(du)<0.97 then return false end
		local sign=du>=0 and 1 or -1
		along=u*sign;edge=(sign==1 and s.maxU or s.minU)*sign
		h=atan2(self.dz*sign,self.dx*sign)
	else
		if math.abs(dv)<0.97 then return false end
		local sign=dv>=0 and 1 or -1
		along=v*sign;edge=(sign==1 and s.maxV or s.minV)*sign
		h=atan2(self.dx*sign,-self.dz*sign)
	end
	local remaining=edge-along-(veh.aiveChain.minZ or 0)+1
	local approach=math.max(8,width*1.5,(veh.acDimensions.radius or 6)+math.abs(veh.aiveChain.minZ or 0)+2)
	if remaining>approach or remaining < -approach then return false end
	remaining=math.max(0,remaining)
	self.finishingPass={start=p,finish=point(p.x+remaining*math.cos(h),p.z+remaining*math.sin(h),h)}
	self.phase="finishPerimeter";veh.aiveLandsPhase=self.phase
	self:setLowered(true)
	AIVELogger.info("Lands","Finishing perimeter pass on '%s': %.1f m forward, without reversing the working pass.",self:name(),remaining)
	return true
end

function AIVELands:requestHandover(reason)
	if self.waitingHandover then return true end
	if not self.finishingPass and not self:isReady() then return false end
	self.finishingPass=nil;self.waitingHandover=true;self.phase="handover"
	self.vehicle.aiveLandsPhase=self.phase
	self.scan=nil;self.snapshot=nil;self.nextScan=0
	self:setLowered(false)
	AIVELogger.info("Lands","Handover on '%s': %s; refreshing remaining work after the last pass.",self:name(),tostring(reason))
	return true
end

function AIVELands:pathCost(path,limit,obstacles)
	local cost=path.length
	local s=self.snapshot
	local field=s.field
	local escape=0
	if obstacles and distance(path[1],obstacles.origin)<0.25 then
		local blocked;blocked,escape=AIVEFieldDispatcher.pathIsBlocked(path[1],obstacles)
	end
	for i=1,#path do
		local p=path[i]
		if obstacles then
			local blocked,mask=AIVEFieldDispatcher.pathIsBlocked(p,obstacles)
			for _,bit in ipairs(peerMaskBits) do
				local occupied=mask%(2*bit)>=bit;local initial=escape%(2*bit)>=bit
				if occupied and not initial then return math.huge end
				if initial and not occupied then escape=escape-bit end
			end
		end
		if not field.getBit(p.x,p.z) then cost=cost+200 end
		local u,v=self:localPoint(p.x,p.z)
		for _,o in ipairs(costOffsets) do
			local row=s.rows[math.floor((v+o[2]-s.v0)/s.step)]
			if row~=nil and row[math.floor((u+o[1]-s.u0)/s.step)] then cost=cost+1000;break end
		end
		if limit and cost>limit then return cost end
	end
	return escape~=0 and math.huge or cost
end

function AIVELands:connector(a,b)
	local best,bestCost
	local obstacles=self.groupSession and AIVEFieldDispatcher.connectorObstacles(self) or nil
	local function consider(paths,prefix,knownPrefixCost)
		local prefixCost=prefix and (knownPrefixCost or self:pathCost(prefix,nil,obstacles)) or 0
		for _,path in ipairs(paths) do
			local cost=self:pathCost(path,bestCost and bestCost-prefixCost or nil,obstacles)+prefixCost
			if cost<math.huge and (bestCost==nil or cost<bestCost) then
				bestCost=cost;best={}
				if prefix then for _,p in ipairs(prefix) do best[#best+1]=p end end
				for _,p in ipairs(path) do best[#best+1]=p end
				best.length=path.length+(prefix and prefix.length or 0)
			end
		end
	end
	consider(self.connectors(a,b,self.radius))
	-- A same-heading transfer from a short perimeter side can otherwise cut
	-- diagonally across the core. Try the two ends of the worked headland too.
	local s=self.snapshot
	local margin=self.radius+2
	for _,u in ipairs({s.minU-margin,s.maxU+margin}) do
		for _,v in ipairs({s.minV-margin,s.maxV+margin}) do
			local x,z=self:world(u,v)
			for _,h in ipairs({0,math.pi/2,math.pi,3*math.pi/2}) do
				local via=point(x,z,atan2(self.dz,self.dx)+h)
				local first,bestFirstCost
				for _,p in ipairs(self.connectors(a,via,self.radius)) do
					local c=self:pathCost(p,bestFirstCost,obstacles)
					if c<math.huge and (bestFirstCost==nil or c<bestFirstCost) then first,bestFirstCost=p,c end
				end
				if first then consider(self.connectors(via,b,self.radius),first,bestFirstCost) end
			end
		end
	end
	return best
end

function AIVELands:makeLanes()
	local s=self.snapshot
	local span=s.maxV-s.minV
	local count=math.max(1,math.ceil(span/self.width))
	local spacing=span/count
	local order=self.laneOrder(count,spacing,self.radius)
	local _,hereV=self:localPoint(self:pose().x,self:pose().z)
	local fromHigh=math.abs(hereV-s.maxV)<math.abs(hereV-s.minV)
	self.lanes={}
	for _,index in ipairs(order) do
		if fromHigh then index=count+1-index end
		local v=s.minV+(index-0.5)*spacing
		local cells={}
		for _,c in ipairs(s.cells) do
			if c.v<v+spacing/2+0.01 and c.v+s.step>v-spacing/2-0.01 then
				local a,b=math.max(s.minU,c.u),math.min(s.maxU,c.u+s.step)
				if b>a then cells[#cells+1]={a,b} end
			end
		end
		table.sort(cells,function(a,b) return a[1]<b[1] end)
		-- Keep disconnected intervals separate instead of driving over a hole.
		local merged={}
		for _,c in ipairs(cells) do
			local last=merged[#merged]
			if last and c[1]<=last[2]+0.01 then last[2]=math.max(last[2],c[2])
			else merged[#merged+1]={c[1],c[2]} end
		end
		for _,interval in ipairs(merged) do
			local a,b=self:trimWorkInterval(interval[1],interval[2],v-spacing/2,v+spacing/2)
			if a~=nil then self.lanes[#self.lanes+1]={u0=a,u1=b,v=v,spacing=spacing,index=index} end
		end
	end
	-- A small leftover at the starting corner must not turn an otherwise
	-- completed perimeter swath into a full-length return working pass.
	local main,fragments={},{}
	local short=math.max(2*self.radius,(s.maxU-s.minU)*0.25)
	for _,lane in ipairs(self.lanes) do
		local list=lane.u1-lane.u0<short and fragments or main
		list[#list+1]=lane
	end
	self.lanes={}
	table.sort(main,function(a,b)
		if math.abs(a.v-b.v)<0.001 then return a.u0<b.u0 end
		if fromHigh then return a.v>b.v end
		return a.v<b.v
	end)
	local low,high=1,#main
	while low<=high do
		self.lanes[#self.lanes+1]=main[low]
		if high~=low then self.lanes[#self.lanes+1]=main[high] end
		low=low+1;high=high-1
	end
	for _,lane in ipairs(fragments) do self.lanes[#self.lanes+1]=lane end
	self.laneIndex=0
	self.direction=nil
end

function AIVELands:trimWorkInterval(u0,u1,v0,v1)
	if not self:hasWork(u0,v0,u1,v1) then return nil end
	local a,b=u0,u1
	if not self:hasWork(u0,v0,math.min(u0+1,u1),v1) then
		while b-a>0.5 do
			local m=(a+b)/2
			if self:hasWork(u0,v0,m,v1) then b=m else a=m end
		end
		u0=a
	end
	a,b=u0,u1
	if not self:hasWork(math.max(u0,u1-1),v0,u1,v1) then
		while b-a>0.5 do
			local m=(a+b)/2
			if self:hasWork(m,v0,u1,v1) then a=m else b=m end
		end
		u1=b
	end
	return u0,u1
end

function AIVELands:tryStart()
	local s=self.snapshot
	if self.active or not self:isReady() then return false end
	-- The grid encloses all detected work; the 4 m tolerance is the requested
	-- approximately 80 m, never a fixed count of perimeter laps.
	if not self.groupSession and math.min(s.maxU-s.minU,s.maxV-s.minV)>self.switchWidth+self.scanStep then return false end
	-- Reorient along the long side of the actual remaining core.
	if not self.groupSession and s.maxV-s.minV>s.maxU-s.minU then
		self.dx,self.dz=-self.dz,self.dx
		local rotated={}
		for _,c in ipairs(s.cells) do rotated[#rotated+1]={u=c.v,v=-c.u-s.step} end
		local a,b,c,d=s.minU,s.maxU,s.minV,s.maxV
		s.minU,s.maxU,s.minV,s.maxV=c,d,-b,-a
		local u0,v0,u1,v1=s.u0,s.v0,s.u1,s.v1
		s.u0,s.v0,s.u1,s.v1=v0,-u1,v1,-u0
		s.cells=rotated;s.rows={}
		for _,p in ipairs(rotated) do
			local i,j=math.floor((p.u-s.u0)/s.step),math.floor((p.v-s.v0)/s.step)
			s.rows[j]=s.rows[j] or {};s.rows[j][i]=true
		end
	end
	local dims=self.vehicle.acDimensions
	self.workBounds={s.minU,s.minV,s.maxU,s.maxV}
	self.width=math.max(0.5,2*dims.distance)
	self.radius=AIVELands.getTurnRadius(self.vehicle)
	self.active=true;self.scan=nil
	self.waitingHandover=false
	self:makeLanes()
	self.vehicle.aiveLandsPhase="transfer"
	AIVELogger.info("Lands","Perimeter -> lands on '%s'; remaining %.1f x %.1f m, width %.2f m, radius %.2f m, %d passes; opposite edges inwards.",
		self:name(),s.maxU-s.minU,s.maxV-s.minV,self.width,self.radius,#self.lanes)
	self:nextLane()
	return true
end

function AIVELands:setLowered(lowered)
	if self.lowered~=lowered or self.vehicle.acImplementsMoveDown~=lowered then
		self.lowered=lowered
		AIVehicleExtension.setAIImplementsMoveDown(self.vehicle,lowered,true)
	end
end

function AIVELands:nextLane()
	self.parking=nil
	self:setLowered(false)
	if self.groupSession then AIVEFieldDispatcher.releaseLane(self) end
	local veh=self.vehicle
	local current=self:pose()
	while self.laneIndex<#self.lanes do
		self.laneIndex=self.laneIndex+1
		local lane=self.lanes[self.laneIndex]
		if self:hasWork(lane.u0,lane.v-lane.spacing/2,lane.u1,lane.v+lane.spacing/2)
			and (not self.groupSession or AIVEFieldDispatcher.claim(self,lane)) then
			local x1,z1=self:world(lane.u0,lane.v)
			local x2,z2=self:world(lane.u1,lane.v)
			-- After each pass reverse direction. Choose the near end only for the
			-- initial handover, so all later loops stay on alternating headlands.
			local sign
			if self.direction then sign=-self.direction
			else sign=distance(current,point(x1,z1))<=distance(current,point(x2,z2)) and 1 or -1 end
			self.direction=sign
			self.groupLane=self.groupSession and lane or nil;self.groupEntryReversed=nil
			local chain=veh.aiveChain
			local lead=math.max(3,0.5*self.radius)
			local toolFront=math.max(0,chain.maxZ or 0)
			local toolBack=math.max(0,-(chain.minZ or 0))
			local start=(sign==1 and lane.u0 or lane.u1)-sign*(toolFront+lead)
			local finish=(sign==1 and lane.u1 or lane.u0)+sign*(toolBack+2)
			local h=atan2(self.dz*sign,self.dx*sign)
			-- Account for asymmetric implement centres in the vehicle's own frame.
			local centre=0.5*((chain.activeX or 0)+(chain.otherX or 0))
			local pathV=lane.v+sign*centre
			local sx,sz=self:world(start,pathV)
			local ex,ez=self:world(finish,pathV)
			self.workStart,self.workEnd=point(sx,sz,h),point(ex,ez,h)
			local turnReady=not self.groupSession
			self.path=turnReady and self:connector(current,self.workStart) or nil
			if turnReady and self.path==nil then self.error="no transfer route";return end
			self.pathIndex=1;self.phase=turnReady and "transfer" or "groupTurnWait";veh.aiveLandsPhase=self.phase
			self.lastProgress=current;self.progressTimer=0
			self.turnLeft=(self.workStart.x-current.x)*(-math.sin(current.h))+(self.workStart.z-current.z)*math.cos(current.h)>0
			if type(veh.aiFieldWorkerSideOffsetChanged)=="function" then
				veh:aiFieldWorkerSideOffsetChanged(self.turnLeft,false)
			end
			veh:aiFieldWorkerStartTurn(self.turnLeft)
			veh:aiFieldWorkerTurnProgress(0,self.turnLeft)
			AIVELogger.info("Lands","Pass %d/%d on '%s': strip %d, direction %d.",self.laneIndex,#self.lanes,self:name(),lane.index,sign)
			return
		end
	end
	if self.groupSession then
		self.phase="groupWait";self.groupWaitGeneration=self.groupGeneration
		veh.aiveLandsPhase=self.phase;return
	end
	self.phase="verify";veh.aiveLandsPhase=self.phase
	self.scan=nil;self.snapshot=nil;self.nextScan=0
end

-- An idle worker must not park on a fragment another width still needs.
-- Move to worked headland, using the same reserved/validated transfer planner.
function AIVELands:parkGroup()
	local s=self.snapshot
	if not s or not s.minU then return false end
	local p=self:pose();local u,v=self:localPoint(p.x,p.z)
	local margin=math.max(12,2*self.radius,self.width+3)
	if u<s.minU-5 or u>s.maxU+5 or v<s.minV-5 or v>s.maxV+5 then return false end
	local choices={}
	for _,q in ipairs({{s.minU-margin,v,-1,0},{s.maxU+margin,v,1,0},{u,s.minV-margin,0,-1},{u,s.maxV+margin,0,1}}) do
		local x,z=self:world(q[1],q[2])
		if self.field.getBit(x,z) and not self:hasWork(q[1]-self.width/2,q[2]-self.width/2,q[1]+self.width/2,q[2]+self.width/2) then
			local dx,dz=self.dx*q[3]-self.dz*q[4],self.dz*q[3]+self.dx*q[4]
			local target=point(x,z,atan2(dz,dx));target.score=distance(p,target)
			choices[#choices+1]=target
		end
	end
	table.sort(choices,function(a,b)return a.score<b.score end)
	if not choices[1] then return false end
	self.workStart=choices[1];self.path=nil;self.pathIndex=1;self.parking=true
	self.phase="groupTurnWait";self.vehicle.aiveLandsPhase=self.phase
	self.nextGroupRouteCheck=nil;self.groupRouteBlockedAt=nil
	self.turnLeft=(self.workStart.x-p.x)*(-math.sin(p.h))+(self.workStart.z-p.z)*math.cos(p.h)>0
	self.vehicle:aiFieldWorkerStartTurn(self.turnLeft);self.vehicle:aiFieldWorkerTurnProgress(0,self.turnLeft)
	self:setLowered(false)
	return true
end

function AIVELands:reverseGroupEntry()
	local lane=self.groupLane
	if not lane or self.parking or self.groupEntryReversed then return false end
	self.groupEntryReversed=true;self.direction=-self.direction
	local sign=self.direction;local chain=self.vehicle.aiveChain
	local lead=math.max(3,0.5*self.radius)
	local start=(sign==1 and lane.u0 or lane.u1)-sign*(math.max(0,chain.maxZ or 0)+lead)
	local finish=(sign==1 and lane.u1 or lane.u0)+sign*(math.max(0,-(chain.minZ or 0))+2)
	local pathV=lane.v+sign*0.5*((chain.activeX or 0)+(chain.otherX or 0))
	local h=atan2(self.dz*sign,self.dx*sign)
	local sx,sz=self:world(start,pathV);local ex,ez=self:world(finish,pathV)
	self.workStart,self.workEnd=point(sx,sz,h),point(ex,ez,h)
	AIVEFieldDispatcher.finishTurn(self)
	return true
end

function AIVELands:getDriveData(dt)
	local veh=self.vehicle
	local p=self:pose()
	if self.error then return p.x,p.z,true,0,0,"blocked" end
	if self.groupSession and self.snapshot and #self.snapshot.cells==0 then return p.x,p.z,true,0,0,"finished" end
	if self.groupSession and self.phase=="groupWait" then
		veh.aiRescueTimer=veh.acDeltaTimeoutStop;veh.acTurnStage=201
		if self.snapshot and #self.snapshot.cells==0 then
			if next(self.groupSession.leases)==nil then return p.x,p.z,true,0,0,"finished" end
			return p.x,p.z,true,0,0
		end
		if self.groupGeneration~=self.groupWaitGeneration then self:makeLanes();self:nextLane() end
		if self.phase=="groupWait" and next(self.groupSession.leases)~=nil and self.clock>=(self.nextParkCheck or 0) then
			self.nextParkCheck=self.clock+3000;self:parkGroup()
		end
		return p.x,p.z,true,0,0
	end
	if self.phase=="groupTurnWait" then
		veh.aiRescueTimer=veh.acDeltaTimeoutStop;veh.acTurnStage=200
		if not self.path then
			if self.clock<(self.nextGroupRouteCheck or 0) then return p.x,p.z,true,0,0 end
			if not AIVEFieldDispatcher.planTurn() then return p.x,p.z,true,0,0 end
			self.path=self:connector(p,self.workStart)
			if not self.path then
				if self:reverseGroupEntry() then return p.x,p.z,true,0,0 end
				self.nextGroupRouteCheck=self.clock+1000
				if self.blockedMotionGeneration~=self.groupSession.motionGeneration then
					self.blockedMotionGeneration=self.groupSession.motionGeneration;self.groupRouteBlockedAt=nil
				end
				self.groupRouteBlockedAt=self.groupRouteBlockedAt or self.clock
				if self.clock-self.groupRouteBlockedAt>45000 then self.error="group transfer corridor remains blocked";return p.x,p.z,true,0,0,"blocked" end
				return p.x,p.z,true,0,0
			end
			self.groupRouteBlockedAt=nil;self.nextGroupRouteCheck=nil
		end
		if not AIVEFieldDispatcher.requestTurn(self) then return p.x,p.z,true,0,0 end
		self.pathIndex=1;self.phase="transfer";veh.aiveLandsPhase=self.phase
		self.lastProgress=p;self.progressTimer=0
	end
	if self.finishingPass then
		local line=self.finishingPass
		local vx,vz=math.cos(line.finish.h),math.sin(line.finish.h)
		local remaining=(line.finish.x-p.x)*vx+(line.finish.z-p.z)*vz
		if remaining<=0.5 then
			self:requestHandover("perimeter pass completed")
			return p.x+vx,p.z+vz,true,0,0
		end
		self:setLowered(true)
		local total=distance(line.start,line.finish)
		local along=total-remaining
		local look=math.max(0,along)+math.max(4,veh.lastSpeed*1000)
		veh.acTurnStage=0;veh.aiRescueTimer=veh.acDeltaTimeoutStop
		return line.start.x+look*vx,line.start.z+look*vz,true,AutoSteeringEngine.getMaxSpeed(veh,dt,1,true,true,2,false,1),math.min(10,remaining)
	end
	if self.waitingHandover then
		veh.acTurnStage=201;veh.aiRescueTimer=veh.acDeltaTimeoutStop
		if self.snapshot==nil then return p.x,p.z,true,0,0 end
		if self.snapshot.minU==nil then return p.x,p.z,true,0,0,"finished" end
		if not self:tryStart() then
			self.waitingHandover=false;self.phase="perimeter";veh.aiveLandsPhase=nil
			self:setLowered(true)
			return p.x,p.z,true,0,0,"perimeter"
		end
	end
	if self.phase=="verify" then
		if self.snapshot then
			if #self.snapshot.cells==0 then return p.x,p.z,true,0,0,"finished" end
			local remaining=#self.snapshot.cells
			if self.lastRemaining and remaining>=self.lastRemaining then
				self.noProgress=(self.noProgress or 0)+1
			else self.noProgress=0 end
			self.lastRemaining=remaining
			if self.noProgress>=2 then self.error="remaining work does not decrease";return p.x,p.z,true,0,0,"blocked" end
			self:makeLanes();self:nextLane()
		end
		return p.x,p.z,true,0,0
	end
	if self.lastProgress==nil or distance(self.lastProgress,p)>0.5 then
		self.lastProgress=p;self.progressTimer=0
	else self.progressTimer=self.progressTimer+dt end
	if self.progressTimer>45000 then self.error="no movement for 45 seconds";return p.x,p.z,true,0,0,"blocked" end
	local target,remaining,speed
	if self.phase=="transfer" then
		local path=self.path
		-- Monotone projection onto the path, restricted to nearby segments. A
		-- crossing loop must never jump to a distant, later part of the route.
		local nearest,best=self.pathIndex,math.huge
		for i=self.pathIndex,math.min(#path,self.pathIndex+18) do
			local d=distance(p,path[i])
			if d<best then nearest,best=i,d end
		end
		self.pathIndex=nearest
		veh:aiFieldWorkerTurnProgress(nearest/math.max(1,#path),self.turnLeft)
		local lookahead=math.max(1.5,math.min(3,self.radius*0.35))
		local ahead=nearest
		local length=0
		while ahead<#path and length<lookahead do length=length+distance(path[ahead],path[ahead+1]);ahead=ahead+1 end
		target=path[ahead];remaining=distance(p,self.workStart)
		speed=math.min(7,AutoSteeringEngine.getMaxSpeed(veh,dt,1,true,true,4,false,1))
		local headingError=math.abs((p.h-self.workStart.h+math.pi)%pi2-math.pi)
		local fx,fz=math.cos(self.workStart.h),math.sin(self.workStart.h)
		local entryAlong=(p.x-self.workStart.x)*fx+(p.z-self.workStart.z)*fz
		local entrySide=-(p.x-self.workStart.x)*fz+(p.z-self.workStart.z)*fx
		if nearest>=#path-5 then target=point(self.workStart.x+fx*4,self.workStart.z+fz*4) end
		if nearest>=#path-5 and entryAlong>=-1.3 and math.abs(entrySide)<1.3 and headingError<0.28 then
			self.phase=self.parking and "groupWait" or "work";veh.aiveLandsPhase=self.phase
			if self.groupSession then AIVEFieldDispatcher.finishTurn(self) end
			veh:aiFieldWorkerTurnProgress(1,self.turnLeft)
			veh:aiFieldWorkerEndTurn(self.turnLeft)
			self:setLowered(not self.parking)
			if self.parking then
				self.parking=nil;self.groupWaitGeneration=nil;self.groupSession.dirty=true
				return p.x,p.z,true,0,0
			end
		end
		-- Braking distance follows the loop rather than the direct distance
		-- to its nearby endpoint.
		remaining=distance(p,path[nearest])
		for i=nearest+1,math.min(#path,nearest+20) do remaining=remaining+distance(path[i-1],path[i]) end
		veh.acTurnStage=200
	else
		self:setLowered(true)
		local vx,vz=math.cos(self.workStart.h),math.sin(self.workStart.h)
		local along=(p.x-self.workStart.x)*vx+(p.z-self.workStart.z)*vz
		local total=distance(self.workStart,self.workEnd)
		remaining=total-along
		if remaining<=0.6 then
			self:nextLane()
			return p.x+vx*2,p.z+vz*2,true,0,0
		end
		local lookahead=math.min(total+5,math.max(0,along)+math.max(4,veh.lastSpeed*1000*0.8))
		target=point(self.workStart.x+lookahead*vx,self.workStart.z+lookahead*vz)
		speed=AutoSteeringEngine.getMaxSpeed(veh,dt,1,true,true,2,false,1)
		local anim,noSneak=AutoSteeringEngine.checkIsAnimPlaying(veh,true)
		if anim or noSneak then speed=0 end
		veh.acTurnStage=0
	end
	veh.aiRescueTimer=veh.acDeltaTimeoutStop
	AIVehicleExtension.setStatus(veh,self.phase=="work" and 1 or 2)
	return target.x,target.z,true,speed,math.max(1,math.min(10,remaining))
end
