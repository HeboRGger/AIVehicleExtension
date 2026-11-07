-- Server-owned field sessions. Native work queries remain the source of truth.
-- Snapshots are immutable after publication; leases are geometric (mixed widths).
AIVEFieldDispatcher={sessions={},mission=nil,nextId=1,maxWorkers=4}
local D=AIVEFieldDispatcher
local function now() return g_currentMission and g_currentMission.time or 0 end
local function overlap(a,b)
    return a.u0<b.u1-0.05 and b.u0<a.u1-0.05 and a.v0<b.v1-0.05 and b.v0<a.v1-0.05
end
local function farm(v)
    local job=(v.spec_aiJobVehicle or {}).job
    if job and job.startedFarmId~=nil then return job.startedFarmId end
    return type(v.getOwnerFarmId)=="function" and v:getOwnerFarmId() or v.ownerFarmId or 0
end
function D.enabled(v)
    local p=v.acParameters or {}
    return p.fieldGroup==true and p.circleLands==true and not p.inverted
end
function D.operation(v)
    local kinds,seeds={},{}
    for _,t in pairs((v.aiveChain or {}).tools or {}) do
        local o=t.obj or {}
        for _,key in ipairs({"isCombine","isMower","isCultivator","isPlough","isSprayer","isSowingMachine","isRoller"}) do
            if t[key] then kinds[key]=true end
        end
        local s=o.spec_sowingMachine
        if s then
            local f=(s.workAreaParameters or {}).seedsFruitType or (s.seeds or {})[s.currentSeed or 1]
            seeds[tostring(f or "unknown")]=true;kinds.isSowingMachine=true
        end
        if o.spec_sprayer and not (v.acParameters or {}).noSprayer then
            seeds["spray="..tostring((o.spec_sprayer.workAreaParameters or {}).sprayFillType or "unknown")]=true
        end
    end
    if v.spec_combine then kinds.isCombine=true end
    local result={}
    for k in pairs(kinds) do result[#result+1]=k end
    for k in pairs(seeds) do result[#result+1]=k end
    table.sort(result)
    return table.concat(result,",")..";fert="..tostring((v.acParameters or {}).noSprayer==true)
end
function D.reset()
    D.sessions={};D.nextId=1;D.mission=g_currentMission;D.frameTime=nil;D.frameIndex=0;D.planTime=nil
end
function D.findField(v)
    if D.mission~=g_currentMission then return nil end
    local chain=v.aiveChain or {}
    local x,_,z=getWorldTranslation(chain.refNode or v.rootNode)
    local operation=D.operation(v)
    for _,s in ipairs(D.sessions) do
        if s.owner==farm(v) and s.operation==operation then
            -- An entry may put only one side of a wide cutter on the crop.
            -- Reuse the already discovered connected mask at the root/edge;
            -- do not require all workers to rediscover it from its boundary.
            if s.field.getBit(x,z) then return s.field end
            local fx,_,fz=localDirectionToWorld(chain.refNode or v.rootNode,0,0,1)
            for _,side in ipairs({-1,1}) do
                local width=math.max(1,(v.acDimensions or {}).distance or 2)
                if s.field.getBit(x-fz*width*side+fx*2,z+fx*width*side+fz*2) then return s.field end
            end
        end
    end
end
function D.join(lands,field)
    if D.mission~=g_currentMission then D.reset() end
    local v=lands.vehicle
    if not D.enabled(v) or not field or type(field.getBounds)~="function" then return nil end
    local x0,z0,x1,z1=field.getBounds()
    if not x0 then return nil end
    local op=D.operation(v);local owner=farm(v);local s
    for _,q in ipairs(D.sessions) do
        if q.owner==owner and q.operation==op and math.abs(q.x0-x0)<2 and math.abs(q.z0-z0)<2
            and math.abs(q.x1-x1)<2 and math.abs(q.z1-z1)<2 then s=q;break end
    end
    if not s then
        s={id=D.nextId,owner=owner,operation=op,field=field,x0=x0,z0=z0,x1=x1,z1=z1,
            members={},count=0,leases={},turnQueue={},turnOwners={},turnPlans={},turnGeneration=0,generation=0,lastTick=-1,area=0,initialArea=0,dirty=false}
        D.nextId=D.nextId+1;D.sessions[#D.sessions+1]=s
        s.key=owner.."|"..op.."|"..string.format("%.0f,%.0f,%.0f,%.0f",x0,z0,x1,z1)
        s.leader=v
    end
    if not s.members[v] then
        if s.count>=D.maxWorkers then lands.error="field group is full (4 workers)";return nil end
        s.count=s.count+1;s.members[v]=lands
        AIVELogger.info("FieldGroup","'%s' joined field session %d (%d/4).",lands:name(),s.id,s.count)
    else s.members[v]=lands end
    lands.groupSession=s;lands.field=s.field
    -- Re-hire reconstructs reservations from live work rather than reviving a
    -- lease another worker may have acquired while this vehicle was dismissed.
    lands.active=false;lands.path=nil;lands.groupLease=nil;lands.phase="perimeter"
    lands.snapshot=nil;lands.scan=nil;lands.groupGeneration=nil
    lands.waitingHandover=false;lands.finishingPass=nil
    lands.groupRouteBlockedAt=nil;lands.nextGroupRouteCheck=nil;lands.blockedMotionGeneration=nil
    lands.nextPeerReplan=nil;lands.parking=nil;lands.groupLane=nil;lands.groupEntryReversed=nil;lands.nextParkCheck=nil
    if v.aiveSavedGroup and v.aiveSavedGroup.key==s.key then s.initialArea=math.max(s.initialArea,v.aiveSavedGroup.area) end
    if not s.scanner then
        local scanner=AIVELands.new(v)
        scanner.dispatchScanner=true;scanner.field=s.field;scanner.axesChosen=false
        s.scanner=scanner
    end
    return s
end
function D.leave(lands)
    local s=lands and lands.groupSession
    if not s then return end
    local v=lands.vehicle
    D.releaseLane(lands)
    if s.members[v]==lands then s.members[v]=nil;s.count=math.max(0,s.count-1) end
    s.turnOwners[v]=nil;s.turnPlans[v]=nil;s.turnGeneration=s.turnGeneration+1
    for i=#s.turnQueue,1,-1 do if s.turnQueue[i]==v then table.remove(s.turnQueue,i) end end
    lands.groupSession=nil;v.aiveFieldGroupStatus=nil
    if AIVEFieldGroupEvent and g_server and not v.isDeleted and not v.isDeleting then
        g_server:broadcastEvent(AIVEFieldGroupEvent.new(v,{id=s.id,count=0,remaining=0,total=0,progress=0}),nil,nil,v)
    end
    if s.leader==v and s.count>0 then
        local replacement
        for candidate,l in pairs(s.members) do
            if not replacement or (candidate.rootNode or 0)<(replacement.rootNode or 0) then replacement=candidate end
        end
        s.leader=replacement
    end
    if s.count==0 then
        for i,q in ipairs(D.sessions) do if q==s then table.remove(D.sessions,i);break end end
    end
end
function D.perimeterProgress(lands)
    local s=lands.groupSession
    if not s then return end
    if lands.perimeterComplete then s.perimeterComplete=true end
    local snapshot=s.snapshot
    -- Every member retains the native contour follower. The whole group
    -- switches at the original measured 80 m core, never after a fixed lap.
    if not s.headlandReady and s.perimeterComplete and snapshot and snapshot.minU
        and math.min(snapshot.maxU-snapshot.minU,snapshot.maxV-snapshot.minV)<=AIVELands.switchWidth+AIVELands.scanStep then
        s.headlandReady=true;s.dirty=true
        AIVELogger.info("FieldGroup","Session %d: measured core ready; four circular workers may hand over at their pass ends.",s.id)
    end
end
function D.releaseLane(lands)
    local s=lands.groupSession
    if not s then return end
    if s.leases[lands.vehicle] then s.leases[lands.vehicle]=nil;s.dirty=true end
    s.turnOwners[lands.vehicle]=nil;s.turnPlans[lands.vehicle]=nil;s.turnGeneration=s.turnGeneration+1
    for i=#s.turnQueue,1,-1 do if s.turnQueue[i]==lands.vehicle then table.remove(s.turnQueue,i) end end
    lands.groupLease=nil
end
function D.claim(lands,lane)
    local s=lands.groupSession
    if not s then return true end
    local rect={u0=lane.u0,u1=lane.u1,v0=lane.v-lane.spacing/2,v1=lane.v+lane.spacing/2}
    for v,r in pairs(s.leases) do if v~=lands.vehicle and overlap(rect,r) then return false end end
    s.leases[lands.vehicle]=rect;lands.groupLease=rect
    return true
end
local function intersects(a,b)
    if a.count>b.count then a,b=b,a end
    for k in pairs(a.cells) do if b.cells[k] then return true end end
    return false
end
function D.planTurn()
    local time=now()
    if D.planTime==time then return false end
    D.planTime=time;return true
end
local function footprint(lands)
    local v=lands.vehicle
    local sensor=v.aiveObstacleController
    if sensor and type(sensor.dimensions)=="function" then sensor:dimensions() end
    local half=math.max((lands.width or 2*((v.acDimensions or {}).distance or 3))/2,sensor and sensor.half or 0)+0.75
    local front=math.max(1,sensor and sensor.front or ((v.size or {}).length or 8)/2)+0.75
    local back=math.max(1,sensor and sensor.back or ((v.size or {}).length or 8)/2)+0.75
    return {half=half,length=(front+back)/2,offset=(front-back)/2}
end
function D.connectorObstacles(lands)
    local s=lands.groupSession
    if not s then return nil end
    local result={own=footprint(lands),origin=lands:pose()}
    for v,other in pairs(s.members) do
        if v~=lands.vehicle and not v.isDeleted and not v.isDeleting then
            local p=other:pose();local box=footprint(other)
            box.fx,box.fz=math.cos(p.h),math.sin(p.h)
            box.x,box.z=p.x+box.fx*box.offset,p.z+box.fz*box.offset
            result[#result+1]=box
        end
    end
    return result
end
function D.pathIsBlocked(p,obstacles)
    if not obstacles then return false,0 end
    local a=obstacles.own;local fx,fz=math.cos(p.h),math.sin(p.h)
    local x,z=p.x+fx*a.offset,p.z+fz*a.offset
    local mask,bit=0,1
    for _,b in ipairs(obstacles) do
        local dx,dz=b.x-x,b.z-z
        local c,s=math.abs(fx*b.fx+fz*b.fz),math.abs(-fz*b.fx+fx*b.fz)
        -- Separating axes of both oriented full-rig rectangles. Extra padding
        -- covers the 2.4 m sampling interval without extra physics queries.
        if math.abs(dx*fx+dz*fz)<a.length+b.length*c+b.half*s
            and math.abs(-dx*fz+dz*fx)<a.half+b.length*s+b.half*c
            and math.abs(dx*b.fx+dz*b.fz)<b.length+a.length*c+a.half*s
            and math.abs(-dx*b.fz+dz*b.fx)<b.half+a.length*s+a.half*c then mask=mask+bit end
        bit=bit*2
    end
    return mask~=0,mask
end
function D.requestTurn(lands)
    local s=lands.groupSession
    if not s then return true end
    local v=lands.vehicle
    if s.turnOwners[v] then return true end
    local plan=s.turnPlans[v]
    if not plan or plan.path~=lands.path then
        if not lands.path then return false end
        plan={path=lands.path,cells={},count=0};s.turnPlans[v]=plan
        local sensor=v.aiveObstacleController or {}
        if type(sensor.dimensions)=="function" then sensor:dimensions() end
        local reach=math.max((lands.width or 6)/2,(v.size or {}).length and v.size.length/2 or 4,sensor.half or 0,sensor.front or 0,sensor.back or 0)+1.5
        for i=1,#lands.path,3 do
            local p=lands.path[i]
            for x=math.floor((p.x-reach)/4),math.floor((p.x+reach)/4) do
                for z=math.floor((p.z-reach)/4),math.floor((p.z+reach)/4) do
                    local key=x..":"..z
                    if not plan.cells[key] then plan.cells[key]=true;plan.count=plan.count+1 end
                end
            end
        end
    end
    if plan.checked==s.turnGeneration then return false end
    plan.checked=s.turnGeneration
    local queued=false
    for _,q in ipairs(s.turnQueue) do if q==v then queued=true;break end end
    if not queued then s.turnQueue[#s.turnQueue+1]=v end
    for owner,other in pairs(s.turnOwners) do if owner~=v and intersects(plan,other) then return false end end
    for i,q in ipairs(s.turnQueue) do
        if q==v then
            s.turnOwners[v]=plan;table.remove(s.turnQueue,i);s.turnGeneration=s.turnGeneration+1;return true
        end
        local other=s.turnPlans[q]
        if s.members[q] and other and intersects(plan,other) then return false end
    end
    return false
end
function D.finishTurn(lands)
    local s=lands.groupSession
    if s then
        s.turnOwners[lands.vehicle]=nil;s.turnPlans[lands.vehicle]=nil;s.turnGeneration=s.turnGeneration+1
    end
end
function D.tick(lands,dt)
    local s=lands.groupSession
    if not s then return end
    local time=now()
    if s.lastTick==time then return end
    s.lastTick=time
    local inactive={}
    local moving=false
    for v,l in pairs(s.members) do
        if v.isDeleted or v.isDeleting or v.aiveIsStarted==false then inactive[#inactive+1]=l
        elseif math.abs(v.lastSpeed or 0)>0.5/3600 then moving=true end
    end
    if moving then s.motionGeneration=(s.motionGeneration or 0)+1 end
    for _,l in ipairs(inactive) do D.leave(l) end
    local scanner=s.scanner
    -- Use a live compatible implement. Never query deleted/unloaded equipment.
    local source
    for v,l in pairs(s.members) do
        if v.aiveIsStarted and not v.isDeleted and not v.isDeleting then source=v;break end
    end
    if not source then return end
    scanner.vehicle=source
    if s.dirty and not scanner.scan then scanner.nextScan=0;s.dirty=false end
    -- One scanner's budget for ALL field sessions, not one budget per vehicle.
    if D.frameTime~=time then
        D.frameTime=time;D.frameIndex=(D.frameIndex or 0)+1
        D.scanSession=D.sessions[(D.frameIndex-1)%math.max(1,#D.sessions)+1]
    end
    if D.scanSession==s then scanner:observe(dt) end
    if scanner.snapshot and scanner.snapshot~=s.snapshot then
        s.snapshot=scanner.snapshot;s.generation=s.generation+1
        s.ox,s.oz,s.dx,s.dz=scanner.ox,scanner.oz,scanner.dx,scanner.dz
        s.area=s.snapshot.workArea or #s.snapshot.cells*s.snapshot.step*s.snapshot.step
        s.initialArea=math.max(s.initialArea,s.area)
        D.perimeterProgress(lands)
    end
    if time>=(s.nextStatus or 0) then
        s.nextStatus=time+2000
        local status={id=s.id,count=s.count,remaining=s.area,total=s.initialArea,
            progress=s.initialArea>0 and math.max(0,math.min(100,100*(1-s.area/s.initialArea))) or 0}
        for v in pairs(s.members) do
            v.aiveFieldGroupStatus=status
            v.aiveSavedGroup={key=s.key,area=s.initialArea}
            if AIVEFieldGroupEvent and g_server then g_server:broadcastEvent(AIVEFieldGroupEvent.new(v,status),nil,nil,v) end
        end
    end
end
function D.adopt(lands)
    local s=lands.groupSession
    if not s or not s.snapshot then return false end
    lands.ox,lands.oz,lands.dx,lands.dz=s.ox,s.oz,s.dx,s.dz
    lands.axesChosen=true;lands.snapshot=s.snapshot
    lands.groupGeneration=s.generation
    if not lands.perimeterCenter then
        local snap=s.snapshot
        if snap.minU then
            local x,z=lands:world((snap.minU+snap.maxU)/2,(snap.minV+snap.maxV)/2)
            lands.perimeterCenter={x=x,z=z}
            lands.minimumPerimeterDistance=0.65*2*(snap.maxU-snap.minU+snap.maxV-snap.minV)
        end
    end
    return true
end

-- Compact status uses the existing native job description; no new HUD layout.
AIVEFieldGroupEvent={}
local eventMt=Class(AIVEFieldGroupEvent,Event)
InitEventClass(AIVEFieldGroupEvent,"AIVEFieldGroupEvent")
function AIVEFieldGroupEvent.emptyNew() return Event.new(eventMt) end
function AIVEFieldGroupEvent.new(vehicle,status)
    local self=AIVEFieldGroupEvent.emptyNew();self.vehicle=vehicle;self.status=status;return self
end
function AIVEFieldGroupEvent:writeStream(id,connection)
    NetworkUtil.writeNodeObject(id,self.vehicle)
    streamWriteInt32(id,self.status.id);streamWriteUInt8(id,self.status.count)
    streamWriteFloat32(id,self.status.remaining);streamWriteFloat32(id,self.status.total)
    streamWriteFloat32(id,self.status.progress)
end
function AIVEFieldGroupEvent:readStream(id,connection)
    self.vehicle=NetworkUtil.readNodeObject(id)
    self.status={id=streamReadInt32(id),count=streamReadUInt8(id),remaining=streamReadFloat32(id),total=streamReadFloat32(id),progress=streamReadFloat32(id)}
    if connection:getIsServer() and self.vehicle then
        self.vehicle.aiveFieldGroupStatus=self.status.count>0 and self.status or nil
    end
end
