local _, ns = ...
local SUI = ns.AlertHost
local T, W, B, Text = ns.SettingsTheme, ns.Widgets, ns.SettingsBuilder, SUI.Text
local M

local function Profile() return M:Profile() end

local visuals = {
    SWORDS = SUI.Text("Мечи", "Swords"),
    CREST = SUI.Text("Герб", "Crest"),
    SLASH = SUI.Text("Резкий взмах", "Slash"),
    BANNER = SUI.Text("Знамя", "Banner"),
    BRACKETS = SUI.Text("Скобы", "Brackets"),
    PLAQUE = SUI.Text("Плашка", "Plaque"),
}
local visualOrder = { SWORDS = 1, CREST = 2, SLASH = 3, BANNER = 4, BRACKETS = 5, PLAQUE = 6 }
local stealthVisuals = {
    EYE = SUI.Text("Прищур", "Squint"),
    CREST = visuals.CREST, SLASH = visuals.SLASH,
    TRACKS = SUI.Text("Следы", "Tracks"),
    MASK = SUI.Text("Маска", "Mask"),
    MIST = SUI.Text("Дымка", "Mist"),
}
local stealthVisualOrder = { EYE = 1, CREST = 2, SLASH = 3, TRACKS = 4, MASK = 5, MIST = 6 }

local function BindAvailable(row, predicate)
    local refresh = row.Refresh
    function row:Refresh(...)
        if refresh then refresh(self, ...) end
        self:SetAvailable(predicate())
    end
    row:Refresh()
    return row
end

local function SignalTextRow(parent, title, getText, setText)
    local row = W:SettingRow(parent, title, 34)
    local edit = W:EditBox(row, SUI.Text("По умолчанию", "Default text"), function() end)
    edit:SetHeight(28)
    edit:SetPoint("LEFT", row, "CENTER", -8, 0)
    edit:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetPoint("RIGHT", edit, "LEFT", -10, 0)
    if edit.SetMaxLetters then edit:SetMaxLetters(48) end

    local available = true
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(getText())
        self:ClearFocus()
    end)
    edit:HookScript("OnEditFocusLost", function(self)
        if available then setText(self:GetText()) end
        self:SetText(getText())
    end)
    edit:HookScript("OnHide", function(self)
        if self:HasFocus() then self:ClearFocus() end
    end)
    function row:Refresh()
        if not edit:HasFocus() then edit:SetText(getText()) end
    end
    function row:SetAvailable(value)
        available = value
        self:SetAlpha(value and 1 or .40)
        edit.skipSettingsFocus = not value
        if not value and edit:HasFocus() then edit:ClearFocus() end
        edit:EnableMouse(value)
    end
    return W:Help(row, SUI.Text("Очисти поле, чтобы вернуть стандартный текст сигнала.",
        "Clear the field to restore the default alert text."))
end

local function AlertTextRow(page, parent, title, field)
    return SignalTextRow(parent, title,
        function() return M:GetAlertText(field) end,
        function(value) M:SetAlertText(field, value); page:RefreshPreview() end)
end

local function Apply()
    M:ApplyAppearance()
end

local function ApplyStealth()
    M:ApplyStealthAppearance()
end

local FONT_ORDER = { INTERFACE = 1, DEFAULT = 2, COMBAT = 3 }
local function UsesCombatFont()
    local module = SUI:GetModule("combatFont")
    return module and module.alertPath ~= nil
end

local function FontRow(page, card, key, apply)
    return W:ChoiceRow(card, SUI.Text("Шрифт текста", "Text font"), function() return T:TextFontChoices(true) end,
        function() return UsesCombatFont() and "COMBAT" or Profile()[key] end, function(value)
            Profile()[key] = value
            apply()
            page:RefreshPreview()
        end, FONT_ORDER)
end

