-- API to read and write database records
local addonName, addon, _ = ...

local bonusSortTable = {}
local function FillBonusTable(bonusID) table.insert(bonusSortTable, tonumber(bonusID)) end
local function GetSortedBonus(bonusIDs)
	if not bonusIDs	or bonusIDs == '' then return '' end
	wipe(bonusSortTable)
	bonusIDs:gsub('[^:]+', FillBonusTable)
	table.sort(bonusSortTable)
	return table.concat(bonusSortTable, ':')
end

local emptyTable = {}
local function Get(itemID, bonusIDs)
	local sortedBonus = GetSortedBonus(bonusIDs)
	local data = addon.db.realm.scanData[itemID]
	local value, count = 0, 0
	for bonus, dataSet in pairs(data or emptyTable) do
		local dataValue, dataCount = strsplit(':', values)
		if bonus == sortedBonus then
			return dataValue, dataCount
		else
			-- TODO: get some kind of average value
			value = (value + dataValue) / 2
			count = count + dataCount
		end
	end
	return value, count, true
end

local function Set(itemID, bonusIDs, price, count)
	local sortedBonus = GetSortedBonus(bonusIDs)
	local data = addon.db.realm.scanData[itemID]
	if not data then
		addon.db.realm.scanData[itemID] = {}
		data = addon.db.realm.scanData[itemID]
		if not data[sortedBonus] then data[sortedBonus] = {} end
	end
	local normalizedTime = addon.GetNormalizedTimeStamp(time())
	data[sortedBonus][normalizedTime] = strjoin('|', price, count)
end

--[[-- "top 95%" / sd / sta/lta
.lastScan = timestamp
[itemID] = {
	[''] = { -- no bonus ids
		[timestamp] = 'price|count',
	}
	['bonus1:bonus2:bonus3'] = {
		[timestamp] = 'price|count',
	}
}
[-speciesID] = {
	['quality:level'] = { ... },
} --]]


--[[-- current example data:
[10106] = { -- itemID
	[-9] = { -- suffixID
		["history"] = {
			[1382958000] = 990000,
			[1381831200] = 990000,
			[1383044400] = 990000,
		},
		["time"] = 1415842958,
		["seen"] = 15,
		["price"] = 250000,
		["count"] = 6,
	},
},
[-1335] = { -- -1*battlePetSpeciesID
	[3] = { -- quality
		{   -- level
			["history"] = {
				[1413453600] = 29989999,
			},
			["time"] = 1415842960,
			["seen"] = 117,
			["count"] = 7,
			["price"] = 8490000,
		}, -- [1]
		[4] = {
			["seen"] = 2,
			["history"] = {
				[1380535200] = 200000000,
				[1380621600] = 200000000,
			},
			["count"] = 0,
		},
	},
},
--]]

-- [x] keep scan data at most X days
-- [ ] keep at most Y data entries for each item / keep only entries that differ no more than Z from the average price / clean time based data?
function addon:Purge()
	-- TODO: purge post history
	local historyThreshold = time() - 60*60*24 * addon.db.profile.lifeSpan
	for itemID, prices in pairs(addon.db.realm.scanData) do
		for bonus, values in pairs(prices) do
			for timestamp, priceData in pairs(values) do
				if timestamp < historyThreshold then
					-- data is outdated
					values[timestamp] = nil
				end
			end
			if not next(values) then
				-- remove empty bonus groups
				values[bonus] = nil
			end
		end
		if not next(prices) then
			-- remove empty items
			addon.db.realm.scanData[itemID] = nil
		end
	end
end
