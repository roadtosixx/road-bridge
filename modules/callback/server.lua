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
        -- ox_lib uses return-values, but the bridge contract is cb-style.
        -- Wrap so registered handlers can keep calling cb(...) (sync or async)
        -- and we forward the captured values as ox_lib's return.
        lib.callback.register(name, function(source, ...)
            local p = promise.new()
            local ok, err = pcall(callback, source, function(...)
                p:resolve(table.pack(...))
            end, ...)
            if not ok then
                print('^1[Bridge Callback]^7 Error in callback "' .. name .. '": ' .. tostring(err))
                p:resolve(table.pack(nil))
            end
            local result = Citizen.Await(p)
            return table.unpack(result, 1, result.n)
        end)
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