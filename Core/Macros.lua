local _, ns = ...

local Macros = {}
ns.Macros = Macros

local ICON = 134400
local TOOLTIP_LINE = "#showtooltip"
local NAMES = { food = "ReFood Food", drink = "ReFood Drink", rest = "ReFood Rest", buff = "ReFood Buff" }
local CHARACTER, ACCOUNT = true, false

local function Index(key)
    local index = GetMacroIndexByName(NAMES[key])
    if index and index > 0 then return index end
end

local function Body(record)
    local text = record.active.text
    if not text then return TOOLTIP_LINE end
    return TOOLTIP_LINE .. "\n" .. text
end

local function Sync(record)
    local index = Index(record.key)
    if not index then return end
    local body = Body(record)
    if GetMacroBody(index) ~= body then EditMacro(index, nil, nil, body) end
end

local function SyncAll()
    if InCombatLockdown() then return end
    for _, record in pairs(ns.Picker.records) do
        Sync(record)
    end
end

local function HasRoom(perCharacter)
    local account, character = GetNumMacros()
    local limits = Constants.MacroConsts
    if perCharacter then return character < limits.MAX_CHARACTER_MACROS end
    return account < limits.MAX_ACCOUNT_MACROS
end

local function Create(record)
    local name, body = NAMES[record.key], Body(record)
    for _, perCharacter in ipairs({ CHARACTER, ACCOUNT }) do
        if HasRoom(perCharacter) then
            CreateMacro(name, ICON, body, perCharacter)
            return Index(record.key)
        end
    end
end

function Macros.Pickup(key)
    if InCombatLockdown() then
        ns.Print(ns.L.MACRO_COMBAT)
        return false
    end
    local record = ns.Picker.records[key]
    if Index(key) then Sync(record) end
    local index = Index(key) or Create(record)
    if not index then
        ns.Print(ns.L.MACRO_FULL)
        return false
    end
    PickupMacro(index)
    return true
end

ns.Listen("PICKS_APPLIED", SyncAll)
