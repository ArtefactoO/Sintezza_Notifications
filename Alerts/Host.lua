local _, ns = ...
local theme = Sintezza_Theme
local modules, subscriptions = {}, {}
local eventFrame, legacy, uiSource
local host = {
    defaults = { modules = { combatAlert = ns.alertDefaults } },
    SettingsTheme = theme and theme:ForAddon() or { accent = { .56, .85, .78, 1 } },
}
ns.AlertHost = host
ns.SettingsTheme = host.SettingsTheme
ns.Widgets = theme and theme:CreateWidgets(ns.SettingsTheme)
host.Theme = theme and theme:ForAddon(nil, theme.Theme) or {
    ApplyTextFont = function(_, region, selection, size, flags)
        local path = selection == "COMBAT" and DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT
        region:SetFont(path, size, flags)
    end,
}

function host.Text(ru, en) return ns.locale == "ruRU" and ru or en end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copied = {}
    for key, child in pairs(value) do copied[key] = Copy(child) end
    return copied
end

local function Fill(profile, defaults)
    for key, value in pairs(defaults) do
        if type(profile[key]) ~= type(value) then profile[key] = Copy(value)
        elseif type(value) == "table" then Fill(profile[key], value) end
    end
end

function host:RegisterModule(key, module)
    modules[key] = module
    return module
end

function host:GetModule(key)
    if key == "combatFont" and uiSource then return uiSource:GetModule(key) end
    if legacy then return legacy:GetModule(key) end
    return modules[key]
end

function host:GetModuleProfile(key)
    if legacy then return legacy:GetModuleProfile(key) end
    return ns.db.alerts
end

function host:SafeModuleCall(module, _, method, ...)
    local ok, result = pcall(method, module, ...)
    if not ok then geterrorhandler()(result) end
    return ok, result
end

function host:After(delay, module, context, method)
    C_Timer.After(delay, function() self:SafeModuleCall(module, context, method) end)
end

function host:RegisterModuleEvent(module, event)
    local listeners = subscriptions[event]
    if not listeners then listeners = {}; subscriptions[event] = listeners end
    listeners[#listeners + 1] = module
end

local function WantsEvent(module, event)
    if legacy and module == modules.combatAlert then return false end
    if module.WantsEvent then return module:WantsEvent(event) end
    local profile = module:Profile()
    if not profile.enabled then return false end
    if event == "UPDATE_STEALTH" or event == "PLAYER_ENTERING_WORLD" then
        return profile.stealthEnabled and (profile.showStealthEnter or profile.showStealthLeave)
    end
    return profile.showEnter or profile.showLeave
end

function host:RefreshModuleEvents()
    if not eventFrame then return end
    for event, listeners in pairs(subscriptions) do
        local wanted = false
        for _, module in ipairs(listeners) do
            if WantsEvent(module, event) then wanted = true; break end
        end
        if wanted and not eventFrame:IsEventRegistered(event) then
            if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event) then
                eventFrame:RegisterEvent(event)
            end
        elseif not wanted and eventFrame:IsEventRegistered(event) then
            eventFrame:UnregisterEvent(event)
        end
    end
end

local features = {
    combatAlert = "enabled", combatEnter = "showEnter", combatLeave = "showLeave",
    stealth = "stealthEnabled", stealthEnter = "showStealthEnter", stealthLeave = "showStealthLeave",
}

function host:SetFeature(id, value)
    if legacy then return legacy:SetFeature(id, value) end
    local key = features[id]
    if not key then return false end
    ns.db.alerts[key] = value == true
    self:SafeModuleCall(self.CombatAlert, "alert settings", self.CombatAlert.OnProfileChanged)
    self:RefreshModuleEvents()
    return true
end

function host:ResetModuleProfile(key)
    ns.db.manaAlert = Copy(ns.manaDefaults)
    if legacy then
        self:RefreshManaAlert()
        return legacy:ResetModuleProfile(key)
    end
    ns.db.alerts = Copy(ns.alertDefaults)
    self:SafeModuleCall(self.CombatAlert, "alert settings", self.CombatAlert.OnProfileChanged)
    self:RefreshModuleEvents()
end

function host:RefreshManaAlert()
    if not ns.db.manaAlert.enabled then self.CombatAlert:StopExtraAlert("manaAlert") end
    local detector = modules.eventAlerts
    self:SafeModuleCall(detector, "mana settings", detector.OnProfileChanged)
end

local function ImportUiAlerts()
    if ns.db.ownsAlertSettings or not uiSource or type(uiSource.GetModuleProfile) ~= "function" then return end
    local profile = uiSource:GetModuleProfile("combatAlert")
    if type(profile) == "table" then
        ns.db.alerts = Copy(profile)
        Fill(ns.db.alerts, ns.alertDefaults)
    end
end

local function UseLegacy()
    legacy = uiSource
    ImportUiAlerts()
    if not ns.db.ownsAlertSettings then
        local logout = CreateFrame("Frame")
        logout:RegisterEvent("PLAYER_LOGOUT")
        logout:SetScript("OnEvent", ImportUiAlerts)
    end
