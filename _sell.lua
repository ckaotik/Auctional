local addonName, addon = ...
if true then return end

local function CreateOverlay()
	local overlay = CreateFrame('Frame', 'AuctionalAuctionOverlay', AuctionFrameBrowse)
	      overlay:SetSize(165, 308)
	      overlay:SetPoint('TOPLEFT', 17, -101)
	      overlay:SetFrameStrata('HIGH')

	local top = overlay:CreateTexture(nil, 'BACKGROUND')
	      top:SetTexture('Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopLeft')
	      top:SetTexCoord(17/256, 182/256, 101/256, 256/256)
	      top:SetPoint('TOPLEFT')
	      top:SetSize(182-17, 256-101)
	local bottom = overlay:CreateTexture(nil, 'BACKGROUND')
	      bottom:SetTexture('Interface\\AuctionFrame\\UI-AuctionFrame-Browse-BotLeft')
	      bottom:SetTexCoord(17/256, 182/256, 0/256, 153/256)
	      bottom:SetSize(182-17, 153-0)
	      bottom:SetPoint('BOTTOMRIGHT')

	-- http://www.townlong-yak.com/framexml/18291/Blizzard_AuctionUI/Blizzard_AuctionUI.xml#1410
	-- PopupButtonTemplate
	local button = CreateFrame('Button', '$parentItemButton', overlay, 'ItemButtonTemplate', index)
	      button:SetPoint('TOPLEFT', 8, -6)
	      -- button:SetScale(0.75)
	local function SyncAuctionItemButton(self, btn, up)
		AuctionSellItemButton_OnClick(_G.AuctionsItemButton, btn, up)

		local name, texture, count, quality, canUse, pricePerStack, pricePerItem, maxStack, invCount = GetAuctionSellItemInfo()
		SetItemButtonTexture(self, texture)
		SetItemButtonCount(self, count)
		SetItemButtonStock(self, invCount)
	end
	button:SetScript('OnClick', SyncAuctionItemButton)
	button:SetScript('OnDragStart', SyncAuctionItemButton)
	button:SetScript('OnReceiveDrag', SyncAuctionItemButton)
	button:SetScript('OnEnter', _G.AuctionsItemButton:GetScript('OnEnter'))
	button:SetScript('OnLeave', GameTooltip_Hide)

	-- AuctionsItemButton:SetParent(overlay)
	-- AuctionsItemButton:ClearAllPoints()
	-- AuctionsItemButton:SetPoint('TOPLEFT', 6, -6)
	-- local name, texture =AuctionsItemButton:GetRegions()
	-- texture:SetWidth(158)
end
CreateOverlay()

local function CreateAuction()
	-- AuctionsCreateAuctionButton:Disable()
	-- AuctionsBuyoutText:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	-- AuctionsBuyoutError:Hide()

	if not GetAuctionSellItemInfo() then
		-- no item selected
		return
	end

	local stackSize   = AuctionsStackSizeEntry:GetNumber()
	local numAuctions = AuctionsNumStacksEntry:GetNumber()

	local startPrice  = MoneyInputFrame_GetCopper(StartPrice)
	local buyoutPrice = MoneyInputFrame_GetCopper(BuyoutPrice)
	if buyoutPrice < startPrice then
		-- buyout must be more than bid price
		-- AuctionsBuyoutText:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
		-- AuctionsBuyoutError:Show()
		return
	elseif startPrice < 1 or startPrice > MAXIMUM_BID_PRICE then
		-- invalid start price
		return
	end

	local stackCount = AuctionsItemButton.stackCount or 0
	local totalCount = AuctionsItemButton.totalCount or 0
	if stackSize == 0 or stackSize > stackCount or numAuctions == 0 or stackSize * numAuctions > totalCount then
		-- trying to sell more than we own
		return
	end

	LAST_ITEM_START_BID, LAST_ITEM_BUYOUT = startPrice, buyoutPrice
	if AuctionFrameAuctions.priceType == PRICE_TYPE_UNIT then
		startPrice  = startPrice  * stackSize
		buyoutPrice = buyoutPrice * stackSize
	end

	-- AuctionsCreateAuctionButton:Enable()
	DropCursorMoney()
	PlaySound('LOOTWINDOWCOINSOUND')
	print('StartAuction', startPrice, buyoutPrice, AuctionFrameAuctions.duration, stackSize, numAuctions)
	-- StartAuction(startPrice, buyoutPrice, AuctionFrameAuctions.duration, stackSize, numAuctions)
