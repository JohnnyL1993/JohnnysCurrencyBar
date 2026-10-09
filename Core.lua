-- Johnny's Currency Tracker - an edge drawer, like Johnny's Addon Hub: a slim
-- "CUR" tab docked to the right, left or top edge of the screen. Hovering the
-- tab (or clicking it to pin) slides out a panel listing Honor, Arena Points,
-- Stone Keeper's Shards, Wintergrasp Marks of Honor, the five WotLK Emblems
-- and a couple of other tokens, one row each: icon, name, amount.
--
-- Only currencies you actually hold are listed by default. An amount flashes
-- lime when it goes up (and so does the tab, so you notice with the drawer
-- shut); Honor and Arena turn amber near their cap. Hover a row for its cap
-- and what you've gained this session; right-click the tab or the panel to
-- choose what's listed and which edge it docks to.
--
-- Fully standalone (no shared code/load-order dependency on the Hub).

local Skin = CurrencyBar.Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT_TITLE = "Fonts\\ARIALN.TTF"
local FONT_TEXT = "Fonts\\FRIZQT__.TTF"

-- Palette shared with the rest of the suite.
local C = {
	ground = { 0.063, 0.078, 0.086 },
	panel = { 0.090, 0.114, 0.125 },
	raised = { 0.122, 0.153, 0.169 },
	rule = { 0.180, 0.224, 0.243 },
	text = { 0.902, 0.925, 0.918 },
	muted = { 0.604, 0.659, 0.651 },
	accent = { 0.725, 0.886, 0.290 },
	nearCap = { 1.000, 0.850, 0.400 },
	atCap = { 1.000, 0.450, 0.400 },
}

local PANEL_WIDTH = 190
local HEADER_HEIGHT = 26
local ROW_HEIGHT = 22
local FOOTER_HEIGHT = 18
local ICON_SIZE = 16
local TAB_THICKNESS = 16
local TAB_LENGTH = 64
local SLIDE_SPEED = 6 -- full open/close takes 1/6 of a second
local CLOSE_DELAY = 0.35 -- grace period after the mouse leaves before closing
local DRAG_THRESHOLD = 6

-- A capped currency stops accumulating, so warn before it gets there.
local NEAR_CAP_FRACTION = 0.9
-- How long an amount (and the tab) stays lime after a gain.
local GAIN_FLASH_SECONDS = 6

-- Display order, top to bottom. "item" rows are matched by exact currency
-- name as reported by GetCurrencyListInfo; a character who has never picked
-- one up simply won't have it in the list yet (standard 3.3.5a client
-- behavior). `short` is the row's label; `label` the full name for tooltips
-- and the menu. staticIcon (where set) shows immediately and doesn't wait on
-- live currency data.
local ROWS = {
	{ key = "honor", label = "Honor Points", short = "Honor", kind = "honor" },
	{
		key = "arena", label = "Arena Points", short = "Arena", kind = "arena",
		staticIcon = "Interface\\PVPFrame\\PVP-ArenaPoints-Icon",
	},
	{ key = "shards", label = "Stone Keeper's Shard", short = "Stone Keeper's Shards", kind = "item", name = "Stone Keeper's Shard" },
	{
		key = "marks", label = "Wintergrasp Mark of Honor", short = "Wintergrasp Marks", kind = "item", name = "Wintergrasp Mark of Honor",
		-- GetCurrencyListInfo doesn't report an icon for a currency the
		-- character has never picked up, so this shows immediately instead
		-- of a question-mark icon. Live data still overrides it once seen.
		staticIcon = "Interface\\Icons\\INV_Jewelry_Ring_66",
	},
	{ key = "heroism", label = "Emblem of Heroism", short = "Heroism", kind = "item", name = "Emblem of Heroism" },
	{ key = "valor", label = "Emblem of Valor", short = "Valor", kind = "item", name = "Emblem of Valor" },
	{ key = "conquest", label = "Emblem of Conquest", short = "Conquest", kind = "item", name = "Emblem of Conquest" },
	{ key = "triumph", label = "Emblem of Triumph", short = "Triumph", kind = "item", name = "Emblem of Triumph" },
	{ key = "frost", label = "Emblem of Frost", short = "Frost", kind = "item", name = "Emblem of Frost" },
	{ key = "championseal", label = "Champion's Seal", short = "Champion's Seals", kind = "item", name = "Champion's Seal" },
	{ key = "cookingaward", label = "Dalaran Cooking Award", short = "Cooking Awards", kind = "item", name = "Dalaran Cooking Award" },
}

