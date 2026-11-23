local _, ns = ...

local UI = ns.UI
local L = ns.L
local C = UI.COLORS
local T = UI.TEXT
local W = ns.Widgets
local Catalog = ns.Catalog
local Inventory = ns.Inventory
local Picker = ns.Picker
local Auras = ns.Auras

local Bar = { buttons = {} }
ns.Bar = Bar

local ORDER = { "food", "drink", "rest", "buff" }
local NAMES = {
    food = "ReFoodFood",
    drink = "ReFoodDrink",
    rest = "ReFoodRest",
    buff = "ReFoodBuff",
}
local KEY_BUTTON, PANEL_BUTTON = "Button", "PanelButton"
local TIP_GLYPH_HEIGHT = 14
local TIP_GLYPH = UI.InlineGlyph(TIP_GLYPH_HEIGHT)
local TIP_GAP = " "
local TIP_LIST_MIN_KINDS = 2
local PAD = 4
local HEADER_HEIGHT, HEADER_GAP = 14, 5
local HEADER_GLYPH_HEIGHT, HEADER_GLYPH_GAP = 11, 5
local BORDER = 1
local ICON_CROP = 0.08
local HALF = 0.5
local PRESS_INSET = 1
local LABEL_INSET = 3
local SCRIM_ALPHA = 0.85
local HOVER_ALPHA, HOVER_TIME = 0.14, 0.12
local EMPTY_ALPHA, FED_ALPHA = 0.45, 0.7
local SHOW_TIME = 0.18
local TIMER_INTERVAL = 1
local SECONDS_PER_MINUTE = 60
local BACKGROUND = { 0.078, 0.076, 0.072 }
local PERCENT = 100
local ICON_BACK = { 0, 0, 0, 0.7 }
local STRATA = "MEDIUM"
local NO_ACTION = "none"
local DRAG_MODIFIERS = { "alt-", "shift-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-", "ctrl-shift-" }
local SHOW, HIDE = "show", "hide"
local VISIBILITY_STATES = {
    always = SHOW,
    combat = "[combat] show; hide",
    never = HIDE,
}

local holder, bar, header, glyph, title
local buttons = Bar.buttons
local keyButtons = {}
local visible = {}
local barFade = {}
local driverState
local pendingLayout = false
local moving = false
local timerTicker, warnTimer

function Bar.Binding(key)
    return "CLICK " .. NAMES[key] .. KEY_BUTTON .. ":LeftButton"
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= SECONDS_PER_MINUTE then
        return string.format("%d:%02d", math.floor(seconds / SECONDS_PER_MINUTE), seconds % SECONDS_PER_MINUTE)
    end
    return tostring(seconds)
end

local function FedState()
    local spell, expiration = Auras.Fed()
    if not spell then return nil end
    local left = expiration > 0 and expiration - GetTime() or math.huge
    return spell, left, left <= ns.db.fedWarnMinutes * SECONDS_PER_MINUTE
end

local function CountColor(foodType, kept, fullColor)
    if kept == 0 then return C.bad end
    if kept < Inventory.StockTarget(foodType) then return C.warn end
    return fullColor or C.text
end

local function AddLine(text, color)
    GameTooltip:AddLine(text, color[1], color[2], color[3], true)
end

local function AddRow(left, right, leftColor, rightColor)
    GameTooltip:AddDoubleLine(left, right, leftColor[1], leftColor[2], leftColor[3], rightColor[1], rightColor[2], rightColor[3])
end

local function AddGap()
    GameTooltip:AddLine(TIP_GAP)
end

local function Describe(entry)
    return Catalog.Name(entry) .. " " .. UI.Colored(Catalog.Effect(entry), C.faint)
end

local function StockValue(foodType, have)
    local count = UI.Colored(have, CountColor(foodType, have, C.good))
    return string.format(L.TIP_STOCK_VALUE, count, Inventory.StockTarget(foodType))
end

local function AddHeader(record)
    AddGap()
    AddRow(TIP_GLYPH .. " " .. ns.TITLE, L["TYPE_" .. record.key], C.accent, C.text)
end

local function AddStockLines(foodType, grade)
    if Inventory.StockTarget(foodType) == 0 then return end
    local have, bank = Inventory.StockCount(foodType, grade)
    AddRow(L.TIP_STOCK, StockValue(foodType, have), C.muted, C.muted)
    if bank > 0 then AddRow(L.TIP_IN_BANK, bank, C.muted, C.text) end
end

local function FedValue()
    local spell, left, expiring = FedState()
    if not spell then return L.TIP_NOT_FED, C.warn end
    if left == math.huge then return L.TIP_FED_ON, C.text end
    return string.format(L.TIP_FED_LEFT, FormatTime(left)), expiring and C.warn or C.text
