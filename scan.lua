local _, ns = ...
-- GLOBALS: _G, AuctionalGDB, AuctionFrame, AuctionFrameBrowse, BrowseName
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
local function InitScanningStatus()
	local scanning = CreateFrame("Frame", "Auctional_ScanningIcon", AuctionFrame)
	scanning:SetSize(300, 30)
	scanning:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -20, -9)
	scanning:SetAlpha(0)
	scanning:Hide()
	scan.loading = scanning

	-- graphical spinner, similar to -- http://wow.go-hero.net/framexml/16309/StreamingFrame.xml + .lua
	local spinner = CreateFrame("Frame", "Auctional_ScanningIconSpin", scanning)
	spinner:SetPoint("RIGHT", scanning, "RIGHT")
	spinner:SetSize(30, 30) -- default: 48
	local bgTex = spinner:CreateTexture("$parentBackground")
	bgTex:SetAllPoints(spinner)
	bgTex:SetDrawLayer("BACKGROUND")
	bgTex:SetTexture("Interface\\COMMON\\StreamBackground")
	bgTex:SetVertexColor(0,1,0)
	local spinTex = spinner:CreateTexture("$parentStatus")
	spinTex:SetAllPoints(spinner)
	spinTex:SetDrawLayer("BACKGROUND")
	spinTex:SetTexture("Interface\\COMMON\\StreamCircle")
	spinTex:SetVertexColor(0,1,0)
	local spark = spinner:CreateTexture()
	spark:SetAllPoints(spinner)
	spark:SetDrawLayer("OVERLAY")
	spark:SetTexture("Interface\\COMMON\\StreamSpark")

	scan.SetSpinnerColor = function(r, g, b)
		bgTex:SetVertexColor(r or 0, g or 1, b or 0)
		spinTex:SetVertexColor(r or 0, g or 1, b or 0)
	end

	-- text status
	local statusText = scanning:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	statusText:SetPoint("RIGHT", scanning, "RIGHT", -30+2, -1)
	statusText:SetText("Scanning...")
	scan.loadingText = statusText

	-- animations, everyone loves them!
	scanning.FadeIn = scanning:CreateAnimationGroup()
	local FadeInFinished = function(self, requested) scanning:SetAlpha(1); scanning:Show(); end
	scanning.FadeIn:SetScript("OnFinished", FadeInFinished)
	scanning.FadeIn:SetScript("OnStop", FadeInFinished)
	local spinFadeIn = scanning.FadeIn:CreateAnimation("Alpha")
		spinFadeIn:SetChange(1.0)
		spinFadeIn:SetDuration(2)
		spinFadeIn:SetOrder(1)

	scanning.FadeOut = scanning:CreateAnimationGroup()
	local FadeOutFinished = function(self, requested) scanning:SetAlpha(0); scanning:Hide(); scanning.Loop:Stop(); end
	scanning.FadeOut:SetScript("OnFinished", FadeOutFinished)
	scanning.FadeOut:SetScript("OnStop", FadeOutFinished)
	local spinFadeOut = scanning.FadeOut:CreateAnimation("Alpha")
		spinFadeOut:SetChange(-1.0)
		spinFadeOut:SetDuration(1)
		spinFadeOut:SetOrder(1)

	scanning.Loop = spinner:CreateAnimationGroup()
		scanning.Loop:SetLooping("REPEAT")
	local spinLoop = scanning.Loop:CreateAnimation("Rotation")
		spinLoop:SetDuration(4)
		spinLoop:SetDegrees(-360)
		spinLoop:SetOrder(1)