end

if true then return end

local _, ns = ...
-- GLOBALS: _G, AuctionalDB, AuctionFrame, AuctionFrameAuctions, AuctionFrameTab3, AuctionsScrollFrame, GameTooltip, PriceDropDown, BuyoutPrice, StartPrice, AuctionsNumStacksEntry, AuctionsStackSizeEntry, AuctionsNumStacksMaxButton, AuctionsStackSizeMaxButton, AuctionsCancelAuctionButton, AuctionsBidSort, AuctionsHighBidderSort, AuctionsDurationSort
-- GLOBALS: ITEM_QUALITY_COLORS, FONT_COLOR_CODE_CLOSE, RED_FONT_COLOR_CODE, UNKNOWN, NUM_AUCTIONS_TO_DISPLAY, BUYOUT, CANCEL_AUCTION, AUCTION_CANCEL_COST, AUCTIONS_BUTTON_HEIGHT, LEVEL, AUCTION_CREATOR, CLOSES_IN, HIGH_BIDDER, CURRENT_BID, BUYOUT_PRICE
-- GLOBALS: GetAuctionSellItemInfo, ClearCursor, GetCursorInfo, IsAltKeyDown, ClickAuctionSellItemButton, UIDropDownMenu_GetSelectedValue, UIDropDownMenu_SetSelectedValue, MoneyInputFrame_SetCopper, PickupContainerItem, FauxScrollFrame_GetOffset, FauxScrollFrame_Update, FauxScrollFrame_OnVerticalScroll, AuctionFrameBrowse_Update, AuctionFrameAuctions_Update, AuctionFrameMoneyFrame, MoneyFrame_Update, UnitName, CreateFrame, hooksecurefunc, GetCVarBool, DressUpBattlePet, DressUpItemLink, BattlePetToolTip_Show, IsModifiedClick, HandleModifiedItemClick, GetItemInfo
-- GLOBALS: string, floor, unpack, tablem strsplit, tonumber, wipe, pairs, select, table

local sell = {}
ns.sell = sell

local PETCAGE = 82800
local selectedIndices = {}
local auctionItemClasses = {
	GetAuctionItemClasses(),
}
for i=1,#auctionItemClasses do
	auctionItemClasses[ auctionItemClasses[i] ] = i
end

--[[ Awesome stuff ahead ]]--
local function sortItemScan(a, b)
	local _, aCount, aBid, aBuyout, _, aOwner = unpack(a)
	local _, bCount, bBid, bBuyout, _, bOwner = unpack(b)

	local aPerItem = (aBuyout > 0 and aBuyout or aBid) / aCount
	local bPerItem = (bBuyout > 0 and bBuyout or bBid) / bCount

	if aPerItem == bPerItem then
		if aCount == bCount then
			return (aOwner or UNKNOWN) > (bOwner or UNKNOWN)
		else
			return aCount > bCount
		end
	else
		return aBuyout < bBuyout
	end
end
-- [TODO] caching?
local function EvaluateLiveData(data, itemID)
	if not itemID or not data[itemID] then return end

	table.sort(data[itemID], sortItemScan)
	sell.info:SetText("Alt-Click an entry to use its price as a reference")
	AuctionsScrollFrame.data = data[itemID]
	AuctionFrameAuctions_Update()