local defaults = {
	-- The Hub's drawer defaults to the left edge, so this one starts on the right.
	dock = "RIGHT",
	offset = 0,
	pinned = false,
	hover = true,
	-- Hide currencies you hold none of (or have never earned).
	hideEmpty = true,
}

local drawer, tab, pinBtn, emptyHint
local rowWidgets = {}
local progress = 0 -- 0 = tucked away, 1 = fully out
local lastOver = 0
local pressX, pressY
local dragging = false
local updateElapsed = 0
local tabFlashUntil = 0
-- [key] = amount the first time it was read this session, for "+N this session".
local sessionStart = {}

local function Solid(parent, layer, color, alpha)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetTexture(WHITE)
	tex:SetVertexColor(color[1], color[2], color[3], alpha or 1)
	return tex
end

local function StyleBox(frame, color, alpha)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
	frame:SetBackdropBorderColor(C.rule[1], C.rule[2], C.rule[3], 1)
end

local function Text(parent, font, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(font, size)
	fs:SetTextColor(color[1], color[2], color[3])
	return fs
end

-- 12345 -> "12,345".
local function FormatNumber(n)
	local text = tostring(math.floor(n + 0.5))
	local formatted, count = text, 0
	repeat
		formatted, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return formatted
end

--------------------------------------
--   Currency data                  --
--------------------------------------

-- Collapsed headers hide their currency children from GetCurrencyListInfo
-- entirely, so every header has to be expanded once before the list can be
-- scanned reliably. Indices shift each time a header is expanded, so this
-- restarts the scan after each expansion rather than trying to compensate.
local function ExpandAllHeaders()
	local guard = 0
	local expandedSomething = true
	while expandedSomething and guard < 20 do
		expandedSomething = false
		guard = guard + 1
		for i = 1, GetCurrencyListSize() do
			local name, isHeader, isExpanded = GetCurrencyListInfo(i)
			if isHeader and not isExpanded then
				ExpandCurrencyList(i, true)
				expandedSomething = true
				break
			end
		end
	end
end

local function ScanCurrencies()
	local honor, arena
	local items = {}
	for i = 1, GetCurrencyListSize() do
		local name, isHeader, isExpanded, isUnused, isWatched, count, extraCurrencyType, icon = GetCurrencyListInfo(i)
		if not isHeader and name then
			if extraCurrencyType == 2 then
				honor = count
			elseif extraCurrencyType == 1 then
				arena = count
			else
				items[name] = { count = count, icon = icon }
			end
		end
	end
	return honor, arena, items
end

local function IsHidden(row)
	return CurrencyBarDB.hidden and CurrencyBarDB.hidden[row.key]
end

-- Whether a row should be listed right now: not switched off, and (unless
-- "hide empty" is off) holding at least one.
local function IsVisible(row)
	if IsHidden(row) then
		return false
	end
	if CurrencyBarDB.hideEmpty then
		local widget = rowWidgets[row.key]
		return widget.count ~= nil and widget.count > 0
	end
	return true
end

--------------------------------------
--   Drawer position                --
--------------------------------------

local function ClampOffset(offset)
	local limit
	if CurrencyBarDB.dock == "TOP" then
		limit = (UIParent:GetWidth() - PANEL_WIDTH) / 2
	else
		limit = (UIParent:GetHeight() - drawer:GetHeight()) / 2
	end
	if limit < 0 then
		limit = 0
	end
	return math.max(-limit, math.min(limit, offset))
end

local function ApplyPosition()
	-- Ease out so the panel decelerates into place.
	local hidden = (1 - progress) * (1 - progress)
	local offset = ClampOffset(CurrencyBarDB.offset or 0)

	drawer:ClearAllPoints()
	if CurrencyBarDB.dock == "LEFT" then
		drawer:SetPoint("LEFT", UIParent, "LEFT", -PANEL_WIDTH * hidden, offset)
	elseif CurrencyBarDB.dock == "TOP" then
		drawer:SetPoint("TOP", UIParent, "TOP", offset, drawer:GetHeight() * hidden)
	else
		drawer:SetPoint("RIGHT", UIParent, "RIGHT", PANEL_WIDTH * hidden, offset)
	end
end

local function LayoutTab()
	local dock = CurrencyBarDB.dock
	tab:ClearAllPoints()
	tab.mark:ClearAllPoints()
	if dock == "TOP" then
		tab:SetWidth(TAB_LENGTH)
		tab:SetHeight(TAB_THICKNESS)
		tab:SetPoint("TOP", drawer, "BOTTOM", 0, 1)
		tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
		tab.mark:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
		tab.mark:SetHeight(2)
		tab.label:SetText("CUR")
	else
		tab:SetWidth(TAB_THICKNESS)
		tab:SetHeight(TAB_LENGTH)
		if dock == "LEFT" then
			tab:SetPoint("LEFT", drawer, "RIGHT", -1, 0)
			tab.mark:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0)
			tab.mark:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
		else
			tab:SetPoint("RIGHT", drawer, "LEFT", 1, 0)
			tab.mark:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
			tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
		end
		tab.mark:SetWidth(2)
		-- No rotated text on this client, so stack the letters instead.
		tab.label:SetText("C\nU\nR")
	end
