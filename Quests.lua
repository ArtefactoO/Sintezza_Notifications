local _, ns = ...
local L = ns.L
local log = C_QuestLog
local records, requests, hints = {}, {}, {}
local fallbackTexts = {}
local timer, scanLog, ready

local function Tracking()
    return ns.db.quests and not ns.HorizonActive()
end

local function QuestID(value)
    return ns.IsPublic(value, "number") and value > 0
end

local function Counter(text)
    local have, need, label = text:match("^(%d+)%s*/%s*(%d+)%s+(.+)$")
    if have then return tonumber(have), tonumber(need), label end
    have, label = text:match("^(%d+)%%%s+(.+)$")
    if have then return tonumber(have), 100, label, true end
    label, have, need = text:match("^(.-)%s*[:%(]?%s*(%d+)%s*/%s*(%d+)%)?$")
    if have and label ~= "" then return tonumber(have), tonumber(need), label end
    label, have = text:match("^(.-)%s*[:%(]?%s*(%d+)%%%)?$")
    if have and label ~= "" then return tonumber(have), 100, label, true end
    return nil, nil, text
end

local function Objective(text, have, need, finished)
    text = ns.Text(text)
    if text == "" then return end
    local textHave, textNeed, label, percent = Counter(text)
    have = ns.IsPublic(have, "number") and have or textHave
    need = ns.IsPublic(need, "number") and need or textNeed
    if textNeed then
        if need == textNeed and have then
            have = math.max(have, textHave)
        else
            have, need = textHave, textNeed
        end
    end
    label = label:match("^(.-)%s*$")
    finished = ns.IsPublic(finished, "boolean") and finished or false
    local progress
    if have and need and need > 1 then
        local count = percent and ("%d%%"):format(have) or ("%d/%d"):format(have, need)
        text = count .. " " .. label
        progress = ns.Clamp(have / need, 0, 1)
    elseif finished then
        progress = 1
        text = label
        if need == 1 then text = L.objectiveDone .. " · " .. text end
    end
    return { text = text, label = label, have = have, need = need, progress = progress, finished = finished }
end

local function ReadQuest(id, info)
    if not log or not QuestID(id) then return end
    if not info and log.GetLogIndexForQuestID and log.GetInfo then
        local index = log.GetLogIndexForQuestID(id)
        if ns.IsPublic(index, "number") and index > 0 then info = log.GetInfo(index) end
    end
    if not ns.IsPublic(info, "table") then info = nil end
    if info and (info.isHidden or info.isInternalOnly) then return end
    local title = ns.Text(info and info.title)
    if title == "" and log.GetTitleForQuestID then title = ns.Text(log.GetTitleForQuestID(id)) end
    if title == "" and C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        title = ns.Text(C_TaskQuest.GetQuestInfoByQuestID(id))
    end
    if title == "" or title:find("^%[DNT%]") then return end
    local world = log.IsWorldQuest and log.IsWorldQuest(id)
    world = ns.IsPublic(world, "boolean") and world or false
    return title, world
end

local function ReadObjectives(id)
    local result = {}
    if not log or not log.GetQuestObjectives then return result end
    local objectives = log.GetQuestObjectives(id)
    if not ns.IsPublic(objectives, "table") then return result end
    for index, objective in ipairs(objectives) do
        if ns.IsPublic(objective, "table") then
            result[index] = Objective(objective.text, objective.numFulfilled, objective.numRequired, objective.finished)
        end
    end
    return result
end

local function ActiveIDs()
    local ids = {}
    if log and log.GetInfo and log.GetNumQuestLogEntries then
        for index = 1, log.GetNumQuestLogEntries() do
            local info = log.GetInfo(index)
            if ns.IsPublic(info, "table") and not info.isHeader and QuestID(info.questID) then ids[info.questID] = info end
        end
    end
    local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if QuestID(super) and not ids[super] then ids[super] = true end
    if C_Map and C_Map.GetBestMapForUnit and C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
        local mapID = C_Map.GetBestMapForUnit("player")
        if QuestID(mapID) then
            local tasks = C_TaskQuest.GetQuestsOnMap(mapID)
            if ns.IsPublic(tasks, "table") then
                for _, task in ipairs(tasks) do
                    if ns.IsPublic(task, "table") and QuestID(task.questID) and not ids[task.questID] then
                        local active = task.inProgress
                        if C_TaskQuest.IsActive then active = C_TaskQuest.IsActive(task.questID) end
                        if ns.IsPublic(active, "boolean") and active then ids[task.questID] = true end
                    end
                end
            end
        end
    end
    return ids, super
