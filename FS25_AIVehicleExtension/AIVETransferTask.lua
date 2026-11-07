-- A native AI job task with an optional, read-only AutoDrive road graph.
-- AutoDrive never takes control: the GIANTS job owns the helper and messages.
-- Field alignment uses checked forward connectors, independent of road AI data.
AIVETransferTask = {}
local mt = Class(AIVETransferTask, AITaskDriveTo)
local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end
local function wrap(a) return (a+math.pi)%(2*math.pi)-math.pi end

-- Speeds are km/h; geometry and braking acceleration use metres/seconds.
AIVETransferTask.TURN_SPEED=12
AIVETransferTask.BRAKE_ACCELERATION=1.5
AIVETransferTask.TURN_CURVATURE=1/200
function AIVETransferTask.getTravelSpeed(vehicle)
    local speed=type(vehicle.getCruiseControlMaxSpeed)=="function" and vehicle:getCruiseControlMaxSpeed() or nil
    if not speed or speed<=0 or speed==math.huge then
        local motor=type(vehicle.getMotor)=="function" and vehicle:getMotor() or nil
        speed=motor and type(motor.getMaximumForwardSpeed)=="function" and motor:getMaximumForwardSpeed()*3.6 or 40
    end
    return speed
end
function AIVETransferTask.getCurrentSpeed(vehicle)
    return math.abs(type(vehicle.getLastSpeed)=="function" and vehicle:getLastSpeed() or (vehicle.lastSpeedReal or vehicle.lastSpeed or 0)*3600)
end
function AIVETransferTask:getRoadSpeed(p,nearest,target)
    local speed=AIVETransferTask.getTravelSpeed(self.vehicle)
    local turn=AIVETransferTask.TURN_SPEED
    local brake=AIVETransferTask.BRAKE_ACCELERATION
    local horizon=math.max(14,(speed/3.6)^2/(2*brake)+8)
    local walked,previous=0,p
    for i=nearest,#self.path do
        local q=self.path[i]
        walked=walked+distance(previous,q)
        if walked>horizon then break end
        local nextPoint=self.path[i+1]
        if nextPoint and distance(q,nextPoint)>0.01 then
            local heading=q.h or atan2(nextPoint.z-q.z,nextPoint.x-q.x)
            local after=self.path[i+2]
            local nextHeading=nextPoint.h or (after and atan2(after.z-nextPoint.z,after.x-nextPoint.x)) or heading
            if math.abs(wrap(nextHeading-heading))/distance(q,nextPoint)>=AIVETransferTask.TURN_CURVATURE then
                speed=math.min(speed,3.6*math.sqrt((turn/3.6)^2+2*brake*math.max(0,walked-4)))
            end
        elseif not nextPoint then
            -- Start braking before the final 2 km/h field handoff.
            speed=math.min(speed,3.6*math.sqrt((2/3.6)^2+2*brake*math.max(0,walked-6)))
        end
        previous=q
    end
    local dx,dz=target.x-p.x,target.z-p.z
    local curvature=2*(-math.sin(p.h)*dx+math.cos(p.h)*dz)/math.max(1,dx*dx+dz*dz)
    if math.abs(curvature)>=AIVETransferTask.TURN_CURVATURE then speed=math.min(speed,turn) end
    return speed
end

function AIVETransferTask.getGraph()
    local env = FS25_AutoDrive
    local graph = (env and env.ADGraphManager) or ADGraphManager
    if graph and type(graph.getWayPoints)=="function" and type(graph.isReverseRoad)=="function" then
        local points=graph:getWayPoints()
        if points and next(points) then return graph,points end
    end
    return nil
end

function AIVETransferTask.hasMapRoads()
    local ai=g_currentMission and g_currentMission.aiSystem
    return ai and ai.roadSplines and #ai.roadSplines>0 and type(getSplineLength)=="function" and type(getSplinePosition)=="function"
end

