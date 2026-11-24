local name, ns = ...

ns.title = "Sintezza Notifications"
ns.defaults = {
    zones = true, quests = true, otherEventsEnabled = true, achievements = true,
    bossEmotes = true, rares = true, scenarios = true, scenarioUpdates = false, levels = false,
    animate = true, speed = 1, hold = 2.4,
    x = 0, y = 356, mainFont = "theme", detailFont = "theme", mainSize = 34, detailSize = 19,
    opacity = 100, backgroundOpacity = 92, softBackground = true,
    hideNativeQuestProgress = true, compactQuestProgress = true, questRewards = true,
}
ns.ranges = {
    speed = { 0.5, 2, 0.1 }, hold = { 1, 6, 0.1 },
    mainSize = { 16, 52, 1 }, detailSize = { 12, 32, 1 },
    opacity = { 0, 100, 1 }, backgroundOpacity = { 0, 100, 1 },
}
ns.colorRoles = { "title", "detail", "accent", "background" }

function ns.Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function ns.Round(value)
    return math.floor(value + .5)
end

function ns.IsPublic(value, kind)
    return not (issecretvalue and issecretvalue(value)) and type(value) == kind
end

function ns.Text(value)
    if not ns.IsPublic(value, "string") then return "" end
    value = value:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return value:gsub("|[TtAa].-|[tTaA]", ""):gsub("[%c]+", " "):match("^%s*(.-)%s*$")
end

function ns.HorizonActive()
    local horizon = HorizonSuite
    return horizon and type(horizon.IsModuleEnabled) == "function" and horizon:IsModuleEnabled("presence") == true
end

function ns.Say(message)
    print("|cff81c9c2" .. ns.title .. "|r  " .. message)
end

function ns.WorldStyle(group)
    return ns.db.worldStyles[group] or ns.db
end

function ns.InfoMessageType(id, types)
    if not GetGameMessageInfo or not ns.IsPublic(id, "number") then return end
    local name = GetGameMessageInfo(id)
    if ns.IsPublic(name, "string") and types[name] then return name end
end

function ns.CreateNativeInfoFilter(types, resolveMissing)
    local current, changing
    local tried, owned = {}, {}
    local watched = setmetatable({}, { __mode = "k" })
    local ids

    local function ResolveIDs()
        ids = {}
        local missing = 0
        for name in pairs(types) do
            local id = _G["LE_GAME_" .. name]
            if ns.InfoMessageType(id, types) == name then ids[name] = id else missing = missing + 1 end
        end
        if not resolveMissing or missing == 0 then return end
        for id = 1, 4096 do
            local name = GetGameMessageInfo(id)
            if not ns.IsPublic(name, "string") or name == "" then break end
            if types[name] and not ids[name] then
                ids[name], missing = id, missing - 1
                if missing == 0 then break end
            end
        end
    end

    local function Set(frame, id, enabled)
        changing = true
        local ok = pcall(frame.SetMessageTypeEnabled, frame, id, enabled)
        changing = false
        return ok
    end

    local function Hide(id)
        if not current or tried[id] then return end
        tried[id] = true
        -- Check ownership without matching a text line already on screen.
        local ok, shown = pcall(current.ShouldDisplayMessageType, current, id, "\0")
        if ok and ns.IsPublic(shown, "boolean") and shown and Set(current, id, false) then owned[id] = true end
    end

    local function Sync(enabled)
        local frame = enabled and UIErrorsFrame or nil
        if not GetGameMessageInfo or not frame or type(frame.SetMessageTypeEnabled) ~= "function"
            or type(frame.ShouldDisplayMessageType) ~= "function" then frame = nil end
        if frame == current then return end
        if current then
            for id in pairs(owned) do Set(current, id, true) end
        end
        current, tried, owned = frame, {}, {}
        if not frame then return end
        if hooksecurefunc and not watched[frame] then
            watched[frame] = pcall(hooksecurefunc, frame, "SetMessageTypeEnabled", function(target, id)
                if not changing and target == current and ns.IsPublic(id, "number") then owned[id] = nil end
            end)
        end
        if not ids then ResolveIDs() end
        for _, id in pairs(ids) do Hide(id) end
    end

    return { Hide = Hide, Sync = Sync }
end

local styleKeys = {
    "x", "y", "mainFont", "detailFont", "mainSize", "detailSize",
    "opacity", "backgroundOpacity", "softBackground", "animate", "speed", "hold",
}

local function NormalizeColor(color)
    if type(color) ~= "table" then return end
    local result = {}
    for index = 1, 4 do
        local channel = color[index]
        if index == 4 and channel == nil then channel = 1 end
        if type(channel) ~= "number" or channel ~= channel then return end
        result[index] = ns.Clamp(channel, 0, 1)
    end
    return result
