-- Bridge Helper Functions
-- Common utility functions for all bridge modules

Bridge = Bridge or {}

-- ============================================================================
-- WAITING
-- ----------------------------------------------------------------------------
-- Every wait in this resource goes through here. Hand-written
-- `while not x do Wait(50) end` loops are what they replace, and those had one
-- flaw in common: no deadline. A framework that never loaded, an inventory that
-- never detected, a model that cannot stream — each of them parked a thread
-- forever, and the symptom was always the same silent nothing.
--
-- Uses ox_lib when it is available (it is a dependency), but never depends on
-- it: the fallback is a plain polling loop, so the bridge keeps working if the
-- resource is missing or the API changes.
-- ============================================================================

--- Poll `check` until it returns a non-nil/true value.
--- @param check function   called repeatedly; any non-nil, non-false result ends the wait
--- @param timeout number?   milliseconds, default 15000. Pass false to wait forever.
--- @param label string?     shown in the timeout warning
--- @return boolean ok, any value
function Bridge.WaitFor(check, timeout, label)
    if type(check) ~= 'function' then return false end

    local result = check()
    if result then return true, result end

    if timeout == nil then timeout = 15000 end

    if lib and lib.waitFor then
        local ok, value = pcall(lib.waitFor, function()
            return check() or nil
        end, label or 'Bridge.WaitFor timed out', timeout)

        if ok then return true, value end
    else
        local deadline = timeout and (GetGameTimer() + timeout) or nil
        while true do
            result = check()
            if result then return true, result end
            if deadline and GetGameTimer() >= deadline then break end
            Wait(50)
        end
    end

    if label then
        print(('^3[Bridge] Timed out waiting for: %s^7'):format(label))
    end

    return false
end

--- Wait until the framework has been detected.
function Bridge.EnsureReady()
    if Bridge.Ready then return true end

    if Bridge.WaitForReady then
        Bridge.WaitForReady()
        return true
    end

    return (Bridge.WaitFor(function() return Bridge.Framework end, 15000, 'framework detection'))
end

--- Wait until framework AND inventory detection are done.
--- The single guard every inventory operation should use.
function Bridge.EnsureInventoryReady()
    if Bridge.Inventory and Bridge.Inventory.Ready then return true end

    Bridge.EnsureReady()

    return (Bridge.WaitFor(function()
        return Bridge.Inventory and Bridge.Inventory.Ready
    end, 15000, 'inventory detection'))
end

-- ============================================================================
-- STREAMING (client only)
-- ----------------------------------------------------------------------------
-- Models and animation dictionaries that cannot load are a fact of life —
-- deleted addon cars, typos in a config, missing stream assets. Asking for them
-- must never cost more than the timeout.
-- ============================================================================

if not IsDuplicityVersion() then
    --- Request a model and report whether it is usable.
    --- @return boolean loaded
    function Bridge.RequestModel(model, timeout)
        if type(model) == 'string' then model = GetHashKey(model) end
        if not model or not IsModelValid(model) then return false end
        if HasModelLoaded(model) then return true end

        if lib and lib.requestModel then
            pcall(lib.requestModel, model, timeout or 10000)
        else
            RequestModel(model)
            Bridge.WaitFor(function() return HasModelLoaded(model) end, timeout or 10000)
        end

        return HasModelLoaded(model)
    end

    --- Request an animation dictionary and report whether it is usable.
    --- @return boolean loaded
    function Bridge.RequestAnimDict(dict, timeout)
        if type(dict) ~= 'string' or dict == '' then return false end
        if HasAnimDictLoaded(dict) then return true end

        if lib and lib.requestAnimDict then
            pcall(lib.requestAnimDict, dict, timeout or 5000)
        else
            RequestAnimDict(dict)
            Bridge.WaitFor(function() return HasAnimDictLoaded(dict) end, timeout or 5000)
        end

        return HasAnimDictLoaded(dict)
    end
end