end

local function InfoOrNil(info)
    if info ~= true then return info end
end

local function ObjectiveComplete(objective)
    return objective and (objective.finished or objective.progress == 1)
end

local function ShowObjective(id, index, title, objective, before)
    ns.Notify("quests", "questProgress", title, objective.text,
        { key = ("quest:%d:%s"):format(id, index), questID = id, progress = objective.progress,
            completion = ObjectiveComplete(objective) and not ObjectiveComplete(before) })
end

local function Improved(before, after)
    if not before then return false end
    if after.finished and not before.finished then return true end
    if before.finished and not after.finished then return false end
    if after.have and before.have then return after.have > before.have end
    return after.text ~= before.text and after.label == before.label
end

local function SameObjective(hint, objective)
    local label = hint.label
    return label == objective.label or hint.text == objective.text
        or hint.finished and objective.finished and label:find(objective.label, 1, true) ~= nil
end

local function Sample(id, info, explicit, matches)
    local previous = records[id]
    if previous and previous.removed then return end
    local title, world = ReadQuest(id, InfoOrNil(info))
    if not title then return end
    local objectives = ReadObjectives(id)
    local old = previous and previous.objectives or {}
    local record = { title = title, world = world or previous and previous.world, objectives = old }
    records[id] = record
    local changed = false
    for index, objective in pairs(objectives) do
        local before = old[index]
        local resetToZero = before and before.have and before.have > 0 and objective.have == 0 and not objective.finished
        if not resetToZero then
            objective.shownAt = before and before.shownAt
            if ready and (Improved(before, objective) or not before and explicit and (objective.finished or (objective.have or 0) > 0)) then
                local fallback = fallbackTexts[objective.text]
                if not fallback or fallback.title and fallback.title ~= title then
                    ShowObjective(id, index, title, objective, before)
                else
                    fallbackTexts[objective.text] = nil
                end
                objective.shownAt = GetTime()
                changed = true
            end
            old[index] = objective
        end
        objective = old[index]
        if objective then
            for _, hint in ipairs(hints) do
                if SameObjective(hint, objective) then
                    local candidate = matches[hint]
                    local recent = objective.shownAt and GetTime() - objective.shownAt < 1.25
                    if recent and (hint.have == nil or objective.have and objective.have >= hint.have) then
                        hint.shown = true
                    elseif candidate == nil then
                        matches[hint] = title
                    elseif candidate ~= title then
                        matches[hint] = false
                    end
                end
            end
        end
    end
    return changed
end

