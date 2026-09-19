local resource = GetCurrentResourceName()
local nearby, active, eligible = {}, nil, {}
local selected, selectedKey, shown, busy = 1, nil, false, false
local nextAction, lastUi, lastOptions, scannedRevision = 0, 0, 0, -1
local playerData = InteractionFramework.GetPlayerData()
local optionsDirty = true
local manualPointId
local api = {}
local hintTextureDict, hintTextureName = 'shared', 'emptydot_32'

if Config.DrawSprite then RequestStreamedTextureDict(hintTextureDict, false) end

local function coords(value)
    assert(value and tonumber(value.x) and tonumber(value.y) and tonumber(value.z), 'tss-interactions: valid vector3 coordinates required')
    return vector3(value.x, value.y, value.z)
end

local function entityKey(entity)
    assert(type(entity) == 'number' and DoesEntityExist(entity), 'tss-interactions: valid local entity handle required')
    if NetworkGetEntityIsNetworked(entity) then return 'net:' .. NetworkGetNetworkIdFromEntity(entity) end
    return 'local:' .. entity
end

function api.AddPoint(owner, name, position, data)
    return InteractionRegistry.add(owner, 'point', name, data, coords(position))
end

function api.AddInteraction(owner, position, options, distance)
    InteractionRegistry.serial = InteractionRegistry.serial + 1
    return api.AddPoint(owner, 'interaction_' .. InteractionRegistry.serial, position, { options = options, distance = distance })
end

function api.RemovePoint(owner, name)
    local record = InteractionRegistry.records[name]
    if record and record.owner == owner then
        InteractionRegistry.records[name] = nil
        InteractionRegistry.revision = InteractionRegistry.revision + 1
    else
        InteractionRegistry.remove(owner, 'point', name)
        for id, candidate in pairs(InteractionRegistry.records) do
            if candidate.owner == owner and candidate.zoneName == name then InteractionRegistry.records[id] = nil end
        end
    end
end
api.RemoveInteraction = api.RemovePoint
api.RemoveZone = api.RemovePoint

function api.AddEntity(owner, entities, data)
    local result
    for _, entity in ipairs(InteractionRegistry.list(entities)) do
        local key = entityKey(entity)
        result = InteractionRegistry.add(owner, 'entity', key, data, {
            handle = entity, model = GetEntityModel(entity),
            netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or nil,
        })
    end
    return result
end

