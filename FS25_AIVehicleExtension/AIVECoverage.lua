-- Small recovery debts, not a second field bitmap. Only real remaining work
-- from the native implement query can keep a debt alive. All scanning is sliced.
AIVECoverage={}
local C=AIVECoverage
local function point(p,u,w)
 local fx,fz=math.cos(p.h),math.sin(p.h)
 return {x=p.x+u*fx-w*fz,z=p.z+u*fz+w*fx,h=p.h}
end
function C.record(c,p,length)
 if not c.precisionCombine or c.savedLowered==false then return end
 local bar
 for _,part in ipairs(c.parts or{})do if part.label=='workbar' and(not bar or part.half>bar.half)then bar=part end end
 if not bar then return end
 c.coverageDebts=c.coverageDebts or{}
 local last=c.coverageDebts[#c.coverageDebts]
 if last and math.abs(last.p.h-p.h)<.1 and (last.p.x-p.x)^2+(last.p.z-p.z)^2<4 then
  last.length=math.max(last.length,length);return last
 end
 -- Never grow an unbounded history during repeated encounters at one corner.
 if #c.coverageDebts>=12 then return end
 local d={p={x=p.x,z=p.z,h=p.h},along=bar.along,side=bar.side,
  half=math.max(.5,bar.half-AIVEObstacles.CLEARANCE),length=math.min(35,math.max(4,length)),attempts=0}
 c.coverageDebts[#c.coverageDebts+1]=d
 return d
end
function C.begin(c)
 local lands=c.strategy.lands
 if lands and(lands.active or lands.waitingHandover or lands.finishingPass)then return false end
 local debts=c.coverageDebts
 if not debts or #debts==0 or not AIVEManeuver then return false end
 local p=c:pose()
 for _,d in ipairs(debts)do
  if (d.nextAt or 0)<=c.clock and (d.p.x-p.x)^2+(d.p.z-p.z)^2<32^2 then
   c.coverageScan={debt=d,u=-1,w=-d.half+.4,cells={}};c.phase='coverageScan'
   c.workCache={};return true
  end
 end
 return false
end
function C.defer(c,d,reason)
 d.attempts=d.attempts+1;d.nextAt=c.clock+math.min(60000,10000*d.attempts)
 c:log('remaining crop retained for a later approach: '..reason)
 c.coverageScan=nil;c.coverageTask=nil;c.workCache=nil
 c:release(false)
end
local function remove(c,d)
 for i,q in ipairs(c.coverageDebts or{})do if q==d then table.remove(c.coverageDebts,i);break end end
end
function C.update(c)
 local scan=c.coverageScan;local d=scan.debt
 if scan.options then
  for _=1,24 do
   local path=scan.options[scan.optionIndex]
   if not path then
    c.coverageScan=nil;c.workCache=nil
    if #scan.goals==0 then C.defer(c,d,'no safe working strip yet');return end
    local goals=#scan.continuingGoals>0 and scan.continuingGoals or scan.goals
    c.coverageTask=d;c:captureRoute(c:pose(),{node=0,distance=0},true)
    c.maneuverSearch=AIVEManeuver.new(c,c:pose(),goals);c.phase='maneuverPlanning'
    c:log(string.format('returning to remaining crop: %d cells, %d checked approaches',#scan.cells,#goals))
    return
   end
   local q=path[scan.checkIndex]
   if c:box(q,false,nil,nil,.04) then
    scan.optionIndex=scan.optionIndex+1;scan.checkIndex=1
   else
    scan.checkIndex=scan.checkIndex+1
    if scan.checkIndex>#path then
     local start=path[1];start.workPath=path;start.escape=false
     scan.goals[#scan.goals+1]=start
     local q=path.goal
     local ahead={x=q.x+3*math.cos(q.h),z=q.z+3*math.sin(q.h),h=q.h}
     if not c:frontSweep(q,3) and c:isWorkingPoseOnField(ahead) then scan.continuingGoals[#scan.continuingGoals+1]=start end
     scan.optionIndex=scan.optionIndex+1;scan.checkIndex=1
    end
   end
  end
  return
 end
 -- 24 native one-square-metre work queries per update, only during recovery.
 for _=1,24 do
  if scan.u>d.length then break end
  local p=point(d.p,d.along+scan.u,d.side+scan.w)
  if c:workAt(p.x,p.z)>0 then scan.cells[#scan.cells+1]=p end
  scan.w=scan.w+1
  if scan.w>d.half then scan.w=-d.half+.4;scan.u=scan.u+1 end
 end
 if scan.u<=d.length then return end
 if #scan.cells==0 then
  remove(c,d);c.coverageScan=nil;c.workCache=nil;c.phase='clear'
  c:log('recovery crop checked: no remaining work in the interrupted strip')
  return
 end
 local cells=scan.cells;local cx,cz=0,0
 d.remainingCells=#cells
 for _,p in ipairs(cells)do cx=cx+p.x;cz=cz+p.z end
 cx,cz=cx/#cells,cz/#cells
 local options={}
 for _,yaw in ipairs({0,math.pi,math.pi/2,-math.pi/2})do
  local h=d.p.h+yaw;local fx,fz=math.cos(h),math.sin(h)
  local lo,hi=math.huge,-math.huge
  for _,p in ipairs(cells)do
   -- Work one cutter-wide strip; further remnants stay in the debt.
   local side=-(p.x-cx)*fz+(p.z-cz)*fx
   if math.abs(side)<d.half-.1 then
    local u=(p.x-cx)*fx+(p.z-cz)*fz;lo=math.min(lo,u);hi=math.max(hi,u)
   end
  end
  if lo<math.huge then
   local origin={x=cx-d.along*fx+d.side*fz,z=cz-d.along*fz-d.side*fx,h=h}
   local path={working=true,length=hi-lo+2,offset=0,coverage=true}
   local count=math.ceil(path.length/.25)
   for i=0,count do
    local q=point(origin,lo-1+path.length*i/count,0)
    path[#path+1]=q
   end
   path.goal=path[#path];options[#options+1]=path
  end
 end
 scan.options=options;scan.optionIndex=1;scan.checkIndex=1;scan.goals={};scan.continuingGoals={}
end
function C.startWork(c,path)
 c.workingBypass=true;c.vehicle.aiveWorkingBypass=true
 c.vehicle:aiFieldWorkerEndTurn(true)
 AIVehicleExtension.setAIImplementsMoveDown(c.vehicle,true,true)
 c.savedLowered=true;c.savedTurning=true;c.savedStage=0
 c.maneuverPath=nil;c.path=path;c.pathIndex=1;c.goal=path.goal
 c.routeTarget=path.goal;c.routeForward=true;c.encounterPose=c:pose();c.blockedAt=c.clock
 c.progressIndex=1;c.progressAt=c.clock;c.nextProbe=0;c.lastHit=nil
 c.phase='detour';c:log('harvesting the interrupted strip with overlap')
end
function C.finished(c)
 local d=c.coverageTask
 if d then d.nextAt=c.clock+2000;d.attempts=d.attempts+1 end
 c.coverageTask=nil;c.nextCoverageAt=c.clock+2000
 -- A path ending is not evidence of harvested crop. C.update re-queries it.
end
