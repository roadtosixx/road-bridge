-- Server Inventory Module

Bridge = Bridge or {}
Bridge.Inventory = {}
Bridge.Inventory.System = nil
Bridge.Inventory.Ready = false

-- ============================================================================
-- AUTO-DETECTION
-- ============================================================================

local DetectionCandidates = {
    { resource = 'ox_inventory',    name = 'ox_inventory' },
    { resource = 'jaksam_inventory', name = 'jaksam' },
    { resource = 'qb-inventory',    name = 'qb-inventory' },
    { resource = 'qs-inventory',    name = 'qs-inventory' },
    { resource = 'codem-inventory', name = 'codem' },
    { resource = 'core_inventory',  name = 'core_inventory' },
}

function Bridge.Inventory.DetectSystem()
    local override = Config and Config.InventorySystem
    if override and override ~= '' and override ~= 'auto' then
        Bridge.Inventory.System = override
        print('^3[Bridge Inventory]^7 Using configured system: ' .. tostring(override) .. ' (auto-detection skipped)')
        Bridge.Inventory.Ready = true
        return
    end

    for _, c in ipairs(DetectionCandidates) do
        if GetResourceState(c.resource) == 'started' then
            Bridge.Inventory.System = c.name
            print('^2[Bridge Inventory]^7 ' .. c.name .. ' detected')
            Bridge.Inventory.Ready = true
            return
        end
    end

    Bridge.Inventory.System = Bridge.Framework or 'standalone'
    print('^3[Bridge Inventory]^7 No standalone inventory detected, falling back to framework-native (' .. Bridge.Inventory.System .. ')')
    Bridge.Inventory.Ready = true
end

CreateThread(function()
    while not Bridge.Framework do Wait(50) end
    Bridge.Inventory.DetectSystem()
end)

-- Helper: Ensure framework + inventory are ready
local function EnsureReady()
    if Bridge.EnsureReady then
        Bridge.EnsureReady()
    elseif not Bridge.Ready then
        while not Bridge.Framework do Wait(50) end
    end
    while not Bridge.Inventory.Ready do Wait(50) end
end

-- Helper: get the active inventory system (after detection)
local function System()
    return Bridge.Inventory.System
end

-- Helper: framework-native fallback for non-ox/non-jaksam systems
local function FrameworkNative()
    return Bridge.Framework
end

-- Helper: resolve a QB-style player object across qbcore/qbox without relying on
-- the qb-core compat layer (qbx_core's Player object preserves Functions.* for compat).
local function GetQBLikePlayer(source)
    if Bridge.Framework == 'qbox' then
        return exports.qbx_core:GetPlayer(source)
    elseif Bridge.Framework == 'qbcore' and Bridge.FrameworkObject then
        return Bridge.FrameworkObject.Functions.GetPlayer(source)
    end
    return nil
end

-- ============================================================================
-- CORE OPERATIONS
-- ============================================================================

-- Give player an item
function Bridge.Inventory.AddItem(source, item, count, metadata)
    EnsureReady()
    count = count or 1
    metadata = metadata or {}

    local sys = System()

    if sys == 'ox_inventory' then
        local success = pcall(function()
            exports.ox_inventory:AddItem(source, item, count, metadata)
        end)
        return success
    elseif sys == 'jaksam' then
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:addItem(source, item, count, metadata)
        end)
        return success and ok or false
    elseif sys == 'codem' then
        local success = pcall(function()
            exports['codem-inventory']:AddItem(source, item, count, nil, metadata)
        end)
        return success
    elseif sys == 'qb-inventory' then
        local success, ok = pcall(function()
            return exports['qb-inventory']:AddItem(source, item, count, false, metadata, 'roadphone')
        end)
        return success and ok or false
    end

    -- Framework-native fallback (esx / qbcore / qs-inventory / core_inventory)
    local fw = FrameworkNative()
    if fw == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addInventoryItem(item, count, metadata)
            return true
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = GetQBLikePlayer(source)
        if player then
            return player.Functions.AddItem(item, count, nil, metadata)
        end
    elseif fw == 'standalone' then
        print('[Bridge] Standalone: AddItem not implemented')
        return false
    end
    return false
end

