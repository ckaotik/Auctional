if true then return end

local _, ns = ...
-- GLOBALS: _G, AuctionalGDB, BUYOUT_COST, YOUR_BID, NUM_BROWSE_TO_DISPLAY, AUCTION_PRICE_PER_ITEM, AUCTIONS_BUTTON_HEIGHT, BrowseScrollFrame, AuctionFrameBrowse, GameFontHighlightSmall, ShowOnPlayerCheckButton, AuctionFrameBrowse_Update, AuctionFrame, BidScrollFrame, AuctionsScrollFrame
-- GLOBALS: hooksecurefunc, CreateFrame, MoneyFrame_Update, MoneyFrame_SetType, MoneyFrame_SetMaxDisplayWidth, FauxScrollFrame_GetOffset, GetAuctionItemInfo, GetAuctionItemTimeLeft, GetCoinTextureString, PlaySound, GetSelectedAuctionItem
-- GLOBALS: ipairs, floor, math


local columnOrder = { "ClosingTime", "Item", "Name", "Level", "MoneyFrame", "HighBidder", }
local durationTextures = {
	"Interface\\COMMON\\Indicator-Red",
	"Interface\\COMMON\\Indicator-Yellow",
	"Interface\\COMMON\\Indicator-Green",
	"Interface\\COMMON\\Indicator-Gray",
}
local moneyWidth, padding = 146, 6

local function CreateColumn(frameName, name)
	if name == "PerItemMoneyFrame" then
		local column = CreateFrame("Frame", frameName..name, _G[frameName], "SmallMoneyFrameTemplate")
		MoneyFrame_SetType(column, "AUCTION")
		MoneyFrame_SetMaxDisplayWidth(column, 80)
		column:SetWidth(80)

		return column
	elseif name == "PerItemBuyoutFrame" then
		local column = CreateFrame("Frame", frameName..name, _G[frameName], "SmallMoneyFrameTemplate")
		MoneyFrame_SetType(column, "AUCTION")
		MoneyFrame_SetMaxDisplayWidth(column, 80)
		column:SetWidth(80)

		return column
	end
end
function ns.ShowTooltipWithHighlight(self)
	self:GetParent():LockHighlight()
	if self.onEnter then self.onEnter() end
	ns.ShowTooltip(self)
end
function ns.HideTooltipWithHighlight(self)
	if self.onLeave then self.onLeave() end
	ns.HideTooltip()

	local currentID, isSelected
	local currentScrollFrame = (BidScrollFrame:IsVisible() and BidScrollFrame)
		or (AuctionsScrollFrame:IsVisible() and AuctionsScrollFrame)
		or (BrowseScrollFrame:IsVisible() and BrowseScrollFrame)

	if currentScrollFrame then
		currentID = FauxScrollFrame_GetOffset(currentScrollFrame) + self:GetParent():GetID()
		isSelected = (currentScrollFrame.data and ns.IsAuctionItemSelected(index))
			or (GetSelectedAuctionItem( AuctionFrame.type ) and GetSelectedAuctionItem( AuctionFrame.type ) == currentID)
	end

	if not isSelected then
		self:GetParent():UnlockHighlight()
	end
end
local function PropagateClicksToParent(self, button)
	self:GetParent():Click()
end
local function EnhanceAuctionEntry(buttonName)
--[[
	-- adjust ItemCount so it fits in with the others
	local itemCount = _G[buttonName.."ItemCount"]
	itemCount:SetFontObject(GameFontHighlightSmall)
	_G[buttonName.."ItemCount"]:SetWidth(30)
	_G[buttonName.."ItemCount"]:SetHeight(32)
--]]
	-- size changes
	_G[buttonName.."HighBidder"]:SetHeight(AUCTIONS_BUTTON_HEIGHT-5)

	_G[buttonName.."Level"]:SetWidth(30)
	_G[buttonName.."ClosingTime"]:SetWidth(12)
	_G[buttonName.."ClosingTimeText"]:SetWidth(12)

	_G[buttonName.."MoneyFrame"]:SetWidth(moneyWidth)
	MoneyFrame_SetMaxDisplayWidth(_G[buttonName.."MoneyFrame"], moneyWidth)
	_G[buttonName.."BuyoutFrame"]:SetWidth(moneyWidth)
	MoneyFrame_SetMaxDisplayWidth(_G[buttonName.."BuyoutFrameMoney"], moneyWidth)

	-- sort columns as we wish
	local column, previousColumn
	for i,columnName in ipairs(columnOrder) do
		column = _G[buttonName .. columnName] or CreateColumn(buttonName, columnName)

		column:ClearAllPoints()
		if i == 1 then
			column:SetPoint("TOPLEFT", -4, 0)
		else
			previousColumn = _G[buttonName .. columnOrder[i-1]]
			if columnName:find("Frame") then
				column:SetPoint("TOPRIGHT", previousColumn, "TOPRIGHT", padding+moneyWidth, -3) -- justify right
			elseif columnOrder[i-1]:find("Frame") then
				column:SetPoint("TOPLEFT", previousColumn, "TOPRIGHT", padding, 3)
			else
				column:SetPoint("TOPLEFT", previousColumn, "TOPRIGHT", padding, 0)
			end
		end
	end

	local moneyFrame = _G[buttonName.."MoneyFrame"]
	moneyFrame.onEnter = moneyFrame:GetScript("OnEnter")
	moneyFrame.onLeave = moneyFrame:GetScript("OnLeave")
	moneyFrame:SetScript("OnEnter", ns.ShowTooltipWithHighlight)
	moneyFrame:SetScript("OnLeave", ns.HideTooltipWithHighlight)

	_G[buttonName.."BuyoutFrameText"]:Hide()
	local buyoutFrame = _G[buttonName.."BuyoutFrame"]
	buyoutFrame.tiptext = BUYOUT_COST
	buyoutFrame.onEnter = buyoutFrame:GetScript("OnEnter")
	buyoutFrame.onLeave = buyoutFrame:GetScript("OnLeave")
	buyoutFrame:SetScript("OnEnter", ns.ShowTooltipWithHighlight)
	buyoutFrame:SetScript("OnLeave", ns.HideTooltipWithHighlight)
	buyoutFrame:SetWidth(moneyWidth)

	--[[
	-- create a new buyout price for per-item values
	local perItemBuyoutFrame = CreateColumn(buttonName, "PerItemBuyoutFrame")
	perItemBuyoutFrame:SetPoint("BOTTOMLEFT", _G[buttonName.."ItemCount"], "BOTTOMRIGHT", padding, 0)
	perItemBuyoutFrame:SetPoint("TOPRIGHT", _G[buttonName.."PerItemMoneyFrame"], "BOTTOMRIGHT", 0, -1)
	perItemBuyoutFrame:Show()
	--]]