end

local function AddBuffLines()
    local value, color = FedValue()
    AddRow(L.TIP_FED, value, C.muted, color)
    local kind = Catalog.BuffKind()
    AddRow(L.BUFF_KIND, kind and Catalog.KindName(kind) or L.BUFF_ANY, C.muted, C.text)
end

local function RestValue(record)
    local foodType, main = record.type, record.active.main
    local have = Inventory.StockCount(foodType)
    local count = Inventory.StockTarget(foodType) > 0 and StockValue(foodType, have)
        or UI.Colored(have, have > 0 and C.text or C.bad)
    if not main then return count end
    return UI.Colored(Catalog.Name(main), C.text) .. " " .. UI.Colored(Catalog.ShortEffect(main), C.faint) .. " " .. count
end

local function AddRestRow(record)
    AddRow(L["TYPE_" .. record.key], RestValue(record), C.muted, C.muted)
end

local function AddFactLines(record, grade)
    if record.rest then
        AddRestRow(Picker.records.food)
        AddRestRow(Picker.records.drink)
    else
        AddStockLines(record.type, grade)
        if Catalog.IsBuff(record.type) then AddBuffLines() end
    end
    if InCombatLockdown() and record.text ~= record.active.text then AddLine(L.TIP_AFTER_COMBAT, C.warn) end
end

local function AddBagLines(record, grade)
    if record.rest then return end
    local foodType, owned = record.type, record.owned
    local stocked = Inventory.StockTarget(foodType) > 0
    local listed = #owned >= TIP_LIST_MIN_KINDS
    if listed then AddGap() end
    if stocked and grade then
        AddLine(string.format(L["TIP_STOCK_FROM_" .. foodType.key], UI.Colored(Catalog.Name(grade), C.text)), C.faint)
    end
    if not listed then return end
    for index = #owned, 1, -1 do
        local entry = owned[index]
        local color = (not stocked or Inventory.Counts(entry, grade)) and C.text or C.faint
        AddRow(Describe(entry), string.format(L.COUNT, Inventory.Count(entry.item)), color, color)
    end
end

local function AddHintLines()
    AddGap()
    if not InCombatLockdown() then
        AddRow(L.TIP_SHIFT_DRAG, L.TIP_TAKE_MACRO, C.accent, C.text)
        if not ns.db.locked then AddRow(L.TIP_ALT_DRAG, L.TIP_MOVE, C.accent, C.text) end
    end
    AddRow(L.TIP_RIGHT_CLICK, L.TIP_SETTINGS, C.accent, C.text)
end

local function ShowTooltip(button)
    local record = button.record
    local entry = Picker.Shown(record)
    local grade = record.type and Inventory.StockFood(record.type)
    GameTooltip:SetOwner(button, UI.VerticalAnchor(button))
    if entry then
        GameTooltip:SetItemByID(entry.item)
    else
        GameTooltip:SetText(L["TYPE_" .. record.key], C.text[1], C.text[2], C.text[3])
    end
    AddHeader(record)
    AddFactLines(record, grade)
    AddBagLines(record, grade)
    AddHintLines()
    GameTooltip:Show()
end

local function PaintCooldown(button, entry)
    local start, duration = 0, 0
    if entry then start, duration = Inventory.Cooldown(entry.item) end
    if duration > 0 then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
end

local function PaintCount(button, have)
    local foodType = button.record.type
    local shown = ns.db.showCounts and foodType ~= nil
    button.count:SetShown(shown)
    button.scrim:SetShown(shown)
    if not shown then return end
    if Inventory.StockTarget(foodType) == 0 then
        button.count:SetText(have)
        button.count:SetTextColor(unpack(have > 0 and C.text or C.bad))
        return
    end
    local kept = Inventory.StockCount(foodType)
    button.count:SetText(kept > 0 and kept or have)
    button.count:SetTextColor(unpack(CountColor(foodType, kept)))
end

local function PaintTimer(button)
    local spell, left, expiring
    if button.record.key == "buff" then spell, left, expiring = FedState() end
    local show = spell ~= nil and expiring
    button.timer:SetShown(show)
    button.timerScrim:SetShown(show)
    if show then button.timer:SetText(FormatTime(left)) end
    return spell ~= nil and not expiring
end

local function SetHalves(button, split)
    local right = split and HALF or 1 - ICON_CROP
    button.icon:SetTexCoord(ICON_CROP, right, ICON_CROP, 1 - ICON_CROP)
    if split then
        button.icon:SetPoint("BOTTOMRIGHT", button.art, "BOTTOM", 0, BORDER)
    else
        button.icon:SetPoint("BOTTOMRIGHT", button.art, "BOTTOMRIGHT", -BORDER, BORDER)
    end
    button.iconRight:SetShown(split)