end

local function RefreshPin()
	local color = CurrencyBarDB.pinned and C.accent or C.muted
	pinBtn.text:SetText(CurrencyBarDB.pinned and "PINNED" or "PIN")
	pinBtn.text:SetTextColor(color[1], color[2], color[3])
end

local function TogglePinned()
	CurrencyBarDB.pinned = not CurrencyBarDB.pinned
	if not CurrencyBarDB.pinned then
		-- Don't linger on the close delay after an explicit un-pin.
		lastOver = 0
	end
	RefreshPin()
end

local function SetDock(dock)
	CurrencyBarDB.dock = dock
	CurrencyBarDB.offset = 0
	LayoutTab()
	ApplyPosition()
end

--------------------------------------
--   Rows                           --
--------------------------------------

-- Stacks the visible rows under the header and sizes the panel to fit.
local function Layout()
	local y = -(1 + HEADER_HEIGHT)
	local shown = 0
	for _, row in ipairs(ROWS) do
		local widget = rowWidgets[row.key]
		if IsVisible(row) then
			widget.seg:ClearAllPoints()
			widget.seg:SetPoint("TOPLEFT", drawer, "TOPLEFT", 1, y)
			widget.seg:Show()
			y = y - ROW_HEIGHT
			shown = shown + 1
		else
			widget.seg:Hide()
		end
	end

	if shown == 0 then
		emptyHint:Show()
		y = y - 34
	else
		emptyHint:Hide()
	end

	drawer:SetHeight(-y + FOOTER_HEIGHT + 1)
	ApplyPosition()
end

local function SetValue(row, widget, count, cap)
	local previous = widget.count
	widget.count = count
	widget.cap = cap

	if count == nil then
		widget.value:SetText("-")
		return
	end
	if sessionStart[row.key] == nil then
		sessionStart[row.key] = count
	end
	if previous ~= nil and count > previous then
		widget.gainUntil = GetTime() + GAIN_FLASH_SECONDS
		tabFlashUntil = widget.gainUntil
	end
	widget.value:SetText(FormatNumber(count))
end

-- Amount colour: lime for a few seconds after a gain, otherwise amber/red
-- as a capped currency fills up, otherwise plain.
local function PaintValue(widget)
	local color = C.text
	if widget.count == nil then
		color = C.muted
	elseif widget.gainUntil and GetTime() < widget.gainUntil then
		color = C.accent
	elseif widget.cap and widget.cap > 0 then
		if widget.count >= widget.cap then
			color = C.atCap
		elseif widget.count >= widget.cap * NEAR_CAP_FRACTION then
			color = C.nearCap
		end
	end
	widget.value:SetTextColor(color[1], color[2], color[3])
end

