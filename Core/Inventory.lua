local _, ns = ...

local Catalog = ns.Catalog
local GetItemCount = C_Item.GetItemCount

local Inventory = { bags = {}, total = {}, mail = {} }
ns.Inventory = Inventory

local MAX_CHOICES = 6

local bags, total, mail = Inventory.bags, Inventory.total, Inventory.mail

local function Arrived(item, grown)
    local waiting = mail[item]
    if not waiting or grown <= 0 then return end
    mail[item] = waiting > grown and waiting - grown or nil
end

local function Recount()
    local changed = false
    for item in pairs(Catalog.byItem) do
        local inBags = GetItemCount(item, false) or 0
        local everywhere = GetItemCount(item, true, false, false, true) or inBags
        if bags[item] ~= inBags or total[item] ~= everywhere then
            if total[item] then Arrived(item, everywhere - total[item]) end
            bags[item], total[item] = inBags, everywhere
            changed = true
        end
    end
    if changed then ns.Fire("INVENTORY_CHANGED") end
end
Inventory.Recount = Recount

function Inventory.Count(item)
    return bags[item] or 0
end

function Inventory.BankCount(item)
    return math.max(0, (total[item] or 0) - (bags[item] or 0))
end

function Inventory.TotalCount(item)
    return total[item] or 0
end

function Inventory.MailCount(item)
    return mail[item] or 0
end

function Inventory.AddBought(item, quantity, countBefore)
    local arrived = math.max(0, Inventory.TotalCount(item) - countBefore)
    local waiting = quantity - arrived
    if waiting <= 0 then return end
    mail[item] = Inventory.MailCount(item) + waiting
    ns.Fire("INVENTORY_CHANGED")
end

function Inventory.Cooldown(item)
    local start, duration = C_Container.GetItemCooldown(item)
    if ns.IsSecret(start) or ns.IsSecret(duration) then return 0, 0 end
    return start or 0, duration or 0
end

function Inventory.StockTarget(foodType)
    if Catalog.IsBuff(foodType) and not Catalog.BuffKind() then return 0 end
    return ns.db[foodType.stockKey]
end

local function Offered(entry, level, floor)
    if not entry.market or not Catalog.IsUsable(entry, level) then return false end
    if Catalog.IsBuff(entry.type) then return true end
    return Catalog.IsPlain(entry) and Catalog.Strength(entry) >= floor
end

function Inventory.Choices(foodType, level, out)
    wipe(out)
    if Catalog.IsBuff(foodType) and not Catalog.BuffKind() then return out end
    local floor = Catalog.EffectiveFloor(foodType, level)
    local foods = foodType.foods
    for index = #foods, 1, -1 do
        local entry = foods[index]
        if Offered(entry, level, floor) then out[#out + 1] = entry end
        if #out == MAX_CHOICES then break end
    end
    return out
end

local function Picked(foodType, level)
    local item = ns.charDB.buyPicks[foodType.key]
    local entry = item and foodType.byItem[item]
    if entry and Catalog.IsUsable(entry, level) and (not Catalog.IsBuff(foodType) or entry.kind == Catalog.BuffKind()) then
        return entry
    end
end

function Inventory.StockFood(foodType, level)
    level = level or UnitLevel("player")
    return Picked(foodType, level) or Catalog.DefaultGrade(foodType, level)
end

function Inventory.SetPick(foodType, entry, default)
    ns.charDB.buyPicks[foodType.key] = entry ~= default and entry.item or nil
    ns.Fire("STOCK_CHANGED")
end

function Inventory.Counts(entry, grade)
    return grade ~= nil and Catalog.Strength(entry) >= Catalog.Strength(grade)
end

function Inventory.Counted(foodType, level, grade, out)
    wipe(out)
    local foods = foodType.foods
    for index = #foods, 1, -1 do
        local entry = foods[index]
        if Catalog.IsUsable(entry, level) and Inventory.Counts(entry, grade) then out[#out + 1] = entry end
    end
    return out
end

local counted = {}

function Inventory.StockCount(foodType, grade)
    local level = UnitLevel("player")
    grade = grade or Inventory.StockFood(foodType, level)
    local inBags, inBank, inMail = 0, 0, 0
    for _, entry in ipairs(Inventory.Counted(foodType, level, grade, counted)) do
        inBags = inBags + Inventory.Count(entry.item)
        inBank = inBank + Inventory.BankCount(entry.item)
        inMail = inMail + Inventory.MailCount(entry.item)
    end
    return inBags, inBank, inMail
end

function Inventory.Stock(foodType, grade)
    local have, bank, inMail = Inventory.StockCount(foodType, grade)
    if not ns.db.countBank then bank = 0 end
    local need = Inventory.StockTarget(foodType) - have - bank - inMail
    return { have = have, bank = bank, mail = inMail, need = need }
end

function Inventory.GetShoppingList(out)
    wipe(out)
    local level = UnitLevel("player")
    for _, foodType in ipairs(Catalog.types) do
        if Catalog.IsActive(foodType) then
            local foods = Inventory.Choices(foodType, level, {})
            local stocks = {}
            for index, entry in ipairs(foods) do
                stocks[index] = Inventory.Stock(foodType, entry)
            end
            if stocks[1] and stocks[1].need > 0 then
                out[#out + 1] = { type = foodType, foods = foods, stocks = stocks }
            end
        end
    end
    return out
end

local MAIL_ATTACHMENTS = 16
local inbox = {}

local function CountInbox()
    wipe(inbox)
    for index = 1, GetInboxNumItems() do
        local _, _, _, _, _, cod, _, attachments = GetInboxHeaderInfo(index)
        if attachments and attachments > 0 and (cod or 0) == 0 then
            for slot = 1, MAIL_ATTACHMENTS do
                local _, item, _, count = GetInboxItem(index, slot)
                if item and total[item] then inbox[item] = (inbox[item] or 0) + count end
            end
        end
    end
end

local function OnInboxUpdate()
    Recount()
    CountInbox()
    local changed = false
    for item, count in pairs(inbox) do
        if count > Inventory.MailCount(item) then
            mail[item] = count
            changed = true
        end
    end
    if changed then ns.Fire("INVENTORY_CHANGED") end
end

ns.Listen("LOGIN", function()
    ns.RegisterEvent("BAG_UPDATE_DELAYED", Recount)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", Recount)
    ns.RegisterEvent("BANKFRAME_CLOSED", Recount)
    ns.RegisterEvent("MAIL_INBOX_UPDATE", OnInboxUpdate)
    Recount()
end)