end

local function PaintRest(button)
    local active = button.record.active
    local food, drink = active.food, active.drink
    local split = food ~= nil and drink ~= nil and food.item ~= drink.item
    SetHalves(button, split)
    local first = food or drink
    button.icon:SetTexture(first and Catalog.Icon(first) or nil)
    if split then button.iconRight:SetTexture(Catalog.Icon(drink)) end
    local empty = active.main == nil
    button.icon:SetDesaturated(empty)
    button.iconRight:SetDesaturated(empty)
    button.art:SetAlpha(empty and EMPTY_ALPHA or 1)
    PaintCount(button)
    button.timer:Hide()
    button.timerScrim:Hide()
    PaintCooldown(button, first)
end

local function PaintButton(button)
    if button.record.rest then return PaintRest(button) end
    local entry = Picker.Shown(button.record)
    local have = entry and Inventory.Count(entry.item) or 0
    button.icon:SetTexture(entry and Catalog.Icon(entry) or nil)
    button.icon:SetDesaturated(have == 0)
    local fed = PaintTimer(button)
    button.art:SetAlpha(have == 0 and EMPTY_ALPHA or fed and FED_ALPHA or 1)
    PaintCount(button, have)
    PaintCooldown(button, entry)
end

local function Paint()
    for _, button in ipairs(visible) do
        PaintButton(button)
    end
end

local function PaintCooldowns()
    for _, button in ipairs(visible) do
        local record = button.record
        PaintCooldown(button, record.rest and record.active.food or Picker.Shown(record))
    end
end

local function StopTicker()
    if timerTicker then timerTicker:Cancel() end
    timerTicker = nil
end

local function PaintBuff()
    local button = buttons.buff
    if button and button:IsShown() then PaintButton(button) end
end

local function ScheduleFedTimers()
    if warnTimer then warnTimer:Cancel() end
    warnTimer = nil
    local spell, left, expiring = FedState()
    if spell and expiring then
        if not timerTicker then timerTicker = C_Timer.NewTicker(TIMER_INTERVAL, PaintBuff) end
        return
    end
    StopTicker()
    if spell and left ~= math.huge then
        warnTimer = C_Timer.NewTimer(left - ns.db.fedWarnMinutes * SECONDS_PER_MINUTE, function()
            warnTimer = nil
            ScheduleFedTimers()
            PaintBuff()
        end)
    end
end

local function Highlight(button, on)
    UI.Tween(button.hover, on and HOVER_ALPHA or 0, HOVER_TIME, function(_, value) button.highlight:SetAlpha(value) end)
end

local function SavePosition()
    local point, _, _, x, y = holder:GetPoint(1)
    local position = ns.db.position
    position.point, position.x, position.y = point, x, y
end

function Bar.ResetPosition()
    local current, default = ns.db.position, ns.DEFAULTS.position
    current.point, current.x, current.y = default.point, default.x, default.y
    ns.Fire("SETTING_CHANGED", "position")
end

local function StartMoving()
    if ns.db.locked or InCombatLockdown() then return false end
    moving = true
    holder:Raise()
    holder:StartMoving()
end

local function StopMoving()
    if not moving then return end
    moving = false
    holder:StopMovingOrSizing()
    SavePosition()
end

local function OnDragStart(button)
    if not IsShiftKeyDown() or IsAltKeyDown() then return end
    GameTooltip:Hide()
    ns.Macros.Pickup(button.record.key)
end

local function StartAltMoving()
    if not IsAltKeyDown() then return false end
    GameTooltip:Hide()
    return StartMoving()
end

local function OnPanelMouseUp(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.Options.Toggle()
    elseif mouseButton == "MiddleButton" and not ns.db.locked and not InCombatLockdown() then
        Bar.ResetPosition()
    end
end

local function CreateScrims(button, overlay)
    button.scrim = overlay:CreateTexture(nil, "BACKGROUND")
    button.scrim:SetColorTexture(1, 1, 1, 1)
    button.scrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, SCRIM_ALPHA), CreateColor(0, 0, 0, 0))
    button.scrim:SetPoint("TOPLEFT", button, "LEFT", BORDER, 0)
    button.scrim:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.count = UI.BoldText(overlay, T.body, C.text)
    button.count:SetPoint("BOTTOMRIGHT", -LABEL_INSET, LABEL_INSET - 1)

    button.timerScrim = overlay:CreateTexture(nil, "BACKGROUND")
    button.timerScrim:SetColorTexture(1, 1, 1, 1)
    button.timerScrim:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, SCRIM_ALPHA))
    button.timerScrim:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.timerScrim:SetPoint("BOTTOMRIGHT", button, "RIGHT", -BORDER, 0)
    button.timerScrim:Hide()
    button.timer = UI.BoldText(overlay, T.body, C.warn)
    button.timer:SetPoint("TOP", 0, -LABEL_INSET)
    button.timer:Hide()
