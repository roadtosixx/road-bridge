-- Server Inventory Module

Bridge = Bridge or {}
Bridge.Inventory = {}

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

-- Give player an item
function Bridge.Inventory.AddItem(source, item, count, metadata)
    EnsureFrameworkReady()
    count = count or 1
    metadata = metadata or {}

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addInventoryItem(item, count, metadata)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.Functions.AddItem(item, count, nil, metadata)
        end
    elseif Bridge.Framework == 'qbox' then
        -- QBX uses a different inventory system (ox_inventory)
        -- We try using exports
        local success = pcall(function()
            exports.ox_inventory:AddItem(source, item, count, metadata)
        end)
        return success
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: AddItem not implemented')
        return false
    end
    return false
end

-- Remove item from player
function Bridge.Inventory.RemoveItem(source, item, count, metadata)
    EnsureFrameworkReady()
    count = count or 1
    metadata = metadata or {}

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(item, count)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.Functions.RemoveItem(item, count, nil, metadata)
        end
    elseif Bridge.Framework == 'qbox' then
        local success = pcall(function()
            exports.ox_inventory:RemoveItem(source, item, count, metadata)
        end)
        return success
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: RemoveItem not implemented')
        return false
    end
    return false
end

-- Get item count
function Bridge.Inventory.GetItemCount(source, item)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            local invItem = xPlayer.getInventoryItem(item)
            return invItem and invItem.count or 0
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            local invItem = player.Functions.GetItemByName(item)
            return invItem and invItem.amount or 0
        end
    elseif Bridge.Framework == 'qbox' then
        local success, count = pcall(function()
            return exports.ox_inventory:GetItemCount(source, item)
        end)
        return success and count or 0
    elseif Bridge.Framework == 'standalone' then
        return 0
    end
    return 0
end

-- Check if player has item
function Bridge.Inventory.HasItem(source, item, count)
    EnsureFrameworkReady()
    count = count or 1
    return Bridge.Inventory.GetItemCount(source, item) >= count
end

-- Get item from player
function Bridge.Inventory.GetItem(source, item)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getInventoryItem(item)
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.Functions.GetItemByName(item)
        end
    elseif Bridge.Framework == 'qbox' then
        local success, itemData = pcall(function()
            return exports.ox_inventory:GetItem(source, item)
        end)
        return success and itemData or nil
    elseif Bridge.Framework == 'standalone' then
        return nil
    end
    return nil
end

-- Get entire inventory
function Bridge.Inventory.GetInventory(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getInventory()
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.items or {}
        end
    elseif Bridge.Framework == 'qbox' then
        local success, inventory = pcall(function()
            return exports.ox_inventory:GetInventory(source)
        end)
        return success and inventory or {}
    elseif Bridge.Framework == 'standalone' then
        return {}
    end
    return {}
end

-- Set item metadata
function Bridge.Inventory.SetItemMetadata(source, item, slot, metadata)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        -- ESX does not support metadata by default, requires ox_inventory
        local success = pcall(function()
            exports.ox_inventory:SetMetadata(source, slot, metadata)
        end)
        return success
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            local invItem = player.Functions.GetItemBySlot(slot)
            if invItem then
                invItem.info = metadata
                return true
            end
        end
    elseif Bridge.Framework == 'qbox' then
        local success = pcall(function()
            exports.ox_inventory:SetMetadata(source, slot, metadata)
        end)
        return success
    elseif Bridge.Framework == 'standalone' then
        return false
    end
    return false
end

-- Can carry item (weight/slots check)
function Bridge.Inventory.CanCarryItem(source, item, count)
    EnsureFrameworkReady()
    count = count or 1

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.canCarryItem(item, count)
        end
    elseif Bridge.Framework == 'qbcore' then
        -- QBCore has no direct canCarryItem function, we simulate it
        return true -- Simplified, could be extended
    elseif Bridge.Framework == 'qbox' then
        local success, canCarry = pcall(function()
            return exports.ox_inventory:CanCarryItem(source, item, count)
        end)
        return success and canCarry or false
    elseif Bridge.Framework == 'standalone' then
        return true
    end
    return false
end

-- ============================================================================
-- METADATA FUNCTIONS (for inventory-system-specific metadata)
-- ============================================================================

-- Get item with metadata (inventory-system-specific)
function Bridge.Inventory.GetItemWithMetadata(source, itemName, metadataFilter)
    EnsureFrameworkReady()

    local inventorySystem = Config.InventorySystem or 'jaksam'

    if inventorySystem == 'ox_inventory' then
        -- ox_inventory: Search all items by name and metadata
        local success, items = pcall(function()
            return exports.ox_inventory:Search(source, 'slots', itemName)
        end)

        if success and items then
            if metadataFilter then
                -- Filter by metadata
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
                -- Return first found item
                for _, item in pairs(items) do
                    return item, item.slot
                end
            end
        end
    elseif inventorySystem == 'jaksam' then
        -- jaksam: We need to search ALL items of this type and filter by metadata
        local success, allItems = pcall(function()
            return exports['jaksam_inventory']:getItemsByName(source, itemName)
        end)

        if success and allItems and type(allItems) == 'table' then
            -- Check if we got multiple items or just one
            if metadataFilter then
                -- Filter by metadata
                for slotId, item in pairs(allItems) do
                    if item and item.metadata then
                        local matches = true
                        for key, value in pairs(metadataFilter) do
                            if tostring(item.metadata[key]) ~= tostring(value) then
                                matches = false
                                break
                            end
                        end
                        if matches then
                            return item, slotId
                        end
                    end
                end
            else
                -- Return first found item
                for slotId, item in pairs(allItems) do
                    return item, slotId
                end
            end
        end

        -- Fallback: Try single item lookup (getItemByName)
        local data, slotId = exports['jaksam_inventory']:getItemByName(source, itemName)
        if data then
            if metadataFilter then
                -- Check if metadata matches
                if data.metadata then
                    local matches = true
                    for key, value in pairs(metadataFilter) do
                        if tostring(data.metadata[key]) ~= tostring(value) then
                            matches = false
                            break
                        end
                    end
                    if matches then
                        return data, slotId
                    end
                end
                return nil, nil -- No match
            end
            return data, slotId
        end
    end

    return nil, nil
end

-- Get item from specific slot (returns full item data or nil if not found)
function Bridge.Inventory.GetItemFromSlot(source, slot)
    EnsureFrameworkReady()

    local inventorySystem = Config.InventorySystem or 'jaksam'

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
    end

    return nil
end

-- Get metadata from an item
function Bridge.Inventory.GetItemMetadata(source, itemName, slot)
    EnsureFrameworkReady()

    local inventorySystem = Config.InventorySystem or 'jaksam'

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
            -- Get item from specific slot using jaksam export
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
    end

    return {}
end

-- Update metadata of an item
function Bridge.Inventory.UpdateItemMetadata(source, itemName, slot, newMetadata)
    EnsureFrameworkReady()

    local inventorySystem = Config.InventorySystem or 'jaksam'

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
        -- Jaksam inventory metadata update
        if not slot then
            local item, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
            slot = foundSlot
        end

        if slot then
            local result = exports['jaksam_inventory']:setItemMetadataInSlot(source, slot, newMetadata)
            return result
        end
    end

    return false
end
