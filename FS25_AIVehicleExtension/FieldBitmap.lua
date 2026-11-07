------------------------------------------------------------------------
-- FieldBitmapTile
------------------------------------------------------------------------
local FieldBitmapTile = {}

------------------------------------------------------------------------
-- getNewTile
------------------------------------------------------------------------
function FieldBitmapTile.getNewTile( iX, iZ, iStepLog2, iRelX, iRelZ, iInvert )

	local relX, relZ, self;
	
	self = {};
	
	if iRelX == nil then
		relX = 0
	else
		relX = math.min( math.max( iRelX, 0 ), 1 )
	end
	
	if iRelZ == nil then
		relZ = 0
	else
		relZ = math.min( math.max( iRelZ, 0 ), 1 )
	end
	
	if iInvert then
		self.invert = true
	else
		self.invert = false
	end
	
	self.sizeLog2 = 5	
	self.sizeInt  = 32
	
	if iStepLog2 == nil then
		self.stepLog2 = 2
	else 
		self.stepLog2 = math.min( math.max( math.floor( iStepLog2 + 0.5 ), 0 ), 4 )
	end
	
	self.size    = 2 ^ ( self.sizeLog2 - self.stepLog2 )
	
	self.step    = 2 ^ self.stepLog2;
	self.stepInv = 2 ^ (-self.stepLog2);
	
	self.startX  = iX + relX * self.size
	self.startZ  = iZ + relZ * self.size
	self.endX    = self.startX + self.size
	self.endZ    = self.startZ + self.size

	self.bitmap  = { 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0 }--, 0,0,0,0,0,0,0,0 }	
	return self
end

------------------------------------------------------------------------
-- clone
------------------------------------------------------------------------
function FieldBitmapTile.clone( template )

	local self = {};
	
	self.stepLog2 = template.stepLog2
	self.invert   = template.invert
	self.sizeLog2 = template.sizeLog2 
	self.sizeInt  = template.sizeInt  	
	self.size     = template.size   
	self.step     = template.step   
	self.stepInv  = template.stepInv
	self.startX   = template.startX 
	self.startZ   = template.startZ 
	self.endX     = template.endX   
	self.endZ     = template.endZ   

	self.bitmap   = {}
	for i,b in pairs(template.bitmap) do
		self.bitmap[i] = b
	end
	
	return self
end

------------------------------------------------------------------------
-- getIndex
------------------------------------------------------------------------
function FieldBitmapTile:getIndex( x, z )
	local i =     math.floor( self.step * ( x - self.startX ) )
	local j = 1 + math.floor( self.step * ( z - self.startZ ) )
	return i,j
end

------------------------------------------------------------------------
-- checkIndex
------------------------------------------------------------------------
function FieldBitmapTile:checkIndex( i, j )
	if i < 0 or i >= self.sizeInt then return false end	
	if j < 1 or j >  self.sizeInt then return false end
	return true
end
	
------------------------------------------------------------------------
-- getBitHelper
------------------------------------------------------------------------	

function FieldBitmapTile.getBitHelper( bitmap, i )	
	if bitmap <= 0 then
		return 0
	elseif bit32 ~= nil then
		return bit32.extract( bitmap, i, 1 )
	else
		if FieldBitmapTile.getBitHelperConstants == nil then
			FieldBitmapTile.getBitHelperConstants = {}
			for b=31,0,-1 do
				table.insert( FieldBitmapTile.getBitHelperConstants, { bit=b, value=2^b } )
			end
		end
		local v = bitmap
		for _,h in pairs(FieldBitmapTile.getBitHelperConstants) do
			if v >= h.value then
				if i > h.bit then
					return 0
				elseif i == h.bit then
					return 1
				end
				v = v - h.value 
			end
		end
		return 0
	end
	
	return math.floor( bitmap / 2^i ) % 2 > 0
end