end
local function InitScanButton()
	local button = CreateFrame("Button", nil, AuctionFrameBrowse, "UIPanelButtonTemplate")
	button:SetPoint("TOPRIGHT", AuctionFrameBrowse, "TOPRIGHT", 70, -35)
	button:SetScript("OnUpdate", function(self)
		local canScan, canFullScan = CanSendAuctionQuery()
		if canScan and canFullScan then
			self:Enable()
		else
			self:Disable()
		end
	end)
	button:SetScript("OnClick", function(self)
		QueryAuctionItems(nil, nil, nil, nil, nil, nil, nil, nil, nil, true)
	end)
	button:SetWidth(100)
	button:SetText("Scan...")

	scan.button = button
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
	elseif not quality or quality < AuctionalGDB.minQuality then
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
		(buyoutPrice == 0 and minBid > 0) and minBid/count*AuctionalGDB.bidOnlyFactor or huge,
		dataHandle.price or huge
	)
	-- skip weird entries ...
	if auctionPrice == huge or auctionPrice == 0 then return true end
	auctionPrice = auctionPrice > 1 and floor(auctionPrice) or 1
	-- [TODO] add some kind of reasonable stray-removal

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
	for i=1, AuctionalGDB.actionsPerFrame do
		if lastScanIndex + i > batchSize then
			scan.ScanCompleted(batchSize)
			break
		end
		UpdateItem("list", lastScanIndex+i)
	end
	lastScanIndex = lastScanIndex + AuctionalGDB.actionsPerFrame
end
local function HandleScanResults()
	-- we don't want any interference. listener will be restarted on the next query
	ns.UnregisterEvent("AUCTION_ITEM_LIST_UPDATE", "updatedata")
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

	QueryAuctionItems(name, nil, nil, nil, itemClass, nil, 0, nil, quality)
end

function scan.ScanStarted(...)
	-- only listen when we know someone scanned. this avoids stray updates of seller names
	ns.RegisterEvent("AUCTION_ITEM_LIST_UPDATE", HandleScanResults, "updatedata", true)

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
		currentQueryArgs.minQuality = ...
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
				QueryAuctionItems(currentQueryArgs.name, currentQueryArgs.minLevel, currentQueryArgs.maxLevel, currentQueryArgs.invType, currentQueryArgs.itemClass, currentQueryArgs.itemSubClass, currentQueryArgs.page + 1, currentQueryArgs.isUsable, currentQueryArgs.minQuality)
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

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
	InitScanningStatus()
	InitScanButton()

	local reset = _G["BrowseResetButton"]
	reset:SetText("x")
	reset:SetWidth(30)
	reset:SetPoint("TOPLEFT", AuctionFrameBrowse, "TOPLEFT", 44, -75)

	local search = _G["BrowseSearchButton"]
	search:SetWidth(104)
	search:ClearAllPoints()
	search:SetPoint("TOPLEFT", AuctionFrameBrowse, "TOPLEFT", 78, -75)

	hooksecurefunc("QueryAuctionItems", scan.ScanStarted)

	ns.UnregisterEvent("AUCTION_HOUSE_SHOW", "showspinner")
end, "showspinner")
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
	scan.HideLoading()
end, "hidespinner")


-- autocomplete item names
-- ----------------------------
-- GLOBALS: AutoCompleteBox, ITEM_QUALITY_COLORS, AUTOCOMPLETE_FLAG_NONE, AUTOCOMPLETE_FLAG_ALL, AUTOCOMPLETE_SIMPLE_REGEX, AUTOCOMPLETE_SIMPLE_FORMAT_REGEX
-- GLOBALS: GetItemInfo, AutoCompleteEditBox_OnChar, AutoCompleteEditBox_OnTextChanged, AutoCompleteEditBox_OnEnterPressed, AutoCompleteEditBox_OnEscapePressed, AutoCompleteEditBox_OnTabPressed, AutoCompleteEditBox_OnEditFocusLost, AutoComplete_UpdateResults
-- GLOBALS: strlen
local function GetCleanText(text)
	if not text then return '' end
	-- remove |cCOLOR|r, |TTEXTURE|t and appended info
	text = text:gsub("\124c........", ""):gsub("\124r", ""):gsub("\124T[^\124]-\124t ", ""):gsub(" %(.-%)$", "") -- :trim()
	return text
end

local AIC_BATTLEPET = select(11, GetAuctionItemClasses())

