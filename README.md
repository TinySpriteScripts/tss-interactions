# tss-interactions

A framework-independent, distance-based interaction resource for FiveM, with optional automatic QBCore integration. Add prompts to coordinates, entities, models and vehicle bones using client exports. It can run alongside qb-target, with each resource handling the interactions registered with it.

Walk near a point to see its options. Up to three options are visible at once. Use the **mouse wheel** to reveal and choose an option, release **E** to activate it, and click the **middle mouse button** to switch between nearby points. The nearest available on-screen point is selected automatically. A manual selection stays active until it becomes unavailable. With `Config.DrawSprite = true`, other available locations show a white outline ring, including nearby points outside interaction range. Set it to `false` to hide these markers while keeping interaction menus enabled.

The interface follows world coordinates without taking NUI focus, leaving movement and camera control in the game. Ranges use 3D distance without line-of-sight checks, so a nearby point may be usable through a wall.

## Credits

Credit to [qb-target](https://github.com/qbcore-framework/qb-target) and its contributors for the base layout and original interaction concept this resource was built from. TinySprite Assets adapted and extended that foundation into TSS's own distance-based interaction system for QBCore.

## Installation

1. Place this folder in your resources directory as `tss-interactions`.
2. Start it before resources that register interactions. If using QBCore, start `qb-core` first:

   ```cfg
   # ensure qb-core # Only on QBCore servers; start it before tss-interactions.
   ensure tss-interactions
   ensure my-resource
   ```

3. Add this to the `fxmanifest.lua` of each resource using its exports:

   ```lua
   dependency 'tss-interactions'
   ```

No framework or external resource is required. `Config.Framework = 'auto'` uses QBCore when available and otherwise runs standalone. The interface and Font Awesome Free 6.7.2 fonts are bundled locally; no CDN connection is needed. No interactions are registered by default; add them through exports or `Config.Points`.

### Using it alongside qb-target

Keep your existing qb-target installation and configuration. This resource does not require a qb-target bridge or a change to `UseTarget`. Calls to `exports['qb-target']` remain separate from calls to `exports['tss-interactions']`.

Register each action with the system you want to display it. Registering it in both systems can produce duplicate prompts. There is no automatic input coordination with qb-target. Use `SetEnabled(false)` when another flow needs exclusive control and `SetEnabled(true)` when it finishes.

## UI showcase

Run `/test_interact` while on foot in an open space to spawn two stationary peds just ahead of you. Both are within interaction range so you can **middle-click** to switch points, scroll through six options on each ped, and release **E** to select. Each option prints `hello` with the ped and option name in your F8 console.

Run `/test_interact` again to remove both peds. They are local to your client and are cleaned up when the resource stops or your character unloads. Set `Config.EnableDemoCommand = false` to disable the command.

## Quick start

Put this in your resource's client script and replace the coordinates with your location:

```lua
local receptionId = exports['tss-interactions']:AddInteraction(
    vector3(307.2, -595.3, 43.3),
    {
        {
            name = 'reception_info',
            label = 'Ask for information',
            icon = 'fas fa-suitcase-medical',
            action = function(entity, data)
                -- Coordinate points have no entity. data.coords is the point.
                print('Please wait here for a member of staff.')
            end,
        },
    },
    2.5 -- Optional; defaults to Config.Distance.
)

-- When no longer needed, call from this same resource:
-- exports['tss-interactions']:RemoveInteraction(receptionId)
```

## Named points and events

Registering the same point name again from the same resource replaces that point.

```lua
exports['tss-interactions']:AddPoint('workshop_desk', vector3(-347.0, -133.0, 39.0), {
    distance = 2.0,
    drawDistance = 8.0,
    options = {
        {
            name = 'view_services',
            label = 'View workshop services',
            icon = 'fas fa-wrench',
            type = 'client',
            event = 'my-resource:client:viewServices',
            workshopId = 'city', -- Custom fields are included in event data.
        },
    },
})

RegisterNetEvent('my-resource:client:viewServices', function(data)
    print(('Selected workshop: %s'):format(data.workshopId))
    -- Open your resource's menu here.
end)

-- exports['tss-interactions']:RemovePoint('workshop_desk')
```

## Entities, models and vehicle bones

Use `AddEntity` after your resource has created an entity. Pass its local handle:

```lua
local function registerReceptionist(ped)
    return exports['tss-interactions']:AddEntity(ped, {
        distance = 2.5,
        offset = vector3(0.0, 0.0, 1.0),
        options = {
            {
                name = 'greet',
                label = 'Speak to receptionist',
                icon = 'fas fa-user',
                action = function(entity, data)
                    TaskTurnPedToFaceEntity(entity, PlayerPedId(), 1000)
                end,
            },
        },
    })
end

-- local receptionistId = registerReceptionist(yourPedHandle)
-- exports['tss-interactions']:RemoveInteraction(receptionistId)
```

Model registrations apply to matching streamed objects, vehicles or peds:

```lua
exports['tss-interactions']:AddModel({ 'prop_vend_soda_01', 'prop_vend_soda_02' }, {
    distance = 1.5,
    options = {
        {
            name = 'inspect_machine',
            label = 'Inspect vending machine',
            action = function(entity, data)
                print(('Vending machine model: %s'):format(GetEntityModel(entity)))
            end,
        },
    },
})

-- Remove just this option from both models:
-- exports['tss-interactions']:RemoveModel(
--     { 'prop_vend_soda_01', 'prop_vend_soda_02' }, 'inspect_machine'
-- )
```

Bone registrations attach to named bones on nearby vehicles:

```lua
exports['tss-interactions']:AddBone('bonnet', {
    distance = 1.5,
    options = {
        {
            name = 'inspect_engine',
            label = 'Inspect engine',
            icon = 'fas fa-wrench',
            job = { mechanic = 0 },
            canInteract = function(entity, distance, option)
                return GetVehicleEngineHealth(entity) < 1000.0
            end,
            action = function(entity, data)
                print(('Engine health: %.0f'):format(GetVehicleEngineHealth(entity)))
            end,
        },
    },
})

-- exports['tss-interactions']:RemoveBone('bonnet', 'inspect_engine')
```

Entity and model offsets use local entity coordinates. Bones use their actual world positions. Registrations sharing an entity anchor combine into one menu; registrations with offsets retain separate anchors. Networked entity registrations save a network ID to resolve the entity after streaming.

## Client export reference

Call these as `exports['tss-interactions']:ExportName(...)` from a **client script**. There are no server exports. Ownership comes from the calling resource; do not pass an owner argument.

| Export | Returns | Purpose |
| --- | --- | --- |
| `AddInteraction(coords, options, distance?)` | Registration ID | Add an automatically named coordinate point. |
| `RemoveInteraction(id)` | Nothing | Remove a registration by its returned ID. |
| `AddPoint(name, coords, data)` | Registration ID | Add or replace a named coordinate point. |
| `RemovePoint(nameOrId)` | Nothing | Remove your named point or registration ID. |
| `AddEntity(entityOrArray, data)` | Last registration ID | Register one or more local entity handles. |
| `RemoveEntity(entityOrArray, labels?)` | Nothing | Remove your entity registrations or selected options. |
| `AddModel(modelOrArray, data)` | Nothing | Register model names or numeric hashes. |
| `RemoveModel(modelOrArray, labels?)` | Nothing | Remove your model registrations or selected options. |
| `AddBone(boneOrArray, data)` | Nothing | Register vehicle bone names. |
| `RemoveBone(boneOrArray, labels?)` | Nothing | Remove your bone registrations or selected options. |
| `AddGlobalPed(data)` | Registration ID | Register nearby non-player peds. |
| `AddGlobalPlayer(data)` | Registration ID | Register other nearby player peds. |
| `AddGlobalVehicle(data)` | Registration ID | Register nearby vehicles. |
| `AddGlobalObject(data)` | Registration ID | Register nearby objects. |
| `RemoveGlobalPed(labels?)` | Nothing | Remove your global ped options. |
| `RemoveGlobalPlayer(labels?)` | Nothing | Remove your global player options. |
| `RemoveGlobalVehicle(labels?)` | Nothing | Remove your global vehicle options. |
| `RemoveGlobalObject(labels?)` | Nothing | Remove your global object options. |
| `SetEnabled(enabled)` | Nothing | Suspend or release your resource's suspension of the interface. |
| `SetPlayerData(snapshot)` | Nothing | Supply a complete player-data snapshot in standalone/custom mode. See framework integration below. |
| `IsActive()` | Boolean | Whether the menu is currently shown, not whether an action succeeded. |

`?` marks an optional argument. `coords` accepts a `vector3` or a table with numeric `x`, `y` and `z`. Registration IDs are opaque strings. Only the resource that registered an interaction can remove it.

`labels` accepts an option name, its label, or an array of either. Omit it to remove the entire matching registration. When adding multiple entities, only the final ID is returned; use `RemoveEntity` with the original array to remove them all.

Entity, model, bone and global registrations merge options by `name` (or `label` when no name is provided) within the calling resource. Adding the same option ID updates that option. Registration settings are updated on each call; include all desired settings when adding more options. Named points replace their entire option list.

### Registration data

| Field | Default | Description |
| --- | --- | --- |
| `options` | Required | Array of interaction options. |
| `distance` | `Config.Distance` | Maximum interaction distance in metres. |
| `drawDistance` | Larger of `Config.DrawDistance` and registration distance | Discovery and hint range. Keep it at least as large as the interaction distance. |
| `offset` | None | Local `vector3` offset for entity/model anchors. Bones use their bone position. |

`AddInteraction` takes the options array and optional distance directly. Use `AddPoint` for additional settings.

### Option fields

| Field | Description |
| --- | --- |
| `label` | Required display string. |
| `name` | Stable option ID; defaults to `label`. |
| `icon` | Font Awesome Free classes, e.g. `fas fa-wrench` or `fa-solid fa-box-open`. See the icon examples below. |
| `num` | Sort order; defaults to the option's array position. Lower values appear first. |
| `distance` | Optional narrower range; cannot exceed the registration range. |
| `action` | Callback `function(entity, data)`. Takes priority over `event`. |
| `event` | Event or command name, interpreted using `type`. |
| `type` | `client` (default), `server`, `command` or `qbcommand`. |
| `job`, `gang` | Required role name or minimum-grade map, e.g. `{ mechanic = 2 }`. |
| `excludejob`, `excludegang` | Hide for a matching role name or minimum-grade map. |
| `jobType`, `excludejobType` | Required/excluded job type: string, string array or map with truthy values. |
| `citizenid` | Allowed citizen ID: string, string array or map with truthy values. |
| `item` | Required item name, array of names, or quantity map such as `{ repairkit = 1, steel = 2 }`. All entries are required; items are not consumed. |
| `required_item` | Alias for `item`; `item` takes precedence. |
| `canInteract` | Callback `function(entity, distance, option)` returning a truthy value to show the option. Errors hide it. Keep this callback lightweight. |
| `hidden` | A truthy value hides the option. |
| `disabled` | Set `true` to show the option as disabled and prevent activation. |

`action` receives a copy of the option with `entity` and current world `coords` added. For coordinate points, `action` receives `nil` as the entity; `canInteract` receives `0`. `canInteract` runs during availability checks, including hint previews outside interaction range, and again before activation.

Client and server events receive the data table with the top-level `action` and `canInteract` callbacks removed. Custom fields sent to a server must be serializable. `command` runs `ExecuteCommand(event)`; `qbcommand` sends the event name and data to `QBCore:CallCommand` when QBCore is active. Without QBCore it uses `Config.CommandHandler`; options using `qbcommand` without an `action` are hidden if no handler is available. Use `command` for ordinary standalone commands.

Filters control client-side availability. Consuming server handlers must validate permissions, inventory, distance and payments themselves. Entity handles in event data are client-local. If the server needs an entity reference, send a network ID from your callback and validate it on the server.

## Font Awesome icons

Each option accepts its own `icon` string:

```lua
options = {
    { label = 'Repair vehicle', icon = 'fas fa-wrench', event = 'my-resource:client:repair' },
    { label = 'Open storage', icon = 'fa-solid fa-box-open', event = 'my-resource:client:storage' },
    { label = 'View ID', icon = 'fa-regular fa-id-card', event = 'my-resource:client:viewId' },
    { label = 'Community', icon = 'fa-brands fa-discord', event = 'my-resource:client:community' },
}
```

Font Awesome **Free 6.7.2** is included with solid, regular and brand fonts. Both the short style prefixes (`fas`, `far`, `fab`) and long names (`fa-solid`, `fa-regular`, `fa-brands`) work. A bare icon class such as `fa-wrench` defaults to solid. Omit `icon` for a text-only option.

Use an icon available in the bundled version and style. Pro-only icons and icons added in later releases are not included; unknown names do not receive a substitute icon. Pass CSS classes, not an HTML `<i>` tag. Existing Font Awesome aliases supplied by the bundled CSS continue to work.

Assets live in `html/vendor/fontawesome`, with upstream licensing in `LICENSE.txt`. The setup follows the [Font Awesome self-hosted webfont documentation](https://docs-v6.fontawesome.com/web/setup/host-yourself/webfonts).

## Framework integration

`Config.Framework` selects the integration:

- `auto` (default): use QBCore if `qb-core` is started; otherwise run standalone. This preserves the existing QBCore city hall integration without changes.
- `standalone`: never access QBCore, even if installed. Works without a framework and provides an API for custom integrations.
- `qbcore`: wait for QBCore and a logged-in character before showing interactions.

Every mode supports coordinate/entity/model/bone/global registrations, callbacks, events, commands, option scrolling, point switching, sprites, icons and the demo. In standalone mode, demo messages use native GTA notifications. QBCore mode retains QBCore notifications and automatic role, inventory, metadata and login checks.

### Custom player data (other frameworks or standalone role systems)

Jobs, gangs, inventories and character identities are not native FiveM concepts. For these filters on another framework, a client integration must translate its data into the following format. Without data, options requiring a role, item or citizen ID remain hidden; unrestricted options still work. Exclusion filters hide only matching roles.

Call this from one dedicated integration resource on character load and whenever its data changes:

```lua
exports['tss-interactions']:SetPlayerData({
    loaded = true,
    citizenid = 'character_123',
    job = { name = 'mechanic', grade = { level = 2 }, type = 'mechanic' },
    gang = { name = 'none', grade = 0 },
    items = {
        { name = 'repairkit', amount = 1 },
        { name = 'steel', amount = 4 },
    },
    metadata = {
        isdead = false,
        inlaststand = false,
        ishandcuffed = false,
    },
})
```

Each call replaces the whole snapshot, so include all current fields. Grades accept a number or `{ level = number }`. Items are a list (or slot-keyed table) of `{ name, amount }` entries. Use your framework's character identifier in `citizenid`; it does not have to be a QBCore ID. This client data controls visibility, not server authorization.

On character logout, clear the data and hide interactions:

```lua
exports['tss-interactions']:SetPlayerData({ loaded = false })
```

Without a snapshot, standalone mode starts ready to interact. For a character-selection screen, send `loaded = false` when your integration starts. Stopping the resource that last supplied data clears it and hides interactions until another snapshot arrives. Re-send your snapshot after `tss-interactions` restarts. `SetPlayerData` is unavailable while the QBCore adapter is active or `Framework = 'qbcore'`.

Use `SetEnabled` for custom busy states. Native death, pause, aiming, NUI focus and the optional vehicle restriction work in every mode; `LocalPlayer.state.inv_busy` is also respected when set.

### Legacy framework commands

Existing QBCore `qbcommand` options keep their original behavior. To support those same options on a custom framework, implement a client handler in `config.lua`:

```lua
Config.CommandHandler = function(name, data)
    -- Your integration must implement this event and validate requests server-side.
    TriggerServerEvent('my-framework:server:interactionCommand', name, data)
end
```

This handler applies only without QBCore. Other frameworks are supported through the player-data API and this hook; no automatic ESX/Qbox/inventory adapters are bundled. If QBCore stops after connecting, interactions stay hidden until it reconnects rather than treating a logged-out character as standalone.

## Configuration

Edit `config.lua`:

| Setting | Default | Purpose |
| --- | --- | --- |
| `Framework` | `'auto'` | Optional QBCore detection, forced `standalone`, or `qbcore`. |
| `CommandHandler` | `nil` | Custom handler for legacy `qbcommand` options without QBCore. |
| `Distance` | `2.5` | Default interaction range in metres. |
| `DrawDistance` | `8.0` | Default discovery and hint range in metres. |
| `DrawSprite` | `true` | Draw white outline rings at nearby, unselected points. Set `false` to hide them. |
| `SpriteSize` | `18.0` | Ring sprite size in screen pixels. |
| `ScanInterval` | `300` | Nearby point/entity scan interval in milliseconds. |
| `OptionInterval` | `100` | Option availability refresh interval in milliseconds. |
| `UiInterval` | `16` | Minimum interval between UI position updates in milliseconds. |
| `SwitchThreshold` | `0.35` | Distance advantage in metres required to switch automatically to another point. |
| `ActionCooldown` | `500` | Minimum time between activations in milliseconds. |
| `DisableInVehicle` | `false` | Hide interactions while in a vehicle. |
| `Controls` | `38 / 15 / 14 / 348` | Interact, previous option, next option and switch point control IDs. |
| `EnableDemoCommand` | `true` | Enable `/test_interact` to toggle two local showcase peds. |
| `Points` | `{}` | Static coordinate registrations owned by this resource. |

The interface displays E, scroll and middle mouse labels. If you change the bindings, update the visible labels in `html/app.js` and `html/index.html` too.

Example static point (your resource must register the event handler):

```lua
Config.Points = {
    {
        name = 'information_desk',
        coords = vector3(307.2, -595.3, 43.3),
        distance = 2.0,
        options = {
            {
                label = 'View information',
                type = 'client',
                event = 'my-resource:client:showInformation',
            },
        },
    },
}
```

## Suspension and lifecycle

The interface hides for native death, weapon aiming, pause or focused NUI, and when the active integration reports a logged-out, dead, last-stand, handcuffed or inventory-busy player. It also hides while its action callback is running and during the action cooldown. E, scroll and middle mouse are claimed while the menu is visible.

For a placement tool, progress flow or custom busy state, explicitly suspend interactions:

```lua
exports['tss-interactions']:SetEnabled(false)
-- Run your resource's flow.
-- Call this when it finishes or is cancelled:
exports['tss-interactions']:SetEnabled(true)
```

Suspension is tracked per calling resource. `true` releases only that resource's suspension; all suspensions must be released before the interface resumes. This is a boolean per resource, not a nested counter.

Registrations and suspensions are removed when their owning resource stops. Restarting `tss-interactions` clears registrations; restart consumer resources afterward or have them register again when it starts. Nothing is persisted to a database.

## Compatibility exports

These names remain available for existing integrations calling **this resource**. They do not replace qb-target or provide its full targeting behavior.

| Export | Behavior |
| --- | --- |
| `AddTargetEntity` / `RemoveTargetEntity` | Aliases for `AddEntity` / `RemoveEntity`. |
| `AddTargetModel` / `RemoveTargetModel` | Aliases for `AddModel` / `RemoveModel`. |
| `AddTargetBone` / `RemoveTargetBone` | Aliases for `AddBone` / `RemoveBone`. |
| `AllowTargeting(enabled)` | Alias for `SetEnabled`. |
| `IsTargetActive()` / `IsTargetSuccess()` | Aliases for `IsActive`; report menu visibility only. |
| `AddCircleZone(name, center, radius, zoneOptions, data)` | Registers a point; ignores radius and zone geometry. |
| `AddBoxZone(name, center, length, width, zoneOptions, data)` | Registers a point; ignores dimensions and zone geometry. |
| `AddEntityZone(name, entity, zoneOptions, data)` | Registers an entity and associates the supplied name for removal; ignores zone geometry. |
| `RemoveZone(nameOrId)` | Alias for `RemovePoint`; also removes entity registrations associated with that zone name. |

`CompatCall(name, owner, ...)` is a legacy bridge hook restricted to calls from a resource named `qb-target`. It is not needed for standalone installation or normal coexistence; use the client exports above for new integrations.
