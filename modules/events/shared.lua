-- Shared Events Module
-- Maps common events to framework-specific event names

Bridge = Bridge or {}
Bridge.Events = {}

-- Event name mappings for different frameworks.
-- Values may be strings (same on server & client) or { server = ..., client = ... }
-- when the framework uses different event names per side.
local EventMappings = {
    -- Player Lifecycle Events
    -- NOTE on Qbox: qbx_core does NOT introduce a `qbx_core:client:playerLoaded`
    -- event — it only fires the QBCore-compat names. Server-side it triggers
    -- `QBCore:Server:OnPlayerLoaded`, client-side `QBCore:Client:OnPlayerLoaded`.
    -- Sources: qbx_core/client/character.lua, qbx_core/server/player.lua.
    PlayerLoaded = {
        esx = 'esx:playerLoaded',
        qbcore = { server = 'QBCore:Server:OnPlayerLoaded', client = 'QBCore:Client:OnPlayerLoaded' },
        qbox   = { server = 'QBCore:Server:OnPlayerLoaded', client = 'QBCore:Client:OnPlayerLoaded' },
        standalone = 'playerLoaded' -- Custom event for standalone
    },

    PlayerUnload = {
        esx = 'esx:onPlayerLogout',
        qbcore = { server = 'QBCore:Server:OnPlayerUnload', client = 'QBCore:Client:OnPlayerUnload' },
        qbox   = { server = 'QBCore:Server:OnPlayerUnload', client = 'QBCore:Client:OnPlayerUnload' },
        standalone = 'playerUnload'
    },

    PlayerSpawn = {
        esx = 'esx:onPlayerSpawn',
        qbcore = 'QBCore:Client:OnPlayerSpawn',
        qbox = nil, -- qbx_core has no spawn event; consumers should use PlayerLoaded
        standalone = 'playerSpawn'
    },

    PlayerDeath = {
        esx = 'esx:onPlayerDeath',
        qbcore = 'QBCore:Client:OnPlayerDied',
        qbox = 'baseevents:onPlayerDied', -- qbx_core fires no death event; baseevents is FiveM-standard
        standalone = 'playerDeath'
    },

    -- Job Events
    JobUpdate = {
        esx = 'esx:setJob',
        qbcore = 'QBCore:Client:OnJobUpdate',
        qbox = 'qbx_core:client:onJobUpdate',
        standalone = 'jobUpdate'
    },

    -- Money Events
    MoneyChange = {
        esx = 'esx:onMoneyChange',
        qbcore = 'QBCore:Player:SetPlayerData',
        qbox = 'QBCore:Client:OnMoneyChange', -- qbx_core fires the QBCore-compat name only
        standalone = 'moneyChange'
    },

    -- Gang Events (QBCore/Qbox specific)
    GangUpdate = {
        esx = nil, -- ESX doesn't have gangs by default
        qbcore = 'QBCore:Client:OnGangUpdate',
        qbox = 'qbx_core:client:onGangUpdate',
        standalone = 'gangUpdate'
    },

    -- Inventory Events
    InventoryUpdate = {
        esx = 'esx:addInventoryItem',
        qbcore = 'QBCore:Player:SetPlayerData',
        qbox = 'qbx_core:client:onInventoryUpdate',
        standalone = 'inventoryUpdate'
    },

    -- Vehicle Events
    VehicleSpawned = {
        esx = 'esx:vehicleSpawned',
        qbcore = 'QBCore:Client:VehicleSpawned',
        qbox = 'qbx_core:client:vehicleSpawned',
        standalone = 'vehicleSpawned'
    }
}

-- Get event name for current framework. `side` overrides the auto-detected
-- side for split-mapping events (used by TriggerClient/TriggerServer to pick
-- the target side rather than the caller's side).
function Bridge.Events.Get(eventKey, side)
    -- Wait for framework initialization
    if not Bridge.Ready then
        if Bridge.WaitForReady then
            Bridge.WaitForReady()
        else
            -- Fallback if WaitForReady is not yet defined
            while not Bridge.Framework do
                Wait(100)
            end
        end
    end

    local mapping = EventMappings[eventKey]
    if not mapping then
        print('^3[Bridge Events]^7 Warning: Unknown event key "' .. tostring(eventKey) .. '"')
        return eventKey -- Return the key itself as fallback
    end

    local entry = mapping[Bridge.Framework]
    -- Resolve { server = ..., client = ... } shape based on requested side.
    if type(entry) == 'table' then
        local resolved = side or (IsDuplicityVersion() and 'server' or 'client')
        entry = entry[resolved]
    end
    if not entry then
        print('^3[Bridge Events]^7 Warning: Event "' .. eventKey .. '" not available for framework "' .. Bridge.Framework .. '"')
        return nil
    end

    return entry
end

-- Register an event listener using framework-agnostic event name
function Bridge.Events.On(eventKey, callback)
    local eventName = Bridge.Events.Get(eventKey)
    if eventName then
        AddEventHandler(eventName, callback)
        return true
    end
    return false
end

function Bridge.Events.OnNet(eventKey, callback)
    local eventName = Bridge.Events.Get(eventKey)
    if eventName then
        RegisterNetEvent(eventName, callback)
        return true
    end
    return false
end


-- Trigger an event using framework-agnostic event name (client-side)
function Bridge.Events.Trigger(eventKey, ...)
    local eventName = Bridge.Events.Get(eventKey)
    if eventName then
        TriggerEvent(eventName, ...)
        return true
    end
    return false
end

-- Trigger a server event using framework-agnostic event name (client-side)
function Bridge.Events.TriggerServer(eventKey, ...)
    local eventName = Bridge.Events.Get(eventKey, 'server')
    if eventName then
        TriggerServerEvent(eventName, ...)
        return true
    end
    return false
end

-- Trigger a client event using framework-agnostic event name (server-side)
function Bridge.Events.TriggerClient(source, eventKey, ...)
    local eventName = Bridge.Events.Get(eventKey, 'client')
    if eventName then
        TriggerClientEvent(eventName, source, ...)
        return true
    end
    return false
end

-- Add custom event mapping (useful for addons)
function Bridge.Events.AddMapping(eventKey, frameworkMappings)
    if EventMappings[eventKey] then
        print('^3[Bridge Events]^7 Warning: Overwriting existing event mapping "' .. eventKey .. '"')
    end
    EventMappings[eventKey] = frameworkMappings
end

-- Get all mappings (for debugging)
function Bridge.Events.GetAllMappings()
    return EventMappings
end

-- List all available event keys
function Bridge.Events.GetAvailableEvents()
    local events = {}
    for key, _ in pairs(EventMappings) do
        table.insert(events, key)
    end
    return events
end