------------------------------------------------------------------------
-- getBit
------------------------------------------------------------------------	
function FieldBitmapTile:getBit( x, z )
	local i, j = FieldBitmapTile.getIndex( self, x, z )	
	if not FieldBitmapTile.checkIndex( self, i, j ) then return false end
	
	local v = FieldBitmapTile.getBitHelper( self.bitmap[j], i )	
	--if bit32 ~= nil then
	--	v = bit32.extract( self.bitmap[j], i, 1 )
	--else
	--	v = math.floor( self.bitmap[j] / 2^i ) % 2
	--end
	
	local ret = 0 < v
	
	if self.invert then
		if ret then ret = false else ret = true end
	end
	
	return ret
end

------------------------------------------------------------------------
-- setBit
------------------------------------------------------------------------
function FieldBitmapTile:setBit( x, z, set )
	local i, j = FieldBitmapTile.getIndex( self, x, z )
	if not FieldBitmapTile.checkIndex( self, i, j ) then return false end

	if self.invert then
		if set == nil or set == true then set = false else set = true end
	end
	
	if set == nil or set == true then 
		if bit32 ~= nil then 
			self.bitmap[j] = bit32.replace( self.bitmap[j], 1, i, 1 )
	--elseif math.floor( self.bitmap[j] / 2^i ) % 2 < 1 then
		elseif FieldBitmapTile.getBitHelper( self.bitmap[j], i ) < 1 then
			self.bitmap[j] = self.bitmap[j] + 2^i
		end
	else
		if bit32 ~= nil then 
			self.bitmap[j] = bit32.replace( self.bitmap[j], 0, i, 1 )
	--elseif math.floor( self.bitmap[j] / 2^i ) % 2 > 0 then
		elseif FieldBitmapTile.getBitHelper( self.bitmap[j], i ) > 0 then
			self.bitmap[j] = self.bitmap[j] - 2^i
		end
	end
	
	return true
end

------------------------------------------------------------------------
-- FieldBitmap
------------------------------------------------------------------------
FieldBitmap = {}

------------------------------------------------------------------------
-- create
------------------------------------------------------------------------
function FieldBitmap.create( iStepLog2, tiles, bufferSize )
	local s = 5 - Utils.getNoNil( iStepLog2, 2 )

	local self = { tiles    = {}, 
								 stepLog2 = s, 
								 factor1  = 2^s, 
								 factor2  = 2^(-s) }
								 
	if bufferSize ~= nil and bufferSize > 0 then
		self.buffer   = {}
		self.index    = 0
		self.bSize    = bufferSize
	end
	
	if type( tiles ) == "table" then
		for i,t1 in pairs(tiles) do
			self.tiles[i] = {}
			for j,t2 in pairs(t1) do
				self.tiles[i][j] = FieldBitmapTile.clone( t2 )
			end
		end	
	end
------------------------------------------------------------------------
-- clone
------------------------------------------------------------------------
	local clone = function( )
		return FieldBitmap.create( 5 - self.stepLog2, self.tiles )
	end
	
------------------------------------------------------------------------
-- getTile
------------------------------------------------------------------------
	local getTile = function( x, z )
		return math.floor( self.factor2 * x ), math.floor( self.factor2 * z )
	end
	
------------------------------------------------------------------------
-- setBit
------------------------------------------------------------------------	
	local setBit = function( x, z, set )
		if self.buffer ~= nil then self.buffer = {} end
		local i, j = getTile( x, z )
		if self.tiles[i] == nil then
			if set ~= nil and set ~= true then return end
			self.tiles[i] = {}
		end
		if self.tiles[i][j] == nil then
			if set ~= nil and set ~= true then return end
			self.tiles[i][j] = FieldBitmapTile.getNewTile( self.factor1 * i, self.factor1 * j, 5 - self.stepLog2 )
		end
		FieldBitmapTile.setBit( self.tiles[i][j], x, z, set )
	end
	
------------------------------------------------------------------------
-- getBit
------------------------------------------------------------------------
	local getBit = function( x, z )
		local i, j = getTile( x, z )
		if self.tiles[i] == nil then return false end
		if self.tiles[i][j] == nil then return false end
		return FieldBitmapTile.getBit( self.tiles[i][j], x, z )
	end
	
