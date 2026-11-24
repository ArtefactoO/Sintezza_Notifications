local name, ns = ...
local L, T, W, B = ns.L, ns.SettingsTheme, ns.Widgets, ns.SettingsBuilder
local theme = Sintezza_Theme
local icon = "Interface\\AddOns\\" .. name .. "\\Media\\Icon"
local prefs = theme and theme:NewWindowPreferences(function() return ns.db end)
local window, minimap, selectSettingsPage
local questExample = "questProgress"
local zoneExample = "zone"
local examples = { quests = "questProgress", zones = "zone", transport = "arrival" }
local otherEvents = { "achievements", "bossEmotes", "rares", "scenarios", "scenarioUpdates", "levels" }
local colorLabels = {
    title = L.colorTitle, detail = L.colorDetail, accent = L.colorAccent, background = L.colorBackground,
}

local function SetMinimapShown(shown)
    ns.db.minimap.hide = not shown
    if minimap then minimap:Refresh(ns.db.minimap) end
end

local function SetWorldOption(page, options, key, value)
    options[key] = value
    ns.RefreshDisplay()
    page:RefreshPreview()
    if options == ns.db then
        if key == "quests" then ns.ResetQuestState() end
        if key == "quests" or key == "hideNativeQuestProgress" then
            ns.SyncNativeQuestProgress()
        end
    elseif key == "opacity" and options == ns.WorldStyle("quests") then
        ns.SyncNativeQuestProgress()
    end
    if (options == ns.db and key == "zones") or (key == "opacity" and options == ns.WorldStyle("zones")) then
        ns.SyncNativeZoneDiscovery()
    end
end

local function BuildWorldPage(page, key)
    local previewKind = examples[key] or "achievement"
    local selection = key == "quests" and {
        label = L.sampleEvent,
        choices = { questProgress = L.questProgress, objectiveDone = L.objectiveDone,
            questAccept = L.questAccept, questComplete = L.questComplete },
        get = function() return questExample end,
        set = function(value) questExample = value end,
        order = { questProgress = 1, objectiveDone = 2, questAccept = 3, questComplete = 4 },
    }
    if key == "zones" then
        selection = {
            label = L.sampleEvent, choices = { zone = L.zone, discovery = L.discovery },
            get = function() return zoneExample end,
            set = function(value) zoneExample = value end,
            order = { zone = 1, discovery = 2 },
        }
    end
    B:AddPreview(page, ns.CreateWorldSample, ns.Preview, selection, previewKind)
    local style = ns.WorldStyle(key)
    local paletteGroup = key == "world" and "achievements" or key
    local function Get(key) return function() return style[key] end end
    local function Set(key) return function(value) SetWorldOption(page, style, key, value) end end
    local function Toggle(card, key, label, options)
        options = options or style
        B:AddRow(page, card, W:Toggle(card, label or L[key], function() return options[key] end,
            function(value) SetWorldOption(page, options, key, value) end))
    end
    local function Slider(card, key, suffix)
        local low, high, step = unpack(ns.ranges[key])
        local row = W:SliderRow(card, L[key], low, high, step, Get(key), Set(key), suffix)
        B:AddRow(page, card, row)
    end
    local function Font(card, key)
        B:AddRow(page, card, W:ChoiceRow(card, L[key], function() return ns.FontChoices(style[key]) end,
            Get(key), Set(key), ns.fontOrder))
    end
    local function Button(card, label, callback, primary)
        B:AddRow(page, card, W:Button(card, label, callback, primary))
    end
    local function Section(label, makeRows)
        local card = B:AddSection(page, label)
        makeRows(card)
        B:FinishSection(page, card)
    end
    Section(L.trigger, function(card)
        if key == "world" then
            Toggle(card, "otherEventsEnabled")
            for _, event in ipairs(otherEvents) do Toggle(card, event) end
        elseif key == "transport" then
            Toggle(card, "enabled", L.transportEnabled)
        else
            Toggle(card, key, nil, ns.db)
        end
    end)
    Section(L.textOptions, function(card)
        if key == "quests" then
            Toggle(card, "hideNativeQuestProgress", nil, ns.db)
            Toggle(card, "compactQuestProgress", nil, ns.db)
            Toggle(card, "questRewards", nil, ns.db)
        end
        Font(card, "mainFont")
        Slider(card, "mainSize")
        Font(card, "detailFont")
        Slider(card, "detailSize")
    end)
    local position = ns.WorldPosition(key)
    position.move = function() ns.Move(selection and selection.get() or previewKind, position) end
    B:AddPosition(page, position)
    Section(L.colors, function(card)
        Slider(card, "opacity", "%")
        Slider(card, "backgroundOpacity", "%")
        Toggle(card, "softBackground")
        for _, role in ipairs(ns.colorRoles) do
            B:AddRow(page, card, W:ColorRow(card, colorLabels[role],
                function() return ns.ToastColor(role, paletteGroup) end,
                function(value)
                    local default = ns.DefaultToastColor(role, paletteGroup)
                    local isDefault = value[1] == default[1] and value[2] == default[2] and value[3] == default[3]
                        and value[4] == (default[4] or 1)
                    if isDefault then style.colors[role] = nil else style.colors[role] = value end
                    ns.RefreshDisplay()
                    page:RefreshPreview()
                end))
        end
        Button(card, L.resetColors, function()
            style.colors = {}
            ns.RefreshDisplay()
            page:Refresh()
        end)
    end)
    Section(L.animation, function(card)
        Toggle(card, "animate")
        Slider(card, "speed", "×")
        if key ~= "transport" then Slider(card, "hold") end
    end)
end

