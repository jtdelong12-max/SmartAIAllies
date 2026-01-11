Mods.BG3MCM.IMGUIAPI:InsertModMenuTab(ModuleUUID, "General", function(tab)
    local button = tab:AddButton("Return Companions to Party")
    button.OnClick = function()
        for _, member in pairs(Osi.DB_Players:Get(nil)) do Osi.RemoveStatus(member[1], "BANISHED_FROM_PARTY") end
    end

    tab:AddText("Removes the 'BANISHED_FROM_PARTY' status from all companions and returns them to your party.")
end)