-- Remove item from player
function Bridge.Inventory.RemoveItem(source, item, count, metadata)
    EnsureReady()
    count = count or 1
    metadata = metadata or {}

    local sys = System()

    if sys == 'ox_inventory' then
        local success = pcall(function()
            exports.ox_inventory:RemoveItem(source, item, count, metadata)
        end)
        return success
    elseif sys == 'jaksam' then
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:removeItem(source, item, count, metadata)
        end)
        return success and ok or false
    elseif sys == 'codem' then
        local success = pcall(function()
            exports['codem-inventory']:RemoveItem(source, item, count)
        end)
        return success
    elseif sys == 'qb-inventory' then
        local success, ok = pcall(function()
            return exports['qb-inventory']:RemoveItem(source, item, count, false, 'roadphone')
        end)
        return success and ok or false
    end

    local fw = FrameworkNative()
    if fw == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(item, count)
            return true
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = GetQBLikePlayer(source)
        if player then
            return player.Functions.RemoveItem(item, count, nil, metadata)
        end
    elseif fw == 'standalone' then
        print('[Bridge] Standalone: RemoveItem not implemented')
        return false
    end
    return false
end

-- Get item count
function Bridge.Inventory.GetItemCount(source, item)
    EnsureReady()

    local sys = System()

    if sys == 'ox_inventory' then
        local success, count = pcall(function()
            return exports.ox_inventory:GetItemCount(source, item)
        end)
        return success and count or 0
    elseif sys == 'jaksam' then
        local success, total = pcall(function()
            return exports['jaksam_inventory']:getTotalItemAmount(source, item)
        end)
        return success and (total or 0) or 0
    elseif sys == 'codem' then
        local success, total = pcall(function()
            return exports['codem-inventory']:GetItemsTotalAmount(source, item)
        end)
        return success and (total or 0) or 0
    elseif sys == 'qb-inventory' then
        local success, total = pcall(function()
            return exports['qb-inventory']:GetItemCount(source, item)
        end)
        return success and (total or 0) or 0
    end

    local fw = FrameworkNative()
    if fw == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            local invItem = xPlayer.getInventoryItem(item)
            return invItem and invItem.count or 0
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = GetQBLikePlayer(source)
        if player then
            local invItem = player.Functions.GetItemByName(item)
            return invItem and invItem.amount or 0
        end
    end
    return 0
end

-- Check if player has item
function Bridge.Inventory.HasItem(source, item, count)
    EnsureReady()
    count = count or 1

    local sys = System()
    if sys == 'jaksam' then
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:hasItem(source, item, count)
        end)
        if success then return ok and true or false end
    elseif sys == 'codem' then
        local success, ok = pcall(function()
            return exports['codem-inventory']:HasItem(source, item, count)
        end)
        if success then return ok and true or false end
    elseif sys == 'qb-inventory' then
        local success, ok = pcall(function()
            return exports['qb-inventory']:HasItem(source, item, count)
        end)
        if success then return ok and true or false end
    end

    return Bridge.Inventory.GetItemCount(source, item) >= count
end

-- Get item from player
function Bridge.Inventory.GetItem(source, item)
    EnsureReady()

    local sys = System()

    if sys == 'ox_inventory' then
        local success, itemData = pcall(function()
            return exports.ox_inventory:GetItem(source, item)
        end)
        return success and itemData or nil
    elseif sys == 'jaksam' then
        local success, itemData = pcall(function()
            return exports['jaksam_inventory']:getItemByName(source, item)
        end)
        return success and itemData or nil
    elseif sys == 'codem' then
        local success, itemData = pcall(function()
            return exports['codem-inventory']:GetItemByName(source, item)
        end)
        return success and itemData or nil
    elseif sys == 'qb-inventory' then
        local success, itemData = pcall(function()
            return exports['qb-inventory']:GetItemByName(source, item)
        end)
        return success and itemData or nil
    end

    local fw = FrameworkNative()
    if fw == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getInventoryItem(item)
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = GetQBLikePlayer(source)
        if player then
            return player.Functions.GetItemByName(item)
        end
    end
    return nil
end

-- Get entire inventory
function Bridge.Inventory.GetInventory(source)
    EnsureReady()

    local sys = System()

    if sys == 'ox_inventory' then
        local success, inventory = pcall(function()
            return exports.ox_inventory:GetInventory(source)
        end)
        return success and inventory or {}
    end

    local fw = FrameworkNative()
    if fw == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getInventory()
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = GetQBLikePlayer(source)
        if player then
            return player.PlayerData.items or {}
        end
    end
    return {}
end

