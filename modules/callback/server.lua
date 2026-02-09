-- Server Callback Module

Bridge = Bridge or {}
Bridge.Callback = {}

-- Helper: Ensure framework is ready
local function EnsureFrameworkReady()
    if Bridge.EnsureReady then
        Bridge.EnsureReady()
    elseif not Bridge.Ready then
        while not Bridge.Framework do
            Wait(100)
        end
    end
end

-- Register a server callback
function Bridge.RegisterCallback(name, callback)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        ESX.RegisterServerCallback(name, callback)
    elseif Bridge.Framework == 'qbcore' then
        QBCore.Functions.CreateCallback(name, callback)
    elseif Bridge.Framework == 'qbox' then
        lib.callback.register(name, callback)
    elseif Bridge.Framework == 'standalone' then
        -- Standalone Callback System
        RegisterNetEvent('bridge:callback:' .. name, function(requestId, ...)
            local _source = source
            local args = {...}

            callback(_source, function(...)
                TriggerClientEvent('bridge:callback:response:' .. requestId, _source, ...)
            end, table.unpack(args))
        end)
    end
end