local modes = {
    BOTH = Text("Эффект и текст", "Effect and text"),
    TEXT = Text("Только текст", "Text only"),
    ICON = Text("Только эффект", "Effect only"),
}
local modeOrder = { BOTH = 1, TEXT = 2, ICON = 3 }
local healthStyles = { PULSE = Text("Пульс", "Pulse"), PLAQUE = visuals.PLAQUE }
local healthStyleOrder = { PULSE = 1, PLAQUE = 2 }
local aggroStyles = { THREAT = Text("Предупреждение", "Warning"), CREST = visuals.CREST, BRACKETS = visuals.BRACKETS }
local aggroStyleOrder = { THREAT = 1, CREST = 2, BRACKETS = 3 }

local function RefreshEventAlerts()
    local module = SUI:GetModule("eventAlerts")
    if module then module:OnProfileChanged() end
end

local function AddRow(page, section, row, available)
    if available then BindAvailable(row, available) end
    return B:AddRow(page, section, row)
end

local function AddSlider(page, section, label, options, key, low, high, step, available, apply, suffix)
    return AddRow(page, section, W:SliderRow(section, label, low, high, step,
        function() return options()[key] end,
        function(value)
            options()[key] = value
            if apply then apply() end
            page:RefreshPreview()
        end, suffix), available)
end

local function AddPreview(page, kind, play, choosePhase)
    local selection
    if choosePhase then
        local phase = "enter"
        local L = ns.L
        selection = {
            label = L.samplePhase, choices = { enter = L.sampleEnter, leave = L.sampleLeave },
            get = function() return phase end, set = function(value) phase = value end,
            order = { enter = 1, leave = 2 },
        }
    end
    B:AddPreview(page, function(parent) return ns.CreateSignalSample(parent, kind) end, play, selection)
    return selection and selection.get
end

local function AddTrigger(page, description, get, set, help, available)
    local section = B:AddSection(page, Text("Срабатывание", "Trigger"), description)
    AddRow(page, section, W:Toggle(section, Text("Включить сигнал", "Enable alert"), get, function(value)
        set(value)
        page:Refresh()
    end, help, true), available)
    return section
end

local signalXRange, signalYRange = { -600, 600, 5 }, { -400, 400, 5 }

local function AddPosition(page, kind, options, available, apply, phase)
    local xKey, yKey = "x", "y"
    if kind == "stealth" then xKey, yKey = "stealthX", "stealthY" end
    local defaults = kind == "manaAlert" and ns.manaDefaults or ns.alertDefaults[kind] or ns.alertDefaults
    local position = {
        get = function()
            local profile = options()
            return profile[xKey], profile[yKey]
        end,
        set = function(x, y)
            local profile = options()
            profile[xKey], profile[yKey] = x, y
            if apply then apply() end
        end,
        ranges = function() return signalXRange, signalYRange end,
        reset = function() return defaults[xKey], defaults[yKey] end,
        available = available,
    }
    position.move = function()
        ns.OpenPlacement(kind, position, function(host)
            return ns.CreateSignalSample(host, kind, true)
        end, phase and phase())
    end
    B:AddPosition(page, position)
end

local function AddColors(page, options, entries, available, apply)
    local section = B:AddSection(page, Text("Цвета", "Colors"))
    AddRow(page, section, W:Toggle(section, Text("Использовать цвета темы", "Use theme colors"),
        function() return options().useThemeColors ~= false end, function(value)
            options().useThemeColors = value
            if apply then apply() end
            page:Refresh()
        end), available)
    local function ManualColors()
        return (not available or available()) and options().useThemeColors == false
    end
    for _, entry in ipairs(entries) do
        local key, label = entry[1], entry[2]
        AddRow(page, section, W:ColorRow(section, label, function() return options()[key] end, function(value)
            options()[key] = value
            if apply then apply() end
            page:RefreshPreview()
        end), ManualColors)
    end
    B:FinishSection(page, section)
end

local function CombatEnabled() return Profile().enabled ~= false end

