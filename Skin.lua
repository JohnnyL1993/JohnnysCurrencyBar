-- Flat black/white "modern" skin, matching Johnny's Addon Hub look so both
-- bars read as one visual family. Deliberately a standalone copy (not a
-- shared library) so this addon has no load-order dependency on the Hub.
CurrencyBar = {}
CurrencyBar.Skin = {}
local Skin = CurrencyBar.Skin

-- Flat white 1x1 texture, tinted per-use - the standard trick for solid-color
-- panels/borders without needing any custom art.
Skin.WHITE = "Interface\\Buttons\\WHITE8X8"

function Skin:StylePanel(frame, alpha)
	frame:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	frame:SetBackdropColor(0.03, 0.03, 0.03, alpha or 0.92)
	frame:SetBackdropBorderColor(0.180, 0.224, 0.243, 1)
end

function Skin:StyleButton(btn)
	btn:SetBackdrop({ bgFile = self.WHITE, edgeFile = self.WHITE, edgeSize = 1 })
	btn:SetBackdropColor(0.090, 0.114, 0.125, 0.95)
	btn:SetBackdropBorderColor(0.243, 0.298, 0.322, 1)

	local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(self.WHITE)
	highlight:SetVertexColor(0.725, 0.886, 0.290, 0.14)
	btn:SetHighlightTexture(highlight)

	btn:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			self:SetBackdropColor(0.160, 0.200, 0.220, 0.95)
		end
	end)
	btn:SetScript("OnMouseUp", function(self)
		self:SetBackdropColor(0.090, 0.114, 0.125, 0.95)
	end)
end

-- Creates a flat-skinned button with a centered white label. Returns the
-- button; its font string is at btn.text if the caller needs to recolor it.
function Skin:CreateButton(parent, width, height, text)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width, height)
	self:StyleButton(btn)

	local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("CENTER")
	fs:SetTextColor(1, 1, 1)
	if text then
		fs:SetText(text)
	end
	btn.text = fs

	return btn
end