end

local function InitializeWorldStyles(db)
    if type(db.worldStyles) ~= "table" then db.worldStyles = {} end
    local styles = db.worldStyles
    local version = type(db.worldSettingsVersion) == "number" and db.worldSettingsVersion or 0
    local ui = _G.Sintezza_UIDB
    local profiles = type(ui) == "table" and ui.profiles
    local profile = version < 2 and type(profiles) == "table" and profiles[ui.activeProfile or "Default"]
    local modules = type(profile) == "table" and profile.modules
    local legacy = type(modules) == "table" and modules.transportMap
    for _, group in ipairs({ "quests", "zones", "transport" }) do
        local style = styles[group]
        if type(style) ~= "table" then style = {}; styles[group] = style end
        for _, key in ipairs(styleKeys) do
            local saved = style[key]
            if type(saved) ~= type(ns.defaults[key]) or saved == "" or saved ~= saved then
                local default = db[key]
                if group == "transport" then
                    if key == "x" then default = type(legacy) == "table" and legacy.arrivalX or 0 end
                    if key == "y" then default = type(legacy) == "table" and legacy.arrivalY or 150 end
                end
                if type(default) ~= type(ns.defaults[key]) or default ~= default then default = ns.defaults[key] end
                style[key] = default
            end
            local range = ns.ranges[key]
            if range then style[key] = ns.Clamp(style[key], range[1], range[2]) end
        end
        local colors = type(style.colors) == "table" and style.colors or (version < 3 and db.colors)
        style.colors = {}
        if colors then
            for _, role in ipairs(ns.colorRoles) do style.colors[role] = NormalizeColor(colors[role]) end
        end
        if group == "transport" and type(style.enabled) ~= "boolean" then
            style.enabled = type(legacy) == "table" and legacy.arrivalAlert == true
        end
    end
    if version < 5 then
        if db.enabled == false then
            db.quests, db.zones, db.otherEventsEnabled = false, false, false
            styles.transport.enabled = false
        end
        db.enabled = nil
    end
    db.worldSettingsVersion = math.max(version, 6)
end

local function MigrateWorldSettings(db)
    local version = type(db.worldSettingsVersion) == "number" and db.worldSettingsVersion or 0
    if version < 4 and db.otherEventsEnabled == nil then db.otherEventsEnabled = ns.defaults.otherEventsEnabled end
    if version < 6 and db.questRewards == nil then db.questRewards = ns.defaults.questRewards end
    if version >= 1 then return end
    local width, height = UIParent:GetSize()
    width = width > 0 and width or 1920
    height = height > 0 and height or 1080
    if type(db.x) == "number" and db.x == db.x then db.x = ns.Round((ns.Clamp(db.x, 0, 100) / 100 - .5) * width) end
    if type(db.y) == "number" and db.y == db.y then db.y = ns.Round((ns.Clamp(db.y, 0, 100) / 100 - .5) * height) end
    -- The old initializer always saved this pair, so it also represents an unchanged default.
    if db.mainFont == "spectral" and db.detailFont == "fira" then
        db.mainFont, db.detailFont = "theme", "theme"
    end
    db.worldSettingsVersion = 1
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:SetScript("OnEvent", function(frame, _, loaded)
    if loaded ~= name then return end
    frame:UnregisterEvent("ADDON_LOADED")
    if type(Sintezza_NotificationsDB) ~= "table" then Sintezza_NotificationsDB = {} end
    ns.db = Sintezza_NotificationsDB
    MigrateWorldSettings(ns.db)
    local height = UIParent:GetHeight()
    if height > 0 then ns.defaults.y = ns.Round(height * .33) end
    for key, default in pairs(ns.defaults) do
        local saved = ns.db[key]
        if type(saved) ~= type(default) or saved == "" or (type(saved) == "number" and saved ~= saved) then
            ns.db[key] = default
        elseif ns.ranges[key] then
            ns.db[key] = ns.Clamp(saved, ns.ranges[key][1], ns.ranges[key][2])
        end
    end
    if type(ns.db.colors) ~= "table" then ns.db.colors = {} end
    for _, role in ipairs(ns.colorRoles) do
        ns.db.colors[role] = NormalizeColor(ns.db.colors[role])
    end
    InitializeWorldStyles(ns.db)
    if type(ns.db.minimap) ~= "table" then ns.db.minimap = {} end
    ns.InitializeAlerts()
    ns.CreateDisplay()
    ns.RegisterSettings()
    ns.StartEvents()
end)