local function BuildCombatTab(page)
    local phase = AddPreview(page, "combat", function(phase) M:Preview(phase) end, true)

    local trigger = AddTrigger(page, nil, CombatEnabled,
        function(value) SUI:SetFeature("combatAlert", value) end,
        Text("Общий переключатель для боя и скрытности.", "Master switch for combat and stealth alerts."))
    AddRow(page, trigger, W:Toggle(trigger, Text("Показывать вход", "Show entry"),
        function() return Profile().showEnter ~= false end,
        function(value) SUI:SetFeature("combatEnter", value) end), CombatEnabled)
    AddRow(page, trigger, W:Toggle(trigger, Text("Показывать выход", "Show exit"),
        function() return Profile().showLeave ~= false end, function(value)
            SUI:SetFeature("combatLeave", value)
            page:Refresh()
        end), CombatEnabled)
    AddSlider(page, trigger, Text("Задержка выхода", "Exit delay"), Profile, "leaveDelay", 0, .60, .05,
        function() return CombatEnabled() and Profile().showLeave ~= false end)
    B:FinishSection(page, trigger)

    local function EffectsEnabled() return CombatEnabled() and Profile().style ~= "TEXT" end
    local function TextEnabled() return CombatEnabled() and Profile().style ~= "SWORDS" end

    local content = B:AddSection(page, Text("Содержимое", "Content"))
    AddRow(page, content, W:ChoiceRow(content, Text("Режим", "Mode"), modes,
        function() return Profile().style == "SWORDS" and "ICON" or Profile().style or "BOTH" end,
        function(value)
            Profile().style = value == "ICON" and "SWORDS" or value
            page:Refresh()
        end, modeOrder), CombatEnabled)
    AddRow(page, content, W:ChoiceRow(content, Text("Вид сигнала", "Signal style"), visuals,
        function() return M:GetVisualStyle() end, function(value)
            Profile().visualStyle = value
            page:Refresh()
        end, visualOrder), EffectsEnabled)
    AddRow(page, content, AlertTextRow(page, content, Text("Текст входа", "Entry text"), "enterText"), TextEnabled)
    AddRow(page, content, AlertTextRow(page, content, Text("Текст выхода", "Exit text"), "leaveText"), TextEnabled)
    B:FinishSection(page, content)

    local appearance = B:AddSection(page, Text("Оформление", "Appearance"))
    AddSlider(page, appearance, Text("Размер эффекта", "Effect size"), Profile, "swordSize", 56, 148, 2, EffectsEnabled, Apply)
    AddRow(page, appearance, FontRow(page, appearance, "font", Apply), function() return TextEnabled() and not UsesCombatFont() end)
    AddSlider(page, appearance, Text("Размер текста", "Text size"), Profile, "fontSize", 20, 52, 1, TextEnabled, Apply)
    AddSlider(page, appearance, Text("Свечение эффекта", "Effect glow"), Profile, "glowIntensity", 0, 1, .05,
        function() return EffectsEnabled() and (M:GetVisualStyle() ~= "SWORDS" or Profile().reducedMotion ~= true) end,
        function() M:RefreshSignalColors() end)
    B:FinishSection(page, appearance)
    AddPosition(page, "combat", Profile, CombatEnabled, Apply, phase)
    AddColors(page, Profile, {
        { "enterColor", Text("Вход в бой", "Enter combat") },
        { "leaveColor", Text("Выход из боя", "Leave combat") },
    }, CombatEnabled, function() M:RefreshSignalColors() end)

    local motion = B:AddSection(page, Text("Анимация", "Animation"))
    AddRow(page, motion, W:Toggle(motion, Text("Уменьшенная анимация", "Reduced motion"),
        function() return Profile().reducedMotion == true end, function(value)
            Profile().reducedMotion = value
            page:Refresh()
        end, Text("Настройка общая для всех сигналов.", "Shared by all signals.")), CombatEnabled)
    local speed = AddSlider(page, motion, Text("Скорость", "Speed"), Profile, "speed", .50, 1.75, .05, CombatEnabled,
        function() M:ApplyAnimationSpeed() end)
    W:Help(speed, Text("Скорость общая для всех сигналов.", "Speed is shared by all signals."))
    AddSlider(page, motion, Text("Разлет мечей", "Sword spread"), Profile, "swordDistance", 30, 150, 2,
        function() return EffectsEnabled() and Profile().reducedMotion ~= true and M:GetVisualStyle() == "SWORDS" end)
    B:FinishSection(page, motion)

    local reset = B:AddSection(page, Text("Сброс", "Reset"))
    B:AddRow(page, reset, W:Button(reset, Text("Сбросить сигналы", "Reset alerts"), function()
        W:Confirm(Text("Сбросить настройки всех сигналов?", "Reset all alert settings?"), function()
            SUI:ResetModuleProfile("combatAlert")
            page:Refresh()
        end)
    end))
    B:FinishSection(page, reset)
