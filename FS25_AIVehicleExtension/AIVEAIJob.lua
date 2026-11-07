-- Native FS25 map job: road transfer, field entry, then the existing AIVE worker.
-- Native lifecycle/messages/network, road-graph travel and checked field alignment.
AIVEJobOption = {}
local optionMt = Class(AIVEJobOption, AIParameter)

function AIVEJobOption.new(choices, index)
    local self = AIParameter.new(optionMt)
    self.type = AIParameterType.SELECTOR
    self.choices = choices
    self:setIndex(index or 1)
    return self
end

function AIVEJobOption:setIndex(index)
    index = tonumber(index)
    if index == nil or index ~= index or index == math.huge or index == -math.huge then index = 1 end
    self.index = math.max(1, math.min(#self.choices, math.floor(index)))
end
function AIVEJobOption:getValue() return self.choices[self.index].value end
function AIVEJobOption:getString() return self.choices[self.index].label end
function AIVEJobOption:setNextItem() self:setIndex(self.index % #self.choices + 1) end
function AIVEJobOption:setPreviousItem() self:setIndex((self.index - 2) % #self.choices + 1) end
function AIVEJobOption:readStream(id, connection) self:setIndex(streamReadUInt8(id)) end
function AIVEJobOption:writeStream(id, connection) streamWriteUInt8(id, self.index) end
function AIVEJobOption:saveToXMLFile(xml, key) xml:setInt(key .. "#index", self.index) end
function AIVEJobOption:loadFromXMLFile(xml, key) self:setIndex(xml:getInt(key .. "#index", self.index)) end

AIVEJobValue = {}
local valueMt = Class(AIVEJobValue, AIParameter)
function AIVEJobValue.new(job)
    local self = AIParameter.new(valueMt)
    self.type, self.job = AIParameterType.SELECTOR, job
    return self
end
function AIVEJobValue:getOption() return self.job.options[self.job.settingParameter:getValue()] end
function AIVEJobValue:getString() return self:getOption():getString() end
function AIVEJobValue:setNextItem() self:getOption():setNextItem() end
function AIVEJobValue:setPreviousItem() self:getOption():setPreviousItem() end

AIVEAIJob = {}
local jobMt = Class(AIVEAIJob, AIJobFieldWork)
AIVEAIJob.NAME = "AIVE_FIELDWORK"
AIVEAIJob.START_ERROR_PREPARATION = 200
AIVEAIJob.SEARCH_RADIUS = 40
AIVEAIJob.BLOCKED_TIMEOUT = 45000
AIVEAIJob.PLANNING_TIMEOUT = 120000

local function txt(key) return g_i18n:getText(key) end
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function choices(keys)
    local result = {}
    for i, key in ipairs(keys) do result[i] = {value=i, label=txt(key)} end
    return result
end
local function range(first, last, step, format)
    local result = {}
    for i=first,last do result[#result+1] = {value=i*step, label=string.format(format, i*step)} end
    return result
end

function AIVEAIJob.new(isServer, customMt)
    local self = AIJobFieldWork.new(isServer, customMt or jobMt)
    -- A second native drive task takes the rig from the selected roadside point
    -- to a nearby field patch, facing the direction selected on the map.
    self.driveToTask = AIVETransferTask.new(isServer, self, false)
    self.entryTask = AIVETransferTask.new(isServer, self, true)
    self.tasks = {}
    for _, task in ipairs({self.driveToTask, self.entryTask, self.fieldWorkTask}) do
        task.taskIndex = nil
        self:addTask(task)
    end
    self.options = {}
    self.optionOrder = {}
    self.optionGroups = {}
    local bools = {{value=false,label=txt("AIVE_OFF")},{value=true,label=txt("AIVE_ON")}}
    self:addOption("upNDown", "AIVE_UTURN_TYPE", choices({"AIVE_UTURN_OFF","AIVE_UTURN_ON","AIVE_UTURN_ON2","AIVE_CIRCLE_LANDS"}))
    self:addOption("rightAreaActive", "AIVE_ACTIVESIDE", choices({"AIVE_ACTIVESIDELEFT","AIVE_ACTIVESIDERIGHT"}))
    self:addOption("headland", "AIVE_HEADLAND", choices({"AIVE_OFF","AIVE_SMALL_HEADLAND","AIVE_BIG_HEADLAND"}))
    self:addOption("maxCircles", "AIVE_MAXCIRCLES", range(0,6,1,"%.0f"))
    self:addOption("widthOffset", "AIVE_WIDTH_OFFSET", range(-16,16,0.125,"%+.3f m"))
    self:addOption("travelMode", "AIVE_JOB_TRAVEL", choices({"AIVE_JOB_TRAVEL_AUTO","AIVE_JOB_TRAVEL_NATIVE","AIVE_JOB_TRAVEL_AD","AIVE_JOB_TRAVEL_MAP"}))
    self:addOption("turnOffset", "AIVE_TURN_OFFSET", range(-10,10,1,"%+.0f m"))
    self:addOption("precision", "AIVE_PRECISION", {{value=0,label=txt("AIVE_PRECISION_0")},{value=1,label=txt("AIVE_PRECISION_1")},{value=2,label=txt("AIVE_PRECISION_2")}})
    self:addOption("collision", "AIVE_COLLISION", bools)
    self:addOption("fieldGroup", "AIVE_FIELD_GROUP", bools)
    self:addOption("noSprayer", "AIVE_NOSPRAYER", bools)
    self:addOption("waitForPipe", "AIVE_WAIT_FOR_PIPE", bools)
    self:addOption("turnLow", "AIVE_TURNLOW", bools)
    self:addOption("useAIFieldFct", "AIVE_USE_AI_FIELD", bools)
    self:addOption("inverted", "AIVE_REVERSE_DRIVING", bools)
    self:addOption("angleFactor", "AIVE_ANGLE_FACTOR", range(0,20,0.05,"%.2f"))
    -- The native map form has no scroll container. Keep its controls on screen;
    -- all advanced settings remain available through a setting/value pair.
    for _, id in ipairs({"upNDown","rightAreaActive","headland","maxCircles"}) do
        table.insert(self.groupedParameters, self.optionGroups[id])
    end
    local settings = {}
    for _, id in ipairs(self.optionOrder) do
        if id ~= "upNDown" and id ~= "rightAreaActive" and id ~= "headland" and id ~= "maxCircles" then
            settings[#settings+1] = {value=id,label=self.optionGroups[id]:getTitle()}
        end
    end
    self.settingParameter = AIVEJobOption.new(settings)
    self:addNamedParameter("aive_setting", self.settingParameter)
    local group = AIParameterGroup.new(txt("AIVE_JOB_SETTING"))
    group:addParameter(self.settingParameter)
    table.insert(self.groupedParameters, group)
    group = AIParameterGroup.new(txt("AIVE_JOB_VALUE"))
    group:addParameter(AIVEJobValue.new(self))
    table.insert(self.groupedParameters, group)
    return self
end

function AIVEAIJob:addOption(id, title, values)
    local parameter = AIVEJobOption.new(values)
    self.options[id] = parameter
    self.optionOrder[#self.optionOrder+1] = id
    self:addNamedParameter("aive_" .. id, parameter)
    local group = AIParameterGroup.new(txt(title))
    group:addParameter(parameter)
    self.optionGroups[id] = group
end

function AIVEAIJob:applyCurrentState(vehicle, mission, farmId, isDirectStart)
    AIJobFieldWork.applyCurrentState(self, vehicle, mission, farmId, isDirectStart)
    for _, id in ipairs(self.optionOrder) do
        local value = vehicle.acParameters[id]
        if id == "upNDown" or id == "headland" or id == "rightAreaActive" then
            value = AIVehicleExtension["aiveUIGet" .. id](vehicle)
        end
        local parameter = self.options[id]
        local best, distance = 1, math.huge
        for i, choice in ipairs(parameter.choices) do
            local d = choice.value == value and 0 or math.huge
            if type(value) == "number" and type(choice.value) == "number" then d = math.abs(choice.value-value) end
            if d < distance then best, distance = i, d end
        end
        parameter:setIndex(best)
    end
end

function AIVEAIJob:getIsAvailableForVehicle(vehicle)
    return vehicle ~= nil and vehicle.acParameters ~= nil and vehicle.spec_aiFieldWorker ~= nil
        and vehicle.getCanStartFieldWork ~= nil and vehicle:getCanStartFieldWork()
        and vehicle.getIsAIJobSupported ~= nil and vehicle:getIsAIJobSupported("AIJobFieldWork")
end

function AIVEAIJob:getHelperName()
    -- Validation messages are also rendered before a helper has been hired.
    local helper = self.helperIndex ~= nil and g_helperManager:getHelperByIndex(self.helperIndex) or nil
    if helper ~= nil then return helper.title end
    local vehicle = self.vehicleParameter:getVehicle()
    return vehicle ~= nil and vehicle:getName() or "AIVE"
end

function AIVEAIJob:applySettings()
    local vehicle = self.vehicleParameter:getVehicle()
    if vehicle == nil or vehicle.acParameters == nil then return end
    for _, id in ipairs(self.optionOrder) do
        local value = self.options[id]:getValue()
        if id == "upNDown" or id == "headland" or id == "rightAreaActive" then
            AIVehicleExtension["aiveUISet" .. id](vehicle, value)
        elseif id ~= "travelMode" then
            vehicle.acParameters[id] = value
        end
    end
    vehicle.acParameters.enabled = true
    vehicle.acPause = false
    vehicle.aiveAutoSteer = false
end

-- No position-dependent implement checks here: the rig can still be in a shed.
-- Explicit seed checks also cover hoppers on other attached vehicles.
function AIVEAIJob:checkSupplies()
    local vehicle = self.vehicleParameter:getVehicle()
    if vehicle == nil or vehicle.acParameters == nil then return false, AIMessageErrorVehicleDeleted.new() end
    local objects = vehicle.getChildVehicles ~= nil and vehicle:getChildVehicles() or {vehicle}
    for _, object in ipairs(objects) do
        local sow = object.spec_sowingMachine
        if sow ~= nil then
            local filled = object:getSowingMachineCanConsume() == true
            for _, src in ipairs((sow.fillTypeSources or {})[sow.seedFillType] or {}) do
                if src.vehicle:getFillUnitFillLevel(src.fillUnitIndex) > 0
                    and src.vehicle:getFillUnitFillType(src.fillUnitIndex) == sow.seedFillType then filled = true end
            end
            if not filled then return false, AIMessageErrorOutOfFill.new() end
            local fruitIndex = sow.seeds ~= nil and sow.seeds[sow.currentSeed] or nil
            local fruit = fruitIndex ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fruitIndex) or nil
            if fruit ~= nil and not object:getCanPlantOutsideSeason()
                and not fruit:getIsPlantableInPeriod(g_currentMission.missionInfo.growthMode, g_currentMission.environment.currentPeriod) then
                return false, AIMessageErrorWrongSeason.new()
            end
        end
        local spray = object.spec_sprayer
        local skipSpray = sow ~= nil and self.options.noSprayer:getValue()
        if spray ~= nil and not skipSpray and spray.needsToBeFilledToTurnOn then
            local index = object:getSprayerFillUnitIndex()
            local filled = object:getFillUnitFillLevel(index) > 0 or object:getFillUnitCapacity(index) == 0
            for _, fillType in ipairs(spray.supportedSprayTypes or {}) do
                for _, src in ipairs((spray.fillTypeSources or {})[fillType] or {}) do
                    if src.vehicle:getFillUnitFillLevel(src.fillUnitIndex) > 0
                        and src.vehicle:getFillUnitFillType(src.fillUnitIndex) == fillType then filled = true end
                end
            end
            if not filled then return false, AIMessageErrorOutOfFill.new() end
        end
    end
    return true, nil
end

function AIVEAIJob.isField(x, z)
    return AutoSteeringEngine.checkFieldNoBuffer(x, z, FieldBitmap.isFieldFast)
end

function AIVEAIJob:hasWorkAt(x, z)
    local vehicle = self.vehicleParameter:getVehicle()
    local known = false
    for _, object in ipairs(vehicle:getChildVehicles()) do
        if object.getFieldCropsQuery ~= nil then
            local query, valid = object:getFieldCropsQuery()
            if query ~= nil and valid then
                known = true
                local area = AIVehicleUtil.getAIFruitArea(x-2,z-2,x+2,z-2,x-2,z+2,query)
                if area > 0 then return true end
            end
        end
    end
    -- Some harvesters initialize crop requirements only when work starts.
    if known then return false end
    return nil
end

function AIVEAIJob:findEntry(farmId)
    local x, z = self.positionAngleParameter:getPosition()
    local angle = self.positionAngleParameter:getAngle()
    if not finite(x) or not finite(z) or not finite(angle) then return nil, AIMessageErrorNoFieldFound.new() end
    local dx, dz = MathUtil.getDirectionFromYRotation(angle)
    local vehicle = self.vehicleParameter:getVehicle()
    local rx, _, rz = getWorldTranslation(vehicle.rootNode)
    local fx, _, fz = localDirectionToWorld(vehicle.rootNode,0,0,1)
    local lo, hi, along = -1.5, 1.5, 0
    local markerWidth = 0
    -- Position the WORKING edge, not the back of the entire combination.
    -- A front header and a rear drill need opposite root offsets at entry.
    for _, object in ipairs(vehicle.getChildVehicles ~= nil and vehicle:getChildVehicles() or {}) do
        if object.getAIMarkers ~= nil then
            local left, right = object:getAIMarkers()
            if left ~= nil and right ~= nil and left ~= 0 and right ~= 0 then
                local lx, _, lz = getWorldTranslation(left)
                local qx, _, qz = getWorldTranslation(right)
                local a,b=(lx-rx)*fz-(lz-rz)*fx,(qx-rx)*fz-(qz-rz)*fx
                if math.abs(a-b)>markerWidth then
                    lo,hi=math.min(a,b),math.max(a,b)
                    along=((lx+qx)*0.5-rx)*fx+((lz+qz)*0.5-rz)*fz
                    markerWidth=hi-lo
                end
            end
        end
    end
    local centre=(lo+hi)/2
    local halfWidth=math.min(25,(hi-lo)/2+math.abs(self.options.widthOffset:getValue()))
    local outsideSign = self.options.rightAreaActive:getValue() == 2 and -1 or 1
    local best, bestScore, foreign, unsuitable = nil, math.huge, false, false
    local function access(px,pz) return g_farmlandManager:getCanAccessLandAtWorldPosition(farmId,px,pz) end
    local function field(px,pz) return AIVEAIJob.isField(px,pz) end
    for ox=-AIVEAIJob.SEARCH_RADIUS,AIVEAIJob.SEARCH_RADIUS,2 do
        for oz=-AIVEAIJob.SEARCH_RADIUS,AIVEAIJob.SEARCH_RADIUS,2 do
            local score = ox*ox + oz*oz
            if score <= AIVEAIJob.SEARCH_RADIUS^2 and score < bestScore then
                local px, pz = x+ox, z+oz
                if field(px,pz) then
                    local accessible = access(px,pz)
                    if not accessible then foreign = true
                    else
                        local outX = px + dz*outsideSign*(halfWidth+0.75)
                        local outZ = pz - dx*outsideSign*(halfWidth+0.75)
                        local inX = px - dz*outsideSign*(halfWidth-0.25)
                        local inZ = pz + dx*outsideSign*(halfWidth-0.25)
                        local edgeX=px+dz*outsideSign*math.max(0,halfWidth-1.5)
                        local edgeZ=pz-dx*outsideSign*math.max(0,halfWidth-1.5)
                        local inside = not field(outX,outZ) and field(edgeX,edgeZ) and field(inX,inZ) and access(inX,inZ)
                        if inside then
                            if self:hasWorkAt(px,pz) ~= false then
                                best, bestScore = {x=px,z=pz}, score
                            else unsuitable = true end
                        end
                    end
                end
            end
        end
    end
    if best == nil then
        if unsuitable then return nil, AIMessageErrorFieldNotReady.new() end
        return nil, foreign and AIMessageErrorFieldNotOwned.new() or AIMessageErrorNoFieldFound.new()
    end
    -- Refine the lateral edge below the old 2 m search grid resolution.
    local low,high=-3,3
    for _=1,12 do
        local shift=(low+high)/2
        local ex=best.x+dz*outsideSign*(halfWidth+shift)
        local ez=best.z-dx*outsideSign*(halfWidth+shift)
        if field(ex,ez) then low=shift else high=shift end
    end
    local shift=(low+high)/2-0.15
    best.x=best.x+dz*outsideSign*shift;best.z=best.z-dx*outsideSign*shift
    -- The vanilla angle selector snaps to 45 degrees. Real field borders
    -- (including Vladimirovka 17) are slightly oblique: tracing the snapped
    -- direction backwards would hit the SIDE halfway along the field. Measure
    -- its local tangent before looking for the front edge.
    local edgeX,edgeZ=best.x+dz*outsideSign*halfWidth,best.z-dx*outsideSign*halfWidth
    local probes={}
    for _,station in ipairs({-12,-4,4,12}) do
        local px,pz=edgeX+dx*station,edgeZ+dz*station
        local a,b=-4,4
        if field(px+dz*outsideSign*a,pz-dx*outsideSign*a) and not field(px+dz*outsideSign*b,pz-dx*outsideSign*b) then
            for _=1,12 do
                local mid=(a+b)/2
                if field(px+dz*outsideSign*mid,pz-dx*outsideSign*mid) then a=mid else b=mid end
            end
            probes[#probes+1]={x=px+dz*outsideSign*(a+b)/2,z=pz-dx*outsideSign*(a+b)/2}
        end
    end
    if #probes>=2 then
        local a,b=probes[1],probes[#probes]
        local ex,ez=b.x-a.x,b.z-a.z
        local length=math.sqrt(ex*ex+ez*ez)
        if length>0 and (ex*dx+ez*dz)/length>math.cos(math.rad(15)) then dx,dz=ex/length,ez/length end
    end
    local function frontAt(back)
        -- The first crop under ANY part of the cutter starts the pass. This
        -- also handles a slanted front boundary without losing a triangle.
        for _,side in ipairs({-halfWidth+0.25,0,halfWidth-0.25}) do
            local px=best.x-dx*back+dz*side
            local pz=best.z-dz*back-dx*side
            if field(px,pz) and access(px,pz) then return true end
        end
        return false
    end
    local inside,outside=0,nil
    for back=2,2048,2 do
        if not frontAt(back) then outside=back;break end
        inside=back
    end
    if not outside then return nil,AIMessageErrorNoFieldFound.new() end
    for _=1,12 do
        local mid=(inside+outside)/2
        if frontAt(mid) then inside=mid else outside=mid end
    end
    local cx,cz=best.x-dx*(inside-0.15),best.z-dz*(inside-0.15)
    local workX,workZ
    for _,side in ipairs({0,-halfWidth+0.25,halfWidth-0.25}) do
        local px,pz=cx+dz*side,cz-dx*side
        if field(px,pz) and access(px,pz) then workX,workZ=px,pz;break end
    end
    if not workX then return nil,AIMessageErrorFieldNotOwned.new() end
    if self:hasWorkAt(workX+dx,workZ+dz)==false then return nil,AIMessageErrorFieldNotReady.new() end
    return {x=cx-dx*along-dz*centre,z=cz-dz*along+dx*centre,workX=workX,workZ=workZ,dx=dx,dz=dz},nil
end

function AIVEAIJob:usesRoadGraph()
    local mode=self.options.travelMode:getValue()
    if mode==2 then return false end
    if mode==3 then return AIVETransferTask.getGraph()~=nil end
    if mode==4 then return AIVETransferTask.hasMapRoads()==true end
    return AIVETransferTask.getGraph()~=nil or AIVETransferTask.hasMapRoads()==true
end

function AIVEAIJob:checkPreparation(farmId)
    local vehicle = self.vehicleParameter:getVehicle()
    if vehicle == nil or vehicle.acParameters == nil or vehicle.spec_aiFieldWorker == nil then
        return false, AIMessageErrorVehicleDeleted.new()
    end
    if not self.isRunning and not self:getIsAvailableForVehicle(vehicle) then return false, AIMessageErrorUnknown.new() end
    if AIVEConflictGuard ~= nil then
        local active = AIVEConflictGuard.isExternalAIActive(vehicle)
        if active then return false, AIMessageErrorUnknown.new() end
    end
    local ready, message = self:checkSupplies()
    if not ready then return false, message end
    local x, z = self.positionAngleParameter:getPosition()
    local angle = self.positionAngleParameter:getAngle()
    local side, width = self.options.rightAreaActive:getValue(), self.options.widthOffset:getValue()
    local cache = self.entryCache
    local now = g_currentMission.time or 0
    local entry
    if cache ~= nil and cache.vehicle == vehicle and cache.farmId == farmId and cache.x == x and cache.z == z
        and cache.angle == angle and cache.side == side and cache.width == width and now < cache.expires then
        entry, message = cache.entry, cache.message
    else
        entry, message = self:findEntry(farmId)
        self.entryCache = {vehicle=vehicle,farmId=farmId,x=x,z=z,angle=angle,side=side,width=width,entry=entry,message=message,expires=now+2000}
    end
    if entry == nil then return false, message end
    self.entry = entry
    return true, nil
end

function AIVEAIJob:validate(farmId)
    if self.options.fieldGroup:getValue() and (self.options.upNDown:getValue()~=4 or self.options.inverted:getValue()) then
        return false,txt("AIVE_FIELD_GROUP_MODE")
    end
    local valid, errorText = AIJobFieldWork.validate(self, farmId)
    if not valid then return valid, errorText end
    local x,z=self.positionAngleParameter:getPosition()
    if not finite(x) or not finite(z) or not finite(self.positionAngleParameter:getAngle()) then
        return false,txt("ai_validationErrorNoPosition")
    end
    if self.options.travelMode:getValue()==3 and not self:usesRoadGraph() then return false,txt("AIVE_JOB_AD_MISSING") end
    if self.options.travelMode:getValue()==4 and not self:usesRoadGraph() then return false,txt("AIVE_JOB_MAP_MISSING") end
    -- A field entry is deliberately independent of the GIANTS road mesh.
    -- Do not reject AutoDrive's valid roads using the native reachability flag.
    if not self:usesRoadGraph() and not self.isDirectStart then
        valid,errorText=self.positionAngleParameter:validate()
        if not valid then self.positionAngleParameter:setIsValid(false);return false,errorText end
    end
    local ready, message = self:checkPreparation(farmId)
    if not ready then return false, message:getMessage(self) end
    return true, nil
end

function AIVEAIJob:getIsStartable(connection)
    local ready, state = AIJobFieldWork.getIsStartable(self, connection)
    if not ready then return ready, state end
    local vehicle = self.vehicleParameter:getVehicle()
    self.entryCache = nil
    ready = self:checkPreparation(vehicle:getOwnerFarmId())
    if not ready then return false, AIVEAIJob.START_ERROR_PREPARATION end
    return true, AIJob.START_SUCCESS
end

function AIVEAIJob.getIsStartErrorText(state)
    if state == AIVEAIJob.START_ERROR_PREPARATION then return txt("AIVE_JOB_CHECK_PREPARATION") end
    return AIJobFieldWork.getIsStartErrorText(state)
end

function AIVEAIJob:setValues()
    AIJobFieldWork.setValues(self)
    self.entryTask:setVehicle(self.vehicleParameter:getVehicle())
    self.entry = nil
    self.entryCache = nil
end

function AIVEAIJob:canStartWork()
    if self.options.travelMode:getValue()>=3 and not self:usesRoadGraph() then return false,AIMessageErrorNotReachable.new() end
    self.entryCache = nil
    local ready, message = self:checkPreparation(self.startedFarmId)
    if not ready then return false, message end
    -- The pin identifies a field and may be inside its crop. Route to the
    -- approach BEFORE the measured cutter entry, otherwise the road leg can
    -- overshoot the front edge and force an unnecessary U-turn on arrival.
    local approach=24
    self.driveToTask:setTargetPosition(self.entry.x-self.entry.dx*approach,self.entry.z-self.entry.dz*approach)
    self.driveToTask:setTargetDirection(self.entry.dx,self.entry.dz)
    self.entryTask:setTargetPosition(self.entry.x, self.entry.z)
    self.entryTask:setTargetDirection(self.entry.dx, self.entry.dz)
    return true, nil
end

function AIVEAIJob:getStartTaskIndex()
    -- Even beside the field, use the entry task to align the rig first.
    local vehicle = self.vehicleParameter:getVehicle()
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local tx, tz = self.positionAngleParameter:getPosition()
    if self.isDirectStart or (x-tx)^2+(z-tz)^2 < 9 then return 2 end
    if self.entry and (x-self.entry.x)^2+(z-self.entry.z)^2<144 then return 2 end
    return 1
end

function AIVEAIJob:canContinueWork()
    local ready, message = self:checkSupplies()
    if not ready then return false, message end
    if self.currentTaskIndex == 2 then
        -- Recheck land access after travel (ownership may have changed).
        if not g_farmlandManager:getCanAccessLandAtWorldPosition(self.startedFarmId,self.entry.workX,self.entry.workZ) then
            return false, AIMessageErrorFieldNotOwned.new()
        end
        if not AIVEAIJob.isField(self.entry.workX,self.entry.workZ) then return false, AIMessageErrorNoFieldFound.new() end
    end
    return true, nil
end

function AIVEAIJob:startTask(task)
    self.blockedTime, self.stationaryTime, self.checkTime = 0, 0, 0
    self.lastX, self.lastZ = nil, nil
    self.workCheckTime, self.workVerified = 0, false
    if task == self.fieldWorkTask then
        self:applySettings()
        if self.isServer then
            local vehicle = self.vehicleParameter:getVehicle()
            -- A new map order must never resume a cached route from another order.
            vehicle.aiveJobMemory = nil
            AIVehicleExtension.sendParameters(vehicle)
            AIVELogger.info("MapJob", "Arrived at field; starting AIVE on '%s'.", vehicle:getName())
        end
    end
    AIJob.startTask(self, task)
end

function AIVEAIJob:update(dt)
    AIJobFieldWork.update(self, dt)
    if not self.isServer or not self.isRunning then return end
    local task = self:getTaskByIndex(self.currentTaskIndex)
    if task == self.fieldWorkTask and not self.workVerified then
        local worker=self.vehicleParameter:getVehicle()
        local lands=worker and worker.aiveMainStrategy and worker.aiveMainStrategy.lands
        if self.options.fieldGroup:getValue() and (not lands or not lands.snapshot
            or (lands.phase~="work" and lands.phase~="perimeter")) then
            self.workCheckTime=0;return
        end
        self.workCheckTime = (self.workCheckTime or 0) + dt
        -- Sowing requirements change when the machine is switched on (e.g. do
        -- not sow grass over an existing grass crop). Allow unfolding first.
        if self.workCheckTime > 10000 then
            local vehicle = self.vehicleParameter:getVehicle()
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            local known, found = false, false
            for _, p in ipairs({{0,0},{-6,0},{6,0},{0,-6},{0,6}}) do
                local work = self:hasWorkAt(x+p[1],z+p[2])
                known, found = known or work ~= nil, found or work == true
            end
            self.workVerified = true
            if known and not found then vehicle:stopCurrentAIJob(AIMessageErrorFieldNotReady.new()) end
        end
        return
    end
    if task ~= self.driveToTask and task ~= self.entryTask then return end
    local vehicle = self.vehicleParameter:getVehicle()
    if vehicle == nil then return end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    if self.lastX == nil or (x-self.lastX)^2+(z-self.lastZ)^2 > 4 then
        self.lastX, self.lastZ, self.stationaryTime = x, z, 0
    else self.stationaryTime = (self.stationaryTime or 0) + dt end
    local spec = vehicle.spec_aiDrivable
    if spec ~= nil and spec.lastIsBlocked then self.blockedTime = (self.blockedTime or 0)+dt else self.blockedTime=0 end
    self.checkTime = (self.checkTime or 0)+dt
    if self.checkTime > 2000 then
        self.checkTime=0
        local ready, message = self:checkSupplies()
        if not ready then vehicle:stopCurrentAIJob(message);return end
    end
    if self.blockedTime > AIVEAIJob.BLOCKED_TIMEOUT or self.stationaryTime > AIVEAIJob.PLANNING_TIMEOUT then
        vehicle:stopCurrentAIJob(AIMessageErrorBlockedByObject.new())
    end
end

function AIVEAIJob:getDescription()
    local description = AIJob.getDescription(self)
    if self.currentTaskIndex == 1 then return description .. " - " .. txt("ai_taskDescriptionDriveToField") end
    if self.currentTaskIndex == 2 then return description .. " - " .. txt("AIVE_JOB_ENTER_FIELD") end
    local status=(self.vehicleParameter:getVehicle() or {}).aiveFieldGroupStatus
    if status then description=description..string.format(" [%d/4, ~%.1f%%]",status.count,status.progress) end
    return description .. " - " .. txt("ai_taskDescriptionFieldWork")
end

function AIVEAIJob.register(manager)
    if manager:getJobTypeIndexByName(AIVEAIJob.NAME) == nil then
        -- The manager runs in the base game's environment; resolve mod text here.
        manager:registerJobType(AIVEAIJob.NAME, txt("AIVE_JOB_TITLE"), AIVEAIJob)
    end
end
AIJobTypeManager.loadMapData = Utils.appendedFunction(AIJobTypeManager.loadMapData, AIVEAIJob.register)