-- Set item metadata (slot-based)
function Bridge.Inventory.SetItemMetadata(source, item, slot, metadata)
    EnsureReady()

    local sys = System()

    if sys == 'ox_inventory' then
        local success = pcall(function()
            exports.ox_inventory:SetMetadata(source, slot, metadata)
        end)
        return success
    elseif sys == 'jaksam' then
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:setItemMetadataInSlot(source, slot, metadata)
        end)
        return success and ok or false
    elseif sys == 'codem' then
        local success = pcall(function()
            exports['codem-inventory']:SetItemMetadata(source, slot, metadata)
        end)
        return success
    elseif sys == 'qb-inventory' then
        local success, ok = pcall(function()
            return exports['qb-inventory']:SetItemData(source, item, 'info', metadata, slot)
        end)
        return success and (ok ~= false)
    end

    local fw = FrameworkNative()
    if fw == 'qbcore' or fw == 'qbox' then
        local player = GetQBLikePlayer(source)
        if player then
            local invItem = player.Functions.GetItemBySlot(slot)
            if invItem then
                invItem.info = metadata
                return true
            end
        end
    end
    return false
end

-- Can carry item (weight/slots check)
function Bridge.Inventory.CanCarryItem(source, item, count)
    EnsureReady()
    count = count or 1

    local sys = System()

    if sys == 'ox_inventory' then
        local success, canCarry = pcall(function()
            return exports.ox_inventory:CanCarryItem(source, item, count)
        end)
        return success and canCarry or false
    elseif sys == 'jaksam' then
        local success, canCarry = pcall(function()
            return exports['jaksam_inventory']:canCarryItem(source, item, count)
        end)
        return success and canCarry or false
    elseif sys == 'qb-inventory' then
        local success, canCarry = pcall(function()
            return exports['qb-inventory']:CanAddItem(source, item, count)
        end)
        return success and canCarry or false
    end

    local fw = FrameworkNative()
    if fw == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.canCarryItem(item, count)
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        return true -- QBCore has no direct canCarryItem
    elseif fw == 'standalone' then
        return true
    end
    return false
end

-- ============================================================================
-- METADATA FUNCTIONS (for inventory-system-specific metadata)
-- ============================================================================

-- Get item with metadata (inventory-system-specific)
function Bridge.Inventory.GetItemWithMetadata(source, itemName, metadataFilter)
    EnsureReady()

    local inventorySystem = System()

    if inventorySystem == 'ox_inventory' then
        local success, items = pcall(function()
            return exports.ox_inventory:Search(source, 'slots', itemName)
        end)

        if success and items then
            if metadataFilter then
                for _, item in pairs(items) do
                    if item.metadata then
                        local matches = true
                        for key, value in pairs(metadataFilter) do
                            if tostring(item.metadata[key]) ~= tostring(value) then
                                matches = false
                                break
                            end
                        end
                        if matches then
                            return item, item.slot
                        end
                    end
                end
            else
                for _, item in pairs(items) do
                    return item, item.slot
                end
            end
        end
    elseif inventorySystem == 'jaksam' then
        local success, items = pcall(function()
            return exports['jaksam_inventory']:getItemsByName(source, itemName, metadataFilter)
        end)
        if success and items then
            for _, item in ipairs(items) do
                if item then
                    return item, item.slot
                end
            end
        end

    elseif inventorySystem == 'codem' then
        local success, items = pcall(function()
            return exports['codem-inventory']:GetItemsByName(source, itemName)
        end)
        if success and items and type(items) == 'table' then
            if metadataFilter then
                for _, item in pairs(items) do
                    local meta = item.metadata or item.info
                    if meta then
                        local matches = true
                        for key, value in pairs(metadataFilter) do
                            if tostring(meta[key]) ~= tostring(value) then
                                matches = false
                                break
                            end
                        end
                        if matches then
                            return item, item.slot
                        end
                    end
                end
            else
                for _, item in pairs(items) do
                    return item, item.slot
                end
            end
        end
    elseif inventorySystem == 'qb-inventory' then
        local success, items = pcall(function()
            return exports['qb-inventory']:GetItemsByName(source, itemName)
        end)
        if success and items and type(items) == 'table' then
            if metadataFilter then
                for _, item in pairs(items) do
                    local meta = item.info or item.metadata
                    if meta then
                        local matches = true
                        for key, value in pairs(metadataFilter) do
                            if tostring(meta[key]) ~= tostring(value) then
                                matches = false
                                break
                            end
                        end
                        if matches then
                            return item, item.slot
                        end
                    end
                end
            else
                for _, item in pairs(items) do
                    return item, item.slot
                end
            end
        end
    elseif inventorySystem == 'core_inventory' then
        local success, items = pcall(function()
            return exports['core_inventory']:getItems(source, itemName)
        end)
        if success and items and type(items) == 'table' then
            if metadataFilter then
                for _, item in pairs(items) do
                    if item.metadata then
                        local matches = true
                        for key, value in pairs(metadataFilter) do
                            if tostring(item.metadata[key]) ~= tostring(value) then
                                matches = false
                                break
                            end
                        end
                        if matches then
                            return item, item.slot
                        end
                    end
                end
            else
                for _, item in pairs(items) do
                    return item, item.slot
                end
            end
        end
    end

    return nil, nil