local function BuildWindowPage(page)
    local options = theme:CreateWindowOptions(page.body, T, {
        windows = { { prefs = prefs } },
        getMinimap = function() return not ns.db.minimap.hide end,
        setMinimap = SetMinimapShown,
    })
    options:SetPoint("TOPLEFT")
    options:SetPoint("TOPRIGHT")
    page.nextY = -options:GetHeight()
    page:AddRefresher(options)
    page:Layout()
end

local navigationGroups = {
    { title = L.notifications, build = BuildWorldPage, entries = {
        { "quests", L.questsPage }, { "zones", L.zonesPage }, { "transport", L.transportPage }, { "world", L.eventsPage },
    } },
    { title = L.signals, build = ns.BuildAlertPage, entries = {
        { "combat", L.combat }, { "stealth", L.stealth }, { "healthAlert", L.health },
        { "manaAlert", L.mana }, { "aggroAlert", L.aggro },
    } },
    { title = L.settingsGroup, build = BuildWindowPage, entries = { { "window", L.window } } },
}

local function Build()
    local frame = CreateFrame("Frame", "SintezzaNotificationsSettings", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(1020, 630)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    T:WindowSurface(frame)
    local header = W:WindowHeader(frame, { title = ns.title, addonName = name, icon = icon })
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if prefs:CanMove() then frame:StartMoving() end
    end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame:HookScript("OnHide", function() frame:StopMovingOrSizing() end)
    table.insert(UISpecialFrames, frame:GetName())

    local sidebar = W:Surface(frame, nil, "sidebar")
    sidebar:SetWidth(182)
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -9)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 13)
    local navScroll, navBody, navBar = W:ScrollFrame(sidebar)
    navScroll:SetPoint("TOPLEFT", 6, -7)
    navScroll:SetPoint("BOTTOMRIGHT", -13, 7)
    navBar:SetPoint("TOPRIGHT", navScroll, "TOPRIGHT", 8, 0)
    navBar:SetPoint("BOTTOMRIGHT", navScroll, "BOTTOMRIGHT", 8, 0)
    navScroll:HookScript("OnSizeChanged", function(owner, width)
        navBody:SetWidth(math.max(1, width))
        owner:RefreshRange()
    end)
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 5, 0)
    content:SetPoint("BOTTOMRIGHT", -14, 12)

    local pages, definitions, buttons, selected = {}, {}, {}
    local function SelectPage(key)
        if not definitions[key] or selected == key then return end
        if selected then
            pages[selected]:Hide()
            buttons[selected]:SetSelected(false)
        end
        if not pages[key] then
            local definition = definitions[key]
            local page = B:CreatePage(content, definition.title, key ~= "window")
            definition.build(page, key)
            pages[key] = page
        end
        selected = key
        buttons[key]:SetSelected(true)
        pages[key]:Show()
    end

    local offset = 0
    for index, group in ipairs(navigationGroups) do
        if index > 1 then offset = offset - 12 end
        if group.title then
            local label = W:Label(navBody, group.title, 11, T.brass)
            label:SetPoint("TOPLEFT", navBody, "TOPLEFT", 9, offset)
            offset = offset - 20
        end
        for _, entry in ipairs(group.entries) do
            local key, title = unpack(entry)
            definitions[key] = { title = title, build = group.build }
            local button = W:NavButton(navBody, title, key, SelectPage)
            button:SetPoint("TOPLEFT", navBody, "TOPLEFT", 0, offset)
            button:SetPoint("TOPRIGHT", navBody, "TOPRIGHT", -1, offset)
            buttons[key] = button
            offset = offset - button:GetHeight()
        end
    end
    navBody:SetHeight(-offset + 2)
    navScroll:RefreshRange()
    SelectPage("quests")
    selectSettingsPage = SelectPage
    frame:HookScript("OnShow", function() pages[selected]:Refresh() end)
    theme:TrackAppearance(frame, "notificationSettingsSample", function() pages[selected]:RefreshPreview() end)
    ns.RefreshAlertSettings = function()
        if frame:IsShown() and pages[selected] then pages[selected]:Refresh() end
    end
    ns.NotifyPositionChanged = function()
        if pages[selected] then pages[selected]:Refresh() end
    end
    prefs:Bind(frame, { resize = { minWidth = 900, minHeight = 490, maxWidth = 1300, maxHeight = 920 } })
    return frame
end

function ns.GetSettingsWindow()
    return window
end

function ns.OpenSettings(page)
    if not theme then ns.Say(L.themeRequired); return false end
    if not window then window = Build() end
    if page then selectSettingsPage(page == "position" and "world" or page) end
    prefs:ApplyTo(window)
    window:Show()
    window:Raise()
    return true
end

function ns.RegisterSettings()
    SLASH_SINTEZZANOTIFICATIONS1 = "/snotify"
    SlashCmdList.SINTEZZANOTIFICATIONS = function(input)
        local action = input:match("^%s*(%S*)"):lower()
        if action == "test" then ns.Preview()
        elseif action == "move" then ns.Move()
        elseif action == "status" then ns.PrintAlertStatus()
        elseif action == "" then ns.OpenSettings()
        else ns.Say(L.help) end
    end
    if not theme then return end

    theme:RegisterGlobalWindowPreferences(ns.title, prefs)
    theme:RegisterLauncherPage({ title = ns.title, icon = icon, buttonLabel = L.open,
        open = ns.OpenSettings, appearance = T })
    minimap = theme:CreateMinimapButton(name, icon, ns.db.minimap,
        { window = ns.GetSettingsWindow, open = ns.OpenSettings }, function(tooltip)
            tooltip:AddLine(ns.title, unpack(T.accent))
            theme:AddMinimapToggleHint(tooltip)
        end)
end
