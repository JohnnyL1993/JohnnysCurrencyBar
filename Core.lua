-- Johnny's Currency Tracker - an always-on-screen draggable bar showing
-- Honor, Arena Points, Stone Keeper's Shards, Wintergrasp Marks of Honor,
-- and the five WotLK Emblems, as a single horizontal line of icon+value
-- segments (meant to sit along the bottom of the screen). Visually matches
-- Johnny's Addon Hub, but is a fully standalone addon (no shared code/
-- load-order dependency on it).

local Skin = CurrencyBar.Skin

local HANDLE_WIDTH = 14
local TOGGLE_WIDTH = 20
local ICON_SIZE = 16
local VALUE_WIDTH = 36
local WIDE_VALUE_WIDTH = 74 -- Honor/Arena show current/max, needs more room
local SEGMENT_GAP = 10
local ROW_HEIGHT = 22
local PADDING = 4

local CONTENT_X = PADDING + HANDLE_WIDTH + PADDING

-- Display order, left to right. "item" rows are matched by exact currency
-- name as reported by GetCurrencyListInfo; a character who has never picked
-- one up simply won't have it in the list yet (standard 3.3.5a client
-- behavior) and the segment shows "-" rather than a fabricated 0. staticIcon
-- (where set) shows immediately and doesn't wait on live currency data - see
-- UpdateRows/CreateSegment for why Honor/Arena/Marks need it.
local ROWS = {
	{ key = "honor", label = "Honor Points", kind = "honor", valueWidth = WIDE_VALUE_WIDTH },
	{
		key = "arena", label = "Arena Points", kind = "arena", valueWidth = WIDE_VALUE_WIDTH,
		staticIcon = "Interface\\PVPFrame\\PVP-ArenaPoints-Icon",
	},
	{ key = "shards", label = "Stone Keeper's Shard", kind = "item", name = "Stone Keeper's Shard" },
	{
		key = "marks", label = "Wintergrasp Mark of Honor", kind = "item", name = "Wintergrasp Mark of Honor",
		-- GetCurrencyListInfo doesn't report an icon for a currency the
		-- character has never picked up, so this shows immediately instead
		-- of leaving a question-mark icon until the first Mark is earned.
		-- Live data (if it ever differs) still overrides this once seen.
		staticIcon = "Interface\\Icons\\INV_Jewelry_Ring_66",
	},
	{ key = "heroism", label = "Emblem of Heroism", kind = "item", name = "Emblem of Heroism" },
	{ key = "valor", label = "Emblem of Valor", kind = "item", name = "Emblem of Valor" },
	{ key = "conquest", label = "Emblem of Conquest", kind = "item", name = "Emblem of Conquest" },
	{ key = "triumph", label = "Emblem of Triumph", kind = "item", name = "Emblem of Triumph" },
	{ key = "frost", label = "Emblem of Frost", kind = "item", name = "Emblem of Frost" },
	{ key = "championseal", label = "Champion's Seal", kind = "item", name = "Champion's Seal" },
	{ key = "cookingaward", label = "Dalaran Cooking Award", kind = "item", name = "Dalaran Cooking Award" },
}

local defaults = {
	point = "BOTTOM",
	relativePoint = "BOTTOM",
	x = 0,
	y = 150,
	collapsed = false,
}

local bar, handle, toggleBtn
local rowWidgets = {}
local expandedWidth = 0
local updateElapsed = 0

local function SavePosition()
	local point, _, relativePoint, x, y = bar:GetPoint()
	CurrencyBarDB.point, CurrencyBarDB.relativePoint, CurrencyBarDB.x, CurrencyBarDB.y = point, relativePoint, x, y
end

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

local function UpdateRows()
	local honor, arena, items = ScanCurrencies()

	for _, row in ipairs(ROWS) do
		local widget = rowWidgets[row.key]

		if row.kind == "honor" then
			if honor then
				widget.value:SetText(MAX_HONOR_POINTS and (honor .. "/" .. MAX_HONOR_POINTS) or tostring(honor))
			else
				widget.value:SetText("-")
			end
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
			if arena then
				widget.value:SetText(MAX_ARENA_POINTS and (arena .. "/" .. MAX_ARENA_POINTS) or tostring(arena))
			else
				widget.value:SetText("-")
			end
		else
			local data = items[row.name]
			if data then
				widget.value:SetText(tostring(data.count))
				if not widget.iconSet and data.icon and data.icon ~= "" then
					widget.icon:SetTexture(data.icon)
					widget.iconSet = true
				end
			else
				widget.value:SetText("-")
			end
		end
	end
end

