local _, ns = ...
local SUI = ns.AlertHost
local M = SUI:RegisterModule("eventAlerts", { supportsHealthInstanceScope = true })
local Public = ns.IsPublic
local manaType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local IsSecret = issecretvalue or function() return false end

local unitEvents = {
    UNIT_HEALTH = "healthAlert", UNIT_MAXHEALTH = "healthAlert",
    UNIT_POWER_UPDATE = "manaAlert", UNIT_POWER_FREQUENT = "manaAlert",
    UNIT_MAXPOWER = "manaAlert", UNIT_DISPLAYPOWER = "manaAlert",
    UNIT_SPELLCAST_SUCCEEDED = "manaAlert",
    UNIT_THREAT_SITUATION_UPDATE = "aggroAlert",
}
local lifecycleEvents = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "ADDON_RESTRICTION_STATE_CHANGED",
}

local function Number(value)
    return Public(value, "number") and value > -math.huge and value < math.huge
end

local function Setting(value, fallback, low, high)
    return Number(value) and ns.Clamp(ns.Round(value), low, high) or fallback
end

local function PlayerAlive()
    if not UnitIsDeadOrGhost then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    return ok and Public(dead, "boolean") and not dead
end

local function PlayerInCombat()
    local combat = InCombatLockdown and InCombatLockdown()
    return Public(combat, "boolean") and combat
end

local function InDungeonOrRaid()
    if not IsInInstance then return false end
    local ok, inside, kind = pcall(IsInInstance)
    return ok and Public(inside, "boolean") and inside and Public(kind, "string")
        and (kind == "party" or kind == "raid")
end

local function Percent(readCurrent, readMax, argument, minimum)
    if not readCurrent or not readMax then return end
    local ok, current = pcall(readCurrent, "player", argument)
    if not (ok and Number(current) and current >= minimum) then return end
    local maxOK, maximum = pcall(readMax, "player", argument)
    if maxOK and Number(maximum) and maximum > 0 then return math.min(current / maximum, 1) * 100 end
end

-- UnitHealthMax takes only the unit token. In Forever UnitHealth also accepts the predicted-health flag.
local function HealthMax(unit) return UnitHealthMax(unit) end

local function HealthPercent()
    if not UnitHealthMax then return end
    return Percent(UnitHealth, HealthMax, false, 1)
end

local function ManaPercent()
    local maxOK, maximum = false, nil
    if UnitPowerMax then maxOK, maximum = pcall(UnitPowerMax, "player", manaType) end
    local hasPool = maxOK and Number(maximum)
    if hasPool and maximum <= 0 then return end

    local ok, current = false, nil
    if UnitPower then ok, current = pcall(UnitPower, "player", manaType) end
    if ok and Number(current) and hasPool then return ns.Clamp(current / maximum, 0, 1) * 100 end

    local restricted = (ok and IsSecret(current)) or (maxOK and IsSecret(maximum))
    if UnitPowerPercent then
        local scale = CurveConstants and CurveConstants.ScaleTo100
        local percentOK, percent = pcall(UnitPowerPercent, "player", manaType, false, scale)
        if percentOK and Number(percent) then
            return ns.Clamp(scale and percent or percent * 100, 0, 100)
        end
        restricted = restricted or (percentOK and IsSecret(percent))
    end
    if restricted and not hasPool then
        local typeOK, active
        if UnitPowerType then typeOK, active = pcall(UnitPowerType, "player") end
        restricted = typeOK and Public(active, "number") and active == manaType
    end
    return nil, restricted
end

local function HasAggro()
    if not UnitThreatSituation then return end
    local ok, status = pcall(UnitThreatSituation, "player")
    if not ok or (issecretvalue and issecretvalue(status)) then return end
    if status == nil or status == 0 or status == 1 then return false end
    if status == 2 or status == 3 then return true end
end

local function Play(kind, detail)
    return SUI.CombatAlert:PlayExtraAlert(kind, detail)
end

local resources = {
    healthAlert = { read = HealthPercent, minimum = 5, displayMin = 1, defaults = ns.alertDefaults.healthAlert },
    manaAlert = { read = ManaPercent, minimum = 0, displayMin = 0, defaults = ns.manaDefaults },
}

