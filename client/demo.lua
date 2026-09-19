local resourceName = GetCurrentResourceName()
local demoPeds = {}
local spawning = false
local generation = 0

local function clearDemo()
    generation = generation + 1
    for _, ped in ipairs(demoPeds) do
        exports[resourceName]:RemoveEntity(ped)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    demoPeds = {}
end

local function demoOptions(pedNumber)
    local definitions = {
        { 'Say hello', 'fa-solid fa-comment' },
        { 'View identification', 'fa-regular fa-id-card' },
        { 'Browse supplies', 'fa-solid fa-box-open' },
        { 'Ask for directions', 'fa-solid fa-map-location-dot' },
        { 'Discuss repairs', 'fa-solid fa-wrench' },
        { 'Say goodbye', 'fa-solid fa-hand' },
    }
    local options = {}
    for index, definition in ipairs(definitions) do
        local label = definition[1]
        options[#options + 1] = {
            name = 'demo_option_' .. index,
            label = ('Ped %d: %s'):format(pedNumber, label),
            icon = definition[2],
            action = function()
                print(('[tss-interactions] hello - ped %d: %s'):format(pedNumber, label))
            end,
        }
    end
    return options
end

if Config.EnableDemoCommand then
    RegisterCommand('test_interact', function()
        if spawning then return end
        if #demoPeds > 0 then
            clearDemo()
            InteractionFramework.Notify('Interaction demo removed.', 'primary')
            return
        end

        local playerPed = PlayerPedId()
        if IsPedInAnyVehicle(playerPed, false) then
            InteractionFramework.Notify('Leave your vehicle to spawn the interaction demo.', 'error')
            return
        end

        spawning = true
        local currentGeneration = generation
        local model = joaat('a_m_m_business_01')
        RequestModel(model)
        local deadline = GetGameTimer() + 5000
        while not HasModelLoaded(model) and GetGameTimer() < deadline and currentGeneration == generation do
            Wait(0)
        end
        if currentGeneration ~= generation or not HasModelLoaded(model) then
            SetModelAsNoLongerNeeded(model)
            spawning = false
            if currentGeneration == generation then
                InteractionFramework.Notify('Could not load the demo ped model. Try again.', 'error')
            end
            return
        end

        playerPed = PlayerPedId()
        local heading = (GetEntityHeading(playerPed) + 180.0) % 360.0
        local ok, err = pcall(function()
            for index, side in ipairs({ -0.9, 0.9 }) do
                local position = GetOffsetFromEntityInWorldCoords(playerPed, side, 1.8, 0.0)
                local ped = CreatePed(4, model, position.x, position.y, position.z-1, heading, false, false)
                assert(ped ~= 0 and DoesEntityExist(ped), 'Could not create demo ped')
                demoPeds[#demoPeds + 1] = ped
                SetEntityAsMissionEntity(ped, true, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                FreezeEntityPosition(ped, true)
                exports[resourceName]:AddEntity(ped, {
                    distance = 3.0,
                    drawDistance = 8.0,
                    offset = vector3(0.0, 0.0, 0.6),
                    options = demoOptions(index),
                })
            end
        end)
        SetModelAsNoLongerNeeded(model)
        spawning = false
        if not ok then
            clearDemo()
            print(('[tss-interactions] Demo failed: %s'):format(err))
            InteractionFramework.Notify('Could not create the interaction demo. Check F8.', 'error')
            return
        end
        InteractionFramework.Notify('Demo ready! Middle-click to switch peds, scroll options, E to select. /test_interact removes them.', 'primary', 8000)
    end, false)
end

AddEventHandler('onClientResourceStop', function(name)
    if name == resourceName then clearDemo() end
end)
AddEventHandler('tss-interactions:client:playerUnloaded', clearDemo)
