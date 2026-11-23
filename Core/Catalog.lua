local _, ns = ...

local Catalog = { types = {}, byKey = {}, byItem = {}, kinds = {}, kindByKey = {}, buffSpells = {} }
ns.Catalog = Catalog

local PERCENT = 100
local NAME_DELAY = 0.2
local TYPE_DEFS = {
    { key = "food", pool = "health", list = ns.FOODS.food },
    { key = "drink", pool = "mana", list = ns.FOODS.drink },
    { key = "buff", list = ns.BUFF_FOODS },
}
local MANA = Enum.PowerType.Mana
local PERCENT_STATS = { CRIT = true, SPEED = true }

local UnitHealthMax, UnitPowerMax = UnitHealthMax, UnitPowerMax

local function Register(entry, foodType)
    entry.type = foodType
    foodType.byItem[entry.item] = entry
    Catalog.byItem[entry.item] = Catalog.byItem[entry.item] or entry
end

for index, def in ipairs(TYPE_DEFS) do
    local foodType = {
        key = def.key,
        index = index,
        pool = def.pool,
        all = def.list,
        foods = def.list,
        byItem = {},
        floorKey = def.pool and def.key .. "Floor",
        stockKey = def.key .. "Stock",
    }
    for _, entry in ipairs(def.list) do
        Register(entry, foodType)
    end
    Catalog.types[index] = foodType
    Catalog.byKey[def.key] = foodType
end

local FOOD, DRINK, BUFF = Catalog.byKey.food, Catalog.byKey.drink, Catalog.byKey.buff
Catalog.BUFF = BUFF

for index, kind in ipairs(ns.BUFF_KINDS) do
    kind.index = index
    kind.foods = {}
    Catalog.kinds[index] = kind
    Catalog.kindByKey[kind.key] = kind
end

