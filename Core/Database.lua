local _, ns = ...

local DEFAULTS = {
    enabled = true,
    locale = "auto",
    visibility = "always",
    showEmpty = true,
    foodFloor = 20,
    foodStock = 20,
    drinkFloor = 20,
    drinkStock = 20,
    buffStock = 5,
    fedWarnMinutes = 3,
    conjuredFirst = true,
    restButton = false,
    countBank = true,
    merchant = true,
    merchantAuto = false,
    merchantX = 0,
    merchantY = 0,
    auction = true,
    priceStep = 20,
    auctionX = 0,
    auctionY = 0,
    bank = true,
    bankAuto = false,
    bankX = 0,
    bankY = 0,
    dock = {},
    iconSize = 40,
    spacing = 4,
    layout = "HORIZONTAL",
    showHeader = true,
    showCounts = true,
    barBackground = 92,
    panelBackground = 98,
    locked = false,
    position = { point = "CENTER", x = -250, y = -160 },
    minimap = { hide = false, angle = 285 },
}

local CHAR_DEFAULTS = {
    types = {},
    buyPicks = {},
}

ns.DEFAULTS = DEFAULTS

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = ApplyDefaults(type(target[key]) == "table" and target[key] or {}, value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

ns.Listen("INIT", function()
    ReFoodDB = ApplyDefaults(ReFoodDB or {}, DEFAULTS)
    ReFoodCharDB = ApplyDefaults(ReFoodCharDB or {}, CHAR_DEFAULTS)
    ns.db = ReFoodDB
    ns.charDB = ReFoodCharDB
    ns.Fire("DB_READY")
end)

function ns.Set(key, value)
    if ns.db[key] == value then return end
    ns.db[key] = value
    ns.Fire("SETTING_CHANGED", key, value)
end

function ns.ResetSettings()
    wipe(ns.db)
    ApplyDefaults(ns.db, DEFAULTS)
    wipe(ns.charDB)
    ApplyDefaults(ns.charDB, CHAR_DEFAULTS)
    ns.Fire("SETTING_CHANGED")
    ns.Fire("TYPES_CHANGED")
end