end
function sell.UpdateSortingHeaders()
	if AuctionsScrollFrame.data then
		AuctionsDurationSort:SetText( LEVEL )
		AuctionsHighBidderSort:SetText( AUCTION_CREATOR )
		AuctionsBidSort:SetText( BUYOUT_PRICE )
	else
		AuctionsDurationSort:SetText( CLOSES_IN )
		AuctionsHighBidderSort:SetText( HIGH_BIDDER )
		AuctionsBidSort:SetText( CURRENT_BID )
	end
end

function sell.CalculateAuctionPrices(compareValue, count)
	local startDiscount, startReduction = AuctionalDB.startPriceDiscount, AuctionalDB.startPriceReduction
	local buyoutDiscount, buyoutReduction = AuctionalDB.buyoutPriceDiscount, AuctionalDB.buyoutPriceReduction

	local startPrice = floor((1 - startDiscount)*(compareValue*count)) - startReduction
	local buyoutPrice = floor((1 - buyoutDiscount)*(compareValue*count)) - buyoutReduction
	return startPrice, buyoutPrice
end
-- compareValue: stack price, count: stack size -- [TODO] reuse my own prices
function sell.SetAuctionPrices(compareValue, count)
	if compareValue and compareValue > 0 and count and count > 0 then
		compareValue = compareValue / count
		if AuctionFrameAuctions.priceType == 1 then count = 1 end -- same as UIDropDownMenu_GetSelectedValue(PriceDropDown)

		local startPrice, buyoutPrice = sell.CalculateAuctionPrices(compareValue, count)
		MoneyInputFrame_SetCopper(StartPrice, startPrice)
		MoneyInputFrame_SetCopper(BuyoutPrice, buyoutPrice)
		-- AuctionsFrameAuctions_ValidateAuction()
		-- AuctionsStackSizeEntry:SetNumber(count)
		-- AuctionsNumStacksEntry:SetNumber(1)
	end
end
function sell.UpdateNewAuctionPrices()
	local itemName, auctionTexture, count, quality, canUse, vendorSingle, vendorStack, maxStack, invCount = GetAuctionSellItemInfo()
	local itemLink, itemClass = nil, nil

	if AuctionsScrollFrame.data then
		wipe(selectedIndices)
		sell.info:SetText("")
		sell.UpdateSortingHeaders()
		AuctionsScrollFrame.data = nil
		AuctionFrameAuctions_Update()
	end

	if itemName then
		GameTooltip:SetOwner(AuctionFrame)
		local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = GameTooltip:SetAuctionSellItem()
		if speciesID and speciesID > 0 then
			itemLink = string.format("%s\124Hbattlepet:%d:%d:%d:%d:%d:%d:%d\124h[%s]\124h\124r", ITEM_QUALITY_COLORS[breedQuality].hex, speciesID, level, breedQuality, maxHealth, power, speed, name, itemName)
			itemClass = 11
		else
			_, itemLink = GameTooltip:GetItem()
			itemClass = select(6, GetItemInfo(itemLink))
			itemClass = auctionItemClasses[itemClass]
		end
		GameTooltip:Hide()
	end

	if itemLink then
		local itemID, special = ns.GetItemLinkData(itemLink)
		ns.scan.RequestLiveData(function(data) EvaluateLiveData(data, itemID) end,
			itemName, quality, itemClass, itemID) -- (itemID > 0 and itemID or PETCAGE))

		-- fill with available scan data
		local compareValue = ns:GetAuctionValue(itemID, special, nil)
		local numItems = AuctionsStackSizeEntry:GetNumber()
		sell.SetAuctionPrices(compareValue, numItems)
	end
