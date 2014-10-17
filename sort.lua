if true then return end

local _, ns = ...
-- GLOBALS: _G, AuctionalDB, AuctionSort, NAME, AuctionFrameBrowse, BrowseBuyoutSort, BrowseQualitySort, BrowseNameSort, BrowseQuantitySort
-- GLOBALS: CreateFrame, hooksecurefunc, AuctionFrame_OnClickSortColumn, SortButton_UpdateArrow
-- GLOBALS: ipairs

local sortOrder = { "BrowseDurationSort", "BrowseQuantitySort", "BrowseQualitySort", "BrowseNameSort", "BrowseLevelSort", "BrowseCurrentBidSort", "BrowseBuyoutSort", "BrowseHighBidderSort", }
local sortWidths = { 22, 36, 80, 105, 30, 73, 73, 105, }
local sortTitles = { "", " #" or AUCTION_STACK_SIZE, RARITY, NAME, REQ_LEVEL_ABBR, BID, BUYOUT_PRICE, AUCTION_CREATOR, }
local sortIDs = {
	["BrowseBuyoutSort"] = "buyout",
	["BrowseNameSort"] = "name",
	["BrowseQuantitySort"] = "quantity"
}
local function CreateSorting(parent, name)
	local sorting = CreateFrame("Button", name, parent, "AuctionSortButtonTemplate")
	sorting:SetSize(95, 19)
	sorting:SetText("")
	sorting:SetScript("OnClick", function()
		AuctionFrame_OnClickSortColumn("list", sortIDs[name])
		SortButton_UpdateArrow(sorting, "list", sortIDs[name])
	end)
	sorting:Show()

	return sorting
end
local function InitSortColumns(frame, event, ...)
	local AuctionFrame_OnClickSortColumn = AuctionFrame_OnClickSortColumn
	local SortButton_UpdateArrow = SortButton_UpdateArrow

	-- Add new sort types
	AuctionSort['list_buyout'] = {
		{ column = 'duration',	reverse = false },
		{ column = 'name',	reverse = false },
		{ column = 'level',	reverse = true },
		{ column = 'quality',	reverse = false },
		{ column = 'quantity',	reverse = false },
		{ column = 'bid',	reverse = false },
		{ column = 'buyout',	reverse = false },
	}
	AuctionSort['list_name'] = {
		{ column = 'duration',	reverse = false },
		{ column = 'quantity',	reverse = false },
		{ column = 'level',	reverse = true },
		{ column = 'bid',	reverse = false },
		{ column = 'buyout',	reverse = false },
		{ column = 'quality',	reverse = false },
		{ column = 'name',	reverse = false },
	}
	AuctionSort['list_quantity'] = {
		{ column = 'duration',	reverse = false },
		{ column = 'level',	reverse = true },
		{ column = 'bid',	reverse = false },
		{ column = 'buyout',	reverse = false },
		{ column = 'quality',	reverse = false },
		{ column = 'name',	reverse = false },
		{ column = 'quantity',	reverse = false },
	}

	local column, previousColumn
	for i,columnName in ipairs(sortOrder) do
		column = _G[columnName] or CreateSorting(AuctionFrameBrowse, columnName)

		column:ClearAllPoints()
		if i == 1 then
			column:SetPoint("TOPLEFT", "AuctionFrameBrowse", "TOPLEFT", 186, -82)
		else
			previousColumn = sortOrder[i-1]
			column:SetPoint("LEFT", previousColumn, "RIGHT", -2, 0)
		end
		column:SetText( sortTitles[i] or column:GetText() )
		column:SetWidth(sortWidths[i] or 95)

		-- local oldSetWidth = column.SetWidth
		-- column.SetWidth = function(self, width) oldSetWidth(self, sortWidths[i] or 95) end
		hooksecurefunc(column, "SetWidth", function(self, width, done)
			if not done then self:SetWidth(sortWidths[i] or 95, true) end
		end)
	end

	-- Hook this to hide arrows nicely.
	hooksecurefunc("AuctionFrameBrowse_UpdateArrows", function()
		SortButton_UpdateArrow(BrowseBuyoutSort, "list", "buyout")
		SortButton_UpdateArrow(BrowseNameSort, "list", "name")
		SortButton_UpdateArrow(BrowseQuantitySort, "list", "quantity")
	end)
end
ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
	InitSortColumns()
	ns.UnregisterEvent("AUCTION_HOUSE_SHOW", "sort")
end, "sort")
