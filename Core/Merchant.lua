local _, ns = ...

local Catalog = ns.Catalog
local Inventory = ns.Inventory

local Merchant = { open = false, sells = false, entries = {}, buying = false }
ns.Merchant = Merchant

Merchant.READY = "ready"
Merchant.PARTIAL = "partial"
Merchant.POOR = "poor"
Merchant.ENOUGH = "enough"
Merchant.BUYING = "buying"

local OPEN_DELAY = 0.3
local STEP_TIMEOUT = 3
local MAX_CHOICES = 6
local UNLIMITED = -1

local entries = Merchant.entries
local byType = {}
local goods = {}
local job
local stepTimer
local windowOpen = false
local buyOnOpen = false

local function Changed()
    ns.Fire("MERCHANT_CHANGED")
end

local function CancelTimer()
    if stepTimer then stepTimer:Cancel() end
    stepTimer = nil
end

local function ReadGoods()
    wipe(goods)
    for index = 1, GetMerchantNumItems() do
        local item = GetMerchantItemID(index)
        local info = item and Catalog.byItem[item] and C_MerchantFrame.GetItemInfo(index)
        if info and info.isPurchasable ~= false and not info.hasExtendedCost and info.numAvailable ~= 0 then
            goods[item] = {
                index = index,
                price = info.price or 0,
                step = math.max(info.stackCount or 1, 1),
                available = info.numAvailable or UNLIMITED,
            }
        end
    end
end

