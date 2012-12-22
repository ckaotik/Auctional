local addonName, ns, _ = ...
addonName = "|cffFFC240"..addonName.."|r"
-- GLOBALS: AuctionalGDB, GameTooltip, BattlePetTooltip, DEFAULT_CHAT_FRAME, C_PetJournal
-- GLOBALS: GetItemInfo, GetSpellLink, BattlePetToolTip_Show
-- GLOBALS: join, pairs, tostringall, setmetatable, getmetatable, strsplit, unpack, tonumber, type, select, format, date, time
local trim = string.trim

function ns.ShowTooltip(frame, link, anchor)
	frame = frame or ns
	anchor = anchor or "ANCHOR_CURSOR" -- ANCHOR_TOPLEFT

	if type(link) == "number" then
		if link > 0 then
			_, link = GetItemInfo(link)
		else
			link = GetSpellLink(link)
		end
	end

	local linktype, id, data = ns.GetLinkData(link)
	if not linktype then
		-- plain text
		link = link or frame.tiptext
		if not link then return end

		GameTooltip:SetOwner(frame, anchor)
		GameTooltip:SetText(link, nil, nil, nil, nil, true)
		GameTooltip:Show()
	elseif linktype == "battlepet" then
		data = { strsplit(":", data) }
		for k,v in pairs(data) do
			data[k] = tonumber(v)
		end

		GameTooltip:SetOwner(frame, anchor)
		local level, breedQuality, maxHealth, power, speed, name = unpack(data)
		BattlePetToolTip_Show(id, tonumber(level), tonumber(breedQuality), tonumber(maxHealth), tonumber(power), tonumber(speed), name)
	else
		GameTooltip:SetOwner(frame, anchor)
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end
end
function ns.HideTooltip()
	GameTooltip:Hide()
	BattlePetTooltip:Hide()
end

-- == Item Functions ==
function ns.GetLinkData(link)
	if not link or type(link) ~= "string" then return end
	local linkType, id, data = link:match("^.-H([^:]+):?([^:]*):?([^|]*)")
	return linkType, tonumber(id), data
end

function ns.GetItemLinkData(link)
	if not link or type(link) ~= "string" then return end
	local linkType, itemID, data = ns.GetLinkData(link)

	local special, petLevel
	if linkType == "battlepet" then
		itemID = -1 * itemID
		petLevel, special = strsplit(':', data) -- get pet quality
		special = special and tonumber(special) or nil
		petLevel = petLevel and tonumber(petLevel) or nil
	else
		_, _, _, _, _, special = strsplit(':', data)
		special = (special and special ~= "0") and tonumber(special) or nil
	end
	return itemID, special, petLevel
end

local battlePet = select(11, GetAuctionItemClasses())
function ns.GetItemInfo(link)
	if not link then return end
	local linkType, itemID, data = ns.GetLinkData(link)

	if linkType == "battlepet" then
		local name, texture, subClass, companionID = C_PetJournal.GetPetInfoBySpeciesID( itemID )
		local level, quality, health, attack, speed = strsplit(':', data)

		-- including some static values for battle pets
		return name, trim(link), tonumber(quality), tonumber(level), 0, battlePet, tonumber(subClass), 1, "", texture, nil, companionID, tonumber(health), tonumber(attack), tonumber(speed)
	elseif linkType == "item" then
		return GetItemInfo( itemID )
	end
end

-- == Output Functions ==
function ns.Print(text, ...)
	if select('#', ...) > 0 then
		text = format(text, ...)
	end
	DEFAULT_CHAT_FRAME:AddMessage(addonName.." "..text)
end

local dayDate = {year = 1970, month = 1, day = 1}
function ns.GetNormalizedTimeStamp(myTime)
	dayDate.month, dayDate.day, dayDate.year = strsplit('/', date("%m/%d/%Y", myTime))
	return time(dayDate)
end

-- prints debug messages only when debug mode is active
function ns.Debug(...)
	if AuctionalGDB and AuctionalGDB.debug then
		ns.Print("! "..join(", ", tostringall(...)))
	end
end

function ns:SetColumns(frame, ...)
end
function ns:SetColumnsTitles(...)
end
function ns:SetRow(frame, index, ...)
end

-- == Table Functions ==
function ns.Find(table, value)
	if not table or not value then return end
	for k, v in pairs(table) do
		if (v == value) then return k end
	end
	return false
end

-- counts table entries. for numerically indexed tables, use #table
function ns.Count(table)
	if not table then return 0 end
	local i = 0
	for _, _ in pairs(table) do
		i = i + 1
	end
	return i
end
function ns.GetTableCopy(t)
	local u = { }
	for k, v in pairs(t) do u[k] = v end
	return setmetatable(u, getmetatable(t))
end

function ns.WalkDataTable(dataSet, handler)
	for itemID, dataHandle in pairs(dataSet) do
		ns.WalkDataTableEntry(dataHandle, handler, itemID)
	end
end
function ns.WalkDataTableEntry(dataHandle, handler, itemID)
	if dataHandle.price then
		-- regular item
		handler(dataHandle, itemID)
	elseif itemID > 0 then
		-- special item
		for special, subData in pairs(dataHandle) do
			if type(subData) == "table" and subData.price then
				handler(subData, itemID, special)
			end
		end
	else
		-- battle pet
		for special, data in pairs(dataHandle) do
			for petLevel, subData in pairs(data) do
				if type(subData) == "table" and subData.price then
					handler(subData, itemID, special, petLevel)
				end
			end
		end
	end
end