local function Flush()
    timer = nil
    if not Tracking() then
        requests, hints, scanLog = {}, {}, false
        return
    end
    local batch, all = requests, scanLog
    requests, scanLog = {}, false
    local matches = {}
    if all or #hints > 0 then
        for id, info in pairs(ActiveIDs()) do
            if not batch[id] then batch[id] = { info = info } end
        end
    end
    for id, request in pairs(batch) do
        local changed = Sample(id, request.info, request.explicit, matches)
        if not changed and request.explicit and not request.retry then
            requests[id] = { explicit = true, retry = true }
        end
    end
    if next(requests) or #hints > 0 then
        local retryHints = {}
        for _, hint in ipairs(hints) do
            if not hint.shown then
                if hint.retry then
                    local title = matches[hint]
                    local fallback = { title = title }
                    local text = hint.text
                    fallbackTexts[text] = fallback
                    C_Timer.After(2, function()
                        if fallbackTexts[text] == fallback then fallbackTexts[text] = nil end
                    end)
                    local detail = title and hint.text or nil
                    title = title or hint.text
                    ns.Notify("quests", "questProgress", title, detail,
                        { key = "questHint:" .. hint.text, progress = hint.progress, completion = ObjectiveComplete(hint) })
                else
                    hint.retry = true
                    retryHints[#retryHints + 1] = hint
                end
            end
        end
        hints = retryHints
        if next(requests) or #hints > 0 then timer = C_Timer.NewTimer(.38, Flush) end
    end
    ready = true
end

local function Schedule()
    if not timer then timer = C_Timer.NewTimer(.20, Flush) end
end

function ns.ResetQuestState()
    if timer then timer:Cancel(); timer = nil end
    records, requests, hints, fallbackTexts = {}, {}, {}, {}
    ready, scanLog = false, true
    Flush()
end

function ns.QuestWatch(id)
    if Tracking() and QuestID(id) then
        requests[id] = { explicit = true }
        Schedule()
    end
end

function ns.QuestLogUpdate()
    if not Tracking() then return end
    scanLog = true
    Schedule()
end

local progressMessages = {
    ERR_QUEST_ADD_FOUND_SII = true,
    ERR_QUEST_ADD_ITEM_SII = true,
    ERR_QUEST_ADD_KILL_SII = true,
    ERR_QUEST_ADD_PLAYER_KILL_SII = true,
    ERR_QUEST_OBJECTIVE_COMPLETE_S = true,
}

local nativeProgress = ns.CreateNativeInfoFilter(progressMessages)

function ns.SyncNativeQuestProgress()
    nativeProgress.Sync(ns.db.hideNativeQuestProgress and ns.WorldStyle("quests").opacity > 0 and Tracking())
end

function ns.QuestMessage(id, message)
    ns.SyncNativeQuestProgress()
    if not Tracking() then return end
    local messageType = ns.InfoMessageType(id, progressMessages)
    if not messageType then return end
    local objective = Objective(message, nil, nil, messageType == "ERR_QUEST_OBJECTIVE_COMPLETE_S")
    if not objective then return end
    nativeProgress.Hide(id)
    for _, hint in ipairs(hints) do
        if hint.text == objective.text then return end
    end
    if #hints >= 12 then table.remove(hints, 1) end
    hints[#hints + 1] = objective
    Schedule()
end

local function Accept(id, retry)
    if not Tracking() or not QuestID(id) then return end
    local title, world = ReadQuest(id)
    if title then
        records[id] = { title = title, world = world, objectives = ReadObjectives(id) }
        ns.Notify("quests", world and "worldAccept" or "questAccept", title, nil,
            { questID = id, key = "questAccept:" .. id })
    elseif not retry then
        C_Timer.After(.25, function()
            if not records[id] then Accept(id, true) end
        end)
    end
end

function ns.QuestAccepted(id)
    Accept(id, false)
end

function ns.QuestRemoved(id)
    if not QuestID(id) then return end
    requests[id] = nil
    local record = records[id]
    if not record or record.removed then return end
    record.removed = true
    C_Timer.After(1, function()
        if records[id] == record then records[id] = nil end
    end)
end

function ns.QuestRewardText(xp, money)
    if not ns.db.questRewards then return end
    local rewards = {}
    if ns.IsPublic(xp, "number") and xp > 0 then rewards[#rewards + 1] = L.experienceReward:format(xp) end
    if ns.IsPublic(money, "number") and money > 0 then
        local gold = math.floor(money / 10000)
        local silver = math.floor(money / 100) % 100
        local copper = money % 100
        local coins = {}
        if gold > 0 then coins[#coins + 1] = L.gold:format(gold) end
        if silver > 0 then coins[#coins + 1] = L.silver:format(silver) end
        if copper > 0 then coins[#coins + 1] = L.copper:format(copper) end
        rewards[#rewards + 1] = "+" .. table.concat(coins, " ")
    end
    if #rewards > 0 then return table.concat(rewards, "  ·  ") end
end

function ns.QuestCompleted(id, xpReward, moneyReward)
    if not Tracking() or not QuestID(id) then return end
    local record = records[id]
    local title, world = ReadQuest(id)
    if record then
        title, world = title or record.title, world or record.world
    end
    if title then
        ns.Notify("quests", world and "worldQuest" or "questComplete", title, ns.QuestRewardText(xpReward, moneyReward),
            { questID = id, final = true, completion = true, key = "questDone:" .. id })
    end
    ns.QuestRemoved(id)
end

function ns.QuestPreview()
    local ids, super = ActiveIDs()
    local best, bestRank
    for id, info in pairs(ids) do
        local title = ReadQuest(id, InfoOrNil(info))
        if title then
            local objectives = ReadObjectives(id)
            for index, objective in pairs(objectives) do
                local rank = (id == super and 8 or 0) + (not objective.finished and 4 or 0)
                    + (objective.progress and 2 or 0) + ((objective.have or 0) > 0 and 1 or 0)
                if not best or rank > bestRank or rank == bestRank and (id < best.id or id == best.id and index < best.index) then
                    best = { title = title, detail = objective.text, progress = objective.progress, id = id, index = index }
                    bestRank = rank
                end
            end
            if not best then
                best, bestRank = { title = title, detail = "", id = id, index = 0 }, -1
            end
        end
    end
    return best
end
