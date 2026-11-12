local Callback = Bridge.Callback
local pending = {}
local sequence = 0
local session = ('%s:%s'):format(GetGameTimer(), math.random(0, 2147483647))

RegisterNetEvent(Callback.EventPrefix .. 'response', function(requestId, ...)
    if type(requestId) ~= 'string' then return end
    local respond = pending[requestId]
    if respond then respond(...) end
end)

local function send(name, respond, ...)
    if Bridge.Framework == 'esx' then
        ESX.TriggerServerCallback(name, respond, ...)
    elseif Bridge.Framework == 'qbcore' then
        QBCore.Functions.TriggerCallback(name, respond, ...)
    elseif Bridge.Framework == 'qbox' then
        lib.callback(name, false, respond, ...)
    else
        error('Unsupported callback framework: ' .. tostring(Bridge.Framework))
    end
end

function Bridge.TriggerCallback(name, callback, ...)
    if not Bridge.EnsureReady() then
        callback(nil)
        return
    end

    local respond
    if Bridge.Framework == 'standalone' then
        sequence = sequence + 1
        local requestId = session .. ':' .. sequence
        respond = Callback.Once(function(...)
            pending[requestId] = nil
            callback(...)
        end, Callback.Timeout, name)
        pending[requestId] = respond
        local ok, err = pcall(TriggerServerEvent, Callback.EventPrefix .. 'request:' .. name, requestId, ...)
        if ok then return end
        print(('^1[Bridge Callback]^7 Could not trigger "%s": %s'):format(name, tostring(err)))
    else
        respond = Callback.Once(callback)
        local ok, err = pcall(send, name, respond, ...)
        if ok then return end
        print(('^1[Bridge Callback]^7 Could not trigger "%s": %s'):format(name, tostring(err)))
    end
    respond(nil)
end
