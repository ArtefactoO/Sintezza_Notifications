local _, ns = ...
local L = ns.L
local lastZone, lastSubzone, zoneTimer, enteringZone
local lastDiscovery, discoveryTime, discoveryDetail
local nativeZoneFrame
local scenario, completedScenario, scenarioTimer
local seenVignettes, rareDeaths = {}, {}
local worldReady
local discoveryTypes = { ERR_ZONE_EXPLORED = true, ERR_ZONE_EXPLORED_XP = true }
local nativeDiscovery = ns.CreateNativeInfoFilter(discoveryTypes, true)

local onboardPatterns = {
    ruRU = "^Прибытие: (.+) через (%d+):(%d%d)$",
    deDE = "^Ankunft in (.+) in (%d+):(%d%d)$",
    esES = "^Llegada a (.+) en (%d+):(%d%d)$",
    esMX = "^Llegada a (.+) en (%d+):(%d%d)$",
    frFR = "^Arrivée à (.+) dans (%d+):(%d%d)$",
    koKR = "^(.+) 도착까지 (%d+):(%d%d)$",
    ptBR = "^Chegando a (.+) em (%d+):(%d%d)$",
    zhCN = "^到达(.+)还需(%d+):(%d%d)$",
    zhTW = "^抵達(.+)還需(%d+):(%d%d)$",
}
local onboardPattern = onboardPatterns[GetLocale()] or "^Arriving at (.+) in (%d+):(%d%d)$"
local hookedWarningUtil

local function RouteTransportArrival(text, color, kind)
    if not worldReady or not ns.WorldStyle("transport").enabled
        or (InCombatLockdown and InCombatLockdown()) or not ns.IsPublic(text, "string")
        or not ns.IsPublic(color, "table") or not ns.IsPublic(kind, "nil") then return end
    if not ChatTypeInfo or color ~= ChatTypeInfo.RAID_WARNING then return end
    local destination, minutes, seconds = text:match(onboardPattern)
    if not destination then return end
    local duration = tonumber(minutes) * 60 + tonumber(seconds)
    if duration < 15 or duration > 20 then return end

    local frame = RaidWarningFrame
    if not frame or not frame.fontStringPool or frame:IsForbidden() then return end
    for line in frame.fontStringPool:EnumerateActive() do
        if line.messageOrder == frame.messageCounter and not line:IsForbidden() then
            local shown = line:GetText()
            if ns.IsPublic(shown, "string") and shown == text and ns.ShowTransportArrival(destination, duration) then
                line:Hide()
            end
            return
        end
    end
end

local function HookTransportArrival()
    local util = RaidWarningUtil
    if not util or util == hookedWarningUtil or type(util.AddMessage) ~= "function" or not hooksecurefunc
        or not C_AddOns or not C_AddOns.IsAddOnLoaded or not C_AddOns.IsAddOnLoaded("ShortestPathForever") then return end
    if pcall(hooksecurefunc, util, "AddMessage", function(text, color, _, kind)
        -- The shared warning renderer can change. Leave its original message visible on failure.
        pcall(RouteTransportArrival, text, color, kind)
    end) then hookedWarningUtil = util end
end

function ns.ZoneNames()
    local zone = ns.Text(GetZoneText and GetZoneText())
    if zone == "" then zone = ns.Text(GetRealZoneText and GetRealZoneText()) end
    local subzone = GetSubZoneText and GetSubZoneText()
    local title = ns.Text(subzone)
    return zone, title ~= zone and title or "", ns.IsPublic(subzone, "string")
end

local function ReplacesNativeZoneText()
    local db = ns.db
    return db.zones and ns.WorldStyle("zones").opacity > 0 and not ns.HorizonActive()
end

function ns.SyncNativeZoneDiscovery()
    nativeDiscovery.Sync(ReplacesNativeZoneText())
end

