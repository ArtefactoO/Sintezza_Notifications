local _, ns = ...
local W, T, L = ns.Widgets, ns.SettingsTheme, ns.L
local B = {}
ns.SettingsBuilder = B

function B:CreatePage(parent, title, withPreview)
    local page, canvas = W:Page(parent)
    local heading = W:Label(canvas, title, 19, T.text, "display")
    heading:SetPoint("TOPLEFT", 2, -2)
    heading:SetPoint("TOPRIGHT", -2, -2)
    heading:SetHeight(29)

    local scroll, body, bar = W:ScrollFrame(canvas)
    scroll:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", -2, -12)
    if withPreview then
        local rail = CreateFrame("Frame", nil, canvas)
        rail:SetWidth(260)
        rail:SetPoint("TOPRIGHT", heading, "BOTTOMRIGHT", 2, -12)
        rail:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT")
        page.rail = rail
        scroll:SetPoint("BOTTOMRIGHT", rail, "BOTTOMLEFT", -16, 0)
    else
        scroll:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -3, 0)
    end
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 9, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 9, 0)

    page.body, page.scroll, page.nextY, page.refreshers = body, scroll, -1, {}
    scroll:HookScript("OnSizeChanged", function(frame)
        body:SetWidth(math.max(1, frame:GetWidth()))
        page:Layout()
    end)
    page:HookScript("OnShow", function(owner) owner:Refresh() end)

    function page:Layout()
        self.body:SetHeight(math.max(1, self.scroll:GetHeight(), -self.nextY + 2))
        self.scroll:RefreshRange()
    end

    function page:AddRefresher(widget)
        self.refreshers[#self.refreshers + 1] = widget
    end

    function page:RefreshPreview()
        if self.sample and self:IsVisible() then self.sample() end
    end

    function page:Refresh()
        for _, widget in ipairs(self.refreshers) do
            if widget.Refresh then widget:Refresh() end
        end
        self:RefreshPreview()
    end

    page:Hide()
    return page
end

function B:AddSection(page, title, description)
    local section = W:Section(page.body, title, description, "settings")
    section:SetPoint("TOPLEFT", page.body, "TOPLEFT", 0, page.nextY)
    section:SetPoint("TOPRIGHT", page.body, "TOPRIGHT", 0, page.nextY)
    section.nextY = -(section.headerHeight + 6)
    return section
end

function B:AddRow(page, section, row)
    row:SetPoint("TOPLEFT", section, "TOPLEFT", 14, section.nextY)
    row:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, section.nextY)
    section.nextY = section.nextY - row:GetHeight()
    page:AddRefresher(row)
    return row
end

function B:FinishSection(page, section)
    local height = math.max(section.headerHeight + 28, -section.nextY + 9)
    section:SetHeight(height)
    page.nextY = page.nextY - height - 12
    page:Layout()
end

local function SizePositionButton(button, width)
    button:SetWidth(width)
    local theme = Sintezza_Theme
    local function Fit(label)
        local measure = label.GetUnboundedStringWidth or label.GetStringWidth
        for size = 11, 1, -1 do
            theme.Fonts:Paint(label, size)
            if measure(label) <= width - 14 then break end
        end
    end
    theme:TrackAppearance(button.text, "font", Fit)
    button:HookScript("OnShow", function() Fit(button.text) end)
    Fit(button.text)
end

function B:AddPosition(page, options)
    local section = self:AddSection(page, L.position)
    local coordinates = CreateFrame("Frame", nil, section)
    local previousAxis
    local function Apply(x, y)
        options.set(x, y)
        page:RefreshPreview()
    end
    for _, axis in ipairs({ 1, 2 }) do
        local function Range()
            return unpack((select(axis, options.ranges())))
        end
        local low, high, step = Range()
        local label = axis == 1 and L.x or L.y
        local row = W:SliderRow(coordinates, label, low, high, step,
            function() return (select(axis, options.get())) end,
            function(value)
                local x, y = options.get()
                if axis == 1 then x = value else y = value end
                Apply(x, y)
            end)
        row:SetWidth(88)
        coordinates:SetHeight(row:GetHeight())
        if previousAxis then
            row:SetPoint("LEFT", previousAxis, "RIGHT", 6, 0)
        else
            row:SetPoint("LEFT", coordinates, "LEFT")
        end
        previousAxis = row
        local caption = W:Label(row, label, 10, T.text)
        caption:SetPoint("LEFT")
        -- Use the standard slider's validation label below the compact controls.
        row.labelText = ""
        row.label:SetText("")
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", row, "BOTTOMLEFT")
        row.label:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT")
        row.label:SetWordWrap(false)
        row.slider:ClearAllPoints()
        row.slider:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.slider:SetWidth(40)
        row.edit:ClearAllPoints()
        row.edit:SetPoint("LEFT", row.slider, "RIGHT", 4, 0)
        row.edit:SetWidth(30)
        local refresh = row.Refresh
        function row:Refresh()
            local minimum, maximum = Range()
            self:SetRange(minimum, maximum)
            if options.available then self:SetAvailable(options.available()) end
            refresh(self)
        end
        page:AddRefresher(row)
    end
    local move = W:Button(coordinates, L.move, options.move, true)
    SizePositionButton(move, 88)
    move:SetPoint("LEFT", previousAxis, "RIGHT", 8, 0)
    local reset = W:Button(coordinates, L.resetButton, function()
        Apply(options.reset())
        page:Refresh()
    end)
    SizePositionButton(reset, 66)
    reset:SetHeight(move:GetHeight())
    reset:SetPoint("LEFT", move, "RIGHT", 4, 0)
    if options.available then
        function coordinates:Refresh()
            local available = options.available()
            reset:SetEnabled(available)
            move:SetEnabled(available)
        end
    end
    self:AddRow(page, section, coordinates)
    self:FinishSection(page, section)
end

function B:AddPreview(page, createSample, play, selection, defaultKind)
    local pane = W:Section(page.rail, L.preview, nil, "settings")
    pane:SetPoint("TOPLEFT")
    pane:SetPoint("TOPRIGHT")
    pane.nextY = -(pane.headerHeight + 6)

    if selection then
        B:AddRow(page, pane, W:ChoiceRow(pane, selection.label, selection.choices, selection.get, function(value)
            selection.set(value)
            page:RefreshPreview()
        end, selection.order))
        pane.nextY = pane.nextY - 7
    end

    local stage = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    T:Backdrop(stage, T.input, T.lineSoft)
    stage:SetHeight(132)
    stage:SetClipsChildren(true)
    B:AddRow(page, pane, stage)
    pane.nextY = pane.nextY - 10
    local draw = createSample(stage)
    page.sample = function() draw(selection and selection.get() or defaultKind) end
    stage:HookScript("OnSizeChanged", function() page:RefreshPreview() end)

    local button = W:Button(pane, L.playInGame, function() play(selection and selection.get() or defaultKind) end, true)
    button:SetHeight(26)
    B:AddRow(page, pane, button)
    W:Help(pane, L.playInGameHelp, pane.title)
    pane:SetHeight(-pane.nextY + 13)
    return pane
end
