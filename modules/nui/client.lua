-- ============================================================================
-- Bridge NUI Module (client)
-- ============================================================================
-- Shared helpers for the two boilerplate patterns that repeat across every
-- client app file:
--   1. Server -> NUI relays  (RegisterNetEvent + SendNUIMessage)
--   2. NUI  -> server proxies (RegisterNUICallback + Bridge.TriggerCallback)
--
-- These generalise the hand-written `forward()` (client/games.lua) and
-- `proxyCallback()` (client/darkchat.lua) helpers so apps don't redefine them.

Bridge = Bridge or {}
Bridge.NUI = {}

-- Thin SendNUIMessage wrapper. Sends { event = nuiEvent, <payload fields> }.
function Bridge.NUI.Send(nuiEvent, payload)
    payload = payload or {}
    payload.event = nuiEvent
    SendNUIMessage(payload)
end

-- Server -> NUI relay. Forwards a single server-event argument to NUI under
-- `key` (default 'data'), i.e. SendNUIMessage({ event = nuiEvent, [key] = arg }).
-- Replaces the recurring:
--   RegisterNetEvent('srv:event')
--   AddEventHandler('srv:event', function(p) SendNUIMessage({ event='x', data=p }) end)
function Bridge.NUI.Relay(serverEvent, nuiEvent, key)
    key = key or 'data'
    RegisterNetEvent(serverEvent, function(payload)
        SendNUIMessage({ event = nuiEvent, [key] = payload })
    end)
end

-- NUI -> server callback proxy. Returns a RegisterNUICallback handler that
-- forwards data[keys...] as ordered arguments to the server callback `serverCb`
-- and passes the server's first return value straight back to NUI. Falls back
-- to { ok = false, error = 'no_response' } when the server doesn't respond.
-- Replaces the per-callback boilerplate in games.lua / darkchat.lua / etc.
function Bridge.NUI.Proxy(serverCb, ...)
    local keys = { ... }
    local n = select('#', ...)
    return function(data, cb)
        local args = {}
        for i = 1, n do
            if data ~= nil then
                args[i] = data[keys[i]]
            end
        end
        Bridge.TriggerCallback(serverCb, function(result)
            cb(result or { ok = false, error = 'no_response' })
        end, table.unpack(args, 1, n))
    end
end