end

local function BuildStealthTab(page)
    local phase = AddPreview(page, "stealth", function(phase) M:PreviewStealth(phase ~= "leave") end, true)

    local function Enabled() return CombatEnabled() and Profile().stealthEnabled ~= false end
    local trigger = AddTrigger(page, nil, function() return Profile().stealthEnabled ~= false end,
        function(value) SUI:SetFeature("stealth", value) end,
        Text("Для скрытности нужен общий переключатель в разделе «Бой».",
            "Stealth requires the master switch on the Combat page."), CombatEnabled)
    AddRow(page, trigger, W:Toggle(trigger, Text("Показывать вход", "Show entry"),
        function() return Profile().showStealthEnter ~= false end,
        function(value) SUI:SetFeature("stealthEnter", value) end), Enabled)
    AddRow(page, trigger, W:Toggle(trigger, Text("Показывать выход", "Show exit"),
        function() return Profile().showStealthLeave ~= false end,
        function(value) SUI:SetFeature("stealthLeave", value) end), Enabled)
    B:FinishSection(page, trigger)

    local content = B:AddSection(page, Text("Содержимое", "Content"))
    AddRow(page, content, W:ChoiceRow(content, Text("Вид сигнала", "Signal style"), stealthVisuals,
        function() return M:GetStealthVisualStyle() end, function(value)
            Profile().stealthVisualStyle = value
            M:RefreshStealthState()
        end, stealthVisualOrder), Enabled)
    AddRow(page, content, AlertTextRow(page, content, Text("Текст входа", "Entry text"), "stealthEnterText"), Enabled)
    AddRow(page, content, AlertTextRow(page, content, Text("Текст выхода", "Exit text"), "stealthLeaveText"), Enabled)
    B:FinishSection(page, content)

    local appearance = B:AddSection(page, Text("Оформление", "Appearance"))
    AddSlider(page, appearance, Text("Размер эффекта", "Effect size"), Profile, "stealthIconSize", 42, 88, 2, Enabled, ApplyStealth)
    AddRow(page, appearance, FontRow(page, appearance, "stealthFont", ApplyStealth), function() return Enabled() and not UsesCombatFont() end)
    AddSlider(page, appearance, Text("Размер текста", "Text size"), Profile, "stealthFontSize", 12, 30, 1, Enabled, ApplyStealth)
    AddSlider(page, appearance, Text("Свечение эффекта", "Effect glow"), Profile, "stealthGlowIntensity", 0, 1, .05, Enabled,
        function() M:RefreshSignalColors() end)
    B:FinishSection(page, appearance)
    AddPosition(page, "stealth", Profile, Enabled, ApplyStealth, phase)
    AddColors(page, Profile, {
        { "stealthEnterColor", Text("Вход в скрытность", "Enter stealth") },
        { "stealthLeaveColor", Text("Выход из скрытности", "Leave stealth") },
    }, Enabled, function() M:RefreshSignalColors() end)
end

