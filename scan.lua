local _, ns = ...
-- GLOBALS: _G, AuctionalDB, AuctionFrame, AuctionFrameBrowse, BrowseName
-- GLOBALS: CreateFrame, hooksecurefunc, GetAuctionItemInfo, GetAuctionItemLink, CanSendAuctionQuery, QueryAuctionItems, GetNumAuctionItems, NUM_AUCTION_ITEMS_PER_PAGE, AuctionFrameFilter_OnClick
-- GLOBALS: time, type, pairs, date, strsplit, select, wipe, table
local floor = math.floor
local min = math.min
local huge = math.huge

local scan = {}
ns.scan = scan

scan.history = {}

--[[-- SavedVariables Management --]]--
local function Stash(dataHandle)
	if not dataHandle.history then
		dataHandle.history = {}
	end
	local timeStamp = ns.GetNormalizedTimeStamp(dataHandle.time)
	if dataHandle.history[ timeStamp ] then
		-- merge existing data for that day via unweighted average
		dataHandle.price = (dataHandle.history[ timeStamp ] + dataHandle.price) / 2
	end
	dataHandle.history[ timeStamp ] = dataHandle.price
	dataHandle.time = nil
	dataHandle.price = nil
	dataHandle.count = 0
end
local function StashPreviousData(onlyItemID)
	if onlyItemID then
		ns.WalkDataTableEntry(ns.DB[onlyItemID], Stash, onlyItemID)
	else
		ns.WalkDataTable(ns.DB, Stash)
	end
end

--[[-- UI Things --]]--
function scan.ShowLoading(r, g, b)
	scan.SetSpinnerColor(r, g, b)

	scan.loading.FadeIn:Play()
	scan.loading.Loop:Play()
	scan.loading:Show()
end
function scan.HideLoading()
	local alpha
	if scan.loading.FadeIn:IsPlaying() then
		alpha = scan.loading:GetAlpha()
		scan.loading.FadeIn:Stop()
		scan.loading:SetAlpha(alpha)
	end
	scan.loading.FadeOut:Play()
end

--[[-- Scan Management --]]--
local lastScanIndex, batchSize, totalAuctions = 0, 0, 0
local statistics, currentQueryArgs = {}, {}
scan.data = {}

local function UpdateItem(list, index)
	local name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemId, hasAllInfo = GetAuctionItemInfo(list, index)
	local itemLink = GetAuctionItemLink(list, index)
	local itemID, special, petLevel = ns.GetItemLinkData(itemLink) -- this actually overrides battle pet containers' ids

	if scan.callback and (not scan.filter or itemID == scan.filter) then
		if not scan.data[itemID] then
			scan.data[itemID] = {}
			-- stash old data as we're finding all there currently is
			StashPreviousData(itemID)
		end
		table.insert(scan.data[itemID], {itemLink, count, minBid, buyoutPrice, highBidder, owner})
	elseif not quality or quality < AuctionalDB.minQuality then
		-- skip low quality items, but still enable explicit scans of these
		statistics['invalid'] = (statistics['invalid'] or 0) + 1
		return
	end

	if not ns.DB[itemID] then ns.DB[itemID] = {} end
	if special and not ns.DB[itemID][special] then ns.DB[itemID][special] = {} end
	if petLevel and not ns.DB[itemID][special][petLevel] then ns.DB[itemID][special][petLevel] = {} end

	local dataHandle = petLevel and ns.DB[itemID][special][petLevel]
		or special and ns.DB[itemID][special]
		or ns.DB[itemID]

	local auctionPrice = min(
		buyoutPrice > 0 and buyoutPrice/count or huge,
		(buyoutPrice == 0 and minBid > 0) and minBid/count*AuctionalDB.bidOnlyFactor or huge,
		dataHandle.price or huge
	)
	-- skip weird entries ...
	if auctionPrice == huge or auctionPrice == 0 then return true end
	auctionPrice = auctionPrice > 1 and floor(auctionPrice) or 1
	-- [TODO] add some kind of reasonable outlier detection

	-- save all this data!
	dataHandle.time = time()
	dataHandle.price = auctionPrice
	-- if dataHandle.price < 1 then print("OOOPS!", name, auctionPrice, dataHandle.price) end
	if not scan.isMultiPage or scan.isFullScan then
		-- we know all there is to this item, let's update
		dataHandle.count = (dataHandle.count or 0) + count
	elseif not dataHandle.count or dataHandle.count < count then
		-- we have at least this many to offer
		dataHandle.count = count
	end
	if not scan.isMultiPage or not dataHandle.seen then
		dataHandle.seen = (dataHandle.seen or 0) + count
	end

	return hasAllInfo
end
local function UpdateDataBatch()
	for i=1, AuctionalDB.actionsPerFrame do
		if lastScanIndex + i > batchSize then
			scan.ScanCompleted(batchSize)
			break
		end
		UpdateItem("list", lastScanIndex+i)
	end
	lastScanIndex = lastScanIndex + AuctionalDB.actionsPerFrame
