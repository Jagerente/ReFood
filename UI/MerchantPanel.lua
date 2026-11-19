local _, ns = ...

local L = ns.L
local C = ns.UI.COLORS
local Merchant = ns.Merchant
local Catalog = ns.Catalog
local SidePanel = ns.SidePanel

local MerchantPanel = {}
ns.MerchantPanel = MerchantPanel

local Money, ShortMoney = SidePanel.Money, SidePanel.ShortMoney
local HOSTS = { "MerchantFrame" }

local panel

local function RowItem(entry)
    return entry.offer.item
end

local function Detail(entry)
    local status = entry.status
    local offer = entry.offer
    if status == Merchant.BUYING then return L.AH_BUYING, C.accent end
    if status == Merchant.POOR then return L.AH_POOR, C.bad end
    if status == Merchant.PARTIAL then
        if offer.short then return string.format(L.VENDOR_AFFORD, offer.quantity), C.warn end
        return string.format(L.VENDOR_LIMITED, offer.quantity), C.warn
    end
    return SidePanel.Stock(entry), C.muted
end

local function AddLine(text, color)
    GameTooltip:AddLine(text, color[1], color[2], color[3], true)
end

local function ShowChoiceTooltip(choice)
    local offer = choice.offer
    GameTooltip:SetOwner(choice, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(offer.item)
    GameTooltip:AddLine(" ")
    AddLine(string.format(L.AH_PER_FOOD, Money(offer.unitPrice)), C.text)
    if offer.need > 0 then
        AddLine(string.format(L.AH_TIP_TOTAL, offer.quantity, Money(offer.cost)), C.muted)
    else
        AddLine(L.AH_TIP_ENOUGH, C.muted)
    end
    if offer.entry.offer ~= offer then AddLine(L.AH_TIP_PICK, C.accent) end
    GameTooltip:Show()
end

local function PaintChoice(choice, offer)
    choice.price:SetText(ShortMoney(offer.unitPrice))
    choice.price:SetTextColor(unpack(C.text))
    choice:SetEnabled(not Merchant.buying)
    choice:SetAlpha(1)
end

local function CreateRow(owner)
    local row = SidePanel.NewRow(owner, Merchant.Buy, RowItem)
    SidePanel.CreateChoices(row, Merchant.Pick, ShowChoiceTooltip)
    return row
end

local function ButtonText(entry)
    if entry.status == Merchant.ENOUGH then return L.AH_ENOUGH end
    return string.format(L.AH_BUY, math.max(entry.offer.quantity, 0))
end

local function PaintRow(row, fresh)
    local entry = row.entry
    local food = entry.offer.food
    row.icon:SetTexture(Catalog.Icon(food))
    row.name:SetText(Catalog.Name(food))
    local text, color = Detail(entry)
    row.detail:SetText(text)
    row.detail:SetTextColor(unpack(color))
    local buyable = entry.status == Merchant.READY or entry.status == Merchant.PARTIAL
    row.price:SetShown(buyable)
    if buyable then row.price:SetText(Money(entry.offer.cost)) end
    row.button.text:SetText(ButtonText(entry))
    SidePanel.SetEnabled(row.button, buyable and not Merchant.buying)
    row:SetHeight(SidePanel.HEAD_HEIGHT + SidePanel.PaintChoices(row, fresh, PaintChoice))
end

local function Paint()
    panel.subtitle:SetText(L.VENDOR_SUBTITLE)
    panel:PaintRows(Merchant.entries, CreateRow, PaintRow)
    local total = Merchant.Total()
    panel.footerText:SetText(string.format(L.AH_TOTAL, Money(total)))
    panel.footerText:SetShown(#Merchant.entries > 0)
    panel:SetAction(Merchant.buying and L.AH_BUYING or L.VENDOR_BUY_ALL, Merchant.HasPurchase() and not Merchant.buying)
end

local function Create()
    panel = SidePanel.Create("ReFoodMerchantPanel", {
        title = "VENDOR_TITLE",
        empty = "VENDOR_EMPTY",
        onAction = function() Merchant.BuyAll() end,
        actionHint = "VENDOR_BUY_ALL_DESC",
        toggles = {
            { key = "merchantAuto", label = "VENDOR_AUTO", desc = "VENDOR_AUTO_DESC" },
            { key = "countBank", label = "COUNT_BANK", desc = "COUNT_BANK_DESC" },
        },
        hosts = HOSTS,
        slot = "merchant",
        offset = { x = "merchantX", y = "merchantY" },
        settingsPage = "vendor",
    })
end

function MerchantPanel.IsShown()
    return panel ~= nil and panel:IsShown()
end

ns.Listen("MERCHANT_SHOWN", function(open)
    if not open then
        if panel then panel:Hide() end
        return
    end
    if not panel then Create() end
    Paint()
    panel:Open()
end)

local function RepaintIfShown()
    if panel and panel:IsShown() then Paint() end
end

ns.Listen("MERCHANT_CHANGED", RepaintIfShown)
ns.Listen("LOCALE_CHANGED", RepaintIfShown)
ns.Listen("NAMES_CHANGED", RepaintIfShown)
