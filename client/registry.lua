-- Registration and option filtering are separated from the game loop for testing.
InteractionRegistry = { records = {}, blocked = {}, revision = 0, serial = 0 }

local function list(value)
    return type(value) == 'table' and value or { value }
end

local function copy(value)
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

function InteractionRegistry.add(owner, kind, key, data, extra)
    assert(type(data) == 'table' and type(data.options) == 'table', 'tss-interactions: options table required')
    local id = owner .. ':' .. kind .. ':' .. tostring(key)
    local record = InteractionRegistry.records[id]
    if not record or kind == 'point' then
        record = { id = id, owner = owner, kind = kind, key = key, options = {}, order = {} }
        InteractionRegistry.records[id] = record
    end
    record.extra = extra or record.extra
    record.distance = tonumber(data.distance) or Config.Distance
    record.drawDistance = tonumber(data.drawDistance) or math.max(Config.DrawDistance, record.distance)
    record.offset = data.offset
    for index, option in ipairs(data.options) do
        assert(type(option.label) == 'string', 'tss-interactions: every option requires a label')
        local optionKey = tostring(option.name or option.label)
        if not record.options[optionKey] then record.order[#record.order + 1] = optionKey end
        local normalized = copy(option)
        normalized.item = option.item or option.required_item
        normalized.distance = math.min(tonumber(option.distance) or record.distance, record.distance)
        normalized.num = tonumber(option.num) or index
        record.options[optionKey] = normalized
    end
    InteractionRegistry.revision = InteractionRegistry.revision + 1
    return id
end

function InteractionRegistry.remove(owner, kind, key, labels)
    local id = owner .. ':' .. kind .. ':' .. tostring(key)
    local record = InteractionRegistry.records[id]
    if not record then return end
    if not labels then InteractionRegistry.records[id] = nil else
        for _, label in ipairs(list(labels)) do
            for optionKey, option in pairs(record.options) do
                if optionKey == label or option.label == label then record.options[optionKey] = nil end
            end
        end
        local order = {}
        for _, optionKey in ipairs(record.order) do
            if record.options[optionKey] then order[#order + 1] = optionKey end
        end
        record.order = order
        if not next(record.options) then InteractionRegistry.records[id] = nil end
    end
    InteractionRegistry.revision = InteractionRegistry.revision + 1
end

function InteractionRegistry.removeOwner(owner)
    for id, record in pairs(InteractionRegistry.records) do
        if record.owner == owner then InteractionRegistry.records[id] = nil end
    end
    InteractionRegistry.blocked[owner] = nil
    InteractionRegistry.revision = InteractionRegistry.revision + 1
end

local function roleMatch(requirement, role)
    role = role or {}
    if type(requirement) == 'string' then return role.name == requirement end
    if type(requirement) ~= 'table' then return false end
    local grade = type(role.grade) == 'table' and role.grade.level or role.grade or 0
    return requirement[role.name] ~= nil and grade >= (tonumber(requirement[role.name]) or 0)
end

local function nameMatch(requirement, name)
    if type(requirement) == 'string' then return requirement == name end
    if type(requirement) ~= 'table' then return false end
    if requirement[name] then return true end
    for _, value in ipairs(requirement) do if value == name then return true end end
    return false
end

local function itemMatch(requirement, items)
    local amounts = {}
    for _, item in pairs(items or {}) do
        if item.name then amounts[item.name] = (amounts[item.name] or 0) + (item.amount or 0) end
    end
    if type(requirement) == 'string' then return (amounts[requirement] or 0) > 0 end
    if type(requirement) ~= 'table' then return false end
    for key, value in pairs(requirement) do
        local name, count = key, tonumber(value) or 1
        if type(key) == 'number' then name, count = value, 1 end
        if (amounts[name] or 0) < count then return false end
    end
    return true
end

function InteractionRegistry.allowed(option, entity, distance, player, preview)
    if option.hidden or (not preview and distance > option.distance) then return false end
    if option.job and not roleMatch(option.job, player.job) then return false end
    if option.excludejob and roleMatch(option.excludejob, player.job) then return false end
    if option.gang and not roleMatch(option.gang, player.gang) then return false end
    if option.excludegang and roleMatch(option.excludegang, player.gang) then return false end
    if option.jobType and not nameMatch(option.jobType, (player.job or {}).type) then return false end
    if option.excludejobType and nameMatch(option.excludejobType, (player.job or {}).type) then return false end
    if option.citizenid and not nameMatch(option.citizenid, player.citizenid) then return false end
    if option.item and not itemMatch(option.item, player.items) then return false end
    if option.canInteract then
        local ok, result = pcall(option.canInteract, entity or 0, distance, option)
        if not ok or not result then return false end
    end
    return true
end

InteractionRegistry.copy = copy
InteractionRegistry.list = list
