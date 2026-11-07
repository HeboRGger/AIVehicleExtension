-- Opt-in measurements. Disabled wrappers preserve all native return values.
AIVEPerformance={enabled=false,stats={},wrapped={},frameCount=0,frameTotal=0}
local P=AIVEPerformance
local unpackValues=unpack or table.unpack
local function pack(...) return {n=select('#',...),...} end
local function clock()
    if type(getTimeSec)=="function" then return getTimeSec() end
    if type(getTime)=="function" then return getTime()/1000 end
    if os and type(os.clock)=="function" then return os.clock() end
    return 0
end
function P.wrap(owner,key,label)
    if not owner or type(owner[key])~="function" then return end
    if P.wrapped[label] then return end
    P.wrapped[label]=true
    local original=owner[key]
    owner[key]=function(...)
        if not P.enabled then return original(...) end
        local start=clock();local result=pack(original(...));local elapsed=math.max(0,clock()-start)*1000
        local s=P.stats[label] or {calls=0,total=0,max=0};P.stats[label]=s
        s.calls=s.calls+1;s.total=s.total+elapsed;s.max=math.max(s.max,elapsed)
        return unpackValues(result,1,result.n)
    end
end
function P.install()
    P.wrap(AIVELands,"hasWork","work.query")
    P.wrap(AIVELands,"observe","lands.observe")
    P.wrap(AIVELands,"connector","lands.connector")
    P.wrap(AIVEObstacles,"dimensions","obstacles.dimensions")
    P.wrap(AIVEObstacles,"queryPart","obstacles.physics")
    P.wrap(AIVEObstacles,"beginWorkingBypass","obstacles.plan")
    P.wrap(AutoSteeringEngine,"getAIAreaOfVehicle","density.query")
end
function P:consoleCommand(argument)
    if argument=="on" then self.install();self.stats={};self.enabled=true;return "AIVE profile ON (inclusive timings in ms)." end
    if argument=="off" then self.enabled=false;return "AIVE profile OFF." end
    local lines={"AIVE profile: "..tostring(self.enabled)}
    local keys={};for k in pairs(self.stats) do keys[#keys+1]=k end;table.sort(keys)
    for _,key in ipairs(keys) do
        local s=self.stats[key]
        lines[#lines+1]=string.format("%s: calls=%d total=%.3f ms avg=%.4f ms max=%.3f ms",key,s.calls,s.total,s.total/math.max(1,s.calls),s.max)
    end
    return table.concat(lines,"\n")
end
