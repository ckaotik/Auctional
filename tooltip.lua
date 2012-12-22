local addonName, ns, _ = ...

-- GLOBALS: AuctionalGDB, _G, ITEM_UNSELLABLE, ITEM_QUALITY_COLORS, BUYOUT_PRICE, ROLL_DISENCHANT, SELL_PRICE, UNKNOWN, UIParent
-- GLOBALS: GetCoinTextureString, GetItemInfo, MoneyFrame_Update, IsModifierKeyDown, IsControlKeyDown
-- GLOBALS: print, format, wipe, select, string, table, math, pairs

local LibGraph = LibStub("LibGraph-2.0")
local LIC = LibStub("LibItemCrush-1.0")

local graph
local oneDay = 60*60*24
local function GetHistoryDataPoints(itemID, special)
	if not itemID or not ns.DB[itemID] then return end
	local dataHandle = ns.DB[itemID]

	local today = ns.GetNormalizedTimeStamp()
	local price, maxPrice = nil, 1

	local dataPoints = {}
	local enchantPoints = LIC:IsCrushable(itemID) and {} or nil

	-- history data
	for i = AuctionalGDB.dataAge or -6, -1 do
		price = ns:GetAuctionValue(itemID, special, today+i*oneDay)
		if price then
			if price > maxPrice then maxPrice = price end
			table.insert(dataPoints, { i, price })
		end
		price = enchantPoints and ns:GetCrushValue(itemID, today+i*oneDay)
		if price then
			if price > maxPrice then maxPrice = price end
			table.insert(enchantPoints, { i, price })
		end
	end

	-- current data
	price = ns:GetAuctionValue(itemID, special, nil)
	if price then
		if price > maxPrice then maxPrice = price end
		table.insert(dataPoints, { 0, price })
	end
	price = enchantPoints and ns:GetDisenchantValue(itemID)
	if price then
		if price > maxPrice then maxPrice = price end
		table.insert(enchantPoints, { 0, price })
	end

	-- normalize prices to 0-100%
	for i, data in pairs(dataPoints) do
		dataPoints[i][2] = dataPoints[i][2]/maxPrice*20
	end
	if enchantPoints then
		for i, data in pairs(enchantPoints) do
			enchantPoints[i][2] = enchantPoints[i][2]/maxPrice*20
		end
	end

	return dataPoints, enchantPoints
end
local aucLineColor = {43/255, 255/255, 88/255, 1}
local enchLineColor = {224/255, 82/255, 255/255, 1}
function ns.CreatePricingGraph(tip, itemLink)
	if not graph then
		graph = LibGraph:CreateGraphLine(addonName.."PriceHistory", UIParent, "CENTER", "CENTER", 0, 0, AuctionalGDB.graphWidth or 140, 40)
		graph:SetYAxis(0, 20)
		graph:SetGridSpacing(1, 5)
	else
		graph:ResetData()
	end

	local points, enchantPoints = GetHistoryDataPoints( ns.GetItemLinkData(itemLink) )
	if points and #points > 1 then
		if tip.AddLine then
			tip:AddLine("Price History:\n|T:50:140|t") -- placeholder texture
			local tipLine = tip:GetName().."TextLeft"..tip:NumLines()
			graph:ClearAllPoints()
			graph:SetPoint("BOTTOMLEFT", tipLine, "BOTTOMLEFT", 0, 2)
		else
			graph:ClearAllPoints()
			graph:SetPoint("TOPRIGHT", tip, "TOPLEFT", -6, -6)
		end
		graph:SetParent(tip)
		graph:AddDataSeries(points, aucLineColor)
		if enchantPoints and #enchantPoints > 1 then
			graph:AddDataSeries(enchantPoints, enchLineColor)
		end
		graph:SetXAxis(AuctionalGDB.dataAge or -6, 0)
		graph:Show()
	else
		graph:Hide()
	end
end