------------------------------------------------------------------------
-- getBit
------------------------------------------------------------------------
	local getBitB = function( x, z )
		local i, j = getTile( x, z )
		if self.tiles[i] == nil then return false end
		if self.tiles[i][j] == nil then return false end
		
		if self.buffer ~= nil then
			for i,b in pairs( self.buffer ) do
				if b.x-0.01 < x and x < b.x+0.01 and b.z-0.01 < z and z < b.z+0.01 then
					return b.b
				end
			end
		end
		
		local b = FieldBitmapTile.getBit( self.tiles[i][j], x, z )
		
		if self.buffer ~= nil then
			if self.index >= self.bSize then
				self.index = 1
			else
				self.index = self.index + 1
			end	
			self.buffer[self.index] = { x=x, z=z, b=b }
		end
		
		return b
	end
	
------------------------------------------------------------------------
-- getPoints
------------------------------------------------------------------------
	local getPoints = function( )
		local points = {}
		for _,t1 in pairs(self.tiles) do
			for _,t2 in pairs(t1) do
				for j=1,32 do
					local z = ( j-1 ) * t2.stepInv + t2.startZ
					local n = t2.bitmap[j]
					local x
					for i=0,31 do
						if n<=0 then 
							if t2.invert then
								x = i * t2.stepInv + t2.startX
								table.insert( points, { x, z } )
							else
								break 
							end
						else
							local bit = ( n%2 > 0 )
							if bit then
								if not t2.invert then
									x = i * t2.stepInv + t2.startX
									table.insert( points, { x, z } )
								end
								n = n - 1
							elseif t2.invert then
								x = i * t2.stepInv + t2.startX
								table.insert( points, { x, z } )
							end
							n = n / 2
						end
					end
				end
			end
		end
		
		return points
	end

------------------------------------------------------------------------
-- tileExists
------------------------------------------------------------------------
	local tileExists = function( x, z )
		local i, j = getTile( x, z )
		if self.tiles[i] == nil then return false end
		if self.tiles[i][j] == nil then return false end
		return true
	end
	
------------------------------------------------------------------------
-- getTileDimensions
------------------------------------------------------------------------
	local getTileDimensions = function( x, z )
		local i, j = getTile( x, z )
		local startX = self.factor1 * i
		local startZ = self.factor1 * j
		local length = self.factor1 
		return startX, startZ, length
	end
	
------------------------------------------------------------------------
-- createOneTile
------------------------------------------------------------------------
	local createOneTile = function( x, z )
		if self.buffer ~= nil then self.buffer = {} end
		local i, j = getTile( x, z )
		
		if self.tiles[i] == nil then
			self.tiles[i] = {}
		end
		self.tiles[i][j] = FieldBitmapTile.getNewTile( self.factor1 * i, self.factor1 * j, 5 - self.stepLog2, nil, nil, true )
	end
	
------------------------------------------------------------------------
-- getPoint
------------------------------------------------------------------------
	local getPoint = function( iX, iZ )
		local f1 = 2^(self.stepLog2 - 5)
		local f2 = 2^(5 - self.stepLog2)
		local x = f1 * math.floor( f2 * iX + 0.5 )
		local z = f1 * math.floor( f2 * iZ + 0.5 )
		return x, z
	end
	