end

local function CreateArt(button)
    button.art = CreateFrame("Frame", nil, button)
    button.art:SetAllPoints()
    UI.Fill(button.art, ICON_BACK)
    button.icon = button.art:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    button.iconRight = button.art:CreateTexture(nil, "ARTWORK")
    button.iconRight:SetPoint("TOPLEFT", button.art, "TOP", 0, -BORDER)
    button.iconRight:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.iconRight:SetTexCoord(HALF, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    button.iconRight:Hide()

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.art)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetHideCountdownNumbers(true)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    button.highlight = UI.Fill(overlay, { 1, 1, 1, 1 }, "ARTWORK")
    button.highlight:SetPoint("TOPLEFT", BORDER, -BORDER)
    button.highlight:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    button.highlight:SetAlpha(0)
    button.hover = {}
    CreateScrims(button, overlay)
end

local function SetPressed(button, pressed)
    local inset = BORDER + (pressed and PRESS_INSET or 0)
    button.art:SetPoint("TOPLEFT", inset - BORDER, BORDER - inset)
    button.art:SetPoint("BOTTOMRIGHT", BORDER - inset, inset - BORDER)
end

local function CreateKeyButton(key)
    local button = CreateFrame("Button", NAMES[key] .. KEY_BUTTON, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", Picker.records[key].active.text)
    keyButtons[key] = button
end

local function CreateButton(key)
    local button = CreateFrame("Button", NAMES[key] .. PANEL_BUTTON, bar, "SecureActionButtonTemplate")
    button.record = Picker.records[key]
    button.UpdateTooltip = ShowTooltip
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type", "macro")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("*type2", NO_ACTION)
    button:SetAttribute("*type3", NO_ACTION)
    for _, prefix in ipairs(DRAG_MODIFIERS) do
        button:SetAttribute(prefix .. "type1", NO_ACTION)
    end
    button:SetAttribute("macrotext", button.record.active.text)
    button:Hide()
    CreateArt(button)

    button:SetScript("PostClick", OnPanelMouseUp)
    button:SetScript("OnDragStart", OnDragStart)
    W.DragHandle(button, StartAltMoving, StopMoving)
    button:HookScript("OnEnter", function(self)
        Highlight(self, true)
        ShowTooltip(self)
    end)
    button:HookScript("OnLeave", function(self)
        Highlight(self, false)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    button:HookScript("OnMouseDown", function(self) SetPressed(self, true) end)
    button:HookScript("OnMouseUp", function(self) SetPressed(self, false) end)
    button:HookScript("OnHide", function(self) SetPressed(self, false) end)
    buttons[key] = button
    return button
end

local function CreateHeader()
    header = CreateFrame("Frame", nil, bar)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header:EnableMouse(true)
    glyph = UI.AddonGlyph(header, HEADER_GLYPH_HEIGHT)
    glyph:SetPoint("LEFT")
    title = UI.BoldText(header, T.label, C.text)
    title:SetPoint("LEFT", glyph, "RIGHT", HEADER_GLYPH_GAP, 0)
    header:SetScript("OnEnter", function(self)
        W.ShowHint(self, ns.db.locked and "HEADER_LOCKED_DESC" or "HEADER_DESC")
    end)
    header:SetScript("OnLeave", W.HideHint)
    header:SetScript("OnMouseUp", OnPanelMouseUp)
    W.DragHandle(header, function()
        if ns.db.locked or InCombatLockdown() then return false end
        StartMoving()
    end, StopMoving)
end

local function HeaderWidth()
    return glyph:GetWidth() + HEADER_GLYPH_GAP + math.ceil(title:GetStringWidth())
end

local function FadeBarIn()
    barFade.tweenValue = 0
    bar:SetAlpha(0)
    UI.Tween(barFade, 1, SHOW_TIME, function(_, value) bar:SetAlpha(value) end)
end

local function PaintBackground()
    bar.background:SetAlpha(ns.db.barBackground / PERCENT)
end

local function Create()
    holder = CreateFrame("Frame", "ReFoodHolder", UIParent)
    holder:SetSize(1, 1)
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:SetFrameStrata(STRATA)
    holder:SetToplevel(true)
    holder:HookScript("OnShow", FadeBarIn)

    bar = CreateFrame("Frame", "ReFoodBar", holder)
    bar:SetPoint("TOPLEFT", holder, "CENTER")
    bar.background = UI.Fill(bar, BACKGROUND)
    PaintBackground()
    CreateHeader()
    for _, key in ipairs(ORDER) do
        CreateButton(key)
        CreateKeyButton(key)
    end
end

local function PlaceHolder()
    local position = ns.db.position
    holder:ClearAllPoints()
    holder:SetPoint(position.point, UIParent, position.point, position.x, position.y)
end

local function WantsRest()
    return ns.db.restButton and Catalog.IsActive(Catalog.byKey.food) and Catalog.IsActive(Catalog.byKey.drink)
end

local function WantsButton(key)
    if key == Picker.REST then return WantsRest() end
    local foodType = Catalog.byKey[key]
    if not Catalog.IsActive(foodType) then return false end
    local active = Picker.records[key].active
    if active.main then return true end
    if active.placeholder == nil then return false end
    return ns.TestMode.active or ns.db.showEmpty
end

local function Layout()
    wipe(visible)
    for _, key in ipairs(ORDER) do
        local button = buttons[key]
        if WantsButton(key) then
            visible[#visible + 1] = button
        else
            button:Hide()
        end
    end
    local size, gap = ns.db.iconSize, ns.db.spacing
    local horizontal = ns.db.layout == "HORIZONTAL"
    local showHeader = ns.db.showHeader
    header:SetShown(showHeader)
    title:SetText(L.HEADER)
    local top = showHeader and HEADER_HEIGHT + HEADER_GAP or 0
    for index, button in ipairs(visible) do
        local offset = (index - 1) * (size + gap)
        button:SetSize(size, size)
        button:ClearAllPoints()
        if horizontal then
            button:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + offset, -(PAD + top))
        else
            button:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -(PAD + top + offset))
        end
        button:Show()
    end
    local count = math.max(1, #visible)
    local along = count * size + (count - 1) * gap
    local width = horizontal and along or size
    local height = horizontal and size or along
    if showHeader then width = math.max(width, HeaderWidth()) end
    bar:SetSize(PAD * 2 + width, PAD * 2 + top + height)
end

local function WantedState()
    if not ns.db.enabled or #visible == 0 then return HIDE end
    if ns.TestMode.active or ns.Options.IsOpen() then return SHOW end
    return VISIBILITY_STATES[ns.db.visibility] or SHOW
end

local function ApplyVisibility()
    local state = WantedState()
    if state == driverState then return end
    driverState = state
    RegisterStateDriver(holder, "visibility", state)
end

function Bar.Refresh()
    if not holder then return end
    if InCombatLockdown() then
        pendingLayout = true
        Paint()
        return
    end
    pendingLayout = false
    Layout()
    ApplyVisibility()
    Paint()
end

local function ApplyTexts()
    if not holder or InCombatLockdown() then return end
    for key, button in pairs(buttons) do
        local text = Picker.records[key].active.text
        button:SetAttribute("macrotext", text)
        keyButtons[key]:SetAttribute("macrotext", text)
    end
end

local function OnAurasChanged()
    ScheduleFedTimers()
    PaintBuff()
end

ns.Listen("PICKS_APPLIED", ApplyTexts)
ns.Listen("PICKS_CHANGED", Bar.Refresh)
ns.Listen("INVENTORY_CHANGED", Paint)
ns.Listen("STOCK_CHANGED", Paint)
ns.Listen("AURAS_CHANGED", OnAurasChanged)
ns.Listen("TYPES_CHANGED", Bar.Refresh)
ns.Listen("TEST_MODE_CHANGED", Bar.Refresh)
ns.Listen("OPTIONS_SHOWN", Bar.Refresh)
ns.Listen("LOCALE_CHANGED", Bar.Refresh)
ns.Listen("SETTING_CHANGED", function(key)
    if not holder then return end
    if (key == nil or key == "position") and not InCombatLockdown() then PlaceHolder() end
    if key == nil or key == "fedWarnMinutes" then ScheduleFedTimers() end
    if key == nil or key == "barBackground" then PaintBackground() end
    Bar.Refresh()
end)

ns.Listen("LOGIN", function()
    Create()
    PlaceHolder()
    ns.RegisterEvent("BAG_UPDATE_COOLDOWN", PaintCooldowns)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        StopMoving()
        if pendingLayout then Bar.Refresh() end
    end)
    Bar.Refresh()
    ScheduleFedTimers()
end)