local function BuildExtraAlertTab(page, tab)
    local mana = tab == "manaAlert"
    local resource = tab ~= "aggroAlert"
    local alert = mana and SUI.CombatAlert or M
    local function Options() return alert:GetExtraAlertProfile(tab) end
    local function RefreshTrigger()
        if mana then SUI:RefreshManaAlert() else RefreshEventAlerts() end
    end
    AddPreview(page, tab, function() alert:PreviewExtraAlert(tab) end)
    local trigger = AddTrigger(page, resource
        and Text("После сигнала ресурс должен восстановиться до верхнего порога.",
            "After an alert, recover to the higher threshold before it can trigger again.")
        or Text("Сигнал работает в подземельях и рейдах.", "This alert runs in dungeons and raids."),
        function() return Options().enabled == true end, function(value)
            Options().enabled = value
            if not value then alert:StopExtraAlert(tab) end
            RefreshTrigger()
        end)
    if resource then
        local detector = SUI:GetModule("eventAlerts")
        if mana or detector and detector.supportsHealthInstanceScope then
            B:AddRow(page, trigger, W:Toggle(trigger, Text("Только в подземельях и рейдах", "Dungeons and raids only"),
                function() return Options().instanceOnly == true end, function(value)
                    Options().instanceOnly = value or nil
                    RefreshTrigger()
                end))
        end
        local label = mana and Text("Порог маны", "Mana threshold") or Text("Порог здоровья", "Health threshold")
        B:AddRow(page, trigger, W:SliderRow(trigger, label, mana and 0 or 5, 90, 1,
            function() return Options().threshold end, function(value)
                local options = Options()
                options.threshold = value
                options.rearm = math.max(options.rearm, value + 1)
                RefreshTrigger()
                page:Refresh()
            end, "%"))
        local rearm = W:SliderRow(trigger, Text("Уровень восстановления", "Rearm at"), Options().threshold + 1, 100, 1,
            function() return Options().rearm end, function(value)
                local options = Options()
                options.rearm = math.max(value, options.threshold + 1)
                RefreshTrigger()
                page:Refresh()
            end, "%")
        local refresh = rearm.Refresh
        function rearm:Refresh()
            self:SetRange(Options().threshold + 1, 100)
            refresh(self)
        end
        B:AddRow(page, trigger, rearm)
    end
    B:FinishSection(page, trigger)

    local function EffectsEnabled() return Options().mode ~= "TEXT" end
    local function TextEnabled() return Options().mode ~= "ICON" end

    local content = B:AddSection(page, Text("Содержимое", "Content"))
    B:AddRow(page, content, W:ChoiceRow(content, Text("Режим", "Mode"), modes,
        function() return Options().mode end, function(value)
            Options().mode = value
            page:Refresh()
        end, modeOrder))
    AddRow(page, content, W:ChoiceRow(content, Text("Вид сигнала", "Signal style"), resource and healthStyles or aggroStyles,
        function() return alert:GetExtraAlertStyle(tab) end, function(value) Options().style = value; page:RefreshPreview() end,
        resource and healthStyleOrder or aggroStyleOrder), EffectsEnabled)
    AddRow(page, content, SignalTextRow(content, Text("Текст сигнала", "Alert text"),
        function() return Options().text end, function(value) alert:SetExtraAlertText(tab, value); page:RefreshPreview() end), TextEnabled)
    B:FinishSection(page, content)

    local appearance = B:AddSection(page, Text("Оформление", "Appearance"))
    AddSlider(page, appearance, Text("Размер эффекта", "Effect size"), Options, "size", 36, 120, 1, EffectsEnabled)
    AddSlider(page, appearance, Text("Размер текста", "Text size"), Options, "fontSize", 16, 48, 1, TextEnabled)
    B:FinishSection(page, appearance)
    AddPosition(page, tab, Options)
    AddColors(page, Options, { { "color", Text("Цвет сигнала", "Alert color") } })
end

function ns.BuildAlertPage(page, kind)
    M = SUI:GetModule("combatAlert")
    if kind == "combat" then BuildCombatTab(page)
    elseif kind == "stealth" then BuildStealthTab(page)
    else BuildExtraAlertTab(page, kind) end
end
