local name, ns = ...
local L = ns.L
local media = "Interface\\AddOns\\" .. name .. "\\Media\\"
local fonts = {
    { "theme", L.themeFont },
    { "combat", L.combatFont },
    { "spectral", "Spectral Medium", media .. "Spectral-Medium.ttf" },
    { "fira", "Fira Sans Medium", media .. "FiraSans-Medium.ttf" },
    { "game", L.gameFont },
    { "quest", L.questFont },
}

local palette = {
    zones = { .96, .83, .62 }, quests = { .55, .91, .82 }, achievements = { 1, .84, .55 },
    bossEmotes = { 1, .66, .58 }, rares = { .84, .75, 1 }, scenarios = { .69, .84, 1 },
    scenarioUpdates = { .69, .84, 1 }, levels = { 1, .88, .65 }, transport = { 1, .79, .54 },
}
local theme = Sintezza_Theme
local titleColor = { .91, .95, .99, 1 }
local detailColor = { .99, .98, .95, 1 }
local tintFallback = palette.zones
local anchor, preview, placement, placementDone, placementSession
local placementSamples = {}
local live = {}
local displayGroups = { "world", "quests", "zones", "transport" }
local queue = {}
local maxPending = 10
local previewContentHeight = 240

local function SharedMedia()
    return LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
end

ns.fontOrder = { theme = 1, combat = 2, spectral = 3, fira = 4, game = 5, quest = 6 }

function ns.FontChoices(selected)
    local choices = {}
    for _, font in ipairs(fonts) do choices[font[1]] = font[2] end
    local library = SharedMedia()
    if library then
        for _, fontName in ipairs(library:List("font")) do
            choices["lsm:" .. fontName] = fontName
        end
    end
    if not choices[selected] and selected:sub(1, 4) == "lsm:" then choices[selected] = selected:sub(5) end
    return choices
end

local function FontPath(id)
    if id == "quest" and QuestFont and QuestFont.GetFont then return QuestFont:GetFont() end
    if id == "game" then return STANDARD_TEXT_FONT end
    for _, font in ipairs(fonts) do
        if id == font[1] then return font[3] end
    end
    local library = SharedMedia()
    if library and id:sub(1, 4) == "lsm:" then return library:Fetch("font", id:sub(5), true) end
end

local function CombatFontPath()
    local shared = theme and theme.Theme
    if shared and shared.GetCombatTextFont then
        local path = shared:GetCombatTextFont()
        if ns.IsPublic(path, "string") and path ~= "" then return path end
    end
    if ns.IsPublic(DAMAGE_TEXT_FONT, "string") and DAMAGE_TEXT_FONT ~= "" then return DAMAGE_TEXT_FONT end
    if ns.IsPublic(COMBAT_TEXT_FONT, "string") and COMBAT_TEXT_FONT ~= "" then return COMBAT_TEXT_FONT end
    if CombatTextFont and CombatTextFont.GetFont then
        local path = CombatTextFont:GetFont()
        if ns.IsPublic(path, "string") and path ~= "" then return path end
    end
end

local function SetFont(text, id, size, role)
    local path
    if id == "theme" then
        if theme and theme.Fonts and theme.Fonts.Paint then
            theme.Fonts:Paint(text, size, "", role)
            return
        end
        path = FontPath(role == "display" and "spectral" or "fira")
    elseif id == "combat" then
        local combat = ns.AlertHost:GetModule("combatFont")
        if combat and type(combat.ApplyToAlert) == "function" and combat:ApplyToAlert(text, size, "") then return end
        path = CombatFontPath()
    else
        path = FontPath(id)
    end
    if path then
        local ok, applied = pcall(text.SetFont, text, path, size, "")
        if ok and applied ~= false then return end
    end
    text:SetFont(STANDARD_TEXT_FONT, size, "")
end

local function Ink(parent, layer)
    local text = parent:CreateFontString(nil, layer, "GameFontNormal")
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetShadowColor(0, 0, 0, .88)
    text:SetShadowOffset(1, -1)
    return text
end