end
local function UpdateAuctionEntry()
	local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame)
	local button, buttonName
	local duration, name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner, saleStatus, itemId, hasAllInfo

	for i=1, NUM_BROWSE_TO_DISPLAY do
		buttonName = "BrowseButton"..i
		button = _G[buttonName]

		name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner, saleStatus, itemId, hasAllInfo =  GetAuctionItemInfo("list", offset + i)
		duration = GetAuctionItemTimeLeft("list", offset + i)

		if not button.enhanced then
			EnhanceAuctionEntry(buttonName)
			button.enhanced = true
		end

		local moneyFrame = _G[buttonName.."MoneyFrame"]
		local buyoutFrame = _G[buttonName.."BuyoutFrame"]
		local buyoutMoneyFrame = _G[buttonName.."BuyoutFrameMoney"]
		local moneyFrameAnchor = _G[buttonName.."Level"]
		local seller = _G[buttonName.."HighBidder"]

		duration = duration == 0 and "" or "|T"..durationTextures[duration]..":0|t"
		_G[buttonName.."ClosingTimeText"]:SetText(duration)

		_G[buttonName.."YourBidText"]:Hide()
		if highBidder then
			moneyFrame.tiptext = YOUR_BID
			moneyFrame:SetAlpha(1)
		else
			moneyFrame:SetAlpha(0.5)
		end

		-- needs to be after first positioning
		moneyFrame:ClearAllPoints()
		moneyFrame:SetPoint("TOPRIGHT", moneyFrameAnchor, "TOPRIGHT", padding+moneyWidth, -3) -- justify right
		if AuctionalGDB.perItemPrice then
			MoneyFrame_Update(moneyFrame:GetName(), floor((bidAmount ~= 0 and bidAmount or minBid)/count))
			MoneyFrame_Update(buyoutMoneyFrame:GetName(), floor(buyoutPrice/count))
		end
		moneyFrame:SetWidth(moneyWidth)
		buyoutMoneyFrame:SetWidth(moneyWidth)
		buyoutFrame.tiptext = count > 1 and BUYOUT_COST .. " x"..count.."\n"..GetCoinTextureString(buyoutPrice) or nil

		--[[== showing / hiding stuff ==]]--
		local mine, you, yours, dx, dy = moneyFrame:GetPoint()
		local mine2, you2, yours2, dx2, dy2 = seller:GetPoint()
		if not AuctionalGDB.showBothWhenEqual and math.abs(buyoutPrice - minBid) <= AuctionalGDB.maxPriceDiffForEqual then
			-- both prices available, but almost equal. show only buyout
			moneyFrame:Hide()
			moneyFrame:SetPoint(mine, you, yours, dx, 4)
			seller:SetPoint(mine2, you2, yours2, dx2, -4)
		elseif buyoutPrice > 0 then
			-- both prices available. show both
			moneyFrame:Show()
			moneyFrame:SetPoint(mine, you, yours, dx, -3)
			seller:SetPoint(mine2, you2, yours2, dx2, 0)
		else
			-- no buyout available. show bid price
			moneyFrame:Show()
			moneyFrame:SetPoint(mine, you, yours, dx, -10)
			seller:SetPoint(mine2, you2, yours2, dx2, 10)
		end

		if level <= 1 and not AuctionalGDB.showLevelOne then
			_G[buttonName.."Level"]:Hide()
		else
			_G[buttonName.."Level"]:Show()
		end

		local itemCount = _G[buttonName.."ItemCount"]
		if count == 1 and AuctionalGDB.showSingleItemCount then
			itemCount:SetText(count)
			itemCount:Show()
		end
	end
end

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
	local showPerItemPrices = CreateFrame("CheckButton", "Auctional_ShowPerItemPrice", AuctionFrameBrowse, "UICheckButtonTemplate")
	showPerItemPrices:SetWidth(26); showPerItemPrices:SetHeight(26)
	showPerItemPrices:SetPoint("LEFT", ShowOnPlayerCheckButton, "RIGHT", 70, 0)
	showPerItemPrices:SetChecked(AuctionalGDB.perItemPrice)
	showPerItemPrices.text:SetFontObject(GameFontHighlightSmall)
	showPerItemPrices.text:SetText(AUCTION_PRICE_PER_ITEM)
	showPerItemPrices:SetScript("OnClick", function(self)
		PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
		AuctionalGDB.perItemPrice = self:GetChecked()
		AuctionFrameBrowse_Update()
	end)
	ns.showPerItemPrices = showPerItemPrices

	hooksecurefunc("AuctionFrameBrowse_Update", UpdateAuctionEntry)

	ns.UnregisterEvent("AUCTION_HOUSE_SHOW", "columns")
end, "columns")
