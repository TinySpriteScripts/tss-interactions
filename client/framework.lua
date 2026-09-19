InteractionFramework = {}
local core
local dataOwner
local data = {}
local loggedIn = true
local mode = Config.Framework or 'auto'
assert(mode == 'auto' or mode == 'standalone' or mode == 'qbcore', 'tss-interactions: invalid Config.Framework')

local function changed()
    TriggerEvent('tss-interactions:client:playerDataChanged')
end

local function connect()
    core = nil
    dataOwner = nil
    if mode ~= 'standalone' and GetResourceState('qb-core') == 'started' then
        local ok, result = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then core = result end
    end
    data = core and core.Functions.GetPlayerData() or {}
    loggedIn = core and LocalPlayer.state.isLoggedIn == true or (not core and mode ~= 'qbcore')
    changed()
end

function InteractionFramework.GetPlayerData(fresh)
    if core and fresh then return core.Functions.GetPlayerData() or {} end
    return data
end

function InteractionFramework.IsBlocked()
    local player = InteractionFramework.GetPlayerData()
    local meta = player.metadata or {}
    local state = LocalPlayer.state
    return not loggedIn or (core and not state.isLoggedIn) or state.inv_busy
        or meta.isdead or meta.inlaststand or meta.ishandcuffed
end

function InteractionFramework.CanRunCommand()
    return core ~= nil or type(Config.CommandHandler) == 'function'
end

function InteractionFramework.RunCommand(name, option)
    if core then
        TriggerServerEvent('QBCore:CallCommand', name, option)
    elseif Config.CommandHandler then
        Config.CommandHandler(name, option)
    end
end

function InteractionFramework.Notify(message, kind, duration)
    if core then return core.Functions.Notify(message, kind, duration) end
    -- Native feed notifications require no chat, framework or UI resource.
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

-- A full snapshot replaces the previous one, including removed roles/items.
exports('SetPlayerData', function(snapshot)
    assert(not core and mode ~= 'qbcore', 'tss-interactions: SetPlayerData is for standalone/custom integrations')
    assert(type(snapshot) == 'table', 'tss-interactions: player data table required')
    dataOwner = GetInvokingResource() or GetCurrentResourceName()
    data = snapshot
    loggedIn = snapshot.loaded ~= false
    changed()
    if not loggedIn then TriggerEvent('tss-interactions:client:playerUnloaded') end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if not core then return end
    loggedIn = true
    data = core.Functions.GetPlayerData() or {}
    changed()
end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if not core then return end
    loggedIn = false
    data = {}
    changed()
    TriggerEvent('tss-interactions:client:playerUnloaded')
end)
RegisterNetEvent('QBCore:Player:SetPlayerData', function(snapshot)
    if not core then return end
    data = snapshot or core.Functions.GetPlayerData() or {}
    changed()
end)
RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, value)
    if not core then return end
    if key == 'all' then data = value or {}
    elseif key then data[key] = value end
    changed()
end)
AddEventHandler('onClientResourceStart', function(name)
    if name == 'qb-core' and mode ~= 'standalone' then connect() end
end)
AddEventHandler('onClientResourceStop', function(name)
    if name == dataOwner then
        dataOwner, data, loggedIn = nil, {}, false
        changed()
        TriggerEvent('tss-interactions:client:playerUnloaded')
    end
    if name ~= 'qb-core' or not core then return end
    core, data, loggedIn = nil, {}, false
    changed()
    TriggerEvent('tss-interactions:client:playerUnloaded')
end)
connect()