end

-- Get ALL items of a name with normalised metadata.
-- Used by phone_cache to find every phone item a player owns (multi-phone).
-- Returns: array of { slot, name, metadata } across all detected systems.
function Bridge.Inventory.GetAllItemsByName(source, itemName)
    EnsureReady()

    local sys = System()
    local results = {}

    local function push(slot, name, meta)
        if slot == nil then return end
        results[#results + 1] = {
            slot = slot,
            name = name or itemName,
            metadata = meta or {},
        }
    end

    if sys == 'ox_inventory' then
        local ok, items = pcall(function()
            return exports.ox_inventory:Search(source, 'slots', itemName)
        end)
        if ok and items then
            for _, item in pairs(items) do
                push(item.slot, item.name, item.metadata)
            end
        end
    elseif sys == 'jaksam' then
        local ok, items = pcall(function()
            return exports['jaksam_inventory']:getItemsByName(source, itemName)
        end)
        if ok and items and type(items) == 'table' then
            for slotKey, item in pairs(items) do
                if item then
                    -- jaksam keys by slot id; fall back to item.slot
                    push(item.slot or slotKey, item.name, item.metadata)
                end
            end
        end
    elseif sys == 'codem' then
        local ok, items = pcall(function()
            return exports['codem-inventory']:GetItemsByName(source, itemName)
        end)
        if ok and items and type(items) == 'table' then
            for _, item in pairs(items) do
                push(item.slot, item.name, item.metadata or item.info)
            end
        end
    elseif sys == 'qb-inventory' then
        local ok, items = pcall(function()
            return exports['qb-inventory']:GetItemsByName(source, itemName)
        end)
        if ok and items and type(items) == 'table' then
            for _, item in pairs(items) do
                push(item.slot, item.name, item.info or item.metadata)
            end
        end
    elseif sys == 'core_inventory' then
        local ok, items = pcall(function()
            return exports['core_inventory']:getItems(source, itemName)
        end)
        if ok and items and type(items) == 'table' then
            for _, item in pairs(items) do
                push(item.slot, item.name, item.metadata)
            end
        end
    else
        -- Framework-native fallback (esx / qbcore / qs-inventory): scan inventory
        local inventory = Bridge.Inventory.GetInventory(source)
        if inventory and type(inventory) == 'table' then
            for _, item in pairs(inventory) do
                if item and (item.name == itemName) then
                    push(item.slot, item.name, item.metadata or item.info)
                end
            end
        end
    end

    return results
end

-- Get item from specific slot (returns full item data or nil if not found)
function Bridge.Inventory.GetItemFromSlot(source, slot)
    EnsureReady()

    local inventorySystem = System()

    if inventorySystem == 'ox_inventory' then
        local success, item = pcall(function()
            return exports.ox_inventory:GetSlot(source, slot)
        end)
        if success and item then
            return item
        end
    elseif inventorySystem == 'jaksam' then
        local success, item = pcall(function()
            return exports['jaksam_inventory']:getItemFromSlot(source, slot)
        end)
        if success and item then
            return item
        end
    elseif inventorySystem == 'codem' then
        local success, item = pcall(function()
            return exports['codem-inventory']:GetItemBySlot(source, slot)
        end)
        if success and item then
            return item
        end
    elseif inventorySystem == 'qb-inventory' then
        local success, item = pcall(function()
            return exports['qb-inventory']:GetItemBySlot(source, slot)
        end)
        if success and item then
            return item
        end
    elseif inventorySystem == 'core_inventory' then
        local success, item = pcall(function()
            return exports['core_inventory']:getItemBySlot(source, slot)
        end)
        if success and item then
            return item
        end
    end

    return nil
end