local lastQuery, queryResults = nil, {}
local function UpdateAutoComplete(parent, text, cursorPosition)
	if parent == BrowseName and cursorPosition <= strlen(text) then
		wipe(queryResults)
		-- TODO: sort inverse so we can get 'last searched' entries
		for _, item in pairs(scan.history) do
			local suggestion, _, quality, iLevel, _, class, subClass, _, equipSlot = ns.GetItemInfo(item)
			      suggestion = suggestion or item

			-- TODO: allow searching for type, level, slot, ...
			if strtrim(text) == '' or suggestion:lower():find('^'..text:lower()) then
				if quality then
					if equipSlot and equipSlot ~= "" then
						suggestion = ("%s%s|r (%d %s)"):format(ITEM_QUALITY_COLORS[quality].hex, suggestion, iLevel, _G[equipSlot])
					elseif class == AIC_BATTLEPET then
						local icon = "Interface\\PetBattles\\PetIcon-"..PET_TYPE_SUFFIX[subClass]
						suggestion = ("|T%s:%s|t %s%s|r"):format(icon, '0:0:0:0:128:256:63:102:129:168', ITEM_QUALITY_COLORS[quality].hex, suggestion)
					else
						suggestion = ("%s%s|r"):format(ITEM_QUALITY_COLORS[quality].hex, suggestion)
					end
				end

				local index
				for i, entry in pairs(queryResults) do
					if entry == suggestion then
						index = i
						break
					end
				end
				if index then
					queryResults[index] = suggestion
				else
					table.insert(queryResults, suggestion)
				end
			end
		end
		-- table.sort(queryResults, SortNames)
		AutoComplete_UpdateResults(AutoCompleteBox, queryResults)

		-- also write out the first match
		local currentText = parent:GetText()
		if queryResults[1] and currentText ~= lastQuery then
			lastQuery = currentText
			local newText = currentText:gsub(parent.autoCompleteRegex or AUTOCOMPLETE_SIMPLE_REGEX,
				(parent.autoCompleteFormatRegex or AUTOCOMPLETE_SIMPLE_FORMAT_REGEX):format(
					queryResults[1],
					currentText:match(parent.autoCompleteRegex or AUTOCOMPLETE_SIMPLE_REGEX)
				), 1)

			parent:SetText( GetCleanText(newText) )
			parent:HighlightText(strlen(currentText), strlen(newText))
			parent:SetCursorPosition(strlen(currentText))
		end
	end
end
local function CleanAutoCompleteOutput(self)
	local editBox = self:GetParent().parent
	if not editBox.addSpaceToAutoComplete then
		local newText = GetCleanText( self:GetText() )
		editBox:SetText(newText)
		editBox:SetCursorPosition(strlen(newText))
	end
end

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
	local editBox = BrowseName
	editBox.autoCompleteParams = { include = AUTOCOMPLETE_FLAG_NONE, exclude = AUTOCOMPLETE_FLAG_ALL }
	editBox.addHighlightedText = true
	editBox.tiptext = 'Enter space to see a list of recent searched.'

	local original = editBox:GetScript("OnTabPressed")
	editBox:SetScript("OnTabPressed", function(self)
		if not AutoCompleteEditBox_OnTabPressed(self) then
			original(self)
		end
	end)
	-- original = editBox:GetScript("OnEnterPressed")
	editBox:SetScript("OnEnterPressed", function(self)
		if not AutoCompleteEditBox_OnEnterPressed(self) then
			-- original(self)
			AuctionFrameBrowse_Search()
			self:ClearFocus()
		end
	end)
	original = editBox:GetScript("OnEscapePressed")
	editBox:SetScript("OnEscapePressed", function(self)
		if not AutoCompleteEditBox_OnEscapePressed(self) then
			original(self)
		end
	end)
	editBox:HookScript("OnEditFocusLost", AutoCompleteEditBox_OnEditFocusLost)
	editBox:HookScript("OnTextChanged", AutoCompleteEditBox_OnTextChanged)
	editBox:HookScript("OnChar", AutoCompleteEditBox_OnChar)
	editBox:HookScript("OnEnter", ns.ShowTooltip)
	editBox:HookScript("OnLeave", ns.HideTooltip)

	hooksecurefunc('AutoComplete_Update', UpdateAutoComplete)
	hooksecurefunc('AutoCompleteButton_OnClick', CleanAutoCompleteOutput)

	ns.UnregisterEvent("AUCTION_HOUSE_SHOW", "autocomplete")
end, "autocomplete")