local function UpdateRows()
	local honor, arena, items = ScanCurrencies()

	for _, row in ipairs(ROWS) do
		local widget = rowWidgets[row.key]

		if row.kind == "honor" then
			SetValue(row, widget, honor, MAX_HONOR_POINTS)
			-- Matches Blizzard's own TokenFrame: Honor Points has no real
			-- icon/itemID of its own, it's shown as the player's PvP-frame
			-- faction emblem. UnitFactionGroup can be nil for a moment right
			-- at login, so this keeps retrying until it resolves.
			if not widget.iconSet then
				local factionGroup = UnitFactionGroup("player")
				if factionGroup then
					widget.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. factionGroup)
					widget.icon:SetTexCoord(0.03125, 0.59375, 0.03125, 0.59375)
					widget.iconSet = true
				end
			end
		elseif row.kind == "arena" then
			SetValue(row, widget, arena, MAX_ARENA_POINTS)
		else
			local data = items[row.name]
			SetValue(row, widget, data and data.count or nil, nil)
			if data and not widget.iconSet and data.icon and data.icon ~= "" then
				widget.icon:SetTexture(data.icon)
				widget.iconSet = true
			end
		end
		PaintValue(widget)
	end

	Layout()

	-- The tab's letters go lime while a gain is still fresh.
	local tabColor = (GetTime() < tabFlashUntil) and C.accent or C.text
	tab.label:SetTextColor(tabColor[1], tabColor[2], tabColor[3])
end

--------------------------------------
--   Right-click menu               --
--------------------------------------

local menuFrame = CreateFrame("Frame", "JohnnysCurrencyBarMenu", UIParent, "UIDropDownMenuTemplate")

local function ShowMenu()
	CurrencyBarDB.hidden = CurrencyBarDB.hidden or {}
	local menu = {
		{ text = "Currency Tracker", isTitle = 1, notCheckable = 1 },
		{
			text = "Keep open (pin)",
			checked = CurrencyBarDB.pinned and true or false,
			func = TogglePinned,
		},
		{
			text = "Open when the mouse touches the tab",
			checked = CurrencyBarDB.hover and true or false,
			keepShownOnClick = 1,
			func = function()
				CurrencyBarDB.hover = not CurrencyBarDB.hover
			end,
		},
		{
			text = "Hide currencies I have none of",
			checked = CurrencyBarDB.hideEmpty and true or false,
			keepShownOnClick = 1,
			func = function()
				CurrencyBarDB.hideEmpty = not CurrencyBarDB.hideEmpty
				Layout()
			end,
		},
		{ text = "Dock to", isTitle = 1, notCheckable = 1 },
	}
	for _, dock in ipairs({ { "LEFT", "Left edge" }, { "RIGHT", "Right edge" }, { "TOP", "Top edge" } }) do
		table.insert(menu, {
			text = dock[2],
			checked = (CurrencyBarDB.dock == dock[1]),
			func = function() SetDock(dock[1]) end,
		})
	end
	table.insert(menu, { text = "List", isTitle = 1, notCheckable = 1 })
	for _, row in ipairs(ROWS) do
		table.insert(menu, {
			text = row.label,
			checked = not IsHidden(row),
			keepShownOnClick = 1,
			func = function()
				CurrencyBarDB.hidden[row.key] = (not CurrencyBarDB.hidden[row.key]) or nil
				Layout()
			end,
		})
	end
	table.insert(menu, { text = CANCEL or "Cancel", notCheckable = 1 })
	EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
end

--------------------------------------
--   Build                          --
--------------------------------------