function api.RemoveEntity(owner, entities, labels)
    for _, entity in ipairs(InteractionRegistry.list(entities)) do
        -- Match the saved handle too: removal often happens after DeleteEntity.
        local keys = {}
        for _, record in pairs(InteractionRegistry.records) do
            if record.owner == owner and record.kind == 'entity' and record.extra.handle == entity then keys[#keys + 1] = record.key end
        end
        if DoesEntityExist(entity) then keys[#keys + 1] = entityKey(entity) end
        for _, key in ipairs(keys) do InteractionRegistry.remove(owner, 'entity', key, labels) end
    end
end

function api.AddModel(owner, models, data)
    for _, model in ipairs(InteractionRegistry.list(models)) do
        InteractionRegistry.add(owner, 'model', type(model) == 'string' and joaat(model) or model, data)
    end
end
function api.RemoveModel(owner, models, labels)
    for _, model in ipairs(InteractionRegistry.list(models)) do InteractionRegistry.remove(owner, 'model', type(model) == 'string' and joaat(model) or model, labels) end
end
function api.AddBone(owner, bones, data)
    for _, bone in ipairs(InteractionRegistry.list(bones)) do InteractionRegistry.add(owner, 'bone', bone, data) end
end
function api.RemoveBone(owner, bones, labels)
    for _, bone in ipairs(InteractionRegistry.list(bones)) do InteractionRegistry.remove(owner, 'bone', bone, labels) end
end
function api.SetEnabled(owner, enabled)
    InteractionRegistry.blocked[owner] = enabled == false or nil
end
function api.IsActive() return shown end

-- Compatibility aliases use distance-based interactions, not qb-target geometry.
api.AllowTargeting = api.SetEnabled
api.IsTargetActive, api.IsTargetSuccess = api.IsActive, api.IsActive
api.AddTargetEntity, api.RemoveTargetEntity = api.AddEntity, api.RemoveEntity
api.AddTargetModel, api.RemoveTargetModel = api.AddModel, api.RemoveModel
api.AddTargetBone, api.RemoveTargetBone = api.AddBone, api.RemoveBone
function api.AddCircleZone(owner, name, center, _, _, data) return api.AddPoint(owner, name, center, data) end
function api.AddBoxZone(owner, name, center, _, _, _, data) return api.AddPoint(owner, name, center, data) end
function api.AddEntityZone(owner, name, entity, _, data)
    local id = api.AddEntity(owner, entity, data)
    InteractionRegistry.records[id].zoneName = name
    return id
end
for name, kind in pairs({ Ped = 'ped', Vehicle = 'vehicle', Object = 'object', Player = 'player' }) do
    api['AddGlobal' .. name] = function(owner, data) return InteractionRegistry.add(owner, 'global', kind, data) end
    api['RemoveGlobal' .. name] = function(owner, labels) InteractionRegistry.remove(owner, 'global', kind, labels) end
end
for name, fn in pairs(api) do
    exports(name, function(...) return fn(GetInvokingResource() or resource, ...) end)
end
exports('CompatCall', function(name, owner, ...)
    assert(GetInvokingResource() == 'qb-target', 'CompatCall is reserved for the qb-target bridge')
    assert(api[name], 'Unsupported legacy target export: ' .. tostring(name))
    return api[name](owner or 'qb-target', ...)
end)

local function blocked()
    return InteractionFramework.IsBlocked() or next(InteractionRegistry.blocked) ~= nil or busy
        or IsEntityDead(PlayerPedId())
        or IsPauseMenuActive() or IsNuiFocused() or IsPlayerFreeAiming(PlayerId())
        or (Config.DisableInVehicle and IsPedInAnyVehicle(PlayerPedId(), false))
end

local function hide()
    if shown then SendNUIMessage({ action = 'hide' }) end
    shown = false
end

local function position(candidate)
    if not candidate.entity then return candidate.coords end
    if not DoesEntityExist(candidate.entity) or GetEntityModel(candidate.entity) ~= candidate.model then return nil end
    if candidate.bone then
        local index = GetEntityBoneIndexByName(candidate.entity, candidate.bone)
        if index == -1 then return nil end
        return GetWorldPositionOfEntityBone(candidate.entity, index)
    end
    if candidate.offset then
        return GetOffsetFromEntityInWorldCoords(candidate.entity, candidate.offset.x, candidate.offset.y, candidate.offset.z)
    end
    return GetEntityCoords(candidate.entity)
end

local function discover()
    local groups = {}
    local playerPos = GetEntityCoords(PlayerPedId())
    local models, bones, globals = {}, {}, {}
    local maxRange = Config.DrawDistance
    local function add(record, entity, bone, point)
        local anchor = entity and ('entity:' .. entity .. ':' .. (bone or 'center')) or record.id
        if record.offset then anchor = anchor .. ':' .. record.id end
        local candidate = groups[anchor]
        if not candidate then
            candidate = { id = anchor, entity = entity, model = entity and GetEntityModel(entity), bone = bone,
                coords = point, offset = record.offset, records = {}, drawDistance = record.drawDistance }
            groups[anchor] = candidate
        end
        candidate.records[#candidate.records + 1] = record
        candidate.drawDistance = math.max(candidate.drawDistance, record.drawDistance)
    end
    for _, record in pairs(InteractionRegistry.records) do
        maxRange = math.max(maxRange, record.drawDistance)
        if record.kind == 'point' then
            if #(playerPos - record.extra) <= record.drawDistance then add(record, nil, nil, record.extra) end
        elseif record.kind == 'entity' then
            local extra, entity = record.extra, record.extra.handle
            if extra.netId then
                entity = NetworkDoesEntityExistWithNetworkId(extra.netId) and NetworkGetEntityFromNetworkId(extra.netId) or 0
            end
            if DoesEntityExist(entity) and GetEntityModel(entity) == extra.model and #(playerPos - GetEntityCoords(entity)) <= record.drawDistance + 10 then
                add(record, entity)
            end
        elseif record.kind == 'model' then
            models[record.key] = models[record.key] or {}
            models[record.key][#models[record.key] + 1] = record
        elseif record.kind == 'bone' then bones[#bones + 1] = record
        elseif record.kind == 'global' then globals[#globals + 1] = record end
    end
    if next(models) or #bones > 0 or #globals > 0 then
        for _, pool in ipairs({ 'CObject', 'CVehicle', 'CPed' }) do
            -- Bone-only registrations only need the vehicle pool.
            if next(models) or #globals > 0 or pool == 'CVehicle' then
                for _, entity in ipairs(GetGamePool(pool)) do
                    if entity ~= PlayerPedId() and #(playerPos - GetEntityCoords(entity)) <= maxRange + 10 then
                        for _, record in ipairs(models[GetEntityModel(entity)] or {}) do add(record, entity) end
                        if pool == 'CVehicle' then
                            for _, record in ipairs(bones) do
                                if GetEntityBoneIndexByName(entity, record.key) ~= -1 then add(record, entity, record.key) end
                            end
                        end
                        for _, record in ipairs(globals) do
                            if (record.key == 'vehicle' and pool == 'CVehicle') or (record.key == 'object' and pool == 'CObject')
                                or (record.key == 'ped' and pool == 'CPed' and not IsPedAPlayer(entity))
                                or (record.key == 'player' and pool == 'CPed' and IsPedAPlayer(entity)) then add(record, entity) end
                        end
                    end
                end
            end
        end
    end
    nearby = {}
    for _, candidate in pairs(groups) do nearby[#nearby + 1] = candidate end
    scannedRevision = InteractionRegistry.revision
    optionsDirty = true -- New candidates need visibility evaluated before their first draw.
end

local function optionsFor(candidate, distance, preview)
    local options = {}
    for _, record in ipairs(candidate.records) do
        if InteractionRegistry.records[record.id] == record then
            for _, key in ipairs(record.order) do
                local option = record.options[key]
                if option and (option.action or option.type ~= 'qbcommand' or InteractionFramework.CanRunCommand()) and InteractionRegistry.allowed(option, candidate.entity, distance, playerData, preview) then
                    options[#options + 1] = { id = record.id .. ':' .. key, key = key, option = option, record = record }
                end
            end
        end
    end
    table.sort(options, function(a, b)
        if a.option.num == b.option.num then return a.id < b.id end
        return a.option.num < b.option.num
    end)
    return options
end

local function selectCandidate(candidate)
    if not active or active.id ~= candidate.id then selected, selectedKey = 1, nil end
    active = candidate
    selected = 1
    for index, entry in ipairs(active.options) do if entry.id == selectedKey then selected = index break end end
    selectedKey = active.options[selected] and active.options[selected].id
end

local function refreshOptions()
    playerData = InteractionFramework.GetPlayerData()
    eligible = {}
    local playerPos = GetEntityCoords(PlayerPedId())
    for _, candidate in ipairs(nearby) do
        local pos = position(candidate)
        if pos then
            candidate.distance = #(playerPos - pos)
            local onScreen = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
            if onScreen then
                candidate.options = optionsFor(candidate, candidate.distance)
                candidate.hint = #candidate.options > 0 or (candidate.distance <= candidate.drawDistance and #optionsFor(candidate, candidate.distance, true) > 0)
                if #candidate.options > 0 then eligible[#eligible + 1] = candidate end
            end
        end
    end
    table.sort(eligible, function(a, b)
        if a.distance == b.distance then return a.id < b.id end
        return a.distance < b.distance
    end)
    local best = eligible[1]
    local manual
    for _, candidate in ipairs(eligible) do if candidate.id == manualPointId then manual = candidate break end end
    if not manual then manualPointId = nil end
    if active and best then
        for _, candidate in ipairs(eligible) do
            if candidate.id == active.id and candidate.distance <= best.distance + Config.SwitchThreshold then best = candidate break end
        end
    end
    if manual then best = manual end
    if best then selectCandidate(best) else active = nil end
end

local function activate()
    local candidate = active
    local entry = candidate and candidate.options[selected]
    if not entry or entry.option.disabled or blocked() or GetGameTimer() < nextAction then return end
    local pos = position(candidate)
    if not pos or InteractionRegistry.records[entry.record.id] ~= entry.record or entry.record.options[entry.key] ~= entry.option then return end
    if not InteractionRegistry.allowed(entry.option, candidate.entity, #(GetEntityCoords(PlayerPedId()) - pos), InteractionFramework.GetPlayerData(true)) then return end
    nextAction = GetGameTimer() + Config.ActionCooldown
    local data = InteractionRegistry.copy(entry.option)
    data.entity, data.coords = candidate.entity, pos
    hide()
    busy = true
    CreateThread(function()
        local ok, err = pcall(function()
            if data.action then data.action(data.entity, data)
            elseif data.event then
                -- Send serializable event data, never function references, across the network.
                data.action, data.canInteract = nil, nil
                if data.type == 'server' then TriggerServerEvent(data.event, data)
                elseif data.type == 'command' then ExecuteCommand(data.event)
                elseif data.type == 'qbcommand' then InteractionFramework.RunCommand(data.event, data)
                else TriggerEvent(data.event, data) end
            end
        end)
        busy = false
        if not ok then print(('[tss-interactions] %s: %s'):format(entry.id, err)) end
    end)
end

CreateThread(function()
    while true do
        if not blocked() then discover() end
        Wait(Config.ScanInterval)
    end
end)

CreateThread(function()
    while true do
        local sleep = 100
        if blocked() or GetGameTimer() < nextAction then hide() else
            local now = GetGameTimer()
            if scannedRevision ~= InteractionRegistry.revision then discover() end
            if optionsDirty or now - lastOptions >= Config.OptionInterval then
                refreshOptions()
                optionsDirty = false
                lastOptions = now
            end
            if #nearby > 0 then sleep = 0 end
            local pos = active and position(active)
            local onScreen, sx, sy = false, nil, nil
            if pos then onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z) end
            if active and onScreen then
                -- Only these controls are claimed; camera and movement stay in game.
                for _, control in pairs(Config.Controls) do DisableControlAction(0, control, true) end
                DisableControlAction(0, 16, true)
                DisableControlAction(0, 17, true)
                if IsDisabledControlJustPressed(0, Config.Controls.previous) then selected = (selected - 2) % #active.options + 1 end
                if IsDisabledControlJustPressed(0, Config.Controls.next) then selected = selected % #active.options + 1 end
                selectedKey = active.options[selected].id
                if #eligible > 1 and IsDisabledControlJustPressed(0, Config.Controls.switch) then
                    for index, candidate in ipairs(eligible) do
                        if candidate.id == active.id then
                            selectCandidate(eligible[index % #eligible + 1])
                            manualPointId = active.id
                            break
                        end
                    end
                    lastOptions = now -- preserve the manually chosen point briefly
                    pos = position(active)
                    if pos then onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z) end
                end
                if IsDisabledControlJustReleased(0, Config.Controls.interact) then activate() end
                if not busy and now >= nextAction and now - lastUi >= Config.UiInterval then
                    local rows = {}
                    for _, entry in ipairs(active.options) do
                        rows[#rows + 1] = { label = entry.option.label, icon = entry.option.icon, disabled = entry.option.disabled == true }
                    end
                    SendNUIMessage({ action = 'show', id = active.id, x = sx, y = sy, options = rows, selected = selected,
                        pointCount = #eligible, distance = active.distance })
                    shown, lastUi = true, now
                end
            else hide() end
            -- Optional outline rings mark nearby, unselected interaction points.
            if Config.DrawSprite then
                for _, candidate in ipairs(nearby) do
                    if not active or candidate.id ~= active.id then
                        local anchor = position(candidate)
                        if anchor then
                            local distance = #(GetEntityCoords(PlayerPedId()) - anchor)
                            if distance <= candidate.drawDistance and candidate.hint then
                                local visible, x, y = GetScreenCoordFromWorldCoord(anchor.x, anchor.y, anchor.z)
                                if visible then
                                    local width, height = GetActiveScreenResolution()
                                    if HasStreamedTextureDictLoaded(hintTextureDict) then
                                        -- Equal pixel dimensions keep the circle round at any aspect ratio.
                                        DrawSprite(hintTextureDict, hintTextureName, x, y,
                                            Config.SpriteSize / width, Config.SpriteSize / height, 0.0, 255, 255, 255, 230)
                                    else
                                        RequestStreamedTextureDict(hintTextureDict, false)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('tss-interactions:client:playerDataChanged', function()
    optionsDirty = true
end)
AddEventHandler('tss-interactions:client:playerUnloaded', function()
    playerData = {}
    active = nil
    hide()
end)
AddEventHandler('onClientResourceStop', function(name)
    InteractionRegistry.removeOwner(name)
    if name == resource then hide() end
end)

for _, point in ipairs(Config.Points) do api.AddPoint(resource, point.name, point.coords, point) end