end
function ns:AUCTION_ITEM_LIST_UPDATE()
	-- we don't want any interference. listener will be restarted on the next query
	ns:UnregisterEvent('AUCTION_ITEM_LIST_UPDATE')
	scan.SetSpinnerColor()

	lastScanIndex = 0
	batchSize, totalAuctions = GetNumAuctionItems("list")
	if scan.isFullScan then
		if batchSize ~= totalAuctions then -- Blizzard bug
			scan.ScanCompleted(0)
			return
		end
	elseif scan.isMultiPage then
		-- check if this was the last page
		if batchSize == 0
			or (currentQueryArgs.page > 0 and currentQueryArgs.page or 1) * NUM_AUCTION_ITEMS_PER_PAGE >= totalAuctions then
			scan.isMultiPage = false
		end
	--[[ elseif false and (currentQueryArgs.page + 1) * NUM_AUCTION_ITEMS_PER_PAGE <= totalAuctions then
		 -- [TODO] setting / detection if appropriate
		scan.isMultiPage = true --]]
	end
	scan.loading:SetScript("OnUpdate", UpdateDataBatch)
end

local function ResetScanStatistics()
	ns.Print("Starting full auction scan ...")
	wipe(statistics)
end
local function PrintScanStatistics(total)
	if total <= 0 then
		ns.Print("Full scan failed because of a Blizzard bug.")
	else
		ns.Print("Full scan completed. We scanned %d auctions, of which %d were invalid.", total, statistics['invalid'])
	end
end

function scan.RequestLiveData(callback, name, quality, itemClass, itemFilter)
	scan.isMultiPage = true
	scan.callback = callback
	scan.filter = itemFilter
	wipe(scan.data)

	AuctionFrameBrowse.page = 1
	if name then BrowseName:SetText(name) end
	if itemClass and itemClass > 0 then
		AuctionFrameFilter_OnClick(_G["AuctionFilterButton"..itemClass])
	end
	-- UIDropDownMenu_SetSelectedValue(BrowseDropDown, quality and tonumber(quality) or -1)

	QueryAuctionItems(name, nil, nil, nil, itemClass, nil, 0, nil, quality, false, true)
end

function scan.ScanStarted(...)
	-- only listen when we know someone scanned. this avoids stray updates of seller names
	ns:RegisterEvent('AUCTION_ITEM_LIST_UPDATE')

	if select(10, ...) == true then
		scan.isFullScan = true
		StashPreviousData()
		ResetScanStatistics()
	else
		-- if we get too many results, this information is essential
		currentQueryArgs.name,
		currentQueryArgs.minLevel,
		currentQueryArgs.maxLevel,
		currentQueryArgs.invType,
		currentQueryArgs.itemClass,
		currentQueryArgs.itemSubClass,
		currentQueryArgs.page,
		currentQueryArgs.isUsable,
		currentQueryArgs.minQuality,
		_, -- full scan
		currentQueryArgs.exactMatch = ...
	end
	scan.ShowLoading(1,0.82,0)
end
function scan.ScanCompleted(numItems)
	if scan.isFullScan then
		scan.isFullScan = false
		PrintScanStatistics(numItems)
	elseif scan.isMultiPage then
		-- get next pages if neccessary
		scan.loading:SetScript("OnUpdate", function()
			if CanSendAuctionQuery() then
				AuctionFrameBrowse.page = currentQueryArgs.page + 1 -- makes the ui show things nicely
				QueryAuctionItems(currentQueryArgs.name, currentQueryArgs.minLevel, currentQueryArgs.maxLevel, currentQueryArgs.invType, currentQueryArgs.itemClass, currentQueryArgs.itemSubClass, currentQueryArgs.page + 1, currentQueryArgs.isUsable, currentQueryArgs.minQuality, false, currentQueryArgs.exactMatch)
			end
		end)
		return
	end

	if scan.callback then
		scan.callback(scan.data)
		scan.callback = nil
	end

	local search = currentQueryArgs.name
	if search and not ns.Find(scan.history, search) then
		local _, link = ns.GetItemInfo(search)
		local firstItemName = GetAuctionItemInfo("list", 1)

		local numResults = GetNumAuctionItems("list")
		if not link and numResults > 0 then
			link = GetAuctionItemLink("list", 1)

			--local lastItem  = GetAuctionItemInfo("list", numResults)
			--if firstItemName ~= lastItem then
				-- names differ, is it still a common itemID?
				local firstType, firstItemID = ns.GetLinkData(link, true)
				local lastType, lastItemID  = ns.GetLinkData( GetAuctionItemLink("list", numResults), true )

				if firstType ~= lastType or firstItemID ~= lastItemID then
					link = nil
				end
			--end
		end

		-- FIXME: 'Schattenfeuerhalskette' name used for rare & uncommon quality
		if link then
			local linkType, linkID, linkData = ns.GetLinkData(link, true)
			linkID = linkType and linkType..':'..linkID..':'..linkData
			if linkID and ns.GetItemInfo(linkID) ~= firstItemName then
				-- searched for a suffixed item, store the item link anyways but keep the original query, too
				-- 'Schattenfeuerhalskette der Schaumkrone' saves 'item:Schattenfeuerhalskette' + query
				if not ns.Find(scan.history, linkID) then
					table.insert(scan.history, linkID)
				end
				linkID = search
			end
			search = linkID
		else
			search = search
		end

		if not ns.Find(scan.history, search) then
			table.insert(scan.history, search)
		end
	end

	scan.HideLoading()
	scan.loading:SetScript("OnUpdate", nil)
end

ns:RegisterEvent('AUCTION_HOUSE_CLOSED', function() scan.HideLoading() end)
