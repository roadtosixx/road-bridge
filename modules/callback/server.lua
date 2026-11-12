local Callback = Bridge.Callback

local function invoke(name, handler, source, respond, ...)
    local ok, err = pcall(handler, source, respond, ...)
    if not ok then
        print(('^1[Bridge Callback]^7 Error in callback "%s": %s'):format(name, tostring(err)))
        respond(nil)
    end
end

local function wrap(name, handler)
    return function(source, callback, ...)
        invoke(name, handler, source, Callback.Once(callback), ...)
    end
end

function Bridge.RegisterCallback(name, callback)
    if not Bridge.EnsureReady() then return false end

    if Bridge.Framework == 'esx' then
        ESX.RegisterServerCallback(name, wrap(name, callback))
    elseif Bridge.Framework == 'qbcore' then
        QBCore.Functions.CreateCallback(name, wrap(name, callback))
    elseif Bridge.Framework == 'qbox' then
        lib.callback.register(name, function(source, ...)
            local pending = promise.new()
            local respond = Callback.Once(function(...)
                pending:resolve(table.pack(...))
            end, Callback.Timeout, name)
            invoke(name, callback, source, respond, ...)
            local result = Citizen.Await(pending)
            return table.unpack(result, 1, result.n)
        end)
    elseif Bridge.Framework == 'standalone' then
        RegisterNetEvent(Callback.EventPrefix .. 'request:' .. name, function(requestId, ...)
            local src = source
            if type(requestId) ~= 'string' or #requestId == 0 or #requestId > 96 then return end
            local respond = Callback.Once(function(...)
                TriggerClientEvent(Callback.EventPrefix .. 'response', src, requestId, ...)
            end)
            invoke(name, callback, src, respond, ...)
        end)
    else
        return false
    end
    return true
end
