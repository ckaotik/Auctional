local _, ns = ...
-- GLOBALS: GetAuctionBuyout, GetDisenchantValue, GetItemInfo
-- GLOBALS: type, pairs, wipe, select

local LIC = LibStub("LibItemCrush-1.0")

-- returns live/history/averaged price, numAvailable or numSimilarConsideredItems
-- runs through database (sub)tables, if need be recursively, to find somewhat usable data
local function GetTableData(dataHandle, useHistory)
	if not dataHandle or type(dataHandle) ~= "table" then return end
	local usedPrice, count

	if not dataHandle.price and not dataHandle.history then
		-- table might have additional levels, let's check them
		local subPrice, subCount
		for sub, _ in pairs(dataHandle) do
			subPrice, subCount = GetTableData(dataHandle[sub], useHistory)
			if subPrice and subCount then
				usedPrice = (usedPrice or 0) + subPrice*subCount
				count = (count or 0) + subCount
			end
		end
		usedPrice = usedPrice and usedPrice / count

	elseif type(useHistory) == "number" then
		-- get data from a specific point in time, e.g. for displaying graphs
		usedPrice = dataHandle.history and dataHandle.history[useHistory]
		count = nil

	elseif useHistory or (useHistory ~= false and not dataHandle.price) then
		-- no live data or allowed to use history data
		local usedTime
		count = nil
		for time, price in pairs(dataHandle.history or {}) do
			if not usedTime or time > usedTime then
				usedPrice = price
				usedTime = time
			end
		end

	else
		usedPrice = dataHandle.price
		count = dataHandle.count
	end
	return usedPrice, count
end

function ns.GetAuctionState(itemLink)
	local itemID, special, battlePetLevel = ns.GetItemLinkData(itemLink)
	if not itemID then return end
	local currentPrice, fallbackCount, minPrice, maxPrice = ns:GetAuctionValue(itemID, special, nil, battlePetLevel)
	local previousPrice = ns:GetAuctionValue(itemID, special, true, battlePetLevel)
	if currentPrice == previousPrice then previousPrice = nil end

	return currentPrice, fallbackCount, previousPrice, minPrice, maxPrice
end

-- returns itemPrice, numAvailable -or- numSimilarConsideredItems, similarItemsMinprice, similarItemsMaxPrice
--[[ useHistory ::
		nil : use live data if available or history data otherwise
		true: use history data, don't use live data
		*false: use live data, don't fallback to history [TODO]
		date (number): use history data of date, don't use any other data
--]]
function ns:GetAuctionValue(itemID, special, useHistory, battlePetLevel)
	if not itemID or not ns.DB[itemID] then return end
	local dataHandle = ns.DB[itemID]
	if itemID < 0 and special then
		-- battle pets have an additional data level
		if ns.DB[itemID][special] then
			dataHandle = ns.DB[itemID][special]
			special = battlePetLevel
		else
			special = nil
		end
	end

	local myPrice, minPrice, maxPrice, count
	if (not special and dataHandle.seen) or dataHandle[special] then
		-- regular items + suffixed items w/ data
		dataHandle = special and dataHandle[special] or dataHandle
		myPrice, count = GetTableData(dataHandle, useHistory)
	else
		-- raw suffixed items + suffixed items w/o data
		local subPrice, subCount
		for subID, subData in pairs(dataHandle) do
			subPrice, subCount = GetTableData(subData, useHistory)
			if subPrice then
				myPrice = (myPrice or 0) + subPrice
				count = (count or 0) + (subCount or 1)
				if not minPrice or subPrice < minPrice then minPrice = subPrice end
				if not maxPrice or subPrice > maxPrice then maxPrice = subPrice end
			end
		end
		myPrice = myPrice and myPrice/count or nil
	end
	return myPrice, count, minPrice, maxPrice
end
--[[ function ns:GetAuctionValue_new(itemID, useHistory, ...)
	if not itemID or not ns.DB[itemID] then return end

	local dataHandle = ns.DB[itemID]
	local subLevels = select('#', ...)
	local subHandle, value, count

	if subLevels > 0 then
		for currentLevel = 1, subLevels do
			subHandle = dataHandle[ (select(currentLevel, ...)) ]
			if subHandle then dataHandle = subHandle
			else break
			end
		end
	end

	if dataHandle.seen then
		value, count = GetTableData(dataHandle, useHistory)
	else
		value, count, minPrice, maxPrice = GetTableData(dataHandle, useHistory)
	end
end --]]

function ns:GetAuctionBuyout(item, when)
	local myPrice
	if type(item) == "number" then
		myPrice = ns:GetAuctionValue(item, nil, when)
	elseif type(item) == "table" then
		myPrice = ns:GetAuctionValue(item.itemID or item.itemid or item.itemId or item.id, nil, when)
	else
		_, item = GetItemInfo(item)
		local item, special, battlePetLevel = ns.GetItemLinkData( item )
		myPrice = ns:GetAuctionValue(item, special, when, battlePetLevel)
	end

	return myPrice
end

local DISENCHANT = GetSpellInfo(13262)
function ns:GetCrushValue(item, when)
	local crushType = LIC:GetCrushType(item)
	if not crushType then return end

	local myPrice
	local results = { LIC:GetPossibleCrushs(item) }
	local item, countText, chanceText, count, chance, value
	for i = 1,#results, 5 do
		item, count, chance = results[i], results[i+3], results[i+4]

		value = item and ns:GetAuctionBuyout(item, when)
		if chance and count and value then
			myPrice = (myPrice or 0) + (count * chance * value)
		end
	end
	wipe(results)
	results = nil

	if crushType ~= DISENCHANT and myPrice then
		myPrice = myPrice / 5
	end

	return myPrice, crushType
end

function ns:GetDisenchantValue(item, when)
	local myPrice

	local disenchants = { LIC:GetPossibleDisenchants(item) }
	local item, countText, chanceText, count, chance, deValue
	for i = 1,#disenchants, 5 do
		item, countText, chanceText, count, chance = disenchants[i], disenchants[i+1], disenchants[i+2], disenchants[i+3], disenchants[i+4]

		deValue = item and ns:GetAuctionBuyout(item, when)
		if chance and count and deValue then
			myPrice = (myPrice or 0) + (count * chance * deValue)
		end
	end
	wipe(disenchants)
	disenchants = nil

	return myPrice
end

--[[ API as suggested by Tekkub. Uses our own Auctional:foo implementations ]]--
local origGetAuctionBuyout = GetAuctionBuyout
function GetAuctionBuyout(item)
	local myPrice = ns:GetAuctionBuyout(item)
	return myPrice or (origGetAuctionBuyout and origGetAuctionBuyout(item));
end

local origGetDisenchantValue = GetDisenchantValue
function GetDisenchantValue(item)
	local myPrice = ns:GetDisenchantValue(item)
	return myPrice or (origGetDisenchantValue and origGetDisenchantValue(item))
end
