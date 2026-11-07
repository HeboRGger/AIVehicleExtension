-- FS25 panel; options and ranges restored from Mogli12's FS22 AIVEScreen.
-- Uses the working Overlay API instead of obsolete FS22 GUI profiles.
AIVEScreen = {}
AIVEScreen.__index = AIVEScreen
local panelDirectory=g_currentModDirectory

local function text(key, fallback)
	local value=AIVEHud.getText(key)
	if value==key then return fallback or key end
	return value
end

local function numbers(first,last,step,format)
	local result={}
	for i=first,last do
		local value=i*step
		result[#result+1]={value=value,label=string.format(format,value)}
	end
	return result
end

-- The 20 active controls in upstream gui/AIVEScreen.xml.
AIVEScreen.options = {
	{ id="enabled", label="AIVE_ENABLED", fallback="Alternative worker", boolean=true, stoppedOnly=true },
	{ id="rightAreaActive", label="AIVE_ACTIVESIDE", fallback="Active side", custom=true },
	{ id="upNDown", label="AIVE_UTURN_TYPE", fallback="Working mode", custom=true, stoppedOnly=true },
	{ id="turnModeIndex", label="AIVE_TURN_MODE", fallback="U-turn manoeuvre" },
	{ id="turnModeIndexC", label="AIVE_TURN_MODEC", fallback="Corner manoeuvre" },
	{ id="headland", label="AIVE_HEADLAND", fallback="Headland", custom=true },
	{ id="maxCircles", label="AIVE_MAXCIRCLES", fallback="Perimeter laps" },
	{ id="widthOffset", label="AIVE_WIDTH_OFFSET", fallback="Working width offset" },
	{ id="turnOffset", label="AIVE_TURN_OFFSET", fallback="Turn offset" },
	{ id="angleFactor", label="AIVE_ANGLE_FACTOR", fallback="Steering tolerance" },
	{ id="precision", label="AIVE_PRECISION", fallback="Detection precision" },
	{ id="waitForPipe", label="AIVE_WAIT_FOR_PIPE", fallback="Wait for unloading", boolean=true },
	{ id="inverted", label="AIVE_REVERSE_DRIVING", fallback="Reverse driving", boolean=true, stoppedOnly=true },
	{ id="noSprayer", label="AIVE_NOSPRAYER", fallback="Disable seeder fertilizing", boolean=true },
	{ id="turnLow", label="AIVE_TURNLOW", fallback="Keep implement lowered on turns", boolean=true },
	{ id="useAIFieldFct", label="AIVE_USE_AI_FIELD", fallback="Use field boundaries", boolean=true },
	{ id="collision", label="AIVE_COLLISION", fallback="Collision detection", boolean=true },
	{ id="GuiActive", label="AIVE_QUICK_HUD", fallback="Show quick controls", boolean=true, localOnly=true },
	{ id="showTrace", label="AIVE_SHOW_EDGE", fallback="Show field edge", boolean=true, localOnly=true },
	{ id="acPause", label="AIVE_PAUSE_OFF", fallback="Pause worker", boolean=true, pause=true }
}

function AIVEScreen.new()
	return setmetatable({isOpen=false,choices={},buttons={}},AIVEScreen)
end

function AIVEScreen:showGui(vehicle)
	if self.isOpen then self:onClose() end
	self.vehicle=vehicle
	self.choices={
		rightAreaActive={{value=1,label=text("AIVE_ACTIVESIDELEFT","Left")},{value=2,label=text("AIVE_ACTIVESIDERIGHT","Right")}},
		upNDown={{value=1,label=text("AIVE_UTURN_OFF","Perimeter")},{value=2,label=text("AIVE_UTURN_ON","Up and down")},{value=3,label=text("AIVE_UTURN_ON2","Straight")},{value=4,label=text("AIVE_CIRCLE_LANDS","Perimeter with lands")}},
		headland={{value=1,label=text("AIVE_OFF","Off")},{value=2,label=text("AIVE_SMALL_HEADLAND","Small")},{value=3,label=text("AIVE_BIG_HEADLAND","Large")}},
		maxCircles=numbers(0,6,1,"%.0f"), widthOffset=numbers(-16,16,0.125,"%+.3f m"),
		angleFactor=numbers(0,20,0.05,"%.2f"),
		precision={},turnOffset={},turnModeIndex={},turnModeIndexC={}
	}
	for i=0,2 do self.choices.precision[#self.choices.precision+1]={value=i,label=text("AIVE_PRECISION_"..i,tostring(i))} end
	for _,choice in ipairs(self.choices.angleFactor) do choice.label=string.format("%.0f%%",100*choice.value) end
	local function distance(d) self.choices.turnOffset[#self.choices.turnOffset+1]={value=d,label=string.format("%+.2f m",d)} end
	for d=-10,-4 do distance(d) end
	for d=-3.5,-1.5,0.5 do distance(d) end
	for d=-1.25,1.25,0.25 do distance(d) end
	for d=1.5,3.5,0.5 do distance(d) end
	for d=4,10 do distance(d) end
	if vehicle.isServer then AIVehicleExtension.checkState(vehicle) end
	for _,mode in ipairs({{true,"turnModeIndex"},{false,"turnModeIndexC"}}) do
		for i,code in ipairs(AIVehicleExtension.getAvailableTurnModes(vehicle,mode[1])) do
			self.choices[mode[2]][i]={value=i,label=text("AIVE_TURN_MODE_"..code,code)}
		end
	end
	self.isOpen=true
	self.hover=nil
	g_inputBinding:setShowMouseCursor(true)
	AIVELogger.info("Settings","Opened extended settings (20 options) on '%s'.",vehicle:getName())
end

function AIVEScreen:getValue(option)
	local vehicle=self.vehicle
	if option.id=="GuiActive" then return vehicle.atHud~=nil and vehicle.atHud.GuiActive end
	if option.pause then return vehicle.acPause==true end
	if option.custom then return AIVehicleExtension["aiveUIGet"..option.id](vehicle) end
	return vehicle.acParameters[option.id]
end

function AIVEScreen:isLocked(option)
	local working=self.vehicle.aiveIsStarted or self.vehicle.aiveAutoSteer
	if option.id=="maxCircles" and self.vehicle.acParameters.circleLands then return true end
	return (option.stoppedOnly and working) or (option.pause and not self.vehicle.aiveIsStarted)
end

function AIVEScreen:changeSetting(id,direction)
	if not self.isOpen or self.vehicle==nil then return end
	local option
	for _,item in ipairs(self.options) do if item.id==id then option=item;break end end
	if option==nil or self:isLocked(option) then return end
	local vehicle,value=self.vehicle,self:getValue(option)
	if option.boolean then value=not value
	else
		local list=self.choices[id]
		if list==nil or #list==0 then return end
		local index,distance=1,math.huge
		for i,entry in ipairs(list) do
			local d=math.abs(entry.value-(value or 0))
			if d<distance then index,distance=i,d end
		end
		value=list[((index-1+(direction or 1)) % #list)+1].value
	end
	if id=="GuiActive" then
		-- This panel keeps cursor ownership until it closes.
		vehicle.atHud.GuiActive=value
	elseif option.pause then AIVehicleExtension.setPause(vehicle,value)
	elseif option.custom then AIVehicleExtension["aiveUISet"..id](vehicle,value)
	else vehicle.acParameters[id]=value end
	if not option.localOnly and not option.pause then
		vehicle.acParameters.leftAreaActive=not vehicle.acParameters.rightAreaActive
		if id=="upNDown" or id=="turnModeIndex" or id=="turnModeIndexC" then
			AIVehicleExtension.checkAvailableTurnModes(vehicle,true)
		end
		vehicle.acCheckStateTimer=nil
		AIVehicleExtension.sendParameters(vehicle)
	end
end

function AIVEScreen:onClickDefaults()
	if self.vehicle.aiveIsStarted or self.vehicle.aiveAutoSteer then return end
	self.vehicle.acParameters=AIVehicleExtension.getParameterDefaults()
	self.vehicle.acCheckStateTimer=nil
	AIVehicleExtension.checkAvailableTurnModes(self.vehicle,true)
	AIVehicleExtension.sendParameters(self.vehicle)
end

function AIVEScreen:onClose()
	local vehicle=self.vehicle
	self.isOpen=false
	self.vehicle=nil
	self.hover=nil
	if g_inputBinding~=nil then
		g_inputBinding:setShowMouseCursor(vehicle~=nil and vehicle.atHud~=nil and vehicle.atHud.GuiActive or false)
	end
end

function AIVEScreen:delete()
	if self.isOpen then self:onClose() end
	if self.overlay~=nil then self.overlay:delete();self.overlay=nil end
end

function AIVEScreen:update(dt)
	if not self.isOpen then return end
	if self.vehicle==nil or not self.vehicle:getIsEntered()
		or (g_gui~=nil and g_gui:getIsGuiVisible()) then self:onClose();return end
	g_inputBinding:setShowMouseCursor(true)
end

function AIVEScreen:rectangle(x,y,w,h,r,g,b,a)
	if self.overlay==nil then self.overlay=Overlay.new(Utils.getFilename("dds/panelFill.dds",panelDirectory),0,0,1,1) end
	self.overlay:setPosition(x,y)
	self.overlay:setDimension(w,h)
	self.overlay:setColor(r,g,b,a)
	self.overlay:render()
end

function AIVEScreen:label(x,y,size,value,center,muted)
	setTextAlignment(center and RenderText.ALIGN_CENTER or RenderText.ALIGN_LEFT)
	setTextColor(1,1,1,muted and 0.55 or 1)
	renderText(x,y,size,value)
end

function AIVEScreen:button(x,y,w,h,label,action,locked)
	local index=#self.buttons+1
	self.buttons[index]={x=x,y=y,w=w,h=h,action=action,locked=locked}
	local hot=self.hover==index
	if hot and not locked then
		self:rectangle(x,y,w,h,0.22,0.46,0.07,1)
	else
		self:rectangle(x,y,w,h,0.14,0.14,0.14,1)
	end
	self:label(x+w/2,y+h/2-0.007,0.016,label,true,locked)
end

function AIVEScreen:draw()
	if not self.isOpen or self.vehicle==nil then return end
	self.buttons={}
	setTextBold(false)
	self:rectangle(0.07,0.10,0.86,0.80,0.035,0.035,0.035,0.97)
	self:rectangle(0.07,0.897,0.86,0.003,0.35,0.65,0.10,1)
	setTextBold(true)
	self:label(0.09,0.851,0.025,text("AIVE_EXTENDED_SETTINGS","AIVE — extended settings"),false)
	setTextBold(false)
	self:label(0.09,0.819,0.014,self.vehicle:getName().."  ·  "..AIVELogger.VERSION,false,true)
	for i,option in ipairs(self.options) do
		local col,row=math.floor((i-1)/10),(i-1)%10
		local x,y=0.09+col*0.43,0.748-row*0.054
		local locked=self:isLocked(option)
		self:rectangle(x,y,0.39,0.048,0.085,0.085,0.085,1)
		local label=text(option.label,option.fallback)
		if option.id=="maxCircles" and self.vehicle.acParameters.circleLands then label=text("AIVE_LANDS_SWITCH_WIDTH","Remaining width for lands") end
		self:label(x+0.009,y+0.031,0.0125,label,false,locked)
		local value,valueText=self:getValue(option),nil
		if option.id=="maxCircles" and self.vehicle.acParameters.circleLands then valueText="~80 m"
		elseif option.boolean then valueText=value and text("AIVE_ON","On") or text("AIVE_OFF","Off")
		else
			valueText=tostring(value)
			for _,entry in ipairs(self.choices[option.id] or {}) do
				if math.abs(entry.value-(value or 0))<0.00001 then valueText=entry.label;break end
			end
		end
		local size=0.0145
		if getTextWidth~=nil then
			local width=getTextWidth(size,valueText)
			if width>0.29 then size=size*0.29/width end
		end
		self:label(x+0.195,y+0.008,size,valueText,true,locked)
		if option.boolean and value and not locked then
			self:rectangle(x,y,0.003,0.048,0.35,0.65,0.10,1)
		end
		self:button(x+0.003,y+0.002,0.025,0.025,"<",function()self:changeSetting(option.id,-1)end,locked)
		self:button(x+0.362,y+0.002,0.025,0.025,">",function()self:changeSetting(option.id,1)end,locked)
	end
	local hint=text("AIVE_SETTINGS_HINT","Arrows apply changes immediately. Field edge display is visual only.")
	if self.vehicle.acParameters.circleLands then hint=text("AIVE_LANDS_THRESHOLD","Start lands when about 80 m remain") end
	if self.hover~=nil and self.buttons[self.hover]~=nil and self.buttons[self.hover].locked then
		if not self.vehicle.acParameters.circleLands then
			hint=text("AIVE_SETTING_LOCKED","Stop the worker before changing this setting; pause requires an active AIVE worker.")
		end
	end
	self:label(0.09,0.219,0.013,hint,false,true)
	self:button(0.09,0.135,0.24,0.045,text("AIVE_DEFAULTS","Defaults"),function()self:onClickDefaults()end,self.vehicle.aiveIsStarted or self.vehicle.aiveAutoSteer)
	self:button(0.38,0.135,0.24,0.045,text("AIVE_MAGIC","Refresh field"),function()AIVehicleExtension.onMagic(self.vehicle)end,false)
	self:button(0.67,0.135,0.24,0.045,text("AIVE_CLOSE","Close"),function()self:onClose()end,false)
	setTextBold(false)
	setTextAlignment(RenderText.ALIGN_LEFT)
	setTextColor(1,1,1,1)
end

function AIVEScreen:mouseEvent(x,y,isDown,isUp,button)
	if not self.isOpen then return false end
	self.hover=nil
	for i,item in ipairs(self.buttons) do
		if x>=item.x and x<=item.x+item.w and y>=item.y and y<=item.y+item.h then
			self.hover=i
			if isDown and button==1 and not item.locked then item.action() end
			break
		end
	end
	return true
end
