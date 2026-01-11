--
-- ████████╗ ██████╗ ████████╗ █████╗ ██╗          █████╗ ██╗     ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  ██████╗ ██╗     
-- ╚══██╔══╝██╔═══██╗╚══██╔══╝██╔══██╗██║         ██╔══██╗██║    ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔═══██╗██║     
--    ██║   ██║   ██║   ██║   ███████║██║         ███████║██║    ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝██║   ██║██║     
--    ██║   ██║   ██║   ██║   ██╔══██║██║         ██╔══██║██║    ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██║   ██║██║     
--    ██║   ╚██████╔╝   ██║   ██║  ██║███████╗    ██║  ██║██║    ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║╚██████╔╝███████╗
--    ╚═╝    ╚═════╝    ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝╚═╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
--

------------------------------------------
--
--- Logging System
--
------------------------------------------
local Logger = {
    LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 },
    currentLevel = MCM.Get("logger_level"),
    functionTable = {[0] = Ext.Utils.Print, [1] = Ext.Utils.Print, [2] = Ext.Utils.PrintWarning, [3] = Ext.Utils.PrintError},
    modName = "Total AI Control"
}

function Logger.log(level, message)
    if level >= Logger.currentLevel then
        local levelName = "UNKNOWN"
        for name, value in pairs(Logger.LEVELS) do
            if value == level then
                levelName = name
                break
            end
        end

        local formatedMessage = string.format("%s  [%s]%s : %s", Logger.modName, levelName, string.rep(" ", 5 - #levelName), message);
        if (Logger.functionTable[level]) then Logger.functionTable[level](formatedMessage) end
    end
end

function Logger.error(message) Logger.log(Logger.LEVELS.ERROR, message) end
function Logger.warn(message) Logger.log(Logger.LEVELS.WARN, message) end
function Logger.info(message) Logger.log(Logger.LEVELS.INFO, message) end
function Logger.debug(message) Logger.log(Logger.LEVELS.DEBUG, message) end



------------------------------------------
--
--- MCM Related
--
------------------------------------------
local ModEnabled = MCM.Get("mod_enabled")
local AutoGrantContainer = MCM.Get("auto_grant_container") ~= false
local RevivifyPrompt = MCM.Get("revivify_prompt") ~= false
local AISummonsEnabled = MCM.Get("ai_summons_enabled") ~= false
local NonLethalFollowControl = MCM.Get("nonlethal_follow_controlled") ~= false
local EnsureContainerSpell
local EnsurePartyHasContainerSpell

Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(function(payload)
    if not payload or payload.modUUID ~= ModuleUUID then
        return
    end

    if payload.settingId == "mod_enabled" then
        ModEnabled = payload.value
        if ModEnabled and AutoGrantContainer then EnsurePartyHasContainerSpell() end
    elseif payload.settingId == "logger_level" then
        Logger.currentLevel = payload.value
    elseif payload.settingId == "ignored_spells" then
        PatchUnwantedSpells(payload.value)
    elseif payload.settingId == "auto_grant_container" then
        AutoGrantContainer = payload.value
        if ModEnabled and AutoGrantContainer then EnsurePartyHasContainerSpell() end
    elseif payload.settingId == "revivify_prompt" then
        RevivifyPrompt = payload.value
    elseif payload.settingId == "ai_summons_enabled" then
        AISummonsEnabled = payload.value
    elseif payload.settingId == "nonlethal_follow_controlled" then
        NonLethalFollowControl = payload.value
    end
end)


------------------------------------------
--
--- Mod vars
--
------------------------------------------
Ext.Vars.RegisterModVariable(ModuleUUID, "aiControlled", {Server = true, Persistent = true})
Ext.Vars.RegisterModVariable(ModuleUUID, "aiSummons", {Server = true, Persistent = true})
Ext.Vars.RegisterModVariable(ModuleUUID, "characterState", {Server = true, Persistent = true})

local function ModVars() return Ext.Vars.GetModVariables(ModuleUUID) end

local function InitModVars()
    if not ModVars().aiControlled then ModVars().aiControlled = {} end
    if not ModVars().aiSummons then ModVars().aiSummons = {} end
    if not ModVars().characterState then ModVars().characterState = {} end 
end

local function EnsureContainerSpell(character)
    local spell = "Target_AI_Container"
    if character and Osi.HasSpell(character, spell) == 0 then
        Osi.AddSpell(character, spell, 1, 1)
    end
end

local function EnsurePartyHasContainerSpell()
    if not AutoGrantContainer then return end
    local party = Osi.DB_PartyMembers:Get(nil)
    for _, memberEntry in ipairs(party) do 
        EnsureContainerSpell(memberEntry[1])
    end
end


------------------------------------------
--
--- Events
--
------------------------------------------
Ext.Events.GameStateChanged:Subscribe(function()
    if ModVars().aiControlled and ModVars().aiSummons and ModVars().characterState then
        ModVars().aiControlled = ModVars().aiControlled
        ModVars().aiSummons = ModVars().aiSummons
        ModVars().characterState = ModVars().characterState
    end
end)

Ext.Events.SessionLoaded:Subscribe(function()
    InitModVars()
    if not ModEnabled then return end
    PatchUnwantedSpells(MCM.Get("ignored_spells"))
    if AutoGrantContainer then EnsurePartyHasContainerSpell() end
end)

------------------------------------------
--
--- Utility Functions
--
------------------------------------------
function PatchUnwantedSpells(list)
    if not list or not list.elements then
        Logger.debug("Ignored spells list is missing; skipping patch.")
        return
    end
    for _, element in pairs(list.elements) do
        local spell = Ext.Stats.Get(element.name)
        if spell then
            local condition = "not HasStatus('BANISHED_FROM_PARTY')"
            local currentConditions = spell.RequirementConditions or ""

            if list.enabled and element.enabled then
                if not string.find(currentConditions, condition, 1, true) then
                    if currentConditions ~= "" then
                        spell.RequirementConditions = currentConditions .. " and " .. condition
                    else
                        spell.RequirementConditions = condition
                    end
                end
            else
                local escapedCondition = condition:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
                currentConditions = currentConditions:gsub(" and " .. escapedCondition, ""):gsub(escapedCondition, "")
                spell.RequirementConditions = currentConditions
            end
            
            spell:Sync()
        end
    end
end

local function GetCharacterName(guid)
    local displayName = guid and Osi.GetDisplayName(guid)
    local readableName = displayName and Osi.ResolveTranslatedString(displayName) or "Unknown"
    return readableName
end

local function GetAIArchetype(character)
    local entity = Ext.Entity.Get(character)
    local statuses = entity.StatusContainer and entity.StatusContainer.Statuses
    if (statuses) then
        for _, name in pairs(statuses) do
            local type = name:match("^AI_CONTROLLED_(.+)")
            if (type) then return type end
        end
      end
    return nil
end

local function ToggleNonLethal(enable)
    Logger.info((enable and "Enabling" or "Disabling") .. " Non-Lethal for AI Companions.")
    
    for companion, _ in pairs(ModVars().aiControlled) do
        Logger.debug((enable and "Enabling" or "Disabling") .. " for " .. GetCharacterName(companion))
        local isActivated = Osi.HasActiveStatus(companion, "NON_LETHAL") ~= 0
        if (enable and not isActivated) or (not enable and isActivated) then
            if Osi.HasPassive(companion, "NonLethal") == 0 then Osi.AddPassive(companion, "NonLethal") end
            Osi.TogglePassive(companion, "NonLethal")
        end
    end
end

local function RegisterSummon(owner, summon) 
    if ModVars().aiSummons[owner] then
        ModVars().aiSummons[owner][summon] = 1
        Osi.ApplyStatus(summon, "AI_CONTROLLED_SUMMON", -1, -1)
    end  
end

local function IsRemainingPartyAlive(exception)
    exception = exception or ""
    local party = Osi.DB_Players:Get(nil)
    
    for _, member in ipairs(party) do
        local character = member[1]
        if character ~= exception and Osi.IsDead(character) == 0 and Osi.HasAppliedStatusOfType(character, "INCAPACITATED") == 0 then
            return true
        end
    end
    return false
end

local function GetAlivePartyMembersCount()
    local party = Osi.DB_PartyMembers:Get(nil)
    local count = 0
    for _, memberEntry in ipairs(party) do 
        local character = memberEntry[1]
        if Osi.IsDead(character) == 0 and Osi.HasAppliedStatusOfType(character, "INCAPACITATED") == 0 then
            count = count + 1
        end
    end
    return count
end


------------------------------------------
--
--- Core Functionality
--
------------------------------------------
Ext.Osiris.RegisterListener("DownedChanged", 2, "before", function(character, isDowned)
   if ModEnabled and Osi.IsInCombat(character) == 1 and GetAlivePartyMembersCount() == 1 and IsRemainingPartyAlive(character) then
        local charName = GetCharacterName(character)
        -- When downed
        if isDowned == 1 then
            Osi.SetHitpointsPercentage(character, 1) -- Healing to avoid Game Over
            if ModVars().characterState[character] ~= "PLAYING_DEAD" then
                Logger.warn("Character downed: " .. charName)
                ModVars().characterState[character] = "DOWNED"
            else
                Logger.warn("Character killed: " .. charName)
                ModVars().characterState[character] = "DEAD"
            end
        -- After being healed 
        else
            if ModVars().characterState[character] == "DOWNED" then 
                Osi.ApplyStatus(character, "TAC_DOWNED", -1, 1)
                Osi.ApplyStatus(character, "BLOCK_ATTACKS", -1, 1) -- Completely nullifies three Attacks
                ModVars().characterState[character] = "PLAYING_DEAD"
            elseif ModVars().characterState[character] == "DEAD" then
                Osi.ApplyStatus(character, "TAC_DYING", -1, 1)
            end
        end
        return
    end
end)

Ext.Osiris.RegisterListener("MessageBoxYesNoClosed", 3, "after", function (character, message, option)
    if not ModEnabled or not RevivifyPrompt then return end
    if message:find("Scroll of Revivify", -20) and option == 1 then
        local scroll_of_revifify = "c1c3e4fb-d68c-4e10-afdc-d4550238d50e"
        local scrollAmount = Osi.TemplateIsInPartyInventory(scroll_of_revifify, character, 1)
        Logger.warn("Scroll of Revivify amount: " .. scrollAmount)
        if scrollAmount > 0 then
            Osi.TemplateRemoveFromParty(scroll_of_revifify, character, 1)
            Osi.RemoveStatus(character, "TAC_DYING")
            Osi.ShowNotification(character, "Scrolls remaining: " .. scrollAmount - 1)
        else 
            Osi.ShowNotification(character, "You don't have a Scroll of Revivify!")
        end
    end
end)

Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", function(character, combat)
    if not ModEnabled then return end

    local playerCharacter = Osi.GetHostCharacter()
    if Osi.IsCharacter(character) == 0 or Osi.IsPartyMember(character, 0) == 0 then return end
   
    Logger.debug("Player character: " .. tostring(playerCharacter))
   
    local characterName = GetCharacterName(character)
    Logger.info(string.format("%s just Entered Combat! ID: %s", characterName, combat))
  
    -- Check for AI Control and apply BANISHED
    local type = GetAIArchetype(character)
    if type then
        ModVars().aiControlled[character] = {type = type, combat = combat}
        if Osi.HasActiveStatus(character, "GLO_PIXIESHIELD") == 1 then Osi.ApplyStatus(character, "AI_HELPER_PIXIESHIELD", -1, 1) end
        Osi.ApplyStatus(character, "BANISHED_FROM_PARTY", -1, 1, playerCharacter)
    end
end)

Ext.Osiris.RegisterListener("LeftCombat", 2, "before", function(character, _)
    if not ModEnabled then return end
    if ModVars().aiControlled[character] then
        Osi.RemoveStatus(character, "BANISHED_FROM_PARTY")
    elseif ModVars().characterState[character] and not IsRemainingPartyAlive() then
        Osi.SetHitpoints(character, 0)
    end
end)

Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(character, status, source, ...)
    if not ModEnabled then return end
    if Osi.IsCharacter(character) == 0 then return end

    local charName = GetCharacterName(character)
    Logger.debug(string.format("Status Applied: %s to: %s (%s)", status, charName, Osi.GetStatusCurrentLifetime(character, status)))
    
    -- Fixes some companions not using smart archetype (ex: Lae'zel using "melee" over "melee_smart")
    if status == "AI_CONTROLLED_DEFAULT" then
        local archetype = Osi.GetBaseArchetype(character):upper()
        Logger.info(string.format("%s's Base Archetype: %s", charName, archetype))
        if archetype == "BASE" then return end
        Osi.ApplyStatus(character, "AI_CONTROLLED_" .. archetype:gsub("_SMART", ""), -1, 1, source)
    -- Removing character from our party
    elseif status == "BANISHED_FROM_PARTY" then
        Logger.info("Removing from party: " .. charName)
        -- Last controllable character in party
        if Osi.IsOnlyPlayerInParty(character) == 1 then
            Osi.OpenMessageBox(character, "Cannot remove " .. charName .. " from the party. You must have at least one controllable character.")
            Osi.RemoveStatus(character, status)
        else 
            Osi.MakeNPC(character)
        end
    -- Toggling Non Lethal to AI Companions
    elseif status == "NON_LETHAL" then
        if NonLethalFollowControl and Osi.IsControlled(character) == 1 then ToggleNonLethal(true) end
    elseif status == "TAC_DYING" then
        if RevivifyPrompt then
            Osi.OpenMessageBoxYesNo(character, string.format("%s has died. Would you like to use a Scroll of Revivify?", charName))
        end
    -- Block statuses that interfere with AI control
    elseif ModVars().aiControlled and ModVars().aiControlled[character] and (status == "AI_HELPER_BREAKCONCENTRATION" or status == "TEMPORARILY_HOSTILE" or status == "GB_GUARDKILLER_WITNESS") then
        Logger.debug("Removing interfering status: " .. status)
        Osi.RemoveStatus(character, status)
    end
end)

Ext.Osiris.RegisterListener("StatusRemoved", 4, "before", function(character, status, ...)
    if not ModEnabled then return end
    local playerCharacter = Osi.GetHostCharacter()
    local charName = GetCharacterName(character)
    if Osi.IsCharacter(character) == 0 or Osi.IsAlly(character, playerCharacter) == 0 then return end
    
    Logger.debug(string.format("Status Removed: %s from %s", status, charName))
    
    -- Adding character back to party
    if status == "BANISHED_FROM_PARTY" then 
        Logger.info("Adding back to party: " .. charName)
        Osi.MakePlayer(character)
        if Osi.IsSummon(character) == 1 then 
            local serverCharacter = Ext.Entity.Get(character).ServerCharacter
            serverCharacter.Flags = serverCharacter.Flags & ~Ext.Enums.ServerCharacterFlags.Multiplayer
            serverCharacter.Multiplayer = false
        end
        
        ModVars().aiControlled[character] = nil
    elseif status == "NON_LETHAL" then 
        if NonLethalFollowControl and Osi.IsControlled(character) == 1 then ToggleNonLethal(false) end
    -- Player "Death" management
    elseif ModVars().characterState and ModVars().characterState[character] then
        if status == "TAC_DOWNED" then
            Osi.RemoveStatus(character, "BLOCK_ATTACKS")
            if ModVars().characterState[character] == "PLAYING_DEAD" then ModVars().characterState[character] = nil end
        elseif status == "TAC_DYING" then
            ModVars().characterState[character] = nil
        end
    end
end)

Ext.Osiris.RegisterListener("CastSpell", 5, "after", function(caster, spell, ...)
    if not ModEnabled or not AISummonsEnabled then return end
    -- Toggling AI Summons passive on spell cast
    if spell == "Shout_AI_SUMMONS" then
        local passive = "AI_SUMMONS_Passive"
        if Osi.HasPassive(caster, passive) == 0 then 
            Osi.AddPassive(caster, passive)
        else 
            Osi.RemovePassive(caster, passive)
        end
    end
end)

-- Enabling AI summons
Ext.Osiris.RegisterListener("TagSet", 2, "after", function(target, tag)
    if not ModEnabled or not AISummonsEnabled then return end
    if tag == "030a4a56-3248-4c91-962c-cf0a8c897c6a" then
        local character = Osi.GetUUID(target) or "Unknown"
        local name = GetCharacterName(character)
        Logger.info("Enabling AI-Controlled SUMMONS for " .. name .. ".")
        
        if not ModVars().aiSummons[character] then ModVars().aiSummons[character] = {} end
        
        for _, table in ipairs(Osi.DB_PlayerSummons:Get(nil)) do
            local summon = table[1]
            if Osi.CharacterGetOwner(summon) == character then RegisterSummon(character, summon) end
        end

        if next(ModVars().aiSummons[character]) ~= nil then 
            Logger.info(string.format("%s's Summons:\n%s", name, Ext.DumpExport(ModVars().aiSummons[character])))
        end
    end
end)

-- Disabling AI summons
Ext.Osiris.RegisterListener("TagCleared", 2, "after", function(target, tag)
    if not ModEnabled or not AISummonsEnabled then return end
    if tag == "030a4a56-3248-4c91-962c-cf0a8c897c6a" then
        local character = Osi.GetUUID(target) or "Unknown"
        local name = GetCharacterName(character)
        Logger.info("Disabling AI-Controlled SUMMONS for " .. name .. ".")

        if ModVars().aiSummons[character] then
            for summon, _ in pairs(ModVars().aiSummons[character]) do
                Osi.ApplyStatus(summon, "AI_CONTROLLED_CLEAR", -1, 1)
            end
        end
        ModVars().aiSummons[character] = nil
    end
end)

-- New summons
Ext.Osiris.RegisterListener("DB_PlayerSummons", 1, "after", function(summon)
    if not ModEnabled or not AISummonsEnabled then return end
    local owner = Osi.CharacterGetOwner(summon) or "Unknown"
    Logger.info("Registering summon: " .. GetCharacterName(summon) .. " for " .. GetCharacterName(owner))
    RegisterSummon(owner, summon)
end)

-- Deleted summons
Ext.Osiris.RegisterListener("DB_PlayerSummons", 1, "afterDelete", function(summon)
    if not ModEnabled or not AISummonsEnabled then return end
    local summoner = Osi.CharacterGetOwner(summon) or "Unknown"
    if ModVars().aiSummons[summoner] then
        Logger.info(string.format("Summon removed: %s from %s", GetCharacterName(summon), GetCharacterName(summoner)))
        ModVars().aiSummons[summoner][summon] = nil
    end
end)

-- Ensuring spell container is available when loading a save
Ext.Osiris.RegisterListener("SavegameLoaded", 0, "after", function()
    Logger.debug("Savegame Loaded! Adding spell container to all party members.")

    InitModVars()
    if not ModEnabled then return end

    EnsurePartyHasContainerSpell()
end)

Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", function(character)
    if not ModEnabled or not AutoGrantContainer then return end
    EnsureContainerSpell(character)
end)