-- Read the map's actual AI road curves. This avoids the GENERIC 6 m native
-- spline limit without changing global navigation or any map/AD data. Explicit
-- bridge/tunnel limits are retained and the full rig is swept while driving.
function AIVETransferTask.getMapGraph()
    if not AIVETransferTask.hasMapRoads() then return nil end
    local ai=g_currentMission.aiSystem
    local old=AIVETransferTask.mapGraphCache
    if old and old.mission==g_currentMission and old.count==#ai.roadSplines then return old.graph end
    local points,buckets,ends={},{},{}
    -- Map authors leave ordinary junction gaps between lane curves. On
    -- Vladimirovka the farm exit has 7.5-10 m gaps, so a 4 m join disconnected
    -- the farm from the field roads even though GIANTS could drive there.
    local junctionRadius=12
    local function bucket(x,z) return math.floor(x/junctionRadius)..":"..math.floor(z/junctionRadius) end
    local function attr(node,key)
        if type(getUserAttribute)~="function" then return nil end
        for _=1,24 do
            if not node or node==0 then break end
            local value=tonumber(getUserAttribute(node,key))
            if value then return value end
            if type(getParent)~="function" then break end
            node=getParent(node)
        end
    end
    for _,spline in ipairs(ai.roadSplines) do
        local length=getSplineLength(spline)
        if length and length>0.1 then
            local steps=math.max(1,math.ceil(length/2.5))
            if #points+steps+1>60000 then return nil end
            local first=#points+1
            local maxWidth,maxHeight,maxRadius=attr(spline,"maxWidth"),attr(spline,"maxHeight"),attr(spline,"maxTurningRadius")
            for j=0,steps do
                local x,y,z=getSplinePosition(spline,j/steps)
                local id=#points+1
                local p={id=id,x=x,y=y,z=z,out={},incoming={},spline=spline,before=j>0 and id-1 or nil,after=j<steps and id+1 or nil,maxWidth=maxWidth,maxHeight=maxHeight,maxRadius=maxRadius}
                points[id]=p
                if j>0 then points[id-1].out[#points[id-1].out+1]=id;p.incoming[#p.incoming+1]=id-1 end
                local key=bucket(x,z);buckets[key]=buckets[key] or {};buckets[key][#buckets[key]+1]=id
            end
            -- Keep spline direction. Parallel/opposite lane curves supplied
            -- by the map provide the return direction; never add a reverse edge.
            ends[#ends+1]={first=first,last=#points}
            if steps>2 and distance(points[first],points[#points])<0.5 then
                points[#points].out[#points[#points].out+1]=first
                points[first].incoming[#points[first].incoming+1]=#points
            end
        end
    end
    local function join(p,q)
        if p.spline==q.spline or not p.before or not q.after or distance(p,q)>junctionRadius or math.abs(p.y-q.y)>2 then return end
        local before,after=points[p.before],points[q.after]
        local ax,az=p.x-before.x,p.z-before.z
        local dx,dz=after.x-q.x,after.z-q.z
        if ax*dx+az*dz>=-0.15*math.sqrt((ax*ax+az*az)*(dx*dx+dz*dz)) then
            p.out[#p.out+1]=q.id;q.incoming[#q.incoming+1]=p.id
        end
    end
    for _,e in ipairs(ends) do
      for _,endpoint in ipairs({e.first,e.last}) do
        local p=points[endpoint]
        local bx,bz=math.floor(p.x/junctionRadius),math.floor(p.z/junctionRadius)
        for ox=-1,1 do for oz=-1,1 do
            for _,id in ipairs(buckets[(bx+ox)..":"..(bz+oz)] or {}) do
                local q=points[id]
                    -- Permit junction turns, reject a direct jump onto the
                    -- oncoming lane. Only physically adjacent curve endpoints
                    -- are joined; field gaps are never bridged.
                if endpoint==e.first then join(q,p) else join(p,q) end
            end
        end end
      end
    end
    local graph={points=points,source="map"}
    graph.getWayPoints=function(self)return self.points end
    graph.isReverseRoad=function()return false end
    AIVETransferTask.mapGraphCache={mission=g_currentMission,count=#ai.roadSplines,graph=graph}
    return graph
end

-- Directed Dijkstra with a heap. Never invent connections or travel down an
-- AutoDrive reverse-only link as a forward road. No markers/settings are edited.
function AIVETransferTask.roadPath(start,finish,source,limits)
    local graph,points
    if source then graph=source;points=source:getWayPoints() else graph,points=AIVETransferTask.getGraph() end
    if not graph then return nil end
    local starts,goals={},{}
    for id,p in pairs(points) do
        if type(p)=="table" and p.x and p.z then
            local a,b=distance(start,p),distance(finish,p)
            if a<=80 and (not p.y or not start.y or math.abs(p.y-start.y)<3) then starts[#starts+1]={id=id,d=a} end
            if b<=80 and (not p.y or not finish.y or math.abs(p.y-finish.y)<3) then goals[#goals+1]={id=id,d=b} end
        end
    end
    table.sort(starts,function(a,b)return a.d<b.d end)
    table.sort(goals,function(a,b)return a.d<b.d end)
    -- A local, checked connection is required at each end. Weight its distance
    -- so a nearby dead-end parking spur does not hide a usable adjacent road.
    if not starts[1] or not goals[1] then return nil end
    local goal={}
    for _,q in ipairs(goals) do goal[q.id]=q.d*5 end
    local heap,cost,previous,closed={},{},{},{}
    local function push(id,value)
        local i=#heap+1
        while i>1 do
            local parent=math.floor(i/2)
            if heap[parent].value<=value then break end
            heap[i]=heap[parent];i=parent
        end
        heap[i]={id=id,value=value}
    end
    local function pop()
        local first,last=heap[1],table.remove(heap)
        if #heap>0 then
            local i=1
            while 2*i<=#heap do
                local child=2*i
                if child<#heap and heap[child+1].value<heap[child].value then child=child+1 end
                if last.value<=heap[child].value then break end
                heap[i]=heap[child];i=child
            end
            heap[i]=last
        end
        return first
    end
    for _,s in ipairs(starts) do
        local p=points[s.id]
        local allowed=not limits or ((not p.maxWidth or p.maxWidth>=limits.width) and (not p.maxHeight or p.maxHeight>=limits.height) and (not p.maxRadius or p.maxRadius>=limits.radius))
        if allowed then
            local turn=0
            local ahead=points[p.after or (p.out or {})[1]]
            if ahead and start.h then turn=math.abs(wrap(atan2(ahead.z-p.z,ahead.x-p.x)-start.h)) end
            local value=s.d*5+3*(limits and limits.radius or 6.5)*turn*turn
            cost[s.id]=value;push(s.id,value)
        end
    end
    local best,bestCost,visits=nil,math.huge,0
    while #heap>0 and visits<100000 do
        local item=pop();local id=item.id
        if not closed[id] then
            if item.value>bestCost then break end
            closed[id]=true;visits=visits+1
            if goal[id] and item.value+goal[id]<bestCost then best,bestCost=id,item.value+goal[id] end
            local p=points[id]
            for _,to in ipairs(p.out or {}) do
                local q=points[to]
                local allowed=q and (not limits or ((not q.maxWidth or q.maxWidth>=limits.width) and (not q.maxHeight or q.maxHeight>=limits.height) and (not q.maxRadius or q.maxRadius>=limits.radius)))
                if allowed and not closed[to] and not graph:isReverseRoad(p,q) then
                    local priority=graph.getIsPointSubPrio and graph:getIsPointSubPrio(to) and (graph.SUB_PRIO_FACTOR or 20) or 1
                    local value=item.value+distance(p,q)*priority
                    if not cost[to] or value<cost[to] then cost[to]=value;previous[to]=id;push(to,value) end
                end
            end
        end
    end
    if not best then return nil end
    local reverse={}
    while best do reverse[#reverse+1]=points[best];best=previous[best] end
    local path={}
    for i=#reverse,1,-1 do
        local p=reverse[i]
        local q=reverse[math.max(1,i-1)]
        local before=reverse[math.min(#reverse,i+1)]
        local h=atan2(q.z-before.z,q.x-before.x)
        path[#path+1]={x=p.x,z=p.z,h=h,id=p.id}
    end
    if #path==1 then path[1].h=start.h end
    return path
end

-- Recorded points can be sparse, and a wide header cannot pivot at a graph
-- vertex. Round the road polyline with tangent arcs of the actual turn radius,
-- retaining <=15 cm simplification error. Reject corners that cannot fit.
function AIVETransferTask.roundRoad(road,radius,tolerance)
    if #road<2 then return road end
    local points={road[1]}
    for i=2,#road-1 do
        local a,b,c=points[#points],road[i],road[i+1]
        local dx,dz=c.x-a.x,c.z-a.z
        local length=math.sqrt(dx*dx+dz*dz)
        local error=length>0 and math.abs(dx*(b.z-a.z)-dz*(b.x-a.x))/length or math.huge
        local dot=(b.x-a.x)*(c.x-b.x)+(b.z-a.z)*(c.z-b.z)
        if error>(tolerance or 0.15) or dot<0 then points[#points+1]=b end
    end
    points[#points+1]=road[#road]
    local h=atan2(points[2].z-points[1].z,points[2].x-points[1].x)
    local path={{x=points[1].x,z=points[1].z,h=h}}
    local function line(q,heading)
        local p=path[#path]
        local steps=math.max(1,math.ceil(distance(p,q)/0.4))
        for j=1,steps do path[#path+1]={x=p.x+(q.x-p.x)*j/steps,z=p.z+(q.z-p.z)*j/steps,h=heading} end
    end
    for i=2,#points-1 do
        local a,b,c=points[i-1],points[i],points[i+1]
        local la,lb=distance(a,b),distance(b,c)
        if la<0.01 or lb<0.01 then return nil end
        local ux,uz=(b.x-a.x)/la,(b.z-a.z)/la
        local vx,vz=(c.x-b.x)/lb,(c.z-b.z)/lb
        local angle=math.acos(math.max(-1,math.min(1,ux*vx+uz*vz)))
        local before=atan2(uz,ux)
        if angle<0.001 then line(b,before)
        else
            local cut=radius*math.tan(angle/2)
            if cut>0.49*math.min(la,lb) then return nil end
            local sign=ux*vz-uz*vx>0 and 1 or -1
            local entry={x=b.x-ux*cut,z=b.z-uz*cut}
            line(entry,before)
            local cx,cz=entry.x-sign*radius*uz,entry.z+sign*radius*ux
            local steps=math.ceil(angle*radius/0.4)
            for j=1,steps do
                local ah=before+sign*angle*j/steps
                path[#path+1]={x=cx+sign*radius*math.sin(ah),z=cz-sign*radius*math.cos(ah),h=ah}
            end
        end
    end
    local last,previous=points[#points],points[#points-1]
    line(last,atan2(last.z-previous.z,last.x-previous.x))
    return path
end

-- A polyline sampled from a smooth road can contain very short segments at
-- junctions. Fitting a separate tangent fillet into EACH segment rejects even
-- a drivable bend. Connect longer sections with the existing radius-correct
-- planner and bound every pose to the actual recorded road corridor.
function AIVETransferTask.connectRoad(road,radius)
    if #road<2 then return road end
    local result={road[1]}
    local first=1
    local function deviation(p,last)
        local best=math.huge
        for i=first,math.max(first,last-1) do
            local a,b=road[i],road[math.min(#road,i+1)]
            local dx,dz=b.x-a.x,b.z-a.z
            local t=math.max(0,math.min(1,((p.x-a.x)*dx+(p.z-a.z)*dz)/math.max(1e-6,dx*dx+dz*dz)))
            best=math.min(best,(p.x-a.x-t*dx)^2+(p.z-a.z-t*dz)^2)
        end
        return best
    end
    while first<#road do
        local last,walked=first,0
        while last<#road and walked<math.max(16,3*radius) do
            walked=walked+distance(road[last],road[last+1]);last=last+1
        end
        local best,cost
        for _,candidate in ipairs(AIVELands.connectors(road[first],road[last],radius)) do
            if candidate.length<=walked+2*radius+6 then
                local score,valid=candidate.length,true
                for _,p in ipairs(candidate) do
                    local d=deviation(p,last)
                    if d>9 then valid=false;break end
                    score=score+d*0.05
                end
                if valid and (not cost or score<cost) then best,cost=candidate,score end
            end
        end
        if not best then return nil end
        for i=2,#best do result[#result+1]=best[i] end
        first=last
    end
    return result
end

function AIVETransferTask.new(isServer,job,entry)
    local self=AITaskDriveTo.new(isServer,job,mt)
    self.isEntry=entry
    return self
end
function AIVETransferTask:reset()
    AITaskDriveTo.reset(self)
    self.localDriving=nil;self.path=nil;self.sensor=nil;self.candidates=nil;self.plan=nil
end
function AIVETransferTask:start()
    self.localDriving=not self.isEntry and self.job:usesRoadGraph()
    self.aiveRoadTransfer=not self.isEntry
    if self.isServer and self.aiveRoadTransfer then
        self.maxSpeed=AIVETransferTask.getTravelSpeed(self.vehicle)
        if type(self.vehicle.getCruiseControlSpeed)=="function" and type(self.vehicle.setCruiseControlMaxSpeed)=="function" then
            self.savedCruiseSpeed=self.vehicle:getCruiseControlSpeed()
            self.vehicle:setCruiseControlMaxSpeed(self.maxSpeed)
        end
    end
    if self.isEntry then
        -- GIANTS aligns the vehicle using its real steering/agent model,
        -- then AITaskDriveTo performs a slow straight final approach. This
        -- also supports rear steering and MoreRealistic without orbiting a
        -- sub-metre goal under our road pure-pursuit controller.
        self.offset=8;self.maxSpeed=2
    end
    self.path=nil;self.plan=nil;self.sensor=nil;self.candidates=nil;self.planTime=0;self.holdTime=0
    AITaskDriveTo.start(self)
end
function AIVETransferTask:fail(noRoute)
	AIVELogger.info("MapJob","%s: stopping transfer; reason=%s; stage=%s; source=%s",self.vehicle:getName(),noRoute and "no drivable road route" or "blocked physical approach",tostring(self.state),tostring(self.roadSource or "field alignment"))
    self.vehicle:stopCurrentAIJob(noRoute and AIMessageErrorNotReachable.new() or AIMessageErrorBlockedByObject.new())
end
function AIVETransferTask:startDriving()
    if not self.localDriving then return AITaskDriveTo.startDriving(self) end
    self.sensor=AIVEObstacles.new(self.vehicle,{})
    AIVEObstacles.controllers[self.vehicle]=nil -- separate transport sensor, no worker ownership
    self.sensor.refNode=self.vehicle.rootNode
    self.sensor:dimensions()
    local p=self.sensor:pose()
    self.destination={x=self.x,y=getTerrainHeightAtWorldPos(g_terrainNode or g_currentMission.terrainRootNode,self.x,0,self.z),z=self.z,h=atan2(self.dirZ,self.dirX)}
    local road
    if not self.isEntry then
        local mode=self.job.options and self.job.options.travelMode:getValue() or 1
        if mode~=4 then
            road=AIVETransferTask.roadPath(p,self.destination)
            if road then road=AIVETransferTask.roundRoad(road,self.sensor.radius) or AIVETransferTask.connectRoad(road,self.sensor.radius) end
            self.roadSource="AutoDrive road graph"
        end
        if not road and mode~=3 then
            local graph=AIVETransferTask.getMapGraph()
            if graph then road=AIVETransferTask.roadPath(p,self.destination,graph,{width=2*self.sensor.half,height=self.sensor.height,radius=self.sensor.radius}) end
            local rawCount=road and #road or 0
            if road then road=AIVETransferTask.roundRoad(road,self.sensor.radius,1.5) or AIVETransferTask.connectRoad(road,self.sensor.radius) end
            AIVELogger.info("MapJob","Map road search: splines=%d; graph=%d; directed path=%d; rounded path=%d; rig width=%.2f radius=%.2f; from=%.2f %.2f to=%.2f %.2f",#(g_currentMission.aiSystem.roadSplines or {}),graph and #graph.points or 0,rawCount,road and #road or 0,2*self.sensor.half,self.sensor.radius,p.x,p.z,self.x,self.z)
            self.roadSource="map road splines (AIVE full-footprint driving)"
        end
        if not road then
            if mode==1 and g_currentMission.aiSystem:getIsPositionReachable(self.x,0,self.z) then
                self.localDriving=false;self.sensor=nil
                AIVELogger.info("MapJob","No usable AutoDrive connection; trying GIANTS roads.")
                return AITaskDriveTo.startDriving(self)
            end
            self:fail(true);return
        end
    end
    self.road=road
    local goal=road and road[1] or self.destination
    if road and #road>1 and distance(p,goal)<12 then
        -- A rolling vehicle at a junction need not first park on the nearest
        -- sampled lane point. Aim far enough along that lane to finish its
        -- existing turn, otherwise Dubins proposes an unnecessary full circle.
        local index,walked=1,0
        while index<#road and walked<math.max(8,2*self.sensor.radius) do
            walked=walked+distance(road[index],road[index+1]);index=index+1
        end
        local remaining={}
        for i=index,#road do remaining[#remaining+1]=road[i] end
        self.road=remaining;goal=remaining[1]
    end
    self.candidates=AIVELands.connectors(p,goal,self.sensor.radius)
    if road and distance(p,goal)<2 and math.abs(wrap(p.h-goal.h))<0.15 then
        -- Already on the selected lane: join its rolling look-ahead rather
        -- than circling 40 m to remove a few centimetres of sampling error.
        self.candidates={{p,goal,length=distance(p,goal)}}
    end
    table.sort(self.candidates,function(a,b)return a.length<b.length end)
    self.plan={index=1,point=1,stage="start",origin=p,goal=goal}
    self.state="aivePlanning"
    self:hold()
    AIVELogger.info("MapJob","%s: %s; target root %.2f %.2f; road nodes=%d",self.vehicle:getName(),self.isEntry and "aligning cutter at front/side edge" or self.roadSource,self.x,self.z,road and #road or 0)
end
function AIVETransferTask:hold()
    local p=self.sensor:pose()
    self.vehicle:setAITarget(self,p.x,getTerrainHeightAtWorldPos(g_terrainNode or g_currentMission.terrainRootNode,p.x,0,p.z),p.z,0,0,1,0,true)
end

-- A recorded road centreline is not a swept route for a 9 m header. Plan a
-- small, physically checked diversion around static roadside objects before
-- the header is too close to steer. Moving helpers and people always wait.
function AIVETransferTask:beginRoadBypass(p,hit,index)
    local old=self.path
    local last,walked=index,0
    while last<#old and walked<math.max(24,4*self.sensor.radius) do
        walked=walked+distance(old[last],old[last+1]);last=last+1
    end
    local goal=old[last]
    local candidates={}
    local function add(path,offset)
        if path.length>walked+4*self.sensor.radius+10 then return end
        local cost=path.length+4*math.abs(offset or 0)
        for _,q in ipairs(path) do
            local best=math.huge
            for i=math.max(1,index-3),math.max(index,last-1) do
                local a,b=old[i],old[math.min(#old,i+1)]
                local dx,dz=b.x-a.x,b.z-a.z
                local t=math.max(0,math.min(1,((q.x-a.x)*dx+(q.z-a.z)*dz)/math.max(1e-6,dx*dx+dz*dz)))
                best=math.min(best,(q.x-a.x-t*dx)^2+(q.z-a.z-t*dz)^2)
            end
            if best>49 then return end
            cost=cost+best*0.02
        end
        path.cost=cost;candidates[#candidates+1]=path
    end
    for _,a in ipairs(AIVELands.connectors(p,goal,self.sensor.radius)) do add(a,0) end
    local fx,fz=math.cos(p.h),math.sin(p.h)
    local along=math.max(5,math.min(walked*0.65,(hit.distance or 0)+self.sensor.front+1))
    for _,offset in ipairs({0.5,1,1.5,2,3,4,6}) do for _,side in ipairs({-1,1}) do
        local via={x=p.x+fx*along-fz*offset*side,z=p.z+fz*along+fx*offset*side,h=p.h}
        for _,a in ipairs(AIVELands.connectors(p,via,self.sensor.radius)) do
            for _,b in ipairs(AIVELands.connectors(via,goal,self.sensor.radius)) do
                local path={length=a.length+b.length}
                for _,q in ipairs(a) do path[#path+1]=q end
                for i=2,#b do path[#path+1]=b[i] end
                add(path,offset)
            end
        end
    end end
    table.sort(candidates,function(a,b)return a.cost<b.cost end)
    self.candidates=candidates
    self.plan={index=1,point=1,stage="road bypass",origin=p,goal=goal,oldPath=old,resume=last}
    self.planTime=0;self.state="aivePlanning"
    AIVELogger.info("MapJob","Checking roadside bypass: %s; candidates=%d; rejoin=%d",self.sensor:describeHit(hit),#candidates,last)
end
function AIVETransferTask:checkPlan()
    local state=self.plan
    for _=1,64 do
        local candidate=self.candidates[state.index]
        if not candidate then
            AIVELogger.info("MapJob","Local approach rejected: section=%s; candidates=%d; hit=%s",state.stage,#self.candidates,state.hit and self.sensor:describeHit(state.hit) or "all curves exceed local length limit")
            self:fail();return
        end
        if candidate.length>distance(state.origin,state.goal)+math.max(4*self.sensor.radius+10,2*math.pi*self.sensor.radius+20) then
            state.index=state.index+1;state.point=1
        else
            local p=candidate[state.point]
            -- The connector library samples at <=0.8 m. Check the swept space
            -- between those samples too, including rotating header corners.
            local previous=candidate[math.max(1,state.point-1)]
            local steps=math.max(1,math.ceil(distance(previous,p)/0.2),math.ceil(math.abs(wrap(p.h-previous.h))*self.sensor.half/0.1))
            local blocked=false
            for i=0,steps do
                local t=i/steps
                local hit=self.sensor:box({x=previous.x+(p.x-previous.x)*t,z=previous.z+(p.z-previous.z)*t,h=previous.h+wrap(p.h-previous.h)*t},false)
                if hit then state.hit=hit;blocked=true;break end
            end
            if blocked then state.index=state.index+1;state.point=1
            else
                state.point=state.point+1
                if state.point>#candidate then
                    AIVELogger.info("MapJob","Local approach accepted: section=%s; length=%.1f m",state.stage,candidate.length)
                    if state.stage=="road bypass" then
                        self.path=candidate
                        for i=state.resume+1,#state.oldPath do self.path[#self.path+1]=state.oldPath[i] end
                    elseif state.stage=="start" and self.road then
                        self.path=candidate
                        for i=2,#self.road do self.path[#self.path+1]=self.road[i] end
                        local last=self.road[#self.road]
                        -- The map point selects the FIELD, not a mandatory
                        -- parking pose. The following entry task already owns
                        -- cutter alignment. Forcing the road task to turn at
                        -- the roadside pin caused an extra, often impossible
                        -- U-turn before that field approach even started.
                        self.destination=last
                        AIVELogger.info("MapJob","Road handoff %.1f m from selected point; field entry owns final alignment",distance(last,{x=self.x,z=self.z}))
                    elseif self.path then
                        for i=2,#candidate do self.path[#self.path+1]=candidate[i] end
                    else self.path=candidate
                    end
                    self.plan=nil;self.candidates=nil;self.pathIndex=1;self.state="aiveDriving"
                    self.vehicle:setAITarget(self,self.x,getTerrainHeightAtWorldPos(g_terrainNode or g_currentMission.terrainRootNode,self.x,0,self.z),self.z,self.dirX,0,self.dirZ,0,true)
                    return
                end
            end
        end
    end
end
function AIVETransferTask:onTargetReached()
    if not self.localDriving then return AITaskDriveTo.onTargetReached(self) end
    -- AIDrivable calls this when it reaches a temporary look-ahead target.
    -- Completion is decided from the saved final pose, never a steering point.
end
function AIVETransferTask:update(dt)
    if not self.isServer then return end
    if not self.localDriving or self.state==AITaskDriveTo.STATE_PREPARE_DRIVING then return AITaskDriveTo.update(self,dt) end
    self.planTime=self.planTime+dt
    if self.state=="aiveBrakingForBypass" then
        local speed=type(self.vehicle.getLastSpeed)=="function" and self.vehicle:getLastSpeed() or math.abs(self.vehicle.lastSpeedReal or 0)*3600
        if speed<0.5 then
            self.sensor:dimensions()
            local p=self.sensor:pose()
            local hit=self.sensor:scanPath(p,self.path,self.bypassIndex,20)
            if hit and not hit.sensorFailed and not AIVEObstacles.mustWait(hit) then self:beginRoadBypass(p,hit,self.bypassIndex)
            else self.state="aiveDriving";self.holdTime=0 end
        end
        return
    end
    if self.state=="aivePlanning" then
        if self.planTime>120000 then self:fail();return end
        self:checkPlan();return
    end
    if self.state~="aiveDriving" then return end
    self.sensor:dimensions()
    local p=self.sensor:pose()
    local best,nearest=math.huge,self.pathIndex
    -- Dense local connectors and sparse recorded road waypoints share the
    -- follower. Search forwards only; never jump to a nearby returning lane.
    for i=self.pathIndex,math.min(#self.path,self.pathIndex+12) do
        local d=distance(p,self.path[i])
        if d<best then best,nearest=d,i end
    end
    self.pathIndex=nearest
    local remaining=distance(p,self.destination)
    if nearest>=#self.path-2 and remaining<0.35 and math.abs(wrap(p.h-self.destination.h))<0.12 then
        self.vehicle.spec_aiDrivable.maxSpeed=0;self.isFinished=true;return
    end
    local index=nearest
    local look=self.isEntry and 2 or math.max(4,math.min(12,AIVETransferTask.getCurrentSpeed(self.vehicle)/3.6*0.7))
    while index<#self.path and distance(p,self.path[index])<look do index=index+1 end
    local target=self.path[index]
    if index==#self.path then
        -- Roll onto the exact pose without pure-pursuit circling at its centre.
        target={x=self.destination.x+3*math.cos(self.destination.h),z=self.destination.z+3*math.sin(self.destination.h)}
        local along=(p.x-self.destination.x)*math.cos(self.destination.h)+(p.z-self.destination.z)*math.sin(self.destination.h)
        local side=math.abs(-(p.x-self.destination.x)*math.sin(self.destination.h)+(p.z-self.destination.z)*math.cos(self.destination.h))
        if along>=-0.15 and along<=0.5 and side<0.3 and math.abs(wrap(p.h-self.destination.h))<0.1 then
            self.vehicle.spec_aiDrivable.maxSpeed=0;self.isFinished=true;return
        end
    end
    local maxSpeed
    if self.isEntry then maxSpeed=4 else maxSpeed=self:getRoadSpeed(p,nearest,target) end
    if remaining<6 then maxSpeed=math.min(maxSpeed,2) end
    -- Validate what the steering can actually sweep now, including the entire
    -- header and people. A narrow graph line never overrides physical space.
    local currentSpeed=AIVETransferTask.getCurrentSpeed(self.vehicle)/3.6
    local preview=self.isEntry and 3 or math.max(14,2*self.sensor.radius+3,currentSpeed*currentSpeed/(2*AIVETransferTask.BRAKE_ACCELERATION)+4)
    local hit=self.sensor:scanPath(p,self.path,nearest,preview) or self.sensor:scan(p,target,true,3)
    if hit and not self.isEntry and not hit.sensorFailed and not AIVEObstacles.mustWait(hit) then
        self.bypassIndex=nearest;self.state="aiveBrakingForBypass";self:hold();return
    end
    if hit or best>math.max(3,look+1) then
        if hit and self.holdNode~=hit.node then
            self.holdNode=hit.node
            AIVELogger.info("MapJob","Transfer holding: %s; road point=%d; support offset=%.2f",self.sensor:describeHit(hit),nearest,self.sensor.groundOffset or 0)
        end
        maxSpeed=0;self.holdTime=self.holdTime+dt
        if self.holdTime>45000 then self:fail();return end
    else self.holdTime=0;self.holdNode=nil end
    local spec=self.vehicle.spec_aiDrivable
    spec.targetX,spec.targetZ=target.x,target.z
    spec.targetY=getTerrainHeightAtWorldPos(g_terrainNode or g_currentMission.terrainRootNode,target.x,0,target.z)
    spec.maxSpeed=maxSpeed
end
function AIVETransferTask:stop(wasJobStopped)
    AITaskDriveTo.stop(self,wasJobStopped)
    if self.savedCruiseSpeed~=nil and type(self.vehicle.setCruiseControlMaxSpeed)=="function" then
        self.vehicle:setCruiseControlMaxSpeed(self.savedCruiseSpeed)
    end
    self.savedCruiseSpeed=nil;self.aiveRoadTransfer=nil
    self.sensor=nil;self.path=nil;self.plan=nil;self.road=nil;self.candidates=nil
end

-- The GIANTS-road option uses the native agent instead of our path follower.
-- Keep its own slower safety limits, and apply the same turn cap only while
-- it belongs to this AIVE transport task. Other helpers are unaffected.
function AIVETransferTask.driveAlongCurvature(vehicle,superFunc,dt,curvature,maxSpeed,acceleration)
    local task=(vehicle.spec_aiDrivable or {}).task
    if task and task.aiveRoadTransfer and math.abs(curvature or 0)>=AIVETransferTask.TURN_CURVATURE then
        maxSpeed=math.min(maxSpeed or math.huge,AIVETransferTask.TURN_SPEED)
    end
    return superFunc(vehicle,dt,curvature,maxSpeed,acceleration)
end
if AIVehicleUtil and AIVehicleUtil.driveAlongCurvature then
    AIVehicleUtil.driveAlongCurvature=Utils.overwrittenFunction(AIVehicleUtil.driveAlongCurvature,AIVETransferTask.driveAlongCurvature)
end