-- Get metadata from an item
function Bridge.Inventory.GetItemMetadata(source, itemName, slot)
    EnsureReady()

    local inventorySystem = System()

    if inventorySystem == 'ox_inventory' then
        if slot then
            local success, item = pcall(function()
                return exports.ox_inventory:GetSlot(source, slot)
            end)
            if success and item and item.name == itemName then
                return item.metadata or {}
            end
            return {}
        else
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            return item and item.metadata or {}
        end
    elseif inventorySystem == 'jaksam' then
        if slot then
            local success, slotData = pcall(function()
                return exports['jaksam_inventory']:getItemFromSlot(source, slot)
            end)
            if success and slotData then
                if slotData.name == itemName then
                    return slotData.metadata or {}
                end
            end
            return {}
        else
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            return item and item.metadata or {}
        end
    elseif inventorySystem == 'codem' then
        if slot then
            local success, item = pcall(function()
                return exports['codem-inventory']:GetItemBySlot(source, slot)
            end)
            if success and item and item.name == itemName then
                return item.metadata or item.info or {}
            end
            return {}
        else
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            if item then
                return item.metadata or item.info or {}
            end
            return {}
        end
    elseif inventorySystem == 'qb-inventory' then
        if slot then
            local success, item = pcall(function()
                return exports['qb-inventory']:GetItemBySlot(source, slot)
            end)
            if success and item and item.name == itemName then
                return item.info or item.metadata or {}
            end
            return {}
        else
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            if item then
                return item.info or item.metadata or {}
            end
            return {}
        end
    elseif inventorySystem == 'core_inventory' then
        if slot then
            local success, item = pcall(function()
                return exports['core_inventory']:getItemBySlot(source, slot)
            end)
            if success and item and item.name == itemName then
                return item.metadata or {}
            end
            return {}
        else
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            return item and item.metadata or {}
        end
    end

    return {}
end

-- Register a useable item across frameworks. The callback receives a normalised
-- item table: { name, slot, metadata }. ESX cannot reliably surface slot/metadata
-- from RegisterUsableItem alone, so callers needing those should look them up via
-- Bridge.Inventory.GetItemFromSlot when running on ESX.
function Bridge.Inventory.RegisterUseableItem(itemName, callback)
    EnsureReady()

    local function normalise(item)
        if type(item) ~= 'table' then return { name = itemName } end
        return {
            name = item.name or itemName,
            slot = item.slot,
            metadata = item.metadata or item.info,
        }
    end

    if Bridge.Framework == 'esx' then
        Bridge.FrameworkObject.RegisterUsableItem(itemName, function(source, _, inventoryItem)
            callback(source, normalise(inventoryItem))
        end)
    elseif Bridge.Framework == 'qbox' then
        exports.qbx_core:CreateUseableItem(itemName, function(source, item)
            callback(source, normalise(item))
        end)
    elseif Bridge.Framework == 'qbcore' then
        Bridge.FrameworkObject.Functions.CreateUseableItem(itemName, function(source, item)
            callback(source, normalise(item))
        end)
    elseif Bridge.Framework == 'standalone' then
        print('^3[Bridge Inventory]^7 RegisterUseableItem not supported in standalone mode (item: ' .. tostring(itemName) .. ')')
    end
end

-- Update metadata of an item
function Bridge.Inventory.UpdateItemMetadata(source, itemName, slot, newMetadata)
    EnsureReady()

    local inventorySystem = System()

    if inventorySystem == 'ox_inventory' then
        if not slot then
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            slot = foundSlot
        end

        if slot then
            local success = pcall(function()
                exports.ox_inventory:SetMetadata(source, slot, newMetadata)
            end)
            return success
        end
    elseif inventorySystem == 'jaksam' then
        if not slot then
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            slot = foundSlot
        end

        if slot then
            local result = exports['jaksam_inventory']:setItemMetadataInSlot(source, slot, newMetadata)
            return result
        end
    elseif inventorySystem == 'codem' then
        if not slot then
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            slot = foundSlot
        end

        if slot then
            local success = pcall(function()
                exports['codem-inventory']:SetItemMetadata(source, slot, newMetadata)
            end)
            return success
        end
    elseif inventorySystem == 'qb-inventory' then
        if not slot then
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            slot = foundSlot
        end

        if slot then
            local success = pcall(function()
                exports['qb-inventory']:SetItemData(source, itemName, 'info', newMetadata, slot)
            end)
            return success
        end
    elseif inventorySystem == 'core_inventory' then
        if not slot then
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            slot = foundSlot
        end

        if slot then
            local success = pcall(function()
                exports['core_inventory']:setMetadata(source, slot, newMetadata)
            end)
            return success
        end
    end

    return false
end