------------------------------------------------------------------------
-- getAreaTotalCount
------------------------------------------------------------------------
	local getAreaTotalCount = function( startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )
		local area  = 0
		local total = 0
	
		local minX = startWorldX
		local maxX = startWorldX
		local minZ = startWorldZ
		local maxZ = startWorldZ
		
		minX = math.min( minX, widthWorldX )
		maxX = math.max( maxX, widthWorldX )
		minZ = math.min( minZ, widthWorldZ )
		maxZ = math.max( maxZ, widthWorldZ )

		minX = math.min( minX, heightWorldX )
		maxX = math.max( maxX, heightWorldX )
		minZ = math.min( minZ, heightWorldZ )
		maxZ = math.max( maxZ, heightWorldZ )
		
		local x = widthWorldX + heightWorldX - startWorldX
		local z = widthWorldZ + heightWorldZ - startWorldZ

		minX = math.min( minX, x )
		maxX = math.max( maxX, x )
		minZ = math.min( minZ, z )
		maxZ = math.max( maxZ, z )
		
		local minI, minJ = getTile( minX, minZ )
		local maxI, maxJ = getTile( maxX, maxZ )
		
		
		local stepInv = 2 ^ (self.stepLog2 - 5)

		for curI=minI,maxI do
			for curJ=minJ,maxJ do
			
				local t2
				if self.tiles[curI] ~= nil then
					t2 = self.tiles[curI][curJ]
				else
					t2 = nil
				end
				
				local startX  = self.factor1 * curI
				local startZ  = self.factor1 * curJ

				for j=1,32 do
					z = ( j-1 ) * stepInv + startZ
					for i=0,31 do
						x = i * stepInv + startX
										
						if FieldBitmap.checkPointInParallelogram( x, z, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ ) then
							total = total + 1
							if t2 ~= nil and FieldBitmapTile.getBit( t2, x, z ) then
								area = area + 1
							end
						end
					end
				end
			end
		end
		
		return area, total 
	end
		
------------------------------------------------------------------------
-- cutArea
------------------------------------------------------------------------
	local cutArea = function( startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )
		if self.buffer ~= nil then self.buffer = {} end
		local minX = startWorldX
		local maxX = startWorldX
		local minZ = startWorldZ
		local maxZ = startWorldZ
		
		minX = math.min( minX, widthWorldX )
		maxX = math.max( maxX, widthWorldX )
		minZ = math.min( minZ, widthWorldZ )
		maxZ = math.max( maxZ, widthWorldZ )

		minX = math.min( minX, heightWorldX )
		maxX = math.max( maxX, heightWorldX )
		minZ = math.min( minZ, heightWorldZ )
		maxZ = math.max( maxZ, heightWorldZ )
		
		local x = widthWorldX + heightWorldX - startWorldX
		local z = widthWorldZ + heightWorldZ - startWorldZ

		minX = math.min( minX, x )
		maxX = math.max( maxX, x )
		minZ = math.min( minZ, z )
		maxZ = math.max( maxZ, z )
		
		local minI, minJ = getTile( minX, minZ )
		local maxI, maxJ = getTile( maxX, maxZ )
		
		
		local stepInv = 2 ^ (self.stepLog2 - 5)

		for curI=minI,maxI do
			for curJ=minJ,maxJ do
				if self.tiles[curI] ~= nil and self.tiles[curI][curJ] ~= nil then
					local t2 = self.tiles[curI][curJ]
				
					local startX  = self.factor1 * curI
					local startZ  = self.factor1 * curJ

					for j=1,32 do
						z = ( j-1 ) * stepInv + startZ
						for i=0,31 do
							x = i * stepInv + startX
											
							if FieldBitmap.checkPointInParallelogram( x, z, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ ) then
								FieldBitmapTile.setBit( t2, x, z, false )
							end
						end
					end
				end
			end
		end
		
	end
	
	local getBitFct = getBit 
	if self.buffer ~= nil then
		getBitFct = getBitB
	end
		
	-- Tile bounds are conservative and cheap: route planners must still use
	-- getBit for the actual outline. Do not materialize every field pixel.
	local getBounds = function()
		local x0,z0,x1,z1
		for _,row in pairs(self.tiles) do
			for _,tile in pairs(row) do
				local x,z=tile.startX,tile.startZ
				local size=32*tile.stepInv
				x0=math.min(x0 or x,x); z0=math.min(z0 or z,z)
				x1=math.max(x1 or x+size,x+size); z1=math.max(z1 or z+size,z+size)
			end
		end
		return x0,z0,x1,z1
	end
	return { setBit            = setBit,
					 getBounds         = getBounds,
					 getBit            = getBitFct, 
					 getPoints         = getPoints,
					 tileExists        = tileExists, 
					 getTileDimensions = getTileDimensions,
					 createOneTile     = createOneTile,
					 getPoint          = getPoint,
					 getAreaTotalCount = getAreaTotalCount,
					 cutArea           = cutArea,
					 clone             = clone }
