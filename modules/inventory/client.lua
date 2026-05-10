-- Client-side Inventory System Detection
-- Mirrors server-side Bridge.Inventory.System so client code can branch on
-- the active inventory system without reading Config.InventorySystem (which
-- is unreliable since the new default is 'auto').

Bridge = Bridge or {}
Bridge.Inventory = Bridge.Inventory or {}
Bridge.Inventory.System = nil
Bridge.Inventory.Ready = false

local DetectionCandidates = {
    { resource = 'ox_inventory',     name = 'ox_inventory' },
    { resource = 'jaksam_inventory', name = 'jaksam' },
    { resource = 'qb-inventory',     name = 'qb-inventory' },
    { resource = 'qs-inventory',     name = 'qs-inventory' },
    { resource = 'codem-inventory',  name = 'codem' },
    { resource = 'core_inventory',   name = 'core_inventory' },
}

function Bridge.Inventory.DetectSystem()
    local override = Config and Config.InventorySystem
    if override and override ~= '' and override ~= 'auto' then
        Bridge.Inventory.System = override
        Bridge.Inventory.Ready = true
        return
    end

    for _, c in ipairs(DetectionCandidates) do
        if GetResourceState(c.resource) == 'started' then
            Bridge.Inventory.System = c.name
            Bridge.Inventory.Ready = true
            return
        end
    end

    -- No standalone inventory detected. Leave System nil so callers can
    -- handle the fallback themselves (server has framework-native fallback,
    -- client typically just skips inventory-specific behavior).
    Bridge.Inventory.Ready = true
end

CreateThread(function()
    -- Wait for config.lua (loaded as shared_script after this client.lua).
    while not Config do Wait(50) end
    Bridge.Inventory.DetectSystem()
end)
