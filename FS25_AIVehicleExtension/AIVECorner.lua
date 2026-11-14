-- Harvest a tight corner in place: retreat on the cut strip, cut the wedge,
-- then follow the next edge. Reverse sections never carry a lowered cutter.
-- Templates are swept a few poses per update; no map coordinates are baked in.
AIVECorner={}
AIVECorner.__index=AIVECorner
local function copy(p)return{x=p.x,z=p.z,h=p.h,forward=p.forward,work=p.work}end
local function wrap(h)return(h+math.pi)%(2*math.pi)-math.pi end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2)end
local function append(path,forward,work,length,curvature)
 local p=path[#path];local count=math.max(1,math.ceil(length/.25));local ds=length/count*(forward and 1 or-1)
 for _=1,count do
  local h=p.h+curvature*ds;local q
  if math.abs(curvature)>1e-8 then
   q={x=p.x+(math.sin(h)-math.sin(p.h))/curvature,z=p.z-(math.cos(h)-math.cos(p.h))/curvature,h=wrap(h)}
  else q={x=p.x+ds*math.cos(p.h),z=p.z+ds*math.sin(p.h),h=p.h}end
  q.forward=forward;q.work=work;path[#path+1]=q;p=q
 end
end
function AIVECorner.new(c,p,hit)
 local self=setmetatable({controller=c,start=copy(p),radius=c.radius,budget=20,bases={},baseIndex=1,index=1,phase='base',options={},optionIndex=1},AIVECorner)
 self.sign=c.vehicle.acParameters.rightAreaActive and-1 or 1
 self.anchorHeading=(c.cornerAnchor or p).h
 -- A short path is not necessarily a useful turn. Retreat by about one
 -- turning radius before cutting the wedge; shorter templates are fallback
 -- options for a genuinely obstructed rear corridor.
 self.preferredRetreat=math.min(12,math.max(6,math.ceil(self.radius/2)*2))
 self.warning=math.min(4,math.max(1,(hit and hit.distance or 2)))
 self.targets={};self.targetKeys={};self.targetSamples={}
 local bar
 for _,part in ipairs(c.parts or{})do if part.label=='workbar'and(not bar or part.half>bar.half)then bar=part end end
 if bar then
  for u=0,math.min(6,math.ceil(self.warning+2))do
   for w=-math.floor(bar.half),math.floor(bar.half)do
    local a,b=bar.along+u,bar.side+w
    self.targetSamples[#self.targetSamples+1]={x=p.x+a*math.cos(p.h)-b*math.sin(p.h),z=p.z+a*math.sin(p.h)+b*math.cos(p.h)}
   end
  end
 end
 self.targetIndex=1;self.phase='targets'
 local retreats={}
 for _,retreat in ipairs({self.preferredRetreat,6,8,10,12,4,0})do
  if not retreats[retreat]then
  retreats[retreat]=true
  for _,angle in ipairs({0,20,30})do for _,lead in ipairs(angle==0 and {0}or {0,2,4})do
   local path={copy(p)};path[1].forward=false;path[1].work=false
   append(path,false,false,retreat,0)
   local first=#path+1;local a=math.rad(angle)
   if lead>0 then append(path,true,true,lead,0)end
   append(path,true,true,self.radius*a,self.sign/self.radius)
   append(path,true,true,math.max(2,retreat+self.warning+4-self.radius*a-lead),0)
   path.workFirst=first;path.retreat=retreat;path.preAngle=a
   self.bases[#self.bases+1]=path
  end end
  end
 end
 return self
end
function AIVECorner:cover(path,p)
 local fx,fz=math.cos(p.h),math.sin(p.h)
 for _,target in ipairs(self.targets)do
  if not path.covered[target]then
   for _,part in ipairs(self.controller.parts or{})do
    if part.label=='workbar'then
     local a=(target.x-p.x)*fx+(target.z-p.z)*fz-part.along
     local b=-(target.x-p.x)*fz+(target.z-p.z)*fx-part.side
     if math.abs(a)<math.max(.3,part.length-.1)and math.abs(b)<part.half-.35 then
      path.covered[target]=true;path.coverage=path.coverage+1;break
     end
    end
   end
  end
 end
end
function AIVECorner:workingCrop(p)
 local c=self.controller;local count=0
 for _,part in ipairs(c.parts or{})do
  if part.label=='workbar'then
   for _,fraction in ipairs({-.8,-.4,0,.4,.8})do
    local b=part.side+fraction*math.max(0,part.half-.1)
    local x=p.x+part.along*math.cos(p.h)-b*math.sin(p.h)
    local z=p.z+part.along*math.sin(p.h)+b*math.cos(p.h)
    count=count+c:workAt(x,z)
   end
  end
 end
 return count
end
function AIVECorner:makeOptions(base,last)
 local prefix={};for i=1,last do prefix[i]=base[i]end
 local worked=0;for i=base.workFirst,last do worked=worked+distance(base[i-1],base[i])end
 if worked<2 then return end
 for _,yaw in ipairs({90,75,60})do
  local desired=self.controller.cornerExitHeading or (self.anchorHeading+self.sign*math.rad(yaw))
  for _,backAngle in ipairs({0,25,40,55})do
   local path={};for i,q in ipairs(prefix)do path[i]=q end
   local remaining=self.sign*wrap(desired-path[#path].h)
   local back=math.min(math.rad(backAngle),math.max(0,remaining))
   if back>.01 then append(path,false,false,self.radius*back,-self.sign/self.radius)end
   remaining=self.sign*wrap(desired-path[#path].h)
   if remaining>.01 then append(path,true,true,self.radius*remaining,self.sign/self.radius)end
   append(path,true,true,4,0)
   path.corner=true;path.escape=true;path.manoeuvre=true;path.length=0
   path.reverseDistance=base.retreat;path.wedgeLength=worked;path.extraReverse=backAngle~=0
   for i=2,#path do path.length=path.length+distance(path[i-1],path[i])end
   path.goal=copy(path[#path]);path.initialReserve=self.startReserve
   -- Prefer a direct continuation when it fits. A second reverse is a
   -- checked alternative, rather than an obligatory extra manoeuvre.
   path.preferredRetreat=self.preferredRetreat
   path.rank=path.length+(backAngle~=0 and 4 or 0)
    +math.max(0,self.preferredRetreat-base.retreat)*40+(90-yaw)*.5
   path.covered={};path.coverage=0
   self.options[#self.options+1]=path
  end
 end
end
function AIVECorner:clear(p,work)
 local c=self.controller;local from=distance(p,self.start)
 local fraction=math.min(1,from/2)
 local reserve=(self.startReserve or 0)*(1-fraction)+.18*fraction
 if c:box(p,false,nil,nil,reserve)then return false end
 if work and not c:isWorkingPoseOnField(p)then return false end
 return true
end
function AIVECorner:update()
 if self.path then return self.path,nil,false end
 if self.failure then return nil,self.failure,false end
 local c=self.controller
 if not self.started then
  self.started=true
  if c:box(self.start,false)then
   if not c:box(self.start,false,nil,nil,-.08)then self.startReserve=-.08
   else self.failure='corner start physically occupied';return nil,self.failure,false end
  end
 end
 for _=1,self.budget do
  if self.phase=='targets'then
   local q=self.targetSamples[self.targetIndex]
   if q then
    local ix,iz=math.floor(q.x),math.floor(q.z);local key=ix..':'..iz
    if not self.targetKeys[key]and c:workAt(q.x,q.z)>0 then
     self.targets[#self.targets+1]={x=ix+.5,z=iz+.5};self.targetKeys[key]=true
    end
    self.targetIndex=self.targetIndex+1
   else self.phase='base'end
  elseif self.phase=='base'then
   local path=self.bases[self.baseIndex]
   if not path then
    table.sort(self.options,function(a,b)return a.rank<b.rank end)
    self.phase='options';self.index=1;self.crop=0
   else
    local q=path[self.index]
    if not q then
     self:makeOptions(path,#path);self.baseIndex=self.baseIndex+1;self.index=1
    elseif not self:clear(q,q.work)then
     if self.index>path.workFirst+8 then self:makeOptions(path,self.index-1)end
     self.baseIndex=self.baseIndex+1;self.index=1
    else self.index=self.index+1 end
   end
  else
   local path=self.options[self.optionIndex]
   if not path then
    if self.bestPath then self.path=self.bestPath;return self.path,nil,false end
    self.failure='no checked retreat/harvest/turn template fits';return nil,self.failure,false
   end
   local q=path[self.index]
   local ahead={x=path.goal.x+3*math.cos(path.goal.h),z=path.goal.z+3*math.sin(path.goal.h),h=path.goal.h}
   if self.index==1 and not c:isWorkingPoseOnField(ahead)then
    self.optionIndex=self.optionIndex+1;self.index=1;self.crop=0
   elseif not q then
    -- The next straight work corridor must actually be usable, otherwise
    -- this would merely move the same stop a few metres around the corner.
    local ahead={x=path.goal.x+3*math.cos(path.goal.h),z=path.goal.z+3*math.sin(path.goal.h),h=path.goal.h}
    if self.crop>0 and c:isWorkingPoseOnField(ahead)and not c:frontSweep(path.goal,3)then
     path.cropSamples=self.crop
     local cost=(#self.targets-path.coverage)*100+path.rank+(path.reverseDistance==0 and 10000 or 0)
     if not self.bestCost or cost<self.bestCost then self.bestCost=cost;self.bestPath=path end
     if path.coverage==#self.targets and path.reverseDistance>=self.preferredRetreat then self.path=path;return path,nil,false end
    end
    self.optionIndex=self.optionIndex+1;self.index=1;self.crop=0
   elseif not self:clear(q,q.work)then
    self.optionIndex=self.optionIndex+1;self.index=1;self.crop=0
   else
    if q.work then
     self:cover(path,q)
     if self.index%4==0 then self.crop=(self.crop or 0)+self:workingCrop(q)end
    end
    self.index=self.index+1
   end
  end
 end
 return nil,nil,true
end
