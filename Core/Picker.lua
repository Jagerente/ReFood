local _, ns = ...

local Catalog = ns.Catalog
local Inventory = ns.Inventory

local Picker = { records = {} }
ns.Picker = Picker

local UPDATE_DELAY = 0.1
local USE_LINE = "/use item:%d"
local REST = "rest"

local records = Picker.records
local pending = false

for _, foodType in ipairs(Catalog.types) do
    records[foodType.key] = { key = foodType.key, type = foodType, owned = {}, active = {} }
end
records[REST] = { key = REST, rest = true, active = {} }
Picker.REST = REST

local function ConjuredFirst(entry, floor)
    return ns.db.conjuredFirst and entry.conjured and Catalog.Strength(entry) >= floor
end

local function Stronger(candidate, current, floor)
    if not current then return true end
    local early, currentEarly = ConjuredFirst(candidate, floor), ConjuredFirst(current, floor)
    if early ~= currentEarly then return early end
    local strength, currentStrength = Catalog.Strength(candidate), Catalog.Strength(current)
    if strength ~= currentStrength then return strength > currentStrength end
    local plain, currentPlain = Catalog.IsPlain(candidate), Catalog.IsPlain(current)
    if plain ~= currentPlain then return plain end
    if candidate.level ~= current.level then return candidate.level > current.level end
    return current.tradeable and not candidate.tradeable
end

local function Strongest(owned, floor)
    local best
    for _, entry in ipairs(owned) do
        if Stronger(entry, best, floor) then best = entry end
    end
    return best
end

local function CollectOwned(record, level)
    local owned = record.owned
    wipe(owned)
    for _, entry in ipairs(record.type.foods) do
        if Catalog.IsUsable(entry, level) and Inventory.Count(entry.item) > 0 then owned[#owned + 1] = entry end
    end
    return owned
end

local function Line(entry)
    return entry and string.format(USE_LINE, entry.item)
end

local function Compute(record, level)
    local foodType = record.type
    local floor = Catalog.EffectiveFloor(foodType, level)
    record.main = Strongest(CollectOwned(record, level), floor)
    record.placeholder = Catalog.DefaultGrade(foodType, level)
    if not record.placeholder and not Catalog.IsBuff(foodType) then
        record.placeholder = Catalog.StrongestUsable(foodType, level)
    end
    record.text = Line(record.main or record.placeholder)
end

local function RestLines(food, drink)
    if not food then return drink end
    if not drink or food == drink then return food end
    return food .. "\n" .. drink
end

local function ComputeRest(rest)
    local food, drink = records.food, records.drink
    rest.food = food.main or food.placeholder
    rest.drink = drink.main or drink.placeholder
    rest.main = food.main or drink.main
    rest.text = RestLines(Line(rest.food), Line(rest.drink))
end

local function Activate(record)
    local active = record.active
    active.main, active.placeholder, active.text = record.main, record.placeholder, record.text
    active.food, active.drink = record.food, record.drink
end

function Picker.Shown(record)
    local active = record.active
    return active.main or active.placeholder
end

function Picker.Update()
    local level = UnitLevel("player")
    for _, foodType in ipairs(Catalog.types) do
        Compute(records[foodType.key], level)
    end
    ComputeRest(records[REST])
    if InCombatLockdown() then
        pending = true
    else
        pending = false
        for _, record in pairs(records) do
            Activate(record)
        end
        ns.Fire("PICKS_APPLIED")
    end
    ns.Fire("PICKS_CHANGED")
end

function Picker.UpdateSoon()
    ns.Schedule("picks", UPDATE_DELAY, Picker.Update)
end

for _, message in ipairs({ "INVENTORY_CHANGED", "TYPES_CHANGED", "STOCK_CHANGED" }) do
    ns.Listen(message, Picker.UpdateSoon)
end

ns.Listen("SETTING_CHANGED", function(key)
    if key == nil or Catalog.TypeOfSetting(key) then Picker.UpdateSoon() end
end)

ns.Listen("LOGIN", function()
    ns.RegisterEvent("PLAYER_LEVEL_UP", Picker.UpdateSoon)
    ns.RegisterUnitEvent("UNIT_MAXHEALTH", "player", Picker.UpdateSoon)
    ns.RegisterUnitEvent("UNIT_MAXPOWER", "player", Picker.UpdateSoon)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pending then Picker.Update() end
    end)
    Picker.Update()
end)