local function Feather(texture, red, green, blue, alpha, reverse, edgeAlpha)
    local edge = CreateColor(red, green, blue, edgeAlpha or 0)
    local center = CreateColor(red, green, blue, alpha)
    texture:SetColorTexture(1, 1, 1, 1)
    if reverse then
        texture:SetGradient("HORIZONTAL", center, edge)
    else
        texture:SetGradient("HORIZONTAL", edge, center)
    end
end

local progressAmber = { .95, .55, .28 }
local progressGold = { 1, .82, .43 }

local function QuestProgressColor(progress, accent, alpha)
    local first, last, fraction = progressAmber, progressGold, progress * 2
    if progress > .5 then
        first, last, fraction = progressGold, accent, progress * 2 - 1
    end
    return CreateColor(
        first[1] + (last[1] - first[1]) * fraction,
        first[2] + (last[2] - first[2]) * fraction,
        first[3] + (last[3] - first[3]) * fraction,
        alpha)
end

function ns.DefaultToastColor(role, group)
    if role == "title" then return titleColor end
    if role == "detail" then return detailColor end
    local accent = palette[group] or tintFallback
    if role == "accent" then return accent end
    local red, green, blue = unpack(accent)
    return { .025 + .021 * red, .034 + .021 * green, .045 + .021 * blue, 1 }
end

function ns.ToastColor(role, group)
    return ns.WorldStyle(group).colors[role] or ns.DefaultToastColor(role, group)
end