function M:SampleResource(kind, silent)
    local state, resource = self.resources[kind], resources[kind]
    local mana = kind == "manaAlert"
    if state.instanceOnly and not self.inDungeon then
        state.previous = nil
        if not mana then state.armed = nil end
        return
    end
    local percent
    if state.enabled and self.alive then percent = resource.read() end
    local previous = state.previous
    state.previous = percent
    if not percent then return end
    if percent >= state.rearm then
        state.armed = true
    elseif percent <= state.threshold then
        local ready = previous ~= nil and state.armed == true
        if mana then
            -- The recovery threshold locks out repeats only after a signal has played.
            ready = previous ~= nil and percent < previous and state.armed ~= false
        end
        if ready and not silent and (not state.instanceOnly or InDungeonOrRaid()) then
            local played = Play(kind, math.max(resource.displayMin, ns.Round(percent)))
            if played or not mana then state.armed = false end
        elseif not mana then
            state.armed = false
        end
    elseif state.armed == nil then
        state.armed = true
    end
end

local function UpdateResource(state, options, resource)
    local enabled = type(options) == "table" and options.enabled == true
    if type(options) ~= "table" then options = resource.defaults end
    local threshold = Setting(options.threshold, resource.defaults.threshold, resource.minimum, 90)
    local rearm = math.max(threshold + 1, Setting(options.rearm, resource.defaults.rearm, resource.minimum + 1, 100))
    local instanceOnly = options.instanceOnly == true
    local changed = options ~= state.options or enabled ~= state.enabled or threshold ~= state.threshold or rearm ~= state.rearm
        or instanceOnly ~= state.instanceOnly
    if changed then
        state.options, state.enabled, state.threshold, state.rearm = options, enabled, threshold, rearm
        state.instanceOnly = instanceOnly
        state.previous = nil
        if resource == resources.healthAlert then state.armed = nil end
    end
    return changed
end

function M:SampleAggro(silent)
    if not (self.aggroEnabled and self.alive and self.inCombat and self.inDungeon and InDungeonOrRaid()) then
        self.hasAggro = nil
        return
    end
    local previous, current = self.hasAggro, HasAggro()
    self.hasAggro = current
    if current == true and previous == false and not silent then Play("aggroAlert") end
end

function M:ClearObservation()
    self.resources.healthAlert.previous, self.resources.healthAlert.armed = nil, nil
    self.resources.manaAlert.previous = nil
    self.hasAggro = nil
end

function M:QueueManaSample()
    if self.pendingManaSample or not self.resources.manaAlert.enabled then return end
    self.pendingManaSample = true
    SUI:After(0, self, "mana sample", function(detector)
        detector.pendingManaSample = nil
        detector:SampleResource("manaAlert")
    end)
end

function M:OnUnitEvent(event, unit, powerToken)
    if not Public(unit, "string") or unit ~= "player" then return end
    local kind = unitEvents[event]
    if not PlayerAlive() then self:ClearObservation(); return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then self:QueueManaSample(); return end
    if kind == "manaAlert" and event ~= "UNIT_DISPLAYPOWER" and Public(powerToken, "string")
        and powerToken ~= "" and powerToken ~= "MANA" then return end
    if kind == "aggroAlert" then self:SampleAggro() else self:SampleResource(kind, event == "UNIT_DISPLAYPOWER") end
end

