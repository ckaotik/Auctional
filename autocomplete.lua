local addonName, addon, _ = ...

-- autocomplete item names
-- ----------------------------
-- GLOBALS: AutoCompleteBox, ITEM_QUALITY_COLORS, AUTOCOMPLETE_FLAG_NONE, AUTOCOMPLETE_FLAG_ALL, AUTOCOMPLETE_SIMPLE_REGEX, AUTOCOMPLETE_SIMPLE_FORMAT_REGEX, BrowseName, _G, PET_TYPE_SUFFIX, LE_AUTOCOMPLETE_PRIORITY_OTHER, AUTOCOMPLETE_MAX_BUTTONS
-- GLOBALS: GetItemInfo, AutoCompleteEditBox_OnChar, AutoCompleteEditBox_OnTextChanged, AutoCompleteEditBox_OnEnterPressed, AutoCompleteEditBox_OnEscapePressed, AutoCompleteEditBox_OnTabPressed, AutoCompleteEditBox_OnEditFocusLost, AutoComplete_UpdateResults, AuctionFrameBrowse_Search
-- GLOBALS: strlen, pairs, strtrim, wipe, hooksecurefunc

local function GetCleanText(text)
	if not text then return '' end
	-- remove |cCOLOR|r, |TTEXTURE|t and appended info
	text = text:gsub("\124c........", ""):gsub("\124r", ""):gsub("\124T[^\124]-\124t ", ""):gsub(" %(.-%)$", "") -- :trim()
	return text
end

local AIC_BATTLEPET = select(11, GetAuctionItemClasses())

-- [[
local lastQuery, queryResults = nil, {}
local function UpdateAutoComplete(parent, text, cursorPosition)
	if cursorPosition > strlen(text) or text == '' then return end
	if parent == BrowseName then
		wipe(queryResults)
		-- TODO: sort inverse so we can get 'last searched' entries
		for _, item in pairs(addon.scan.history) do
			local suggestion, _, quality, iLevel, _, class, subClass, _, equipSlot = addon.GetItemInfo(item)
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
					if entry.name == suggestion then
						index = i
						break
					end
				end

				if not index then
					index = #queryResults + 1
					queryResults[index] = {}
				end

				queryResults[index].name = suggestion
				queryResults[index].priority = LE_AUTOCOMPLETE_PRIORITY_OTHER
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
					GetCleanText(queryResults[1].name),
					currentText:match(parent.autoCompleteRegex or AUTOCOMPLETE_SIMPLE_REGEX)
				), 1)

			parent:SetText( GetCleanText(newText) )
			parent:HighlightText(strlen(currentText), strlen(newText))
			parent:SetCursorPosition(strlen(currentText))
		end
	end
end
local function CleanAutoCompleteOutput(self, ...)
	local editBox = self:GetParent().parent
	if not editBox.addSpaceToAutoComplete then
		local newText = GetCleanText( self:GetText() )
		editBox:SetText(newText)
		editBox:SetCursorPosition(strlen(newText))
	end
end
--]]

addon.OldRegisterEvent("AUCTION_HOUSE_SHOW", function()
	local editBox = BrowseName
	editBox.autoCompleteParams = { include = AUTOCOMPLETE_FLAG_NONE, exclude = AUTOCOMPLETE_FLAG_ALL }
	editBox.addHighlightedText = true
	editBox.autoCompleteContext = 'none'
	editBox.tiptext = 'Enter space to see a list of recent searches.'

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
	editBox:HookScript("OnEnter", addon.ShowTooltip)
	editBox:HookScript("OnLeave", addon.HideTooltip)

	hooksecurefunc('AutoComplete_Update', UpdateAutoComplete)
	for i = 1, AUTOCOMPLETE_MAX_BUTTONS do
		_G["AutoCompleteButton"..i]:HookScript('OnClick', CleanAutoCompleteOutput)
	end

	addon.OldUnregisterEvent("AUCTION_HOUSE_SHOW", "autocomplete")
end, "autocomplete")

-- TODO: FIXME: current bug when selecting battle pets via keyboard nothing gets added