local function Candidates(foodType, level, out)
    wipe(out)
    local floor = Catalog.EffectiveFloor(foodType, level)
    local foods = foodType.foods
    for index = #foods, 1, -1 do
        local entry = foods[index]
        if goods[entry.item] and Catalog.IsUsable(entry, level) and Catalog.AboveFloor(entry, floor) then
            out[#out + 1] = entry
        end
        if #out == MAX_CHOICES then break end
    end
    return out
end

local function Purchase(offer, need)
    local good = offer.good
    local steps = math.ceil(need / good.step)
    if good.available ~= UNLIMITED then steps = math.min(steps, good.available) end
    local affordable = good.price > 0 and math.floor(GetMoney() / good.price) or steps
    offer.short = affordable < steps
    steps = math.min(steps, affordable)
    offer.quantity = steps * good.step
    offer.cost = steps * good.price
end

local function MakeOffer(foodType, food)
    local stock = Inventory.Stock(foodType, food)
    local good = goods[food.item]
    local offer = { food = food, item = food.item, good = good, unitPrice = good.price / good.step }
    offer.need, offer.have, offer.bank, offer.mail = stock.need, stock.have, stock.bank, stock.mail
    Purchase(offer, math.max(stock.need, 0))
    return offer
end

local function ChosenOffer(entry)
    local item = ns.charDB.buyPicks[entry.type.key]
    for _, offer in ipairs(entry.offers) do
        if offer.item == item then return offer end
    end
    return entry.offers[1]
end

local function Settle(entry)
    local offer = ChosenOffer(entry)
    entry.offer = offer
    entry.need, entry.have, entry.bank, entry.mail = offer.need, offer.have, offer.bank, offer.mail
    if job and job.entry == entry then
        entry.status = Merchant.BUYING
    elseif offer.need <= 0 then
        entry.status = Merchant.ENOUGH
    elseif offer.quantity == 0 then
        entry.status = Merchant.POOR
    elseif offer.short or offer.quantity < offer.need then
        entry.status = Merchant.PARTIAL
    else
        entry.status = Merchant.READY
    end
end

local candidates = {}

local function Rebuild()
    wipe(entries)
    Merchant.sells = false
    local level = UnitLevel("player")
    for _, foodType in ipairs(Catalog.types) do
        if Catalog.IsActive(foodType) and Inventory.StockTarget(foodType) > 0 then
            Candidates(foodType, level, candidates)
            if #candidates > 0 then Merchant.sells = true end
            local entry = byType[foodType.key] or { type = foodType, offers = {} }
            byType[foodType.key] = entry
            wipe(entry.offers)
            for index, food in ipairs(candidates) do
                local offer = MakeOffer(foodType, food)
                offer.entry = entry
                entry.offers[index] = offer
            end
            if entry.offers[1] and entry.offers[1].need > 0 then
                Settle(entry)
                entries[#entries + 1] = entry
            end
        end
    end
end

local function Refresh()
    ReadGoods()
    Rebuild()
    Changed()
end

local function Buyable(entry)
    return entry.status == Merchant.READY or entry.status == Merchant.PARTIAL
end

local Step

local function Finish()
    CancelTimer()
    job = nil
    Merchant.buying = false
    Inventory.Recount()
    Refresh()
end

local function NextEntry()
    local entry = table.remove(job.queue, 1)
    if not entry then return Finish() end
    local offer = entry.offer
    local good = offer.good
    local count = C_Item.GetItemCount(offer.item)
    local maxStack = GetMerchantItemMaxStack(good.index) or good.step
    job.entry, job.item, job.index = entry, offer.item, good.index
    job.target, job.step = offer.quantity, good.step
    job.chunk = math.max(math.floor(maxStack / good.step) * good.step, good.step)
    job.base, job.last, job.issued = count, count, 0
    entry.status = Merchant.BUYING
    Changed()
    Step()
end

local function ArmTimeout()
    CancelTimer()
    stepTimer = C_Timer.NewTimer(STEP_TIMEOUT, Finish)
end

function Step()
    if not job or not Merchant.open then return Finish() end
    if not job.entry then return NextEntry() end
    local count = C_Item.GetItemCount(job.item)
    if count < job.last then return Finish() end
    job.last = count
    local got = count - job.base
    if got < job.issued then return end
    if got >= job.target then
        job.entry = nil
        return NextEntry()
    end
    local amount = math.floor(math.min(job.chunk, job.target - got) / job.step) * job.step
    if amount <= 0 or GetMerchantItemID(job.index) ~= job.item then return Finish() end
    job.issued = got + amount
    ArmTimeout()
    BuyMerchantItem(job.index, amount)
end

local function Start(list)
    if job or not Merchant.open then return end
    local queue = {}
    for _, entry in ipairs(list) do
        if Buyable(entry) then queue[#queue + 1] = entry end
    end
    if #queue == 0 then return end
    job = { queue = queue }
    Merchant.buying = true
    NextEntry()
end

function Merchant.Buy(entry)
    Start({ entry })
end

function Merchant.BuyAll()
    Start(entries)
end

function Merchant.Pick(entry, food)
    if job then return end
    Inventory.SetPick(entry.type, food, entry.offers[1].food)
    Settle(entry)
    Changed()
end

function Merchant.Total()
    local cost = 0
    for _, entry in ipairs(entries) do
        if Buyable(entry) then cost = cost + entry.offer.cost end
    end
    return cost
end

function Merchant.HasPurchase()
    for _, entry in ipairs(entries) do
        if Buyable(entry) then return true end
    end
    return false
end

local function ShowPanel(runAuto)
    Merchant.open = true
    buyOnOpen = buyOnOpen or runAuto
    ns.Schedule("merchantOpen", OPEN_DELAY, function()
        local buy = buyOnOpen
        buyOnOpen = false
        if not Merchant.open then return end
        Inventory.Recount()
        Refresh()
        if not Merchant.sells then return end
        ns.Fire("MERCHANT_SHOWN", true)
        if buy and ns.db.merchantAuto then Merchant.BuyAll() end
    end)
end

local function HidePanel()
    if not Merchant.open then return end
    Merchant.open = false
    CancelTimer()
    job = nil
    Merchant.buying = false
    wipe(entries)
    ns.Fire("MERCHANT_SHOWN", false)
end

local function OnShow()
    windowOpen = true
    if ns.db.merchant then ShowPanel(true) end
end

local function OnClosed()
    windowOpen = false
    buyOnOpen = false
    HidePanel()
end

local function SyncPanel()
    if not ns.db.merchant then
        HidePanel()
    elseif windowOpen and not Merchant.open then
        ShowPanel(false)
    end
end

local function RefreshIfIdle()
    if not Merchant.open or job then return end
    Refresh()
end

local function OnBagUpdate()
    if job then Step() end
end

local function OnLevelUp()
    ns.Schedule("merchantLevel", 0, RefreshIfIdle)
end

ns.Listen("INVENTORY_CHANGED", RefreshIfIdle)
ns.Listen("TYPES_CHANGED", RefreshIfIdle)
ns.Listen("SETTING_CHANGED", function(key)
    if key == nil or key == "merchant" then SyncPanel() end
    RefreshIfIdle()
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("MERCHANT_SHOW", OnShow)
    ns.RegisterEvent("MERCHANT_CLOSED", OnClosed)
    ns.RegisterEvent("MERCHANT_UPDATE", RefreshIfIdle)
    ns.RegisterEvent("PLAYER_MONEY", RefreshIfIdle)
    ns.RegisterEvent("PLAYER_LEVEL_UP", OnLevelUp)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", OnBagUpdate)
end)