local function ShowRowTooltip(seg)
	local row, widget = seg.row, rowWidgets[seg.row.key]
	GameTooltip:SetOwner(seg, (CurrencyBarDB.dock == "RIGHT") and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
	GameTooltip:AddLine(row.label, 1, 1, 1)
	if widget.count == nil then
		GameTooltip:AddLine("None earned yet on this character.", C.muted[1], C.muted[2], C.muted[3])
	else
		if widget.cap and widget.cap > 0 then
			GameTooltip:AddDoubleLine("Held", string.format("%s of %s (%d%%)", FormatNumber(widget.count), FormatNumber(widget.cap),
				math.floor(widget.count / widget.cap * 100 + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
			if widget.count >= widget.cap then
				GameTooltip:AddLine("At the cap - anything more you earn is lost.", C.atCap[1], C.atCap[2], C.atCap[3])
			elseif widget.count >= widget.cap * NEAR_CAP_FRACTION then
				GameTooltip:AddLine("Close to the cap.", C.nearCap[1], C.nearCap[2], C.nearCap[3])
			end
		else
			GameTooltip:AddDoubleLine("Held", FormatNumber(widget.count), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		local gained = widget.count - (sessionStart[row.key] or widget.count)
		if gained ~= 0 then
			local color = (gained > 0) and C.accent or C.atCap
			GameTooltip:AddDoubleLine("This session", (gained > 0 and "+" or "-") .. FormatNumber(math.abs(gained)),
				0.8, 0.8, 0.8, color[1], color[2], color[3])
		end
	end
	GameTooltip:Show()
end

local function CreateRow(row)
	local seg = CreateFrame("Frame", nil, drawer)
	seg:SetSize(PANEL_WIDTH - 2, ROW_HEIGHT)
	seg.row = row
	seg:EnableMouse(true)

	local hover = Solid(seg, "BACKGROUND", C.raised)
	hover:SetAllPoints()
	hover:Hide()

	seg:SetScript("OnEnter", function(self)
		hover:Show()
		ShowRowTooltip(self)
	end)
	seg:SetScript("OnLeave", function()
		hover:Hide()
		GameTooltip:Hide()
	end)
	seg:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			ShowMenu()
		end
	end)

	local icon = seg:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("LEFT", seg, "LEFT", 9, 0)
	icon:SetTexture(row.staticIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
	-- Matches Blizzard's own TokenFrame rendering (uncropped), rather than
	-- the inset crop used for equipped-item icons elsewhere in this suite.
	icon:SetTexCoord(0, 1, 0, 1)

	local value = Text(seg, FONT_TEXT, 11, C.text)
	value:SetPoint("RIGHT", seg, "RIGHT", -9, 0)
	value:SetJustifyH("RIGHT")
	value:SetText("-")

	local label = Text(seg, FONT_TEXT, 11, C.muted)
	label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
	label:SetPoint("RIGHT", value, "LEFT", -6, 0)
	label:SetJustifyH("LEFT")
	label:SetHeight(12)
	label:SetText(row.short)

	-- Arena's icon is fully static (Blizzard never varies it), so it's done
	-- the moment it's set. Marks' staticIcon is only a first-paint fallback -
	-- iconSet stays false so live currency data can still override it.
	rowWidgets[row.key] = { seg = seg, icon = icon, value = value, iconSet = (row.kind == "arena") }
end

local function OnUpdate(self, elapsed)
	local db = CurrencyBarDB

	-- Dragging the tab slides the whole drawer along its edge.
	if pressX then
		local x, y = GetCursorPosition()
		if not dragging and (math.abs(x - pressX) > DRAG_THRESHOLD or math.abs(y - pressY) > DRAG_THRESHOLD) then
			dragging = true
		end
		if dragging then
			local scale = UIParent:GetEffectiveScale()
			if db.dock == "TOP" then
				db.offset = ClampOffset(x / scale - UIParent:GetWidth() / 2)
			else
				db.offset = ClampOffset(y / scale - UIParent:GetHeight() / 2)
			end
			ApplyPosition()
		end
	end

	local menuOpen = DropDownList1 and DropDownList1:IsShown()
	local over = MouseIsOver(tab) or (progress > 0 and (MouseIsOver(drawer) or menuOpen))
	local now = GetTime()
	if over then
		lastOver = now
	end

	local want
	if db.pinned then
		want = true
	elseif dragging then
		want = progress > 0.5
	elseif db.hover then
		want = over or (progress > 0 and (now - lastOver) < CLOSE_DELAY)
	else
		want = false
	end

	local target = want and 1 or 0
	if progress ~= target then
		local step = elapsed * SLIDE_SPEED
		if progress < target then
			progress = math.min(1, progress + step)
		else
			progress = math.max(0, progress - step)
		end
		ApplyPosition()
	end

	-- Fallback poll in case CURRENCY_DISPLAY_UPDATE doesn't fire for every
	-- change on this server - cheap. Also what ends a gain flash.
	updateElapsed = updateElapsed + elapsed
	if updateElapsed >= 2 then
		updateElapsed = 0
		UpdateRows()
	end
end

local function CreateDrawer()
	drawer = CreateFrame("Frame", "JohnnysCurrencyBar", UIParent)
	drawer:SetFrameStrata("MEDIUM")
	drawer:SetWidth(PANEL_WIDTH)
	drawer:SetHeight(HEADER_HEIGHT + FOOTER_HEIGHT + 2)
	drawer:EnableMouse(true)
	StyleBox(drawer, C.ground, 0.95)
	drawer:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			ShowMenu()
		end
	end)

	local head = Solid(drawer, "BORDER", C.panel)
	head:SetPoint("TOPLEFT", drawer, "TOPLEFT", 1, -1)
	head:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -1, -1)
	head:SetHeight(HEADER_HEIGHT)

	local title = Text(drawer, FONT_TITLE, 14, C.text)
	title:SetPoint("LEFT", head, "LEFT", 9, 0)
	title:SetText("CURRENCIES")

	pinBtn = CreateFrame("Button", nil, drawer)
	pinBtn:SetWidth(54)
	pinBtn:SetHeight(HEADER_HEIGHT)
	pinBtn:SetPoint("RIGHT", head, "RIGHT", 0, 0)
	pinBtn.text = Text(pinBtn, FONT_TEXT, 10, C.muted)
	pinBtn.text:SetPoint("RIGHT", pinBtn, "RIGHT", -9, 0)
	pinBtn:SetScript("OnClick", TogglePinned)

	local footRule = Solid(drawer, "ARTWORK", C.rule)
	footRule:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 1, FOOTER_HEIGHT)
	footRule:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", -1, FOOTER_HEIGHT)
	footRule:SetHeight(1)

	local foot = Text(drawer, FONT_TEXT, 10, C.muted)
	foot:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 10, 1)
	foot:SetHeight(FOOTER_HEIGHT - 1)
	foot:SetJustifyV("MIDDLE")
	foot:SetText("Right-click for options")

	emptyHint = Text(drawer, FONT_TEXT, 10, C.muted)
	emptyHint:SetPoint("TOPLEFT", drawer, "TOPLEFT", 10, -(HEADER_HEIGHT + 8))
	emptyHint:SetWidth(PANEL_WIDTH - 20)
	emptyHint:SetJustifyH("LEFT")
	emptyHint:SetText("Nothing to list. Right-click to choose currencies.")
	emptyHint:Hide()

	tab = CreateFrame("Button", "JohnnysCurrencyBarTab", drawer)
	StyleBox(tab, C.panel, 0.95)
	tab.mark = Solid(tab, "ARTWORK", C.accent)
	tab.label = Text(tab, FONT_TEXT, 10, C.text)
	tab.label:SetPoint("CENTER", tab, "CENTER", 0, 0)
	tab.label:SetJustifyH("CENTER")

	-- Left-click pins/unpins, left-drag moves along the edge, right-click
	-- opens the options menu.
	tab:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			pressX, pressY = GetCursorPosition()
			dragging = false
		end
	end)
	tab:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			ShowMenu()
		elseif button == "LeftButton" then
			if not dragging then
				TogglePinned()
			end
			dragging = false
			pressX, pressY = nil, nil
		end
	end)

	for _, row in ipairs(ROWS) do
		CreateRow(row)
	end

	LayoutTab()
	RefreshPin()
	UpdateRows()

	drawer:SetScript("OnUpdate", OnUpdate)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
	if event == "ADDON_LOADED" then
		if addonName ~= "JohnnysCurrencyBar" then
			return
		end
		CurrencyBarDB = CurrencyBarDB or {}
		for k, v in pairs(defaults) do
			if CurrencyBarDB[k] == nil then
				CurrencyBarDB[k] = v
			end
		end
		CurrencyBarDB.hidden = CurrencyBarDB.hidden or {}
	elseif event == "PLAYER_ENTERING_WORLD" then
		ExpandAllHeaders()
		if not drawer then
			CreateDrawer()
		end
		UpdateRows()
		drawer:Show()
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		if drawer then
			UpdateRows()
		end
	end
end)

-- /curbar            hide or show the tab completely
-- /curbar left|right|top   dock to that edge
-- /curbar pin        keep the drawer open
SLASH_JOHNNYSCURRENCYBAR1 = "/curbar"
SlashCmdList["JOHNNYSCURRENCYBAR"] = function(input)
	if not drawer then
		CreateDrawer()
	end
	local cmd = string.lower(strtrim(input or ""))
	if cmd == "left" or cmd == "right" or cmd == "top" then
		SetDock(string.upper(cmd))
	elseif cmd == "pin" then
		TogglePinned()
	elseif cmd == "" then
		if drawer:IsShown() then
			drawer:Hide()
		else
			drawer:Show()
		end
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffb9e24aCurrency Tracker|r: /curbar (hide or show), /curbar left | right | top (dock), /curbar pin (keep open). Right-click the tab for more.")
	end
end