end

------------------------------------------------------------------------
-- prepareIsField
------------------------------------------------------------------------
function FieldBitmap.resolveFS25TerrainDetail()
	if g_currentMission == nil then
		return nil, 0, 0
	end
	if g_currentMission.terrainDetailId ~= nil and g_currentMission.terrainDetailId ~= 0 then
		return g_currentMission.terrainDetailId,
		       g_currentMission.terrainDetailTypeFirstChannel or 0,
		       g_currentMission.terrainDetailTypeNumChannels or 4
	end
	if g_currentMission.fieldGroundSystem ~= nil then
		local fgs = g_currentMission.fieldGroundSystem
		if type(fgs.getDensityMapData) == "function" and FieldDensityMap ~= nil and FieldDensityMap.GROUND_TYPE ~= nil then
			local ok, mapId, firstCh, numCh = pcall(fgs.getDensityMapData, fgs, FieldDensityMap.GROUND_TYPE)
			if ok and mapId ~= nil and mapId ~= 0 then
				return mapId, firstCh or 0, numCh or 4
			end
		end
		if fgs.fieldGroundId ~= nil and fgs.fieldGroundId ~= 0 then
			return fgs.fieldGroundId, fgs.firstChannel or 0, fgs.numChannels or 4
		end
	end
	return nil, 0, 0
end

function FieldBitmap.prepareIsField( )
	if FieldBitmap.fieldMod == nil and g_currentMission ~= nil and DensityMapModifier ~= nil then
		local mapId, firstCh, numCh = FieldBitmap.resolveFS25TerrainDetail()
		if mapId ~= nil and mapId ~= 0 then
			local ok, mod = pcall(function()
				if g_currentMission.terrainRootNode ~= nil then
					return DensityMapModifier.new(mapId, firstCh, numCh, g_currentMission.terrainRootNode)
				end
				return DensityMapModifier.new(mapId, firstCh, numCh)
			end)
			if not ok or mod == nil then
				ok, mod = pcall(function() return DensityMapModifier.new(mapId, firstCh, numCh) end)
			end
			if ok and mod ~= nil and DensityMapFilter ~= nil then
				local okF, flt = pcall(function() return DensityMapFilter.new(mod) end)
				if okF and flt ~= nil then
					FieldBitmap.fieldMod = {
						modifier = mod,
						filter   = flt
					}
					pcall(function() FieldBitmap.fieldMod.filter:setValueCompareParams(DensityValueCompareType.GREATER, 0) end)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- getAreaTotal