end

local function Enabled(profile)
    return type(profile) == "table" and profile.enabled == true
end

local function SharedPhase(ui, notifications, enter, leave)
    return ui[enter] and notifications[enter] or ui[leave] and notifications[leave]
end

local function AnnounceSharedAlerts()
    if type(uiSource.GetModuleProfile) ~= "function" then return end
    local ui = uiSource:GetModuleProfile("combatAlert")
    if type(ui) ~= "table" then return end
    local profile, L = ns.db.alerts, ns.L
    local names = {}
    if Enabled(ui) and Enabled(profile) then
        if SharedPhase(ui, profile, "showEnter", "showLeave") then names[#names + 1] = L.combat end
        if ui.stealthEnabled and profile.stealthEnabled
            and SharedPhase(ui, profile, "showStealthEnter", "showStealthLeave") then
            names[#names + 1] = L.stealth
        end
    end
    if Enabled(ui.healthAlert) and Enabled(profile.healthAlert) then names[#names + 1] = L.health end
    if Enabled(ui.aggroAlert) and Enabled(profile.aggroAlert) then names[#names + 1] = L.aggro end
    if #names == 0 then return end

    local message = L.alertHandoff:format(table.concat(names, ", "))
    local function Post()
        C_Timer.After(.5, function()
            if type(uiSource.Print) == "function" then uiSource:Print(message)
            else ns.Say(message) end
        end)
    end
    if IsPlayerInWorld and IsPlayerInWorld() then
        Post()
    else
        local login = CreateFrame("Frame")
        login:RegisterEvent("PLAYER_ENTERING_WORLD")
        login:SetScript("OnEvent", function(frame)
            frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            Post()
        end)
    end
end

local alertPages = { combat = true, stealth = true, healthAlert = true, manaAlert = true, aggroAlert = true }
local owner = {
    OpenSettings = function(_, page)
        return ns.OpenSettings(alertPages[page] and page or "combat")
    end,
    GetFeature = function(_, id)
        local key = features[id]
        return key ~= nil and ns.db.alerts[key] == true
    end,
    SetFeature = function(_, id, value)
        local applied = host:SetFeature(id, value)
        if applied and ns.RefreshAlertSettings then ns.RefreshAlertSettings() end
        return applied
    end,
}

function ns.InitializeAlerts()
    if type(ns.db.manaAlert) ~= "table" then ns.db.manaAlert = {} end
    Fill(ns.db.manaAlert, ns.manaDefaults)
    local ui = Sintezza_UI
    if ui and ui.initialized and type(ui.GetModule) == "function" then uiSource = ui end
    local alert = uiSource and uiSource:GetModule("combatAlert")
    local compatibleLegacy = alert and alert.initialized and type(alert.PreviewExtraAlert) == "function"
        and type(ui.GetModuleProfile) == "function" and type(ui.SetFeature) == "function"
        and type(ui.ResetModuleProfile) == "function"
    local canClaim = uiSource and type(uiSource.ClaimNotificationsAlerts) == "function"
    if compatibleLegacy and not canClaim then
        UseLegacy()
    else
        if canClaim then ImportUiAlerts() end
        if type(ns.db.alerts) ~= "table" then ns.db.alerts = {} end
        Fill(ns.db.alerts, ns.alertDefaults)
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        for _, module in ipairs(subscriptions[event]) do
            if WantsEvent(module, event) then host:SafeModuleCall(module, event, module.OnEvent, event, ...) end
        end
    end)
    for _, key in ipairs({ "combatAlert", "eventAlerts" }) do
        local module = modules[key]
        if not legacy or key == "eventAlerts" then
            module.initialized = host:SafeModuleCall(module, "initialize", module.Initialize, legacy ~= nil)
        end
    end
    host.initialized = true

    local combat, detector = modules.combatAlert, modules.eventAlerts
    local ready = combat.initialized and detector.initialized
    if canClaim then
        local ok, claimed
        if ready then
            ok, claimed = host:SafeModuleCall(uiSource, "notifications handoff", uiSource.ClaimNotificationsAlerts, owner)
        end
        if ok and claimed then
            AnnounceSharedAlerts()
        elseif compatibleLegacy then
            UseLegacy()
            combat:StopAnimations()
            combat:StopStealthAnimations()
            combat:StopExtraAlerts()
            detector.manaOnly = true
            host:SafeModuleCall(detector, "fallback settings", detector.OnProfileChanged)
        end
    end
    if ready and not legacy then ns.db.ownsAlertSettings = true end
    host:RefreshModuleEvents()
end

function ns.PrintAlertStatus()
    local L = ns.L
    local mode = uiSource and uiSource.notificationsAlertOwner == owner and L.handoffStatusActive
        or legacy and L.handoffStatusLegacy or L.handoffStatusSolo
    ns.Say(mode .. " " .. modules.eventAlerts:GetManaStatus())
end
