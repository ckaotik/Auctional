local addonName, addon, _ = ...

-- GLOBALS: AuctionFrame, AuctionFrameBrowse, AuctionFrameTab2, AuctionFrameTab3, AUCTIONS, BIDS, PanelTemplates_TabResize, PanelTemplates_SetTab, CanSendAuctionQuery, QueryAuctionItems
-- GLOBALS: CreateFrame, hooksecurefunc

-- TODO: consolidate UI changes in here
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
end

local function InitScanningStatus()
	local scan = addon.scan
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
	local scan = addon.scan
	local button = CreateFrame("Button", nil, AuctionFrameBrowse, "UIPanelButtonTemplate")
	button:SetPoint("TOPRIGHT", AuctionFrameBrowse, "TOPRIGHT", 40, -12) -- 70, -35
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

local function InitScanUI()
	InitScanningStatus()
	InitScanButton()

	--[[ local reset = _G["BrowseResetButton"]
	reset:SetText("x")
	reset:SetWidth(30)
	reset:ClearAllPoints()
	reset:SetPoint("TOPLEFT", AuctionFrameBrowse, "TOPLEFT", 44, -75)

	local search = _G["BrowseSearchButton"]
	search:SetWidth(104)
	search:ClearAllPoints()
	search:SetPoint("TOPLEFT", AuctionFrameBrowse, "TOPLEFT", 78, -75) --]]
end

function addon:InitializeUI()
	ChangeTabOrder()
	InitScanUI()

	addon:UnregisterEvent('AUCTION_HOUSE_SHOW')
end

-- "tab" key navigation
-- "enter" key create
-- "alt" click autobuy
-- create auction reminder timer (using Blizz's timer!)
