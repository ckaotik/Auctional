local addonName, ns, _ = ...
Auctional = ns

--[[
Auctional
- scan handlers
- tooltip
	- GetAuctionBuyout API
	- tooltip hooks
		- show stack/show single/show graph
	- history graph

AuctionalUI
- general
	- scan button w/ cooldown timer
	- reposition search button
	- swap bids/auctions tabs
- sell
	- alt-click to sell item
	- show competition (use GnomishAuctionShrinker style)
		- browse frame sidebar overlay?
	- cancel own auctions
	- buy competition

use AceAddon
create libs\ folder
--]]

-- GLOBALS: Auctional, AuctionalGDB, AuctionFrameTab2, AuctionFrameTab3
-- GLOBALS: GetRealmName, UnitFactionGroup, GetAuctionBuyout, GetItemInfo, GetDisenchantValue
-- GLOBALS: assert, string, pairs, type, wipe, tonnumber

local defaultSettings = {
	-- scanning settings
	bidOnlyFactor = 1.5,
	actionsPerFrame = 200,
	minQuality = 1,
	lifeSpan = 30,

	-- browse frame settings
	perItemPrice = false,
	showSingleItemCount = true,
	showLevelOne = true,
	showBothWhenEqual = true,
	maxPriceDiffForEqual = 100, -- [TODO] percentages?

	-- auction posting frame settings
	priceType = 1, -- 1: per item, 2: per stack
	startPriceDiscount = 0.05, -- 1.0 = 100% discount
	startPriceReduction = 1, -- price reduction in copper
	buyoutPriceDiscount = 0.05,
	buyoutPriceReduction = 1,

	-- tooltip settings
	priceCombineDifference = 50000, -- [TODO] percentages?
	minCountForAvailable = 0, -- how often must an item be currently available to *not* show its value in red
	showGraphFunc = IsAltKeyDown,
	showDetailedDEFunc = IsModifierKeyDown,
	showDEPriceFunc = function() return true end,
	showFullStackFunc = IsModifierKeyDown,
	dataAge = -10,

	-- static (required /reload when changed)
	graphWidth = 140,
}

-- event management
local frame, eventHooks = CreateFrame("frame"), {}
ns.eventHooks = eventHooks
local function eventHandler(frame, event, arg1, ...)
	if event == "ADDON_LOADED" and arg1 == addonName then
		local realm = GetRealmName("player")
		local _, faction = UnitFactionGroup("player")
		realm = realm .. "_" .. faction

		if not AuctionalGDB then AuctionalGDB = {} end
		if not AuctionalGDB[realm] then AuctionalGDB[realm] = {} end
		if not AuctionalGDB[realm]["price"] then AuctionalGDB[realm]["price"] = {} end
		if not AuctionalGDB[realm]["userprice"] then AuctionalGDB[realm]["userprice"] = {} end

		ns.DB = AuctionalGDB[realm]["price"]
		ns.userDB = AuctionalGDB[realm]["userprice"]

		for option, setting in pairs(defaultSettings) do
			if AuctionalGDB[option] == nil then
				AuctionalGDB[option] = setting
			end
		end

	elseif eventHooks[event] then
		for id, listener in pairs(eventHooks[event]) do
			listener(frame, event, arg1, ...)
		end
	end
end
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", eventHandler)

function ns.RegisterEvent(event, callback, id, silentFail)
	assert(callback and event and id, string.format("Usage: RegisterEvent(event, callback, id[, silentFail])"))

	if not eventHooks[event] then
		eventHooks[event] = {}
		frame:RegisterEvent(event)
	end
	if not silentFail then
		assert(not eventHooks[event][id], string.format("Event %s already registered by id %s.", event, id))
	end

	eventHooks[event][id] = callback
end
function ns.UnregisterEvent(event, id)
	if not eventHooks[event] or not eventHooks[event][id] then return end
	eventHooks[event][id] = nil
	if ns.Count(eventHooks[event]) < 1 then
		eventHooks[event] = nil
		frame:UnregisterEvent(event)
	end
end

-- [x] keep scan data at most X days
-- [ ] keep at most Y data entries for each item / keep only entries that differ no more than Z from the average price / clean time based data?
local function PurgeUserData()
	local historyThreshold = ns.GetNormalizedTimeStamp() - 60*60*24*AuctionalGDB.lifeSpan
	ns.WalkDataTable(ns.userDB, function(dataHandle)
		if dataHandle.history then
			for date, price in pairs(dataHandle.history) do
			 	if date < historyThreshold then
					dataHandle.history[date] = nil
				end
			end
		end
	end)
end
local function PurgePriceData()
	local historyThreshold = ns.GetNormalizedTimeStamp() - 60*60*24*AuctionalGDB.lifeSpan
	ns.WalkDataTable(ns.DB, function(dataHandle)
		if dataHandle.history then
			for date, price in pairs(dataHandle.history) do
			 	if date < historyThreshold then
					dataHandle.history[date] = nil
				end
			end
		end
	end)
end
ns.RegisterEvent("ADDON_LOADED", function()
	PurgePriceData()
	PurgeUserData()
	ns.UnregisterEvent("ADDON_LOADED", "cleanDB")
end, "cleanDB")

local function ChangeTabOrder()
	local bid, sell = AuctionFrameTab2, AuctionFrameTab3

	-- BROWSE should rather be "stöbern"
	bid:SetID(3); bid:SetText(AUCTIONS)
	sell:SetID(2); sell:SetText(BIDS)

	PanelTemplates_TabResize(bid, 0, nil, 36)
	PanelTemplates_TabResize(sell, 0, nil, 36)

	hooksecurefunc("AuctionFrameTab_OnClick", function(self, button, down, index)
		local index = self:GetID()
		PanelTemplates_SetTab(AuctionFrame, (index == 2 and 3) or (index == 3 and 2) or index)
	end)

	ns.UnregisterEvent("AUCTION_HOUSE_SHOW", "tabOrder")
end
ns.RegisterEvent("AUCTION_HOUSE_SHOW", ChangeTabOrder, "tabOrder")

-- "tab" key navigation
-- "enter" key create
-- "alt" click autobuy
-- create auction reminder timer (using Blizz's timer!)