local function CreateToast(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame.layout = parent
    frame:EnableMouse(false)
    frame:Hide()

    local card = CreateFrame("Frame", nil, frame)
    card:SetPoint("CENTER")
    frame.card = card
    local body = card:CreateTexture(nil, "BACKGROUND")
    body:SetPoint("TOPLEFT", 12, 0)
    body:SetPoint("BOTTOMRIGHT", -12, 0)
    local left = card:CreateTexture(nil, "BACKGROUND")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", body, "BOTTOMLEFT")
    local right = card:CreateTexture(nil, "BACKGROUND")
    right:SetPoint("TOPLEFT", body, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    frame.washBody, frame.washLeft, frame.washRight = body, left, right

    for _, role in ipairs({ "label", "title", "detail" }) do frame[role] = Ink(card, "OVERLAY") end
    frame.label:SetPoint("TOP", card, "TOP", 0, -9)
    frame.detail:SetPoint("TOP", frame.title, "BOTTOM", 0, -3)
    frame.label:SetMaxLines(1)
    frame.detail:SetMaxLines(2)
    frame.rule = CreateFrame("Frame", nil, card)
    frame.rule:SetPoint("BOTTOM", card, "BOTTOM", 0, 7)
    frame.rule:SetSize(120, 2)
    frame.progressBacking = frame.rule:CreateTexture(nil, "BACKGROUND")
    frame.progressBacking:SetPoint("TOPLEFT", frame.rule, "TOPLEFT", -1, 1)
    frame.progressBacking:SetPoint("BOTTOMRIGHT", frame.rule, "BOTTOMRIGHT", 1, -1)
    frame.progressBacking:SetColorTexture(.025, .02, .015, .9)
    frame.ruleLeft = frame.rule:CreateTexture(nil, "ARTWORK")
    frame.ruleLeft:SetPoint("TOPLEFT")
    frame.ruleLeft:SetPoint("BOTTOMRIGHT", frame.rule, "BOTTOM")
    frame.ruleRight = frame.rule:CreateTexture(nil, "ARTWORK")
    frame.ruleRight:SetPoint("TOPRIGHT")
    frame.ruleRight:SetPoint("BOTTOMLEFT", frame.rule, "BOTTOM")
    frame.progress = frame.rule:CreateTexture(nil, "OVERLAY")
    frame.progress:SetPoint("BOTTOMLEFT", frame.rule, "BOTTOMLEFT")
    frame.progress:SetHeight(2)
    return frame
end

local function Fill(frame, entry)
    local card = frame.card
    local width = frame.layout:GetWidth()
    local hasDetail = entry.detail ~= ""
    local compact = ns.db.compactQuestProgress and entry.kind == "questProgress"
    local style = ns.WorldStyle(entry.group)
    local titleSize, detailSize = style.mainSize, style.detailSize
    if compact then
        detailSize = math.max(13, ns.Round(detailSize * .92))
        if hasDetail then
            titleSize = math.max(11, ns.Round(titleSize * .45))
        else
            titleSize = math.max(14, ns.Round(titleSize * .68))
        end
    end
    card:SetWidth(width)
    frame.label:SetWidth(width - 28)
    frame.title:SetWidth(width - 28)
    frame.detail:SetWidth(width - 28)
    SetFont(frame.label, style.detailFont, math.max(12, math.floor(style.detailSize * .72)), "body")
    SetFont(frame.title, style.mainFont, titleSize, "display")
    SetFont(frame.detail, style.detailFont, detailSize, "body")
    frame.title:ClearAllPoints()
    if compact then frame.title:SetPoint("TOP", card, "TOP", 0, -8)
    else frame.title:SetPoint("TOP", frame.label, "BOTTOM", 0, -4) end
    frame.title:SetMaxLines(compact and hasDetail and 1 or 2)
    frame.title:SetWordWrap(not (compact and hasDetail))
    local accent = ns.ToastColor("accent", entry.group)
    local red, green, blue, accentAlpha = unpack(accent)
    accentAlpha = accentAlpha or 1
    local washR, washG, washB, washAlpha = unpack(ns.ToastColor("background", entry.group))
    local backgroundAlpha = style.backgroundOpacity / 100 * washAlpha
    frame.washBody:SetColorTexture(washR, washG, washB, backgroundAlpha)
    local edge = not style.softBackground and backgroundAlpha or 0
    Feather(frame.washLeft, washR, washG, washB, backgroundAlpha, false, edge)
    Feather(frame.washRight, washR, washG, washB, backgroundAlpha, true, edge)
    frame.label:SetText(entry.label)
    frame.label:SetTextColor(red, green, blue, accentAlpha)
    frame.label:SetShown(not compact)
    frame.title:SetText(entry.title)
    frame.title:SetTextColor(unpack(ns.ToastColor("title", entry.group)))
    frame.detail:SetText(entry.detail)
    frame.detail:SetTextColor(unpack(ns.ToastColor("detail", entry.group)))
    frame.detail:SetShown(hasDetail)
    local detailHeight = hasDetail and frame.detail:GetStringHeight() + 3 or 0
    local labelHeight = compact and 0 or frame.label:GetStringHeight()
    local padding = compact and (entry.progress and 24 or 18) or 31
    card:SetHeight(padding + labelHeight + frame.title:GetStringHeight() + detailHeight)
    local progress = entry.progress
    local questMeter = entry.kind == "questProgress" and progress ~= nil
    frame.ruleBaseHeight = questMeter and 3 or 2
    frame.rule:SetShown(not compact or progress ~= nil)
    frame.progressBacking:SetShown(questMeter)
    local trackAlpha = (questMeter and .22 or .63) * accentAlpha
    Feather(frame.ruleLeft, red, green, blue, trackAlpha)
    Feather(frame.ruleRight, red, green, blue, trackAlpha, true)
    if progress and progress > 0 then
        local alpha = .95 * accentAlpha
        if entry.kind == "questProgress" then
            local fraction = ns.Clamp(progress, 0, 1)
            frame.progress:SetColorTexture(1, 1, 1, 1)
            frame.progress:SetGradient("HORIZONTAL", QuestProgressColor(fraction, accent, alpha),
                QuestProgressColor(math.min(1, fraction + .14), accent, alpha))
        else
            frame.progress:SetColorTexture(red, green, blue, alpha)
        end
    end
    frame.progress:SetShown(progress ~= nil and progress > 0)
end

local function Ease(value)
    return value * value * (3 - 2 * value)
end

local function Pose(frame, visibility, offset, reveal, detailOpacity, pulse)
    frame.card:SetAlpha(visibility * ns.WorldStyle(frame.entry.group).opacity / 100)
    frame.detail:SetAlpha(detailOpacity or 1)
    frame.card:SetPoint("CENTER", frame, "CENTER", 0, offset)
    local maxWidth = math.min(frame.layout:GetWidth() * .42, 192)
    local width = math.max(1, maxWidth * reveal)
    frame.rule:SetWidth(width)
    local height = frame.ruleBaseHeight + (pulse or 0) * 2
    if frame.ruleHeight ~= height then
        frame.ruleHeight = height
        frame.rule:SetHeight(height)
        frame.progress:SetHeight(height)
    end
    local progress = frame.entry.progress
    if progress then frame.progress:SetWidth(math.max(1, width * progress)) end
end

local function Stop(frame)
    frame.entry = nil
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
end

local function SamePosition(first, second)
    return first.x == second.x and first.y == second.y
end

local function UpdatePreviewVisibility()
    local moving = placementSession and placementSession.hiddenLayout
    for _, frame in pairs(live) do
        local covered = (preview.entry and SamePosition(frame.layout, anchor))
            or (moving and SamePosition(frame.layout, moving))
        frame:SetAlpha(covered and 0 or 1)
    end
end

local function Countdown(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function UpdateAnimation(frame, elapsed)
    local entry = frame.entry
    local style = ns.WorldStyle(entry.group)
    local enter, leave = 0, 0
    if style.animate then enter, leave = .58 / style.speed, .52 / style.speed end
    local hold = style.hold + (entry.long and 1.2 or 0)
    local age = entry.countdown and GetTime() - frame.startedAt or frame.age + elapsed
    frame.age = age
    if entry.countdown then
        local remaining = math.max(0, math.ceil(entry.countdown - age))
        if remaining ~= entry.remaining then
            entry.remaining, entry.detail = remaining, Countdown(remaining)
            frame.detail:SetText(entry.detail)
        end
        hold = math.max(0, entry.countdown - enter)
    end
    if enter > 0 and age < enter then
        local motion = Ease(age / enter)
        local detailOpacity = Ease(ns.Clamp((age / enter - .18) / .82, 0, 1))
        Pose(frame, motion, 14 * (1 - motion), .2 + .8 * motion, detailOpacity)
    elseif age < enter + hold then
        local pulse
        if entry.completion and style.animate then
            local phase = (age - enter) * style.speed / .55
            if phase < 1 then pulse = math.sin(math.pi * phase) end
        end
        Pose(frame, 1, 0, 1, nil, pulse)
    elseif leave > 0 and age < enter + hold + leave then
        local motion = Ease((age - enter - hold) / leave)
        Pose(frame, 1 - motion, -12 * motion, 1 - .3 * motion, 1 - motion)
    else
        Stop(frame)
        if frame == preview then UpdatePreviewVisibility() else ns.PlayNext() end
    end
end

local function Play(frame, entry)
    frame.entry, frame.age = entry, 0
    if entry.countdown then frame.startedAt = GetTime() end
    Fill(frame, entry)
    UpdateAnimation(frame, 0)
    frame:SetScript("OnUpdate", UpdateAnimation)
    frame:Show()
end

function ns.AllowsNotification(group)
    local style = ns.WorldStyle(group)
    if style.opacity <= 0 then return false end
    if group == "transport" then
        return style.enabled
    end
    if style == ns.db and not ns.db.otherEventsEnabled then return false end
    return ns.db[group] and not ns.HorizonActive()
end

local function CanPlay(frame)
    if frame.entry then return false end
    for _, other in pairs(live) do
        if other.entry and SamePosition(frame.layout, other.layout) then return false end
    end
    return true
end

function ns.PlayNext()
    local index = 1
    while index <= #queue do
        local entry = queue[index]
        local frame = live[entry.group] or live.world
        if not ns.AllowsNotification(entry.group) then
            table.remove(queue, index)
        elseif CanPlay(frame) then
            table.remove(queue, index)
            Play(frame, entry)
        else
            index = index + 1
        end
    end
end

function ns.Notify(group, kind, title, detail, options)
    options = options or {}
    local entry = {
        group = group, kind = kind, label = L[kind], title = ns.Text(title), detail = ns.Text(detail),
        key = options.key, questID = options.questID, final = options.final, long = options.long,
        progress = options.progress, priority = options.priority, completion = options.completion,
    }
    if entry.title == "" or not ns.AllowsNotification(group) then return end
    local frame = live[group] or live.world
    if entry.final and entry.questID then
        for index = #queue, 1, -1 do
            if queue[index].questID == entry.questID and queue[index].kind == "questProgress" then
                table.remove(queue, index)
            end
        end
    end
    if entry.key then
        for index, pending in ipairs(queue) do
            if pending.key == entry.key then queue[index] = entry; return end
        end
        if (entry.priority or #queue == 0) and frame.entry and frame.entry.key == entry.key then
            frame.entry = entry
            Fill(frame, entry)
            local style = ns.WorldStyle(group)
            frame.age = style.animate and math.min(frame.age, .58 / style.speed) or 0
            return
        end
    end
    if CanPlay(frame) then Play(frame, entry); return end
    if #queue >= maxPending then
        local discard
        for index, pending in ipairs(queue) do
            if not pending.priority and not pending.final then discard = index; break end
        end
        if not discard and not (entry.priority or entry.final) then return end
        table.remove(queue, discard or 1)
    end
    if entry.priority then
        local index = 1
        while queue[index] and queue[index].priority do index = index + 1 end
        table.insert(queue, index, entry)
    else
        queue[#queue + 1] = entry
    end
end

function ns.ShowTransportArrival(destination, duration)
    local entry = { group = "transport", label = L.arrival, title = ns.Text(destination),
        detail = Countdown(duration), countdown = duration }
    local frame = live.transport
    if not frame or entry.title == "" or not ns.AllowsNotification(entry.group) then return false end
    if preview.entry and SamePosition(frame.layout, anchor) then return false end
    if not frame.entry and not CanPlay(frame) then return false end
    Play(frame, entry)
    return true
end

function ns.ApplyPosition()
    if not anchor then return end
    local width, height = UIParent:GetSize()
    width = width > 0 and width or 1920
    height = height > 0 and height or 1080
    local anchorWidth, anchorHeight = math.min(560, width * .94), math.min(168, height * .8)
    local maxX = math.max(1, math.floor((width - anchorWidth) / 2))
    local maxY = math.max(1, math.floor((height - anchorHeight) / 2))
    local boundsChanged = not ns.ranges.x or ns.ranges.x[2] ~= maxX or ns.ranges.y[2] ~= maxY
    if boundsChanged then ns.ranges.x, ns.ranges.y = { -maxX, maxX, 1 }, { -maxY, maxY, 1 } end
    local function Position(layout, group)
        local style = ns.WorldStyle(group)
        layout.x, layout.y = ns.Clamp(style.x, -maxX, maxX), ns.Clamp(style.y, -maxY, maxY)
        layout:SetSize(anchorWidth, anchorHeight)
        layout:ClearAllPoints()
        layout:SetPoint("CENTER", UIParent, "CENTER", layout.x, layout.y)
    end
    for group, frame in pairs(live) do Position(frame.layout, group) end
    Position(anchor, anchor.group or "world")
    UpdatePreviewVisibility()
    if boundsChanged and ns.NotifyPositionChanged then ns.NotifyPositionChanged() end
end

function ns.RefreshDisplay()
    ns.ApplyPosition()
    for _, frame in pairs(live) do
        if frame.entry then
            if ns.AllowsNotification(frame.entry.group) then Fill(frame, frame.entry) else Stop(frame) end
        end
    end
    if preview.entry then Fill(preview, preview.entry) end
    ns.PlayNext()
end

local function PreviewEntry(kind)
    if kind == "arrival" then
        return { group = "transport", label = L.arrival, title = L.arrivalExample, detail = "0:20", countdown = 20 }
    elseif kind == "achievement" then
        return { group = "achievements", label = L.achievement, title = L.achievementExample, detail = "" }
    elseif kind ~= "zone" and kind ~= "discovery" then
        local quest = ns.QuestPreview() or { title = L.questExample, detail = L.questExampleDetail, progress = .5 }
        if kind == "questAccept" or kind == "questComplete" then
            local completed = kind == "questComplete"
            return { group = "quests", label = L[kind], title = quest.title, completion = completed,
                detail = completed and ns.QuestRewardText(350, 1250) or "" }
        end
        if kind == "objectiveDone" then
            quest.detail, quest.progress, quest.completion = L.objectiveDone, 1, true
        end
        quest.group, quest.kind, quest.label = "quests", "questProgress", L.questProgress
        return quest
    end
    local zone, subzone = ns.ZoneNames()
    if kind == "discovery" then
        local title = subzone ~= "" and subzone or zone
        return { group = "zones", label = L.discovery, title = title ~= "" and title or L.preview,
            detail = L.experienceReward:format(60) }
    end
    return {
        group = "zones", label = zone ~= "" and L.zone or nil,
        title = zone ~= "" and zone or L.preview,
        detail = subzone ~= zone and subzone or "",
    }
end

function ns.CreateWorldSample(stage, fullSize)
    local layout = CreateFrame("Frame", nil, stage)
    layout:SetPoint("CENTER")
    local sample = CreateToast(layout)
    return function(value)
        local width = anchor:GetWidth()
        layout:SetSize(width, anchor:GetHeight())
        sample.entry = fullSize and value or PreviewEntry(value)
        Fill(sample, sample.entry)
        if not fullSize then
            local w, h = stage:GetSize()
            -- Fitting to the current text would resize both lines when only one changes.
            layout:SetScale(math.min(1, math.max(1, w - 10) / width, math.max(1, h - 10) / previewContentHeight))
        end
        Pose(sample, 1, 0, 1)
        if fullSize and ns.WorldStyle(sample.entry.group).opacity == 0 then sample.card:SetAlpha(1) end
        sample:Show()
        return width, sample.card:GetHeight()
    end
end

function ns.Preview(kind)
    local entry = PreviewEntry(kind)
    anchor.group = entry.group
    ns.ApplyPosition()
    Play(preview, entry)
    UpdatePreviewVisibility()
end

function ns.WorldPosition(group)
    local function GetStyle() return ns.WorldStyle(group) end
    return {
        get = function()
            local style = GetStyle()
            return style.x, style.y
        end,
        set = function(x, y)
            local style = GetStyle()
            style.x, style.y = x, y
            ns.RefreshDisplay()
        end,
        ranges = function() return ns.ranges.x, ns.ranges.y end,
        reset = function() return ns.defaults.x, group == "transport" and 150 or ns.defaults.y end,
    }
end

function ns.Move(kind, position)
    if placement:IsShown() then placement:Hide(); return end
    local entry = PreviewEntry(kind)
    local group = entry.group
    ns.OpenPlacement("world", position or ns.WorldPosition(group), function(host)
        return ns.CreateWorldSample(host, true)
    end, entry, (live[group] or live.world).layout)
end

local function PlacementButton(parent, label, click, primary)
    if ns.Widgets then return ns.Widgets:Button(parent, label, click, primary) end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(label)
    button:SetScript("OnClick", click)
    return button
end

local function AnchorDoneButton()
    local bottom = placement:GetBottom()
    local above = bottom ~= nil and bottom < placementDone:GetHeight() + 6
    if placement.doneAbove == above then return end
    placement.doneAbove = above
    placementDone:ClearAllPoints()
    if above then placementDone:SetPoint("BOTTOMRIGHT", placement, "TOPRIGHT", 0, 5)
    else placementDone:SetPoint("TOPRIGHT", placement, "BOTTOMRIGHT", 0, -5) end
end

local function SetDraftPosition(x, y)
    placement:ClearAllPoints()
    placement:SetPoint("CENTER", UIParent, "CENTER", x, y)
    AnchorDoneButton()
end

local function SaveDraftPosition()
    local session = placementSession
    if not session or not session.dragging then return end
    placement:StopMovingOrSizing()
    placement:SetScript("OnUpdate", nil)
    session.dragging = nil
    local x, y = placement:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    if not (x and y and centerX and centerY) then return end
    local xRange, yRange = session.options.ranges()
    session.x = ns.Clamp(ns.Round((x - centerX) / xRange[3]) * xRange[3], xRange[1], xRange[2])
    session.y = ns.Clamp(ns.Round((y - centerY) / yRange[3]) * yRange[3], yRange[1], yRange[2])
    SetDraftPosition(session.x, session.y)
end

function ns.OpenPlacement(key, options, createSample, value, hiddenLayout)
    if placement:IsShown() then placement:Hide(); return end
    local sample = placementSamples[key]
    if not sample then
        local host = CreateFrame("Frame", nil, placement)
        host:SetPoint("CENTER")
        sample = { host = host, draw = createSample(host) }
        placementSamples[key] = sample
    end
    local width, height = sample.draw(value)
    sample.host:SetSize(width, height)
    sample.host:Show()
    placement:SetSize(width + 4, height + 4)
    placementSession = { options = options, host = sample.host, hiddenLayout = hiddenLayout }
    local window = ns.GetSettingsWindow()
    placementSession.returnToSettings = window and window:IsShown()
    if placementSession.returnToSettings then window:Hide() end
    Stop(preview)
    local x, y = options.get()
    local xRange, yRange = options.ranges()
    SetDraftPosition(ns.Clamp(x, xRange[1], xRange[2]), ns.Clamp(y, yRange[1], yRange[2]))
    placement:Show()
    AnchorDoneButton()
    UpdatePreviewVisibility()
end

function ns.CreateDisplay()
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("HIGH")
    for _, group in ipairs(displayGroups) do
        local layout = CreateFrame("Frame", nil, UIParent)
        layout:SetFrameStrata("HIGH")
        live[group] = CreateToast(layout)
    end
    preview = CreateToast(anchor)
    preview:SetFrameStrata("TOOLTIP")
    ns.ApplyPosition()

    placement = CreateFrame("Frame", "SintezzaNotificationsPlacement", UIParent, "BackdropTemplate")
    placement:SetFrameStrata("TOOLTIP")
    placement:SetFrameLevel(preview:GetFrameLevel() + 5)
    placement:SetClampedToScreen(true)
    placement:SetMovable(true)
    placement:EnableMouse(true)
    placement:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    local border = ns.SettingsTheme and ns.SettingsTheme.brass or { .93, .76, .57, 1 }
    placement:SetBackdropBorderColor(unpack(border))
    placement:Hide()
    tinsert(UISpecialFrames, placement:GetName())

    placement:RegisterForDrag("LeftButton")
    placement:SetScript("OnDragStart", function(frame)
        if not placementSession then return end
        placementSession.dragging = true
        frame:StartMoving()
        frame:SetScript("OnUpdate", AnchorDoneButton)
    end)
    placement:SetScript("OnDragStop", SaveDraftPosition)
    placementDone = PlacementButton(placement, L.done, function()
        SaveDraftPosition()
        local session = placementSession
        if not session then return end
        if session.x then session.options.set(session.x, session.y) end
        placement:Hide()
    end, true)
    placementDone:SetSize(66, 24)
    placement:SetScript("OnHide", function(frame)
        local session = placementSession
        if not session then return end
        frame:StopMovingOrSizing()
        frame:SetScript("OnUpdate", nil)
        session.host:Hide()
        placementSession = nil
        UpdatePreviewVisibility()
        if session.returnToSettings then
            -- Escape is still closing special frames when this handler runs.
            C_Timer.After(0, function()
                if not placementSession then ns.OpenSettings() end
            end)
        end
    end)
    if theme and theme.TrackAppearance then
        theme:TrackAppearance(anchor, "notificationAppearance", ns.RefreshDisplay)
    end
end
