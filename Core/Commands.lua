local _, ns = ...

SLASH_REFOOD1 = "/food"
SLASH_REFOOD2 = "/refood"
SlashCmdList.REFOOD = function()
    ns.Options.Toggle()
end

function ReFood_OnAddonCompartmentClick()
    ns.Options.Toggle()
end