end
-- hooksecurefunc("AuctionSellItemButton_OnEvent", sell.UpdateNewAuctionPrices)
ns.RegisterEvent("NEW_AUCTION_UPDATE", sell.UpdateNewAuctionPrices, "defaultprices")

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
	local numStacks = AuctionsNumStacksEntry
	local stackSize = AuctionsStackSizeEntry
	local mine, you, yours, dx, dy = stackSize:GetPoint()
	numStacks:ClearAllPoints()
	numStacks:SetPoint(mine, you, yours, dx+6, dy-14)
	stackSize:ClearAllPoints()
	stackSize:SetPoint("LEFT", numStacks, "RIGHT", 64, 0)

	local info = numStacks:GetParent():CreateFontString("$parentStacking", "ARTWORK", "GameFontNormalSmall")
	info:SetParent(numStacks)
	info:SetPoint("LEFT", numStacks, "RIGHT", -8, 0)
	info:SetPoint("RIGHT", stackSize, "LEFT", -8, 0)
	info:SetJustifyH("CENTER")
	info:SetText("Stacks of") -- STACKS

	local numStacksMax = AuctionsNumStacksMaxButton
	local stackSizeMax = AuctionsStackSizeMaxButton
	numStacksMax:ClearAllPoints()
	numStacksMax:SetPoint("TOP", numStacks, "BOTTOM", -8, 2)
	numStacksMax:SetWidth(50)
	numStacksMax:SetText("Max")
	stackSizeMax:ClearAllPoints()
	stackSizeMax:SetPoint("TOP", stackSize, "BOTTOM", -8, 2)
	stackSizeMax:SetWidth(50)
	stackSizeMax:SetText("Max")

	AuctionFrameAuctions.priceType = AuctionalDB.priceType or 1
    UIDropDownMenu_SetSelectedValue(PriceDropDown, AuctionFrameAuctions.priceType)

    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button, ...)
		if AuctionFrame:IsShown() and IsAltKeyDown() then
			local bag, slot = self:GetParent():GetID(), self:GetID()

			AuctionFrameTab2:Click() -- go to auctions, but we swapped those tabs
			PickupContainerItem(bag, slot)
			if GetCursorInfo() == "item" then
				ClickAuctionSellItemButton()
				ClearCursor()
			end
		end
	end)

    AuctionsScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
		if AuctionsScrollFrame.data then
			FauxScrollFrame_OnVerticalScroll(self, offset, AUCTIONS_BUTTON_HEIGHT, sell.UpdateAuctions)
		else
			FauxScrollFrame_OnVerticalScroll(self, offset, AUCTIONS_BUTTON_HEIGHT, AuctionFrameBrowse_Update)
		end
	end)

    local unselect = CreateFrame("Button", "UnselectAuctionsButton", AuctionFrameAuctions, "UIPanelButtonTemplate")
    unselect:SetSize(90, 22)
    unselect:SetPoint("RIGHT", AuctionsCancelAuctionButton, "LEFT", 2, 0)
    unselect:SetText("Unselect all")
    unselect:SetScript("OnClick", function(self, btn)
    	wipe(selectedIndices)
    	sell.UpdateAuctions()
    end)
    sell.unselect = unselect

    local infoText = AuctionFrameAuctions:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	infoText:SetPoint("LEFT", AuctionFrameMoneyFrame, "RIGHT", 6, -1)
	infoText:SetPoint("RIGHT", unselect, "LEFT", -6, -1)
	infoText:SetText("Alt-Click an item to post it.")
	sell.info = infoText

	ns.UnregisterEvent("AUCTION_HOUSE_SHOW", "initsellpane")
end, "initsellpane")

function ns.IsAuctionItemSelected(index)
	return selectedIndices[index]
end
local function ToggleAuctionItem(button, index)
	if selectedIndices[index] then
		selectedIndices[index] = nil
		button:UnlockHighlight()
	else
		selectedIndices[index] = true
		button:LockHighlight()
	end
