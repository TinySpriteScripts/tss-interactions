Config = {}
Config.Framework = 'auto' -- auto: optional QBCore detection; standalone: custom/no framework; qbcore: require QBCore login
Config.CommandHandler = nil -- optional function(name, data) for legacy qbcommand options without QBCore
Config.Distance = 2.5 -- default interaction range, in metres (3D distance)
Config.DrawDistance = 8.0 -- nearby point discovery and sprite range, in metres
Config.DrawSprite = true -- show a white outline ring at nearby, unselected interaction points
Config.SpriteSize = 18.0 -- ring sprite size in screen pixels
Config.ScanInterval = 300 -- nearby entity/point discovery, milliseconds
Config.OptionInterval = 100 -- permission and canInteract refresh, milliseconds
Config.UiInterval = 16 -- screen position refresh; never takes mouse focus
Config.SwitchThreshold = 0.35 -- another point must be this much closer to auto-switch
Config.ActionCooldown = 500
Config.DisableInVehicle = false
Config.Controls = { interact = 38, previous = 15, next = 14, switch = 348 } -- E, wheel up/down, middle mouse button
Config.Points = {} -- optional static definitions: { name = 'example', coords = vector3(...), options = {...}, distance = 2.5 }

Config.EnableDemoCommand = true -- /test_interact toggles two local showcase peds