------------------------------------------------------------------------
function FieldBitmap.getAreaTotal( startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )
	FieldBitmap.prepareIsField( )
	if FieldBitmap.fieldMod ~= nil and FieldBitmap.fieldMod.modifier ~= nil and FieldBitmap.fieldMod.filter ~= nil then
		FieldBitmap.fieldMod.modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, DensityCoordType.POINT_POINT_POINT)
		FieldBitmap.fieldMod.filter:setValueCompareParams(DensityValueCompareType.GREATER, 0)

		local _, area, totalArea = FieldBitmap.fieldMod.modifier:executeGet(FieldBitmap.fieldMod.filter)
		return area or 0, totalArea or 0
	end
	if g_currentMission ~= nil and g_currentMission.fieldCropsQuery ~= nil then
		local x, z, widthX, widthZ, heightX, heightZ = MathUtil.getXZWidthAndHeight(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
		local ok, area, totalArea = pcall(function()
			return g_currentMission.fieldCropsQuery:getParallelogram(x, z, widthX, widthZ, heightX, heightZ, true)
		end)
		if ok and area ~= nil then
			return area, totalArea
		end
	end
	return 0, 0
end

------------------------------------------------------------------------
-- isFieldFast
------------------------------------------------------------------------
function FieldBitmap.isFieldFast( startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )
  local area,totalArea = FieldBitmap.getAreaTotal( startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )
	return area > 0
end

------------------------------------------------------------------------
-- isField
------------------------------------------------------------------------
function FieldBitmap.isField( startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )
  local area,totalArea = FieldBitmap.getAreaTotal( startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )
	return area > 0
end

------------------------------------------------------------------------
-- getParallelogram
------------------------------------------------------------------------
function FieldBitmap.getParallelogram( x, z, size, ofs )
	return x-ofs, z-ofs, x+size, z, x, z+size
end

------------------------------------------------------------------------
-- cleanupAfterIsField
------------------------------------------------------------------------
function FieldBitmap.cleanupAfterIsField( )
end

------------------------------------------------------------------------
-- checkPointInParallelogram
------------------------------------------------------------------------
function FieldBitmap.checkPointInParallelogram( px, pz, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ )

	local x2 = widthWorldX  - startWorldX
	local z2 = widthWorldZ  - startWorldZ
	local x3 = heightWorldX - startWorldX
	local z3 = heightWorldZ - startWorldZ
	local x1 = px           - startWorldX
	local z1 = pz           - startWorldZ
	
	local bz = z2 * x1 - x2 * z1
	local bn = z2 * x3 - x2 * z3
	
	if     bz == 0
			or ( 0 < bz and bz <= bn )
			or ( 0 > bz and bz >= bn ) then
		local az = z3 * x1 - x3 * z1
		local an = z3 * x2 - x3 * z2
		if     az == 0
				or ( 0 < az and az <= an )
				or ( 0 > az and az >= an ) then
			return true
		end
	end
	
	return false
end

------------------------------------------------------------------------
-- createForFieldAtWorldPositionSimple
------------------------------------------------------------------------
-- Immediate entry points are kept for callers that need the complete bitmap.
function FieldBitmap.createForFieldAtWorldPositionSimple(iX, iZ, iStepLog2, iOverlap, iCheckFunction)
	return FieldBitmap.beginForFieldAtWorldPositionSimple(iX, iZ, iStepLog2, iOverlap, iCheckFunction).resume(0)
end

function FieldBitmap.createForFieldAtWorldPosition(iX, iZ, iStepLog2, iOverlap, iAreaTotalFunction, iPrepareFunction, iCleanupFunction)
	return FieldBitmap.beginForFieldAtWorldPosition(iX, iZ, iStepLog2, iOverlap, iAreaTotalFunction, iPrepareFunction, iCleanupFunction).resume(0)
end

function FieldBitmap.beginForFieldAtWorldPositionSimple(iX, iZ, iStepLog2, iOverlap, iCheckFunction)
	if iCheckFunction == nil or iCheckFunction == FieldBitmap.isFieldFast then
		return FieldBitmap.beginForFieldAtWorldPosition(iX, iZ, iStepLog2, iOverlap)
	end
	local function areaTotalFunction(...)
		if iCheckFunction(...) then return 1, 2 end
		return 0, 2
	end
	return FieldBitmap.beginForFieldAtWorldPosition(iX, iZ, iStepLog2, iOverlap, areaTotalFunction)
end

function FieldBitmap.beginForFieldAtWorldPosition( iX, iZ, iStepLog2, iOverlap, iAreaTotalFunction, iPrepareFunction, iCleanupFunction )

	local field, done, f1, f2
	if iAreaTotalFunction == nil then
		iAreaTotalFunction = FieldBitmap.getAreaTotal
		iPrepareFunction   = FieldBitmap.prepareIsField
		iCleanupFunction   = FieldBitmap.cleanupAfterIsField
	end
	
	if iStepLog2 == nil or iStepLog2 == 2 then
		f1 = 0.25
		f2 = 4
	else
		f1 = 2^(-iStepLog2)
		f2 = 2^(iStepLog2)
	end
	local f3 = f1 * 0.5
	
	local fo1,fo3 = f1,f3
	if iOverlap ~= nil then 
		fo1 = fo1 * iOverlap
		fo3 = fo3 * iOverlap
	end

	if iPrepareFunction ~= nil then
		iPrepareFunction( )
	end
	
	if iAreaTotalFunction( FieldBitmap.getParallelogram( iX, iZ, fo1, fo3 ) ) <= 0 then 
		if iCleanupFunction ~= nil then
			iCleanupFunction( )
		end
		return { isFinished = true, resume = function() return nil, 0 end }
	end

	field = FieldBitmap.create( iStepLog2 )
	done  = FieldBitmap.create( iStepLog2 )
	
	local x = f1 * math.floor( f2 * iX + 0.5 )
	local z = f1 * math.floor( f2 * iZ + 0.5 )
	local x1, z1, l1
	
	local lists = {}
	local cur, nxt = 1,2
	lists[1] = { { x, z } }
	lists[2] = {}
	
	done.setBit( x, z )
	
	local pointIndex = 1
	local task = { isFinished = false }
	local sqrm  = 0
	local sumX  = 0
	local sumZ  = 0
	local skip  = false
	local a,t

	-- FS25 does not expose coroutine in the mod sandbox. Each resume processes
	-- at most stepLimit frontier points and releases density-map state before returning.
	if iCleanupFunction ~= nil then iCleanupFunction() end
	local function resume(stepLimit)
		if task.isFinished then
			return field, sqrm*f1*f1*0.0001, sumX / math.max(1, sqrm), sumZ / math.max(1, sqrm)
		end
		if iPrepareFunction ~= nil then iPrepareFunction() end
		local count = 0
		while #lists[cur] > 0 do
			while pointIndex <= #lists[cur] do
				if stepLimit ~= nil and stepLimit > 0 and count >= stepLimit then
					if iCleanupFunction ~= nil then iCleanupFunction() end
					return nil, sqrm*f1*f1*0.0001, sumX / math.max(1, sqrm), sumZ / math.max(1, sqrm)
				end
				local p = lists[cur][pointIndex]
				pointIndex = pointIndex + 1
				count = count + 1
				x, z = unpack(p)
				skip = false
				if not field.tileExists( x, z ) then
					x1, z1, l1 = field.getTileDimensions( x, z )
					a, t = iAreaTotalFunction( FieldBitmap.getParallelogram( x1, z1, l1, fo3 ) )
					if     a == 0 then
						skip = true
						done.createOneTile( x, z )
					elseif a == t then
						skip = true
						done.createOneTile( x, z )
						field.createOneTile( x, z )
						sqrm = sqrm + 1024
						sumX = sumX + 1024 * (x1 + 0.5 * (l1 - f1)) 
						sumZ = sumZ + 1024 * (z1 + 0.5 * (l1 - f1)) 
	
						x = x1
						z = z1
	
						x1 = x-f1; z1 = z;    if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
						x1 = x+l1; z1 = z;    if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
						x1 = x;    z1 = z-f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
						x1 = x;    z1 = z+l1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
						x1 = x-f1; z1 = z-f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
						x1 = x+l1; z1 = z-f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
						x1 = x-f1; z1 = z+l1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
						x1 = x+l1; z1 = z+l1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					end
				end
	
				if not skip and iAreaTotalFunction( FieldBitmap.getParallelogram( x, z, fo1, fo3 ) ) > 0 then
					field.setBit( x, z )
					x1 = x-f1; z1 = z;    if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					x1 = x+f1; z1 = z;    if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					x1 = x;    z1 = z-f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					x1 = x;    z1 = z+f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					x1 = x-f1; z1 = z-f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					x1 = x+f1; z1 = z-f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					x1 = x-f1; z1 = z+f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					x1 = x+f1; z1 = z+f1; if not done.getBit( x1, z1 ) then done.setBit( x1, z1 ) table.insert( lists[nxt], { x1, z1 } ) end
					sqrm = sqrm + 1
					sumX = sumX + x 
					sumZ = sumZ + z 
				end
			end
			cur, nxt = nxt, cur
			lists[nxt] = {}
			pointIndex = 1
		end
		if iCleanupFunction ~= nil then iCleanupFunction() end
		task.isFinished = true
		return field, sqrm*f1*f1*0.0001, sumX / math.max(1, sqrm), sumZ / math.max(1, sqrm)
	end
	task.resume = resume
	return task
end


------------------------------------------------------------------------
-- unitTest(s)
------------------------------------------------------------------------
local function unitTest1( )
	print("------------------------------------------------------------------------")
	
	local tileTest = FieldBitmapTile.getNewTile( 10, 5, 2, nil, nil, true )
	
	print(tostring( tileTest.size ))
	print(tostring( tileTest.sizeInt ))
	print(tostring( tileTest.step ))
	print(tostring( tileTest.startX ))
	print(tostring( tileTest.startZ ))
	print(tostring( tileTest.endX ))
	print(tostring( tileTest.endZ ))
  
	FieldBitmapTile.setBit( tileTest, 17.75, 12.75, false )
	print(tostring( FieldBitmapTile.getBit( tileTest, 17.75, 12.75 ) ))
	FieldBitmapTile.setBit( tileTest, 18, 13, false )
	print(tostring( FieldBitmapTile.getBit( tileTest, 18, 13 ) ))
	
	FieldBitmapTile.setBit( tileTest, 10, 5, false )
	print(tostring( FieldBitmapTile.getBit( tileTest, 10, 5 ) ))
	FieldBitmapTile.setBit( tileTest, 9.75, 4.75, false )
	print(tostring( FieldBitmapTile.getBit( tileTest, 9.75, 4.75 ) ))
	
	print(tostring( FieldBitmapTile.getBit( tileTest, 11, 11 ) ))
	FieldBitmapTile.setBit( tileTest, 11, 11, false )
  
	print("------------------------------------------------------------------------")
	
	for i=-3,3 do for j=-3,3 do
		local x = 11 + tileTest.stepInv * i
		local z = 11 + tileTest.stepInv * j
		print(tostring(x).." "..tostring(z).." "..tostring( FieldBitmapTile.getBit( tileTest, x, z ) ))
	end end
  
	print("------------------------------------------------------------------------")
  
	FieldBitmapTile.setBit( tileTest, 11, 11, true )
	print(tostring( FieldBitmapTile.getBit( tileTest, 11, 11 ) ))
	
	print("------------------------------------------------------------------------")
end

local function unitTest2( )
	print("------------------------------------------------------------------------")
	
	local x0,z0 = -134.750, 12.750
	local map = FieldBitmap.create( )
	local stepInv = 2 ^ (-2)
	
	
	map.setBit( x0, z0 )
	for i=-3,3 do for j=-3,3 do
		local x = x0 + stepInv * i
		local z = z0 + stepInv * j
		print(tostring(x).." "..tostring(z).." "..tostring( map.getBit( x, z ) ))
	end end

	local map2 = FieldBitmap.create( )
	print(tostring( map.getBit( x0, z0 ) ))
	print(tostring( map2.getBit( x0, z0 ) ))

	map.setBit( x0, z0, false )
	print(tostring( map.getBit( x0, z0 ) ))
	print(tostring( map2.getBit( x0, z0 ) ))

	map2.setBit( x0, z0 )
	print(tostring( map.getBit( x0, z0 ) ))
	print(tostring( map2.getBit( x0, z0 ) ))

	print("------------------------------------------------------------------------")
	
	print("------------------------------------------------------------------------")
	
	local x0,z0 = -134.750, 12.750
	local map = FieldBitmap.create( 3 )
	
	map.setBit( x0, z0 )
	for i=-3,3 do for j=-3,3 do
		local x = x0 + stepInv * i
		local z = z0 + stepInv * j
		print(tostring(x).." "..tostring(z).." "..tostring( map.getBit( x, z ) ))
	end end

	local map2 = FieldBitmap.create( 3 )
	print(tostring( map.getBit( x0, z0 ) ))
	print(tostring( map2.getBit( x0, z0 ) ))

	map.setBit( x0, z0, false )
	print(tostring( map.getBit( x0, z0 ) ))
	print(tostring( map2.getBit( x0, z0 ) ))

	map2.setBit( x0, z0 )
	print(tostring( map.getBit( x0, z0 ) ))
	print(tostring( map2.getBit( x0, z0 ) ))

	print("------------------------------------------------------------------------")
end

--unitTest1( )
--unitTest2( )