end
local function IsSelectionAllMine(frame)
	if not frame.data then return end
	local allMine, compare = true, nil
	for index, selected in pairs(selectedIndices) do
		if selected then
			compare = frame.data[index] and frame.data[index][7]
			allMine = (compare and allMine) and compare == UnitName("player")
		end
	end
	return allMine
end
local function HasSelection(frame)
	-- return ns.Count(frame.selectedIndices) > 0 -- [TODO] enable multiselect for other lists, too!
	return ns.Count(selectedIndices) > 0
end
local function UpdateButtonHighlight(button)
	if AuctionsScrollFrame.data then
		local index = FauxScrollFrame_GetOffset(AuctionsScrollFrame) + button:GetID()
		if ns.IsAuctionItemSelected(index) then
			button:LockHighlight()
		end
	end
end
local function ButtonClick(self, ...)
	if AuctionsScrollFrame.data then
		local index = FauxScrollFrame_GetOffset(AuctionsScrollFrame) + self:GetID()
		local link = self.link
		local companionID = select(12, ns.GetItemInfo(link))

		if IsModifiedClick() then
			if not HandleModifiedItemClick(link) and companionID then DressUpBattlePet(companionID, 0) end
		else
			if GetCVarBool("auctionDisplayOnCharacter") then
				if not DressUpItemLink(link) and companionID then DressUpBattlePet(companionID, 0) end
			end
			sell.SetAuctionPrices(self.buyoutPrice, self.itemCount)
		end

		if not IsControlKeyDown() then
			wipe(selectedIndices)
		end
		ToggleAuctionItem(self, index)
		sell.UpdateAuctions()
	elseif self.onClick then
		self.onClick(self, ...)
	end
end

