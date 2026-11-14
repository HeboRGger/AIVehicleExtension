-- Bounded local forward/reverse search. Headings describe the VEHICLE body,
-- including on reverse arcs; the full raised rig is swept at every substep.
AIVEManeuver={}
AIVEManeuver.__index=AIVEManeuver
local pi2=2*math.pi
local function wrap(a)return (a+math.pi)%pi2-math.pi end
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)end
local function push(heap,item)
 local i=#heap+1
 while i>1 do
  local parent=math.floor(i/2)
  if heap[parent].f<=item.f then break end
  heap[i]=heap[parent];i=parent
 end
 heap[i]=item
end
local function pop(heap)
 local first=heap[1];local last=table.remove(heap)
 if #heap>0 then
  local i=1
  while i*2<=#heap do
   local j=i*2
   if j<#heap and heap[j+1].f<heap[j].f then j=j+1 end
   if heap[j].f>=last.f then break end
   heap[i]=heap[j];i=j
  end
  heap[i]=last
 end
 return first
end
local function key(p)
 return math.floor(p.x/.6+.5)..":"..math.floor(p.z/.6+.5)..":"
  ..(math.floor((wrap(p.h)+math.pi)/math.rad(10)+.5)%36)..":"..(p.forward and"F"or"R")
end
function AIVEManeuver.new(controller,start,goals)
 local self=setmetatable({controller=controller,start={x=start.x,z=start.z,h=start.h},goals={},heap={},best={},expanded=0,created=1,limit=6000,budget=8,range=35,step=1.2},AIVEManeuver)
 self.radius=math.max(3.5,controller.radius or 6)
 for _,g in ipairs(goals or{})do
  if finite(g.x)and finite(g.z)and finite(g.h)and distance(start,g)<=self.range-1 then
   self.goals[#self.goals+1]=g
  end
 end
 if #self.goals==0 then self.failure="no local recovery goal";return self end
 local n={x=start.x,z=start.z,h=start.h,forward=true,g=0}
 n.key=key(n);n.f=self:heuristic(n);self.best[n.key]=n;push(self.heap,n)
 return self
end
function AIVEManeuver:heuristic(p)
 local result=math.huge
 for _,g in ipairs(self.goals)do
  result=math.min(result,distance(p,g)+self.radius*math.abs(wrap(p.h-g.h))+(g.penalty or 0))
 end
 return result
end
function AIVEManeuver:goalAt(p)
 for _,g in ipairs(self.goals)do
  if distance(p,g)<=.85 and math.abs(wrap(p.h-g.h))<=math.rad(12)then return g end
 end
end
-- Exact constant-curvature integration; intermediate poses are deliberately
-- retained so a thin pole cannot be skipped by either search or following.
function AIVEManeuver:primitive(p,forward,curvature)
 local q={x=p.x,z=p.z,h=p.h,forward=forward}
 local points={}
 local count=math.ceil(self.step/.25)
 local ds=self.step/count*(forward and 1 or -1)
 for i=1,count do
  local h=q.h+curvature*ds
  if math.abs(curvature)>1e-8 then
   q={x=q.x+(math.sin(h)-math.sin(q.h))/curvature,
      z=q.z-(math.cos(h)-math.cos(q.h))/curvature,h=wrap(h),forward=forward}
  else q={x=q.x+ds*math.cos(q.h),z=q.z+ds*math.sin(q.h),h=q.h,forward=forward}end
  local fromStart=distance(q,self.start)
  local fraction=math.min(1,fromStart/2)
  local reserve=(self.startReserve or 0)*(1-fraction)+(self.controller.precisionCombine and .12 or .15)*fraction
  if fromStart>self.range or self.controller:box(q,false,nil,nil,reserve)then return nil end
  points[#points+1]=q
 end
 return q,points
end
function AIVEManeuver:reconstruct(last,goal)
 local chain={}
 while last.parent do chain[#chain+1]=last;last=last.parent end
 local path={{x=self.start.x,z=self.start.z,h=self.start.h,forward=true}}
 local length=0
 for i=#chain,1,-1 do
  for _,q in ipairs(chain[i].points)do
   length=length+distance(path[#path],q);path[#path+1]=q
  end
 end
 path.length=length;path.goal={x=path[#path].x,z=path[#path].z,h=path[#path].h}
 path.escape=goal.escape==true;path.manoeuvre=true;path.recoveryGoal=goal;path.initialReserve=self.startReserve
 return path
end
-- Returns path, failure, pending. No unbounded work is performed in one tick.
function AIVEManeuver:update()
 if self.path then return self.path,nil,false end
 if self.failure then return nil,self.failure,false end
 if not self.started then
  self.started=true
  if self.controller:box(self.start,false)then
   -- A rigid combine already closer than the usual 10cm margin may move
   -- AWAY from contact. The real full hull plus 2cm must still be clear;
   -- restore the entire normal tracking margin over the first two metres.
   if self.controller.precisionCombine and not self.controller:box(self.start,false,nil,nil,-.08)then self.startReserve=-.08
   else self.failure="initial full-rig footprint occupied";return nil,self.failure,false end
  end
 end
 local pops=0
 while pops<self.budget and #self.heap>0 and self.expanded<self.limit do
  local n=pop(self.heap);pops=pops+1
  if self.best[n.key]==n then
   self.expanded=self.expanded+1
   local goal=self:goalAt(n)
   if goal then self.path=self:reconstruct(n,goal);return self.path,nil,false end
   for _,forward in ipairs({true,false})do
    for _,steering in ipairs({0,-1,1})do
     local q,points=self:primitive(n,forward,steering/self.radius)
     if q then
      local cost=n.g+self.step*(forward and 1 or 1.25)+(forward~=n.forward and 2.5 or 0)+(steering~=0 and .08 or 0)
      local k=key(q);local old=self.best[k]
      if not old or cost<old.g-1e-6 then
       q.g=cost;q.key=k;q.parent=n;q.points=points;q.f=cost+self:heuristic(q)
       self.best[k]=q;push(self.heap,q);self.created=self.created+1
      end
     end
    end
   end
  end
 end
 if #self.heap==0 or self.expanded>=self.limit then
  self.failure=#self.heap==0 and"local free space exhausted"or"local search budget exhausted"
  return nil,self.failure,false
 end
 return nil,nil,true
end