function ns.AnyTooltipSetAuctionPrice(tip, label, text)
	if tip.AddDoubleLine then
		tip:AddDoubleLine(label, text)
	else
		if not tip.value then
			local value = tip:CreateFontString("$parentItemValue", "ARTWORK", "GameTooltipText")
			tip.value = value
		end
		--[[if tip:GetName() == "FloatingBattlePetTooltip" then
			tip.value:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", -12, 36)
		else
			tip.value:SetPoint("BOTTOMRIGHT", tip, "BOTTOMRIGHT", -12, 8)
		end--]]
		tip.value:SetPoint("TOPRIGHT", tip.PetTypeTexture, "BOTTOMRIGHT", -4, -16)

		tip.value:SetText(text)
	end
end

function ns.TooltipAddVendorPrice(tip, itemLink, stackSize)
	local vendorPrice = select(11, GetItemInfo(itemLink))
	if not vendorPrice or vendorPrice == 0 then
		tip:AddLine(ITEM_UNSELLABLE)
		return
	end

	vendorPrice = (stackSize or 1) * vendorPrice
	local vendorLabel = SELL_PRICE .. (stackSize and " x"..stackSize or "")
	local vendorText = "|cffFFFFFF"..GetCoinTextureString(vendorPrice).."|r"

	tip:AddDoubleLine(vendorLabel, vendorText)
end

local up, down = " |TInterface\\BUTTONS\\Arrow-Up-Up:0|t", " |TInterface\\BUTTONS\\Arrow-Down-Up:0|t"
function ns.TooltipAddAuctionPrice(tip, itemLink, stackSize)
	if not (tip and itemLink) then return end

	local itemPrice, currentCount, previousPrice, minPrice, maxPrice = ns.GetAuctionState( itemLink )

	local changeIndicator = ""
	if itemPrice and previousPrice then
		if itemPrice > previousPrice then
			changeIndicator = changeIndicator .. up
		elseif itemPrice < previousPrice then
			changeIndicator = changeIndicator .. down
		end
	end

	itemPrice = itemPrice and (itemPrice * (stackSize or 1)) or nil

	local color = "FFFFFF" -- FFCC00 as yellow
	if not itemPrice or not currentCount or currentCount <= AuctionalGDB.minCountForAvailable then color = "FF0000" end
	if not itemPrice and not previousPrice then return end

	local auctionText
	if minPrice and maxPrice and math.abs(maxPrice - minPrice) > AuctionalGDB.priceCombineDifference then
		-- this uses an ndash, i.e. alt + -
		auctionText = string.format("%s – %s", GetCoinTextureString(minPrice), GetCoinTextureString(maxPrice))
	else
		auctionText = string.format("%s|cFF%s%s|r", changeIndicator, color, itemPrice and GetCoinTextureString(itemPrice) or UNKNOWN)
	end

	local auctionLabel
	if (currentCount and currentCount > 0) then
		auctionLabel = format(BUYOUT_PRICE.." (%s)", (currentCount and currentCount > 0 and currentCount))
		auctionLabel = auctionLabel .. (stackSize and " x"..stackSize or "")
	end
	auctionLabel = auctionLabel or BUYOUT_PRICE

	ns.AnyTooltipSetAuctionPrice(tip, auctionLabel, auctionText)
end

local deDetails = setmetatable({ }, { __mode = "v" })
local function ShowDisenchantDetails(tip, item, indent)
	local textLeft, textRight = "", ""
	if deDetails[item] then
		textLeft, textRight = string.split('_', deDetails[item])
	else
		local disenchants = { LIC:GetPossibleCrushs(item) }
		local result, countText, chanceText, count, chance, quality
		for i = 1,#disenchants, 5 do
			result, countText, chanceText, count, chance = disenchants[i], disenchants[i+1], disenchants[i+2], disenchants[i+3], disenchants[i+4]

			result = result and select(2, GetItemInfo(result))
			if result and countText and chanceText then
				-- tip:AddDoubleLine((indent or "")..chanceText.." "..item, countText)
				textLeft = (textLeft ~= "" and textLeft.."\n" or "") .. (indent or "") .. result
				textRight = (textRight ~= "" and textRight.."\n" or "") .. countText
			end
		end
		deDetails[item] = textLeft.."_"..textRight
		wipe(disenchants)
		disenchants = nil
	end
	if textLeft ~= "" and textRight ~= "" then
		tip:AddDoubleLine(textLeft, textRight)
		_G[tip:GetName().."TextRight"..tip:NumLines()]:SetJustifyH("RIGHT")
	end
