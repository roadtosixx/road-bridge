-- Client Vehicle Keys Module
--
-- Auto-detects the running vehicle key system (no config needed) and hands
-- out/removes keys through it. Adapter matrix modeled after fmLib
-- (https://github.com/meesvrh/fmLib, adapters/client/keys).
--
-- All Bridge.VehicleKeys functions return true when a supported key system
-- handled the call and false otherwise — callers (e.g. GiveCarKeys in
-- client/clientAPI.lua) use that to fall back to their own custom logic.

Bridge = Bridge or {}
Bridge.VehicleKeys = {}

-- Each adapter: resource name to detect + give/remove/has implementations.
-- Signature: fn(resource, vehicle, plate, model) — vehicle may be 0 when the
-- caller only knows the plate (entity-based systems resolve it via plate scan).
local Adapters = {
    {
        name = 'qb',
        resource = 'qb-vehiclekeys',
        give = function(res, veh, plate)
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
        end,
        remove = function(res, veh, plate)
            TriggerEvent('vehiclekeys:client:RemoveKeys', plate)
        end,
        has = function(res, veh, plate)
            return exports[res]:hasKey(plate)
        end,
    },
    {
        name = 'qbx',
        resource = 'qbx_vehiclekeys',
        needsEntity = true,
        give = function(res, veh)
            exports[res]:GiveKeys(veh)
        end,
        remove = function(res, veh)
            exports[res]:RemoveKeys(veh)
        end,
        has = function(res, veh)
            return exports[res]:HasKeys(veh)
        end,
    },
    {
        name = 'qs',
        resource = 'qs-vehiclekeys',
        give = function(res, veh, plate, model)
            exports[res]:GiveKeys(plate, model, true)
        end,
        remove = function(res, veh, plate, model)
            exports[res]:RemoveKeys(plate, model)
        end,
        has = function(res, veh, plate)
            return exports[res]:GetServerKey(plate)
        end,
    },
    {
        name = 'wasabi',
        resource = 'wasabi_carlock',
        give = function(res, veh, plate)
            exports[res]:GiveKey(plate)
        end,
        remove = function(res, veh, plate)
            exports[res]:RemoveKey(plate)
        end,
        has = function(res, veh, plate)
            return exports[res]:HasKey(plate)
        end,
    },
    {
        name = 'renewed',
        resource = 'Renewed-Vehiclekeys',
        give = function(res, veh, plate)
            exports[res]:addKey(plate)
        end,
        remove = function(res, veh, plate)
            exports[res]:removeKey(plate)
        end,
        has = function(res, veh, plate)
            return exports[res]:hasKey(plate)
        end,
    },
    {
        name = 'fast',
        resource = 'fast-vehiclekeys',
        give = function(res, veh, plate)
            exports[res]:GiveKey(plate)
        end,
    },
    {
        name = 'filo',
        resource = 'filo_vehiclekey',
        give = function(res, veh, plate)
            exports[res]:GiveKeys(plate)
        end,
        remove = function(res, veh, plate)
            exports[res]:RemoveKeys(plate)
        end,
        has = function(res, veh, plate)
            return exports[res]:HasKeys(plate)
        end,
    },
    {
        name = 'is',
        resource = 'is_vehiclekeys',
        give = function(res, veh, plate)
            exports[res]:GiveKey(plate)
        end,
    },
    {
        name = 'mm',
        resource = 'mm_carkeys',
        give = function(res, veh, plate)
            exports[res]:GiveKey(plate)
        end,
        remove = function(res, veh, plate)
            exports[res]:RemoveKey(plate)
        end,
    },
    {
        name = 'mrnewb',
        resource = 'MrNewbVehicleKeys',
        needsEntity = true,
        give = function(res, veh)
            exports[res]:GiveKeys(veh)
        end,
        remove = function(res, veh)
            exports[res]:RemoveKeys(veh)
        end,
        has = function(res, veh)
            return exports[res]:HaveKeys(veh)
        end,
    },
    {
        name = 'tc',
        resource = 'tc_keys',
        needsEntity = true,
        give = function(res, veh)
            exports[res]:GiveKeys(veh)
        end,
        remove = function(res, veh)
            exports[res]:RemoveKeys(veh)
        end,
        has = function(res, veh)
            return exports[res]:HasKeys(veh)
        end,
    },
    {
        name = 'tgiann',
        resource = 'tgiann-hotwire',
        give = function(res, veh, plate)
            exports[res]:GiveKeyPlate(plate, true)
        end,
        has = function(res, veh, plate)
            return exports[res]:HasKeyPlate(plate)
        end,
    },
}

-- Detection is lazy + cached; false = "checked, nothing found" so a server
-- without any key system doesn't rescan on every call.
local detected = nil

local function DetectAdapter()
    if detected ~= nil then
        return detected or nil
    end
    for _, adapter in ipairs(Adapters) do
        if GetResourceState(adapter.resource) == 'started' then
            detected = adapter
            print(('^2[Bridge]^7 Vehicle key system detected: %s (%s)'):format(adapter.name, adapter.resource))
            return adapter
        end
    end
    detected = false
    return nil
end

-- Key resources may start after roadphone — drop the negative cache so the
-- next call rescans, and re-detect if a known key resource just started.
AddEventHandler('onClientResourceStart', function(resourceName)
    if detected == false then
        for _, adapter in ipairs(Adapters) do
            if adapter.resource == resourceName then
                detected = nil
                break
            end
        end
    end
end)

local function TrimPlate(plate)
    return plate and plate:gsub('^%s*(.-)%s*$', '%1') or nil
end

-- Entity-based systems (qbx, mrnewb, tc) need the vehicle handle. When the
-- caller only knows the plate, find the entity in the game pool.
local function FindVehicleByPlate(plate)
    local wanted = TrimPlate(plate)
    if not wanted then return 0 end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if TrimPlate(GetVehicleNumberPlateText(veh)) == wanted then
            return veh
        end
    end
    return 0
end

-- Normalizes the flexible input (entity handle OR plate string) into
-- (vehicle, plate, model) for the adapter call.
local function ResolveVehicle(vehicleOrPlate, model, needsEntity)
    local vehicle, plate = 0, nil

    if type(vehicleOrPlate) == 'number' and vehicleOrPlate ~= 0 and DoesEntityExist(vehicleOrPlate) then
        vehicle = vehicleOrPlate
        plate = GetVehicleNumberPlateText(vehicle)
    elseif type(vehicleOrPlate) == 'string' then
        plate = vehicleOrPlate
        if needsEntity then
            vehicle = FindVehicleByPlate(plate)
        end
    end

    if vehicle ~= 0 and not model then
        model = string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
    end

    return vehicle, plate, model
end

local function CallAdapter(action, vehicleOrPlate, model)
    local adapter = DetectAdapter()
    if not adapter or not adapter[action] then
        return false, nil
    end

    local vehicle, plate, resolvedModel = ResolveVehicle(vehicleOrPlate, model, adapter.needsEntity)
    if not plate and vehicle == 0 then
        return false, nil
    end
    if adapter.needsEntity and vehicle == 0 then
        return false, nil
    end

    local ok, result = pcall(adapter[action], adapter.resource, vehicle, plate, resolvedModel)
    if not ok then
        print(('^1[Bridge]^7 Vehicle key system "%s" call %s failed: %s'):format(adapter.name, action, tostring(result)))
        return false, nil
    end
    return true, result
end

-- Give keys for a vehicle. Accepts an entity handle or a plate string.
-- Returns true when a supported key system handled it.
function Bridge.VehicleKeys.GiveKeys(vehicleOrPlate, model)
    local handled = CallAdapter('give', vehicleOrPlate, model)
    return handled
end

-- Remove keys for a vehicle. Returns true when handled (not every system
-- supports removal — fast/is/tgiann don't).
function Bridge.VehicleKeys.RemoveKeys(vehicleOrPlate, model)
    local handled = CallAdapter('remove', vehicleOrPlate, model)
    return handled
end

-- Whether the player has keys. Returns nil when no system (or the detected
-- one) supports the query, otherwise the system's boolean-ish answer.
function Bridge.VehicleKeys.HasKeys(vehicleOrPlate)
    local handled, result = CallAdapter('has', vehicleOrPlate)
    if not handled then return nil end
    return result
end

-- Detected system name ('qb', 'qs', ...) or nil.
function Bridge.VehicleKeys.GetSystem()
    local adapter = DetectAdapter()
    return adapter and adapter.name or nil
end