local function Layout()
	local collapsed = CurrencyBarDB.collapsed

	for _, row in ipairs(ROWS) do
		local widget = rowWidgets[row.key]
		if collapsed then
			widget.seg:Hide()
		else
			widget.seg:Show()
		end
	end

	toggleBtn:ClearAllPoints()
	if collapsed then
		toggleBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", CONTENT_X, 0)
		toggleBtn.text:SetText(">")
		bar:SetSize(CONTENT_X + TOGGLE_WIDTH + PADDING, ROW_HEIGHT)
	else
		toggleBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", expandedWidth, 0)
		toggleBtn.text:SetText("<")
		bar:SetSize(expandedWidth + TOGGLE_WIDTH + PADDING, ROW_HEIGHT)
	end
end

-- Each currency is a small mouse-enabled segment (icon + value, left to
-- right) with a tooltip on hover for the full name, since there's no room
-- for a text label on every entry in a single-line bar. Returns the x
-- position the next segment should start at.
local function CreateSegment(x, row)
	local width = ICON_SIZE + 4 + (row.valueWidth or VALUE_WIDTH)

	local seg = CreateFrame("Frame", nil, bar)
	seg:SetSize(width, ROW_HEIGHT)
	seg:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
	seg:EnableMouse(true)
	seg:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(row.label)
		GameTooltip:Show()
	end)
	seg:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local icon = seg:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("LEFT", seg, "LEFT", 0, 0)
	icon:SetTexture(row.staticIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
	-- Matches Blizzard's own TokenFrame rendering (uncropped), rather than
	-- the inset crop used for equipped-item icons elsewhere in this suite.
	icon:SetTexCoord(0, 1, 0, 1)

	local value = seg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	value:SetSize(row.valueWidth or VALUE_WIDTH, ROW_HEIGHT)
	value:SetJustifyH("LEFT")
	value:SetJustifyV("MIDDLE")
	value:SetTextColor(1, 1, 1)
	value:SetText("-")

	-- Arena's icon is fully static (Blizzard never varies it), so it's done
	-- the moment it's set. Marks' staticIcon is only a first-paint fallback -
	-- iconSet stays false so live currency data can still override it.
	rowWidgets[row.key] = { seg = seg, icon = icon, value = value, iconSet = (row.kind == "arena") }

	return x + width + SEGMENT_GAP
end

local function CreateBar()
	bar = CreateFrame("Frame", "JohnnysCurrencyBar", UIParent)
	bar:SetPoint(CurrencyBarDB.point, UIParent, CurrencyBarDB.relativePoint, CurrencyBarDB.x, CurrencyBarDB.y)

	Skin:StylePanel(bar, 0.85)
	bar:SetFrameStrata("MEDIUM")

	bar:SetMovable(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	-- Dedicated drag grip, same trick as the Hub bar: once segments are
	-- packed edge-to-edge there's no bare background left to grab.
	handle = CreateFrame("Frame", nil, bar)
	handle:SetSize(HANDLE_WIDTH, ROW_HEIGHT)
	handle:SetPoint("TOPLEFT", bar, "TOPLEFT", PADDING, 0)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function() bar:StartMoving() end)
	handle:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		SavePosition()
	end)
	for i = 1, 3 do
		local dot = handle:CreateTexture(nil, "ARTWORK")
		dot:SetTexture(Skin.WHITE)
		dot:SetVertexColor(0.55, 0.55, 0.55, 1)
		dot:SetSize(HANDLE_WIDTH - 6, 2)
		dot:SetPoint("CENTER", handle, "CENTER", 0, 7 - (i - 1) * 6)
	end

	toggleBtn = Skin:CreateButton(bar, TOGGLE_WIDTH, ROW_HEIGHT, "<")
	toggleBtn:SetScript("OnClick", function()
		CurrencyBarDB.collapsed = not CurrencyBarDB.collapsed
		Layout()
	end)

	local x = CONTENT_X
	for _, row in ipairs(ROWS) do
		x = CreateSegment(x, row)
	end
	expandedWidth = x - SEGMENT_GAP + PADDING

	Layout()
	UpdateRows()
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
	elseif event == "PLAYER_ENTERING_WORLD" then
		ExpandAllHeaders()
		if not bar then
			CreateBar()
		end
		UpdateRows()
		bar:Show()
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		if bar then
			UpdateRows()
		end
	end
end)

-- Fallback poll in case CURRENCY_DISPLAY_UPDATE doesn't fire for every
-- change on this server - cheap, and only runs while the bar is shown.
eventFrame:SetScript("OnUpdate", function(self, elapsed)
	if not bar or not bar:IsShown() then
		return
	end
	updateElapsed = updateElapsed + elapsed
	if updateElapsed >= 2 then
		updateElapsed = 0
		UpdateRows()
	end
end)

SLASH_JOHNNYSCURRENCYBAR1 = "/curbar"
SlashCmdList["JOHNNYSCURRENCYBAR"] = function()
	if not bar then
		CreateBar()
	end
	if bar:IsShown() then
		bar:Hide()
	else
		bar:Show()
	end
end