function sell.UpdateAuctions()
	if not AuctionsScrollFrame.data then return end
	sell.UpdateSortingHeaders()

	local total = #AuctionsScrollFrame.data
	local offset = FauxScrollFrame_GetOffset(AuctionsScrollFrame)

	local buttonName, button, index
	local count, quality, level, minBid, buyoutPrice, highBidder, owner, name, texture, itemLink, isMine
	local itemName, iconTexture, highBidderFrame, closingTimeFrame, closingTimeText, itemCount, bidAmountMoneyFrame, bidAmountMoneyFrameLabel, buttonBuyoutFrame

	local hasScrollbar = total <= NUM_AUCTIONS_TO_DISPLAY
	for i=1, NUM_AUCTIONS_TO_DISPLAY do
		index = offset + i

		buttonName = "AuctionsButton"..i
		button = _G[buttonName]
		if index > total or not AuctionsScrollFrame.data[index] then
			button:Hide()
		else
			button:Show()
			if not button.enhanced then
				button.onClick = button:GetScript("OnClick")
				button:SetScript("OnClick", ButtonClick) -- no hooking or we produce HandleModifiedItemClick without links
				button:HookScript("OnLeave", UpdateButtonHighlight)
				button.enhanced = true
			end

			itemLink, count, minBid, buyoutPrice, highBidder, owner = unpack( AuctionsScrollFrame.data[index] )
			name, _, quality, level, _, _, _, _, _, texture = ns.GetItemInfo(itemLink)
			isMine = owner and owner == UnitName("player")

			-- Resize button if there isn't a scrollbar
			button:SetWidth(hasScrollbar and 599 or 576)
			_G[buttonName.."Highlight"]:SetWidth(hasScrollbar and 565 or 543)
			AuctionsBidSort:SetWidth(hasScrollbar and 213 or 193)

			--[[ Row Fields ]]--
			iconTexture = _G[buttonName.."ItemIconTexture"]
			iconTexture:SetTexture(texture)
			iconTexture:SetVertexColor(1.0, 1.0, 1.0)

			local color = ITEM_QUALITY_COLORS[quality]
			itemName = _G[buttonName.."Name"]
			itemName:SetVertexColor(color.r, color.g, color.b)
			itemName:SetText(name)

			highBidderFrame = _G[buttonName.."HighBidder"]
			highBidderFrame:SetText( (isMine and highBidder or owner) or RED_FONT_COLOR_CODE..UNKNOWN..FONT_COLOR_CODE_CLOSE or "" )

			closingTimeFrame = _G[buttonName.."ClosingTime"]
			closingTimeFrame:EnableMouse(false)
			closingTimeText = _G[buttonName.."ClosingTimeText"]
			if level > 1 or AuctionalDB.showLevelOne then
				closingTimeText:Show()
				closingTimeText:SetText(level)
			else
				closingTimeText:Hide()
			end

			itemCount = _G[buttonName.."ItemCount"]
			if count > 1 or AuctionalDB.showSingleItemCount then
				itemCount:SetText(count)
				itemCount:Show()
			else
				itemCount:Hide()
			end

			-- bid
			local priceFormat = AuctionFrameAuctions.priceType == 1 and floor(minBid / count) or minBid
			bidAmountMoneyFrame = _G[buttonName.."MoneyFrame"]
			bidAmountMoneyFrameLabel = _G[buttonName.."MoneyFrameLabel"]
			MoneyFrame_Update(buttonName.."MoneyFrame", priceFormat)
			bidAmountMoneyFrame:SetAlpha(1)
			bidAmountMoneyFrameLabel:Hide()

			-- buyout
			priceFormat = AuctionFrameAuctions.priceType == 1 and floor(buyoutPrice / count) or buyoutPrice
			buttonBuyoutFrame = _G[buttonName.."BuyoutFrame"]
			if buyoutPrice > 0 then -- [TODO] combine prices when possible
				bidAmountMoneyFrame:SetPoint("RIGHT", buttonName, "RIGHT", 10, 10)
				MoneyFrame_Update(_G[buttonName.."BuyoutFrameMoney"], priceFormat)
				buttonBuyoutFrame:Show()
			else
				bidAmountMoneyFrame:SetPoint("RIGHT", buttonName, "RIGHT", 10, 3)
				buttonBuyoutFrame:Hide()
			end

			button.cancelPrice = floor((minBid * AUCTION_CANCEL_COST) / 100)
			button.bidAmount = minBid
			button.buyoutPrice = buyoutPrice
			button.link = itemLink
			button.itemCount = count
			button.isMine = isMine

			if ns.IsAuctionItemSelected(index) then
				button:LockHighlight()
			else
				button:UnlockHighlight()
			end
		end
	end

	-- [TODO] enable auction cancelling when all selected entries are ours
	-- [TODO] enable alt-click quick purchase
	if IsSelectionAllMine(AuctionsScrollFrame) then
		AuctionsCancelAuctionButton:Disable()
		AuctionsCancelAuctionButton:SetText(CANCEL_AUCTION)
	else
		AuctionsCancelAuctionButton:Disable()
		AuctionsCancelAuctionButton:SetText(BUYOUT)
	end
	if HasSelection(AuctionsScrollFrame) then
		sell.unselect:Enable()
	else
		sell.unselect:Disable()
	end

	FauxScrollFrame_Update(AuctionsScrollFrame, total, NUM_AUCTIONS_TO_DISPLAY, AUCTIONS_BUTTON_HEIGHT)
end
hooksecurefunc("AuctionFrameAuctions_Update", sell.UpdateAuctions)

-- [TODO]
local function OnAuctionCreated(startPrice, buyoutPrice, duration, stackSize, numStacks)
	local _, itemLink = GetItemInfo(LAST_ITEM_AUCTIONED)
	print("Created auction for", itemLink)
end
hooksecurefunc("StartAuction", OnAuctionCreated)

hooksecurefunc("AuctionFrameItem_OnEnter", function(self, type, index)
	if type ~= "owner" or not AuctionsScrollFrame.data then return end
	ns.ShowTooltip(self, AuctionsScrollFrame.data[index][1], "ANCHOR_RIGHT")
end)