local function EscapePattern(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function DiscoveryText(kind, message)
    local text = ns.Text(message)
    if text == "" then
        local zone, subzone = ns.ZoneNames()
        return subzone ~= "" and subzone or zone
    end
    local template = _G[kind]
    if type(template) ~= "string" then return text end
    local prefix, tail = template:match("^(.-)%%[%d%$]*s(.*)$")
    if not prefix then return text end
    local pattern = "^" .. EscapePattern(prefix)
    local divider = tail:match("^(.-)%%[%d%$]*d")
    if divider then
        local title, xp = text:match(pattern .. "(.-)" .. EscapePattern(divider) .. "(%d+)")
        if title and title ~= "" then return title, L.experienceReward:format(tonumber(xp)) end
    else
        local title = text:match(pattern .. "(.+)" .. EscapePattern(tail) .. "$")
        if title then return title end
    end
    return text
end

local function ZoneDiscovery(id, message)
    local kind = ns.InfoMessageType(id, discoveryTypes)
    if not kind then return false end
    ns.SyncNativeZoneDiscovery()
    if not ReplacesNativeZoneText() then return true end
    local title, detail = DiscoveryText(kind, message)
    if title == "" then return true end
    nativeDiscovery.Hide(id)
    local now = GetTime()
    if title == lastDiscovery and now - discoveryTime < 1 and (not detail or detail == discoveryDetail) then
        return true
    end
    lastDiscovery, discoveryTime, discoveryDetail = title, now, detail
    ns.Notify("zones", "discovery", title, detail, { key = "location", priority = true, long = true })
    return true
end

local function CheckZone()
    local newArea = enteringZone
    zoneTimer = nil
    enteringZone = nil
    local zone, subzone, hasSubzone = ns.ZoneNames()
    if zone == "" then return end
    local zoneChanged = newArea or zone ~= lastZone
    if ReplacesNativeZoneText() and (zoneChanged or (hasSubzone and subzone ~= lastSubzone)) then
        local showSubzone = subzone ~= ""
        local kind = not zoneChanged and showSubzone and "subzone" or "zone"
        local title = kind == "subzone" and subzone or zone
        local detail = kind == "subzone" and zone or (showSubzone and subzone or nil)
        local recentlyDiscovered = discoveryTime and GetTime() - discoveryTime < 1
            and (lastDiscovery == zone or lastDiscovery == subzone)
        if not recentlyDiscovered then
            ns.Notify("zones", kind, title, detail, { key = "location", priority = true, long = zoneChanged })
        end
    end
    lastZone = zone
    if zoneChanged or hasSubzone then lastSubzone = subzone end
end

local function ScheduleZone(event)
    if not worldReady then return end
    if event == "ZONE_CHANGED_NEW_AREA" then enteringZone = true end
    if not zoneTimer then zoneTimer = C_Timer.NewTimer(.20, CheckZone) end
end

local zoneEvents = { ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true }

local function HideNativeZone(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    if InCombatLockdown and InCombatLockdown() and (not frame.IsProtected or frame:IsProtected()) then return end
    pcall(frame.Hide, frame)
end

local function HookNativeZoneText()
    local frame = ZoneTextFrame
    if not frame or frame == nativeZoneFrame or not frame.HookScript then return end
    local ok = pcall(frame.HookScript, frame, "OnEvent", function(target, event)
        if not zoneEvents[event] or not worldReady then return end
        ScheduleZone(event)
        if not ReplacesNativeZoneText() then return end
        local zone, _, hasSubzone = ns.ZoneNames()
        if zone == "" then return end
        HideNativeZone(target)
        if hasSubzone then HideNativeZone(SubZoneTextFrame) end
    end)
    if ok then nativeZoneFrame = frame end
end

local function GetScenario()
    local info = C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo and C_ScenarioInfo.GetScenarioInfo()
    if not ns.IsPublic(info, "table") then return end
    local name = ns.Text(info.name)
    local stage = info.currentStage
    if name == "" or not ns.IsPublic(stage, "number") or stage < 1 then return end
    local id = ns.IsPublic(info.scenarioID, "number") and info.scenarioID or name
    local done = ns.IsPublic(info.isComplete, "boolean") and info.isComplete
    return { name = name, stage = stage, id = id, done = done, criteria = {} }
end

local function CompleteScenario(info)
    if not info or completedScenario == info.id then return end
    completedScenario = info.id
    ns.Notify("scenarios", "scenarioComplete", info.name, nil, { final = true, long = true })
end

local function ReadCriteria(info, previous)
    if not C_ScenarioInfo.GetScenarioStepInfo or not C_ScenarioInfo.GetCriteriaInfo then return end
    local step = C_ScenarioInfo.GetScenarioStepInfo()
    if not ns.IsPublic(step, "table") or not ns.IsPublic(step.numCriteria, "number") then return end
    for index = 1, step.numCriteria do
        local criterion = C_ScenarioInfo.GetCriteriaInfo(index)
        if ns.IsPublic(criterion, "table") then
            local name = ns.Text(criterion.description)
            local count, total = criterion.quantity, criterion.totalQuantity
            if name ~= "" and ns.IsPublic(count, "number") and ns.IsPublic(total, "number") then
                local old = previous and previous.criteria[index]
                info.criteria[index] = count
                if old and count > old then
                    local detail = total > 1 and ("%d/%d %s"):format(count, total, name) or name
                    ns.Notify("scenarioUpdates", "scenarioProgress", info.name, detail, {
                        key = ("scenario:%s:%d:%d"):format(info.id, info.stage, index),
                        progress = total > 0 and ns.Clamp(count / total, 0, 1) or nil,
                    })
                end
            end
        end
    end
end

local function CheckScenario(seed)
    scenarioTimer = nil
    local info = GetScenario()
    local previous = scenario
    scenario = info
    if not info then completedScenario = nil; return end
    local started = not previous or previous.id ~= info.id or previous.done and not info.done
    if started and not info.done then
        completedScenario = nil
        if not seed then ns.Notify("scenarios", "scenarioStart", info.name, nil, { long = true }) end
    elseif info.done then
        if seed then completedScenario = info.id else CompleteScenario(info) end
    end
    if not info.done and ns.db.scenarioUpdates then
        ReadCriteria(info, not started and previous.stage == info.stage and previous or nil)
    end
end

local function ScheduleScenario()
    if worldReady and not scenarioTimer then
        scenarioTimer = C_Timer.NewTimer(.23, function() CheckScenario(false) end)
    end
end

local function NotifyRare(guid, name)
    if not ns.IsPublic(guid, "string") or rareDeaths[guid] or name == "" then return end
    rareDeaths[guid] = true
    C_Timer.After(30, function() rareDeaths[guid] = nil end)
    ns.Notify("rares", "rare", name, nil, { key = "rare:" .. guid, long = true })
end

local function RareVignette(info)
    local atlas = ns.Text(info.atlasName):lower()
    return atlas:find("rare", 1, true) or atlas:find("vignettekill", 1, true)
end

local function CheckVignettes(seed)
    if not C_VignetteInfo or not C_VignetteInfo.GetVignettes or not C_VignetteInfo.GetVignetteInfo then return end
    if not ns.db.rares then seenVignettes = {}; return end
    local ids = C_VignetteInfo.GetVignettes()
    if not ns.IsPublic(ids, "table") then return end
    local current = {}
    for _, id in ipairs(ids) do
        if ns.IsPublic(id, "string") then
            local info = C_VignetteInfo.GetVignetteInfo(id)
            if ns.IsPublic(info, "table") and RareVignette(info) then
                local dead = ns.IsPublic(info.isDead, "boolean") and info.isDead
                if dead and not seed and seenVignettes[id] == false then
                    local guid = ns.IsPublic(info.objectGUID, "string") and info.objectGUID or id
                    NotifyRare(guid, ns.Text(info.name))
                end
                if info.onMinimap then current[id] = not not dead end
            end
        end
    end
    seenVignettes = current
end

local function CheckRareUnit(unit)
    if not ns.db.rares or not UnitClassification or not UnitIsDead then return end
    local dead = UnitIsDead(unit)
    if not ns.IsPublic(dead, "boolean") or not dead then return end
    local classification = UnitClassification(unit)
    if not ns.IsPublic(classification, "string") or (classification ~= "rare" and classification ~= "rareelite") then return end
    NotifyRare(UnitGUID(unit), ns.Text(UnitName(unit)))
end

function ns.StartEvents()
    local handlers = {
        PLAYER_ENTERING_WORLD = function(initial, reload)
            ns.SyncNativeQuestProgress()
            ns.SyncNativeZoneDiscovery()
            HookNativeZoneText()
            HookTransportArrival()
            if not worldReady or initial or reload then
                lastZone, lastSubzone = ns.ZoneNames()
                ns.ResetQuestState()
                CheckScenario(true)
                CheckVignettes(true)
                worldReady = true
                if (ns.db.quests or ns.db.zones or ns.db.otherEventsEnabled) and ns.HorizonActive() then
                    ns.Say(L.conflict)
                end
            else
                ScheduleZone()
                ScheduleScenario()
                CheckVignettes(true)
                ns.QuestLogUpdate()
            end
        end,
        ADDON_LOADED = function(addon)
            if addon == "ShortestPathForever" or addon == "Blizzard_RaidWarning" then HookTransportArrival() end
        end,
        ZONE_CHANGED_NEW_AREA = function() ScheduleZone("ZONE_CHANGED_NEW_AREA") end,
        ZONE_CHANGED_INDOORS = ScheduleZone,
        ZONE_CHANGED = ScheduleZone,
        QUEST_ACCEPTED = ns.QuestAccepted,
        QUEST_WATCH_UPDATE = ns.QuestWatch,
        QUEST_LOG_UPDATE = ns.QuestLogUpdate,
        QUEST_REMOVED = ns.QuestRemoved,
        QUEST_TURNED_IN = ns.QuestCompleted,
        UI_INFO_MESSAGE = function(id, message)
            if not ZoneDiscovery(id, message) then ns.QuestMessage(id, message) end
        end,
        SCENARIO_UPDATE = ScheduleScenario,
        SCENARIO_CRITERIA_UPDATE = ScheduleScenario,
        SCENARIO_COMPLETED = function() CompleteScenario(GetScenario() or scenario) end,
        VIGNETTES_UPDATED = function() CheckVignettes(false) end,
        UNIT_HEALTH = function(unit)
            if ns.IsPublic(unit, "string") and (unit == "target" or unit == "mouseover") then CheckRareUnit(unit) end
        end,
        ACHIEVEMENT_EARNED = function(id)
            if ns.IsPublic(id, "number") and GetAchievementInfo then
                local _, title = GetAchievementInfo(id)
                ns.Notify("achievements", "achievement", title, nil, { long = true })
            end
        end,
        RAID_BOSS_EMOTE = function(message, author)
            local text, speaker = ns.Text(message), ns.Text(author)
            if text ~= "" then
                text = text:gsub("%%s", function() return speaker end)
                ns.Notify("bossEmotes", "boss", text, nil, { priority = true, long = true })
            end
        end,
        PLAYER_LEVEL_UP = function(level)
            if ns.IsPublic(level, "number") then
                ns.Notify("levels", "level", L.levelNumber:format(level), nil, { priority = true, long = true })
            end
        end,
        DISPLAY_SIZE_CHANGED = ns.RefreshDisplay,
        UI_SCALE_CHANGED = ns.RefreshDisplay,
    }
    local frame = CreateFrame("Frame")
    for event in pairs(handlers) do
        if event ~= "UNIT_HEALTH" and (not C_EventUtils or C_EventUtils.IsEventValid(event)) then
            frame:RegisterEvent(event)
        end
    end
    if not pcall(frame.RegisterUnitEvent, frame, "UNIT_HEALTH", "target", "mouseover") then
        frame:RegisterEvent("UNIT_HEALTH")
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_ENTERING_WORLD" or worldReady then handlers[event](...) end
    end)
end