end
function ns.TooltipAddDisenchantPrice(tip, itemLink)
	local dePrice, crushType = ns:GetCrushValue(itemLink)
	if dePrice and dePrice > 0 then
		tip:AddDoubleLine(crushType, "|cffFFFFFF"..GetCoinTextureString(dePrice).."|r")
	end
	-- even if we don't have prices, disenchant reagents are of interest!
	if AuctionalGDB.showDetailedDEFunc() then
		ShowDisenchantDetails(tip, itemLink, "    ")
	end
end

-- weak cach as users tend to show tooltips for more than one frame
-- Blizzard, you make my life really really hard ... can't GetItemInfo on item names we don't have in our bags. can't get ids/links from recipes
local recipeCrafts = setmetatable({ }, { __mode = "v" })
local function GetRecipeItem(tip)
	local tipName, leftText, craftedName = tip:GetName().."TextLeft", nil, nil
	for i=1, tip:NumLines() do
		leftText = string.match(_G[tipName..i]:GetText(), "^\n(.*)")
		if leftText then
			craftedName = leftText
			break
		end
	end
	return craftedName or false -- empty string to find recipes that do not craft items
end

local RECIPE = select(7, GetAuctionItemClasses())
function ns.ShowSimpleTooltipData(tip, useLink)
	local itemLink = useLink or select(2, tip:GetItem())
	if not itemLink then return end

	local itemType, _, stackSize = select(6, GetItemInfo(itemLink))
	stackSize = (AuctionalGDB.showFullStackFunc() and stackSize > 1) and stackSize or nil

	if itemType == RECIPE then
		if recipeCrafts[itemLink] == nil then recipeCrafts[itemLink] = GetRecipeItem(tip) end
		if recipeCrafts[itemLink] and not tip.showPrices then
			-- not all recipes create items. handle those!
			tip.showPrices = true
			return
		else
			tip.showPrices = nil
		end
	end

	-- add all of these together, so they can cuddle each other
	-- no need to add these for battle pets, as they can neither be vendored nor disenchanted
	ns.TooltipAddVendorPrice(tip, itemLink, stackSize)
	ns.TooltipAddAuctionPrice(tip, itemLink, stackSize)
	if AuctionalGDB.showDEPriceFunc() then
		ns.TooltipAddDisenchantPrice(tip, itemLink)
	end

	if AuctionalGDB.showGraphFunc() then
		ns.CreatePricingGraph(tip, itemLink)
	elseif graph then
		graph:Hide()
	end
end

-- hide default vendor price without taint, yay!
GameTooltip:HookScript("OnTooltipAddMoney", function(frame, amount, max)
	if max then return end

	local me = frame:GetName()
	local moneyLine = frame:NumLines()

	for i=1, frame.shownMoneyFrames or 0 do
		MoneyFrame_Update(me.."MoneyFrame"..i,0)
		_G[me.."TextLeft"..(moneyLine+i-1)]:SetText("")
	end
	-- GameTooltip_ClearMoney(frame)
end)
GameTooltip:HookScript("OnHide", function() if graph then graph:Hide() end end)
GameTooltip:HookScript("OnTooltipSetItem", ns.ShowSimpleTooltipData)
ItemRefTooltip:HookScript("OnTooltipSetItem", ns.ShowSimpleTooltipData)
ShoppingTooltip1:HookScript("OnTooltipSetItem", ns.ShowSimpleTooltipData)
ShoppingTooltip2:HookScript("OnTooltipSetItem", ns.ShowSimpleTooltipData)
ShoppingTooltip3:HookScript("OnTooltipSetItem", ns.ShowSimpleTooltipData)

hooksecurefunc("BattlePetTooltipTemplate_SetBattlePet", function(tip, data)
	local link = format("%s\124Hbattlepet:%d:%d:%d:%d:%d:%d:%d\124h[%s]\124h\124r", ITEM_QUALITY_COLORS[data.breedQuality].hex, data.speciesID, data.level, data.breedQuality, data.maxHealth, data.power, data.speed, data.name, data.name)

	ns.TooltipAddAuctionPrice(tip, link)

	if AuctionalGDB.showGraphFunc() then
		ns.CreatePricingGraph(tip, link)
	elseif graph then
		graph:Hide()
	end
end)