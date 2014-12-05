local addonName, addon, _ = ...
LibStub('AceAddon-3.0'):NewAddon(addon, addonName, 'AceEvent-3.0')
_G[addonName] = addon

--[[
Auctional
- scan
	- hook into QueryAuctionItems
	- store data
	- prevent disconnect
- tooltip
	- GetAuctionBuyout API
	- tooltip hooks
		- show stack/show single/show graph
	- history graph

AuctionalUI
- general
	- scan button w/ cooldown timer
	- reposition search button
	- reposition/relabel reset button
	- swap bids/auctions tabs
- buy (browse)
	- color names: self, alts, guild members, friends
	- enable "exact match" by default
- sell (auctions)
	- alt-click to sell item
	- show competition (use GnomishAuctionShrinker style)
		- browse frame sidebar overlay?
	- cancel own auctions
	- buy competition

use AceAddon
create libs\ folder

Changes in WoD: http://wowpedia.org/Patch_6.0.1/API_changes
- cross faction auction house
- item link revamp
- QueryAuctionItems new return (#11): exactMatch
--]]

-- GLOBALS: Auctional, AuctionalDB, AuctionFrameTab2, AuctionFrameTab3
-- GLOBALS: GetRealmName, UnitFactionGroup, GetAuctionBuyout, GetItemInfo, GetDisenchantValue
-- GLOBALS: assert, string, pairs, type, wipe, tonnumber

local defaults = {
	profile = {
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
		dataAge = -10,
		-- FIXME: this sucks
		showFullStackFunc  = IsModifierKeyDown,
		showGraphFunc      = IsAltKeyDown,
		showDetailedDEFunc = IsModifierKeyDown,
		showDEPriceFunc    = function() return true end,

		-- static (requires /reload when changed)
		graphWidth = 140,
	},
	realm = { -- AuctionalPricesDB?
		postData = {},
		scanData = {},
		lastScan = 0,
	},
}

function addon:OnEnable()
	-- self.db = LibStub('AceDB-3.0'):New(addonName..'DB', defaults, true)

	-- TODO/FIXME: update to Ace
	local realms = GetAutoCompleteRealms()
	if realms then table.sort(realms) end
	local realm = realms and realms[1] or GetRealmName():gsub(' ', '')

	if not AuctionalDB then AuctionalDB = {} end
	if not AuctionalDB[realm] then AuctionalDB[realm] = {} end
	if not AuctionalDB[realm]["price"] then AuctionalDB[realm]["price"] = {} end
	if not AuctionalDB[realm]["userprice"] then AuctionalDB[realm]["userprice"] = {} end

	self.DB = AuctionalDB[realm]["price"]
	self.userDB = AuctionalDB[realm]["userprice"]

	for option, setting in pairs(defaults.profile) do
		if AuctionalDB[option] == nil then
			AuctionalDB[option] = setting
		end
	end

	-- self:Purge()
	self:RegisterEvent('AUCTION_HOUSE_SHOW', self.InitializeUI)
	hooksecurefunc('QueryAuctionItems', self.scan.ScanStarted)
end

-- event management
local frame, eventHooks = CreateFrame("frame"), {}
addon.eventHooks = eventHooks
local function eventHandler(frame, event, arg1, ...)
	if event == "ADDON_LOADED" and arg1 == addonName then

	elseif eventHooks[event] then
		for id, listener in pairs(eventHooks[event]) do
			listener(frame, event, arg1, ...)
		end
	end
end
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", eventHandler)

function addon.OldRegisterEvent(event, callback, id, silentFail)
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
function addon.OldUnregisterEvent(event, id)
	if not eventHooks[event] or not eventHooks[event][id] then return end
	eventHooks[event][id] = nil
	if addon.Count(eventHooks[event]) < 1 then
		eventHooks[event] = nil
		frame:UnregisterEvent(event)
	end
end