for _, entry in ipairs(BUFF.all) do
    local kind = Catalog.kindByKey[entry.kind]
    entry.kind = kind
    kind.foods[#kind.foods + 1] = entry
    kind.level = math.min(kind.level or entry.level, entry.level)
    Catalog.buffSpells[entry.spell] = entry
end

for _, foodType in ipairs({ FOOD, DRINK }) do
    local other = foodType == FOOD and DRINK or FOOD
    for _, entry in ipairs(foodType.all) do
        entry.buff = BUFF.byItem[entry.item]
        entry.dual = other.byItem[entry.item] ~= nil
    end
end

local SETTING_TYPES = {}
for _, foodType in ipairs(Catalog.types) do
    if foodType.floorKey then SETTING_TYPES[foodType.floorKey] = foodType end
    SETTING_TYPES[foodType.stockKey] = foodType
end
SETTING_TYPES.conjuredFirst = FOOD

function Catalog.TypeOfSetting(key)
    return SETTING_TYPES[key]
end

function Catalog.IsBuff(foodType)
    return foodType == BUFF
end

function Catalog.MaxPool(foodType)
    local value
    if foodType.pool == "health" then
        value = UnitHealthMax("player")
    elseif foodType.pool == "mana" then
        value = UnitPowerMax("player", MANA)
    end
    if value == nil or ns.IsSecret(value) then return nil end
    return value
end

function Catalog.HasPool(foodType)
    if foodType.pool ~= "mana" then return true end
    local max = Catalog.MaxPool(foodType)
    return max == nil or max > 0
end

function Catalog.IsEnabled(foodType)
    local choice = ns.charDB.types[foodType.key]
    if choice == nil then return Catalog.HasPool(foodType) end
    return choice
end

function Catalog.IsActive(foodType)
    return Catalog.HasPool(foodType) and Catalog.IsEnabled(foodType)
end

function Catalog.SetEnabled(foodType, enabled)
    ns.charDB.types[foodType.key] = enabled
    ns.Fire("TYPES_CHANGED")
end

function Catalog.BuffKind()
    local key = ns.charDB and ns.charDB.buffKind
    return key and Catalog.kindByKey[key]
end

function Catalog.Strength(entry)
    if entry.type == BUFF then
        if Catalog.BuffKind() then return entry.value end
        return entry.level
    end
    if entry.percent then
        local max = Catalog.MaxPool(entry.type)
        return max and max * entry.percent / PERCENT or 0
    end
    return entry.amount
end

local function Weaker(a, b)
    local strengthA, strengthB = Catalog.Strength(a), Catalog.Strength(b)
    if strengthA ~= strengthB then return strengthA < strengthB end
    if a.level ~= b.level then return a.level < b.level end
    return a.item < b.item
end

local function SortType(foodType)
    table.sort(foodType.foods, Weaker)
end

function Catalog.Resort()
    SortType(FOOD)
    SortType(DRINK)
end

local function ApplyBuffKind()
    local kind = Catalog.BuffKind()
    BUFF.foods = kind and kind.foods or BUFF.all
    SortType(BUFF)
end

function Catalog.SetBuffKind(key)
    if ns.charDB.buffKind == key then return end
    ns.charDB.buffKind = key
    ns.charDB.buyPicks.buff = nil
    ApplyBuffKind()
    ns.Fire("TYPES_CHANGED")
end

function Catalog.IsReserved(entry)
    local buff = entry.buff
    return buff ~= nil and buff.kind == Catalog.BuffKind()
end

function Catalog.IsUsable(entry, level)
    return entry.level <= level and not Catalog.IsReserved(entry)
end

function Catalog.IsPlain(entry)
    return entry.buff == nil and not entry.dual
end

function Catalog.Floor(foodType)
    if not foodType.floorKey then return 0 end
    local max = Catalog.MaxPool(foodType)
    if not max then return 0 end
    return max * ns.db[foodType.floorKey] / PERCENT
end

function Catalog.StrongestUsable(foodType, level, accept)
    local foods = foodType.foods
    for index = #foods, 1, -1 do
        local entry = foods[index]
        if Catalog.IsUsable(entry, level) and (not accept or accept(entry)) then return entry end
    end
end

local function Restockable(entry)
    return entry.tradeable and (entry.type == BUFF or Catalog.IsPlain(entry))
end

function Catalog.DefaultGrade(foodType, level)
    if foodType == BUFF and not Catalog.BuffKind() then return nil end
    return Catalog.StrongestUsable(foodType, level, Restockable) or Catalog.StrongestUsable(foodType, level)
end

function Catalog.EffectiveFloor(foodType, level)
    local floor = Catalog.Floor(foodType)
    local top = Catalog.DefaultGrade(foodType, level)
    if top and Catalog.Strength(top) < floor then return Catalog.Strength(top) end
    return floor
end

function Catalog.AboveFloor(entry, floor)
    return entry.type == BUFF or Catalog.Strength(entry) >= floor
end

function Catalog.Name(entry)
    return C_Item.GetItemNameByID(entry.item) or string.format(ns.L.ITEM_LOADING, entry.item)
end

function Catalog.Icon(entry)
    return C_Item.GetItemIconByID(entry.item)
end

function Catalog.TypeName(foodType)
    return ns.L["TYPE_" .. foodType.key]
end

function Catalog.KindName(kind)
    return ns.L["KIND_" .. kind.key] or kind.key
end

function Catalog.Effect(entry)
    local L = ns.L
    if entry.type == BUFF then
        local format = PERCENT_STATS[entry.kind.stats[1]] and L.BUFF_PERCENT_VALUE or L.BUFF_VALUE
        return string.format(format, Catalog.KindName(entry.kind), entry.value)
    end
    if entry.percent then return string.format(L["PERCENT_" .. entry.type.key], entry.percent) end
    return string.format(L["AMOUNT_" .. entry.type.key], entry.amount)
end

function Catalog.ShortEffect(entry)
    local L = ns.L
    if entry.type == BUFF then
        return string.format(PERCENT_STATS[entry.kind.stats[1]] and L.SHORT_BUFF_PERCENT or L.SHORT_BUFF, entry.value)
    end
    if entry.percent then return string.format(L.SHORT_PERCENT, entry.percent) end
    return tostring(entry.amount)
end

local function OnItemLoaded(item)
    if not Catalog.byItem[item] then return end
    ns.Schedule("names", NAME_DELAY, function() ns.Fire("NAMES_CHANGED") end)
end

ns.Listen("DB_READY", ApplyBuffKind)
ns.Listen("SETTING_CHANGED", function(key)
    if key == nil then ApplyBuffKind() end
end)

ns.Listen("LOGIN", function()
    Catalog.Resort()
    ns.RegisterUnitEvent("UNIT_MAXHEALTH", "player", Catalog.Resort)
    ns.RegisterUnitEvent("UNIT_MAXPOWER", "player", Catalog.Resort)
    ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemLoaded)
    for item in pairs(Catalog.byItem) do
        C_Item.RequestLoadItemDataByID(item)
    end
end)