function M:UpdateUnitEvents()
    local health, mana = self.resources.healthAlert, self.resources.manaAlert
    local wanted = {
        healthAlert = self.alive and health.enabled and (not health.instanceOnly or self.inDungeon) and UnitHealth and UnitHealthMax,
        manaAlert = self.alive and mana.enabled and (not mana.instanceOnly or self.inDungeon)
            and (UnitPowerPercent or (UnitPower and UnitPowerMax)),
        aggroAlert = self.alive and self.aggroEnabled and self.inCombat and self.inDungeon and UnitThreatSituation,
    }
    if not self.frame and (wanted.healthAlert or wanted.manaAlert or wanted.aggroAlert) then
        self.frame, self.bound = CreateFrame("Frame"), {}
        self.frame:SetScript("OnEvent", function(_, event, unit, ...)
            SUI:SafeModuleCall(self, "player alert event", self.OnUnitEvent, event, unit, ...)
        end)
    end
    if not self.frame then return end
    for event, kind in pairs(unitEvents) do
        if wanted[kind] and self.bound[event] == nil then
            local valid = not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
            local bound = false
            if valid and self.frame.RegisterUnitEvent then
                local ok, registered = pcall(self.frame.RegisterUnitEvent, self.frame, event, "player")
                bound = ok and registered ~= false
            end
            if valid and not bound and kind == "manaAlert" then
                local ok, registered = pcall(self.frame.RegisterEvent, self.frame, event)
                bound = ok and registered ~= false
            end
            self.bound[event] = bound
        elseif not wanted[kind] then
            if self.bound[event] then self.frame:UnregisterEvent(event) end
            self.bound[event] = nil
        end
    end
end

function M:OnProfileChanged()
    if not self.resources then return end
    local profile = not self.manaOnly and SUI:GetModuleProfile("combatAlert")
    local health = profile and profile.healthAlert
    local aggro = profile and profile.aggroAlert
    local healthChanged = UpdateResource(self.resources.healthAlert, health, resources.healthAlert)
    local manaChanged = UpdateResource(self.resources.manaAlert, ns.db.manaAlert, resources.manaAlert)
    local aggroEnabled = type(aggro) == "table" and aggro.enabled == true
    local aggroChanged = profile ~= self.profile or aggroEnabled ~= self.aggroEnabled
    if not (healthChanged or manaChanged or aggroChanged) then return end

    self.profile, self.aggroEnabled = profile, aggroEnabled
    self.alive, self.inCombat, self.inDungeon = PlayerAlive(), PlayerInCombat(), InDungeonOrRaid()
    if healthChanged then self:SampleResource("healthAlert", true) end
    if manaChanged then self:SampleResource("manaAlert", true) end
    if aggroChanged then
        self.hasAggro = nil
        self:SampleAggro(true)
    end
    self:UpdateUnitEvents()
    if SUI.initialized then SUI:RefreshModuleEvents() end
end

function M:WantsEvent(event)
    local mana = self.resources.manaAlert.enabled
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then return mana end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then return self.aggroEnabled or mana end
    return self.resources.healthAlert.enabled or self.resources.manaAlert.enabled or self.aggroEnabled
end

function M:OnEvent(event)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        self:QueueManaSample()
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:QueueManaSample()
        if self.inCombat then return end
        self.alive, self.inDungeon, self.inCombat = PlayerAlive(), InDungeonOrRaid(), true
        self.hasAggro = false
        self:SampleAggro()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat, self.hasAggro = false, nil
        self:QueueManaSample()
    elseif event == "PLAYER_DEAD" then
        self.alive, self.inCombat = false, false
        self:ClearObservation()
    else
        if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then self:ClearObservation() end
        self.alive, self.inCombat, self.inDungeon = PlayerAlive(), PlayerInCombat(), InDungeonOrRaid()
        self:SampleResource("healthAlert", true)
        self:SampleResource("manaAlert", true)
        self:SampleAggro(true)
    end
    self:UpdateUnitEvents()
end

function M:Initialize(manaOnly)
    self.manaOnly = manaOnly
    self.resources = { healthAlert = {}, manaAlert = {} }
    for _, event in ipairs(lifecycleEvents) do SUI:RegisterModuleEvent(self, event) end
    self:OnProfileChanged()
end

function M:GetManaStatus()
    local L = ns.L
    if not self.resources then return L.manaStatusUnavailable end
    local state = self.resources.manaAlert
    if not state.enabled then return L.manaStatusOff end
    if state.instanceOnly and not InDungeonOrRaid() then return L.manaStatusOutside end
    local percent, restricted = ManaPercent()
    if restricted then return L.manaStatusRestricted end
    if not percent then return L.manaStatusUnavailable end
    if state.armed == false then return L.manaStatusRearming:format(percent, state.rearm) end
    return L.manaStatusReady:format(percent, state.threshold)
end
