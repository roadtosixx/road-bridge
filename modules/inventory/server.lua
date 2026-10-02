-- Server Inventory Module

Bridge = Bridge or {}
Bridge.Inventory = {}
Bridge.Inventory.System = nil
Bridge.Inventory.Ready = false

--- Read an item's per-slot data, whatever the inventory calls it.
---
--- `metadata` is ALWAYS preferred. Only qb-derived inventories keep this data
--- in `info` (qb-inventory is the documented case — our own write path uses
--- SetItemData(..., 'info', ...) there), so only those may fall back to it.
--- ox / jaksam / one_inventory have no `info` field at all.
---
--- Why this exists: 20 call sites used to write `item.metadata or item.info`
--- by hand — some the other way round. That picks the EMPTY table whenever the
--- first field exists but is empty, because `{}` is truthy in Lua. Reading the
--- wrong field makes a configured phone look brand new, so it gets a fresh
--- number assigned on every open.
---
--- Always returns a table.
local INFO_BASED_SYSTEMS = {
    ['qb-inventory'] = true,
    codem = true,
    core_inventory = true,
    -- tgiann is qb-derived and hands out BOTH fields: `metadata` as an empty
    -- table and the real payload in `info`. Reading `metadata` only made every
    -- configured phone look brand new — a fresh number was assigned on every
    -- open and each write seemed to vanish. `metadata` still wins whenever it
    -- actually holds something, so nothing changes for setups that use it.
    tgiann = true,
}

-- ============================================================================
-- tgiann metadata write — VERIFIED
-- ----------------------------------------------------------------------------
-- tgiann's UpdateItemMetadata accepts the call, returns nothing and can persist
-- NOTHING, without raising an error. A silently dropped write means the phone
-- item never keeps its number: every open assigns a new one and nothing ever
-- sticks. So this path does not assume success — it checks whether the write
-- actually landed, and remembers which call shape works.
--
--   'name' — UpdateItemMetadata(src, itemName, slot, metadata)   (documented)
--   'item' — UpdateItemMetadata(src, itemTable, slot, metadata)  (item object)
--
-- The check runs until one shape is proven; from then on the winner is used
-- directly, so the read-back costs nothing in normal operation.
-- ============================================================================
local tgiannWriteShape = nil

local function TgiannReadSlot(source, slot)
    local ok, item = pcall(function()
        return exports['tgiann-inventory']:GetItemBySlot(source, slot)
    end)

    if not ok then return nil end
    return item
end

-- Did the data we wrote actually arrive? Compares the first scalar field.
local function MetadataLanded(readItem, written)
    local readMeta = Bridge.Inventory.ItemMetadata(readItem)
    if type(readMeta) ~= 'table' then return false end

    for key, value in pairs(written) do
        local t = type(value)
        if t == 'string' or t == 'number' or t == 'boolean' then
            return readMeta[key] == value
        end
    end

    return next(readMeta) ~= nil
end

local function TgiannWriteMetadata(source, itemName, slot, metadata)
    local shapes = tgiannWriteShape and { tgiannWriteShape } or { 'name', 'item' }

    for _, shape in ipairs(shapes) do
        local target = itemName
        if shape == 'item' then
            target = TgiannReadSlot(source, slot)
        end

        if target then
            local ok, err = pcall(function()
                return exports['tgiann-inventory']:UpdateItemMetadata(source, target, slot, metadata)
            end)

            if not ok then
                print(('^1[Bridge Inventory] tgiann UpdateItemMetadata raised (item=%s slot=%s): %s^7')
                    :format(tostring(itemName), tostring(slot), tostring(err)))
            elseif tgiannWriteShape == shape then
                return true -- proven shape, no read-back needed
            elseif MetadataLanded(TgiannReadSlot(source, slot), metadata) then
                tgiannWriteShape = shape
                return true
            end
        end
    end

    print(('^1[Bridge Inventory] tgiann did NOT persist metadata for %s (slot %s). ' ..
        'Phone data cannot be saved on this inventory — no call shape worked.^7')
        :format(tostring(itemName), tostring(slot)))
    return false
end

function Bridge.Inventory.ItemMetadata(item)
    if type(item) ~= 'table' then return {} end

    local meta = item.metadata
    if type(meta) == 'table' and next(meta) ~= nil then
        return meta
    end

    if INFO_BASED_SYSTEMS[Bridge.Inventory.System] then
        local info = item.info
        if type(info) == 'table' and next(info) ~= nil then
            return info
        end
        if type(info) == 'table' then return info end
    end

    -- Empty/absent: hand back a real table so callers can write into it.
    if type(meta) == 'table' then return meta end
    return {}
end

-- ============================================================================
-- AUTO-DETECTION
-- ============================================================================

-- Kept in sync with the client list in inventory/client.lua - if the two
-- disagree, client and server report a different Bridge.Inventory.System for
-- the same server. Only list an inventory that has an adapter below; anything
-- else falls through to the framework-native fallback on both sides.
local DetectionCandidates = {
    { resource = 'ox_inventory',    name = 'ox_inventory' },
    { resource = 'one_inventory',   name = 'one_inventory' },
    { resource = 'jaksam_inventory', name = 'jaksam' },
    { resource = 'tgiann-inventory', name = 'tgiann' },
    { resource = 'qb-inventory',    name = 'qb-inventory' },
    { resource = 'codem-inventory', name = 'codem' },
    { resource = 'core_inventory',  name = 'core_inventory' },
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

    Bridge.Inventory.System = Bridge.Framework or 'standalone'
    Bridge.Inventory.Ready = true
end

CreateThread(function()
    -- Bounded: without a framework this waited forever and detection never ran,
    -- which in turn blocked every inventory call downstream. Standalone setups
    -- are legitimate, so time out and detect anyway.
    Bridge.WaitFor(function() return Bridge.Framework end, 15000, 'framework detection')

    Bridge.Inventory.DetectSystem()
end)

-- Ensure framework + inventory are ready.
--
-- This used to be `while not Ready do Wait(50) end` — an UNBOUNDED wait. If
-- detection never finished (framework missing, inventory resource not started,
-- an error inside DetectSystem), every single inventory call hung forever and
-- the phone simply never opened, with nothing in the console explaining it.
-- Bridge.EnsureInventoryReady puts a deadline on it; after that we run degraded
-- (System() is nil → the framework-native adapter) and say so, once.
local readyTimeoutReported = false

local function EnsureReady()
    if Bridge.Inventory.Ready then return end

    if Bridge.EnsureInventoryReady() then return end

    if not readyTimeoutReported then
        readyTimeoutReported = true
        print('^1[Bridge Inventory] Detection did not finish in time. ' ..
            'Is the inventory resource started, and does Config.InventorySystem match it? ' ..
            'Falling back to framework-native item handling.^7')
    end
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

-- Capability report: which inventory systems can persist metadata writes back to
-- the item. Owners running Config.UseMetadata=true on a system marked 'none'
-- here will silently lose data, so server.lua warns loudly on resource start.
-- Values:
--   'full'    — full per-slot metadata read+write (recommended for UseMetadata)
--   'partial' — read works, write may not persist all fields across server restart
--   'none'    — UpdateItemMetadata is a no-op
local InventoryMetadataSupport = {
    ox_inventory   = 'full',
    one_inventory  = 'full',
    jaksam         = 'full',
    tgiann         = 'full',
    ['qb-inventory'] = 'full',
    codem          = 'partial',
    core_inventory = 'partial',
}

function Bridge.Inventory.SupportsMetadata()
    if not Bridge.Inventory.System then return 'none' end
    return InventoryMetadataSupport[Bridge.Inventory.System] or 'none'
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
        -- ox AddItem returns success (false when the inventory can't carry it)
        local success, added = pcall(function()
            return exports.ox_inventory:AddItem(source, item, count, metadata)
        end)
        return success and added ~= false
    elseif sys == 'one_inventory' then
        -- one_inventory: AddItem(inv, item, count?, metadata?, slot?) -> boolean, string?
        -- Pass nil instead of {} so the inventory applies its own default metadata
        local success, added = pcall(function()
            return exports.one_inventory:AddItem(source, item, count, next(metadata) ~= nil and metadata or nil)
        end)
        return success and added == true
    elseif sys == 'jaksam' then
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:addItem(source, item, count, metadata)
        end)
        return success and ok or false
    elseif sys == 'tgiann' then
        -- tgiann: AddItem(source, item, amount, slot, metadata, isClotheSlot)
        local success, ok = pcall(function()
            return exports['tgiann-inventory']:AddItem(source, item, count, nil, metadata)
        end)
        return success and (ok ~= false)
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
    -- Keep an omitted filter nil so items with metadata can also be removed.

    local sys = System()

    if sys == 'ox_inventory' then
        -- ox RemoveItem returns success (false when the player lacks the item)
        local success, removed = pcall(function()
            return exports.ox_inventory:RemoveItem(source, item, count, metadata)
        end)
        return success and removed ~= false
    elseif sys == 'one_inventory' then
        -- one_inventory: RemoveItem(inv, item, count?, metadata?, slot?);
        -- metadata is a slot FILTER — pass nil instead of {} so any slot matches
        local success, removed = pcall(function()
            return exports.one_inventory:RemoveItem(source, item, count, metadata and next(metadata) ~= nil and metadata or nil)
        end)
        return success and removed == true
    elseif sys == 'jaksam' then
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:removeItem(source, item, count, metadata)
        end)
        return success and ok or false
    elseif sys == 'tgiann' then
        -- tgiann: RemoveItem(source, item, amount, slot, metadata)
        local success, ok = pcall(function()
            return exports['tgiann-inventory']:RemoveItem(source, item, count, nil, metadata)
        end)
        return success and (ok ~= false)
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

-- Remove item from a specific slot (metadata-safe removal for unique items)
function Bridge.Inventory.RemoveItemFromSlot(source, item, count, slot)
    EnsureReady()
    count = count or 1

    if slot == nil then
        return Bridge.Inventory.RemoveItem(source, item, count)
    end

    local sys = System()

    if sys == 'ox_inventory' then
        local success, removed = pcall(function()
            return exports.ox_inventory:RemoveItem(source, item, count, nil, slot)
        end)
        return success and removed ~= false
    elseif sys == 'one_inventory' then
        -- one_inventory: RemoveItem(inv, item, count?, metadata?, slot?)
        local success, removed = pcall(function()
            return exports.one_inventory:RemoveItem(source, item, count, nil, slot)
        end)
        return success and removed == true
    elseif sys == 'jaksam' then
        -- jaksam slot ids may be prefixed ('SLOT-3'); its removeItem takes the numeric slot
        local slotNum = tonumber((tostring(slot):gsub('SLOT%-', ''))) or slot
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:removeItem(source, item, count, nil, slotNum)
        end)
        return success and ok or false
    elseif sys == 'tgiann' then
        -- tgiann: RemoveItem(source, item, amount, slot, metadata)
        local success, ok = pcall(function()
            return exports['tgiann-inventory']:RemoveItem(source, item, count, slot)
        end)
        return success and (ok ~= false)
    elseif sys == 'codem' then
        local success = pcall(function()
            exports['codem-inventory']:RemoveItem(source, item, count, slot)
        end)
        return success
    elseif sys == 'qb-inventory' then
        local success, ok = pcall(function()
            return exports['qb-inventory']:RemoveItem(source, item, count, slot, 'roadphone')
        end)
        return success and ok or false
    elseif sys == 'core_inventory' then
        -- core_inventory has no slot-targeted removal
        return Bridge.Inventory.RemoveItem(source, item, count)
    end

    local fw = FrameworkNative()
    if fw == 'esx' then
        -- ESX native inventory is not slot-based
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(item, count)
            return true
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local player = GetQBLikePlayer(source)
        if player then
            return player.Functions.RemoveItem(item, count, slot)
        end
    elseif fw == 'standalone' then
        print('[Bridge] Standalone: RemoveItemFromSlot not implemented')
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
    elseif sys == 'one_inventory' then
        local success, count = pcall(function()
            return exports.one_inventory:GetItemCount(source, item)
        end)
        return success and (count or 0) or 0
    elseif sys == 'jaksam' then
        local success, total = pcall(function()
            return exports['jaksam_inventory']:getTotalItemAmount(source, item)
        end)
        return success and (total or 0) or 0
    elseif sys == 'tgiann' then
        local success, total = pcall(function()
            return exports['tgiann-inventory']:GetItemCount(source, item)
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
    if sys == 'one_inventory' then
        local success, ok = pcall(function()
            return exports.one_inventory:HasItem(source, item, count)
        end)
        if success then return ok and true or false end
    elseif sys == 'jaksam' then
        local success, ok = pcall(function()
            return exports['jaksam_inventory']:hasItem(source, item, count)
        end)
        if success then return ok and true or false end
    elseif sys == 'tgiann' then
        local success, ok = pcall(function()
            return exports['tgiann-inventory']:HasItem(source, item, count)
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
    elseif sys == 'one_inventory' then
        -- Returns a slot table { name, slot, count, metadata, ... }
        local success, itemData = pcall(function()
            return exports.one_inventory:GetItem(source, item)
        end)
        return success and itemData or nil
    elseif sys == 'jaksam' then
        local success, itemData = pcall(function()
            return exports['jaksam_inventory']:getItemByName(source, item)
        end)
        return success and itemData or nil
    elseif sys == 'tgiann' then
        local success, itemData = pcall(function()
            return exports['tgiann-inventory']:GetItemByName(source, item)
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
    elseif sys == 'one_inventory' then
        -- Array of populated slot tables (no holes to worry about)
        local success, inventory = pcall(function()
            return exports.one_inventory:GetInventoryItems(source)
        end)
        return success and inventory or {}
    elseif sys == 'tgiann' then
        local success, inventory = pcall(function()
            return exports['tgiann-inventory']:GetPlayerItems(source)
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
    elseif sys == 'one_inventory' then
        local success, canCarry = pcall(function()
            return exports.one_inventory:CanCarryItem(source, item, count)
        end)
        return success and canCarry == true
    elseif sys == 'jaksam' then
        local success, canCarry = pcall(function()
            return exports['jaksam_inventory']:canCarryItem(source, item, count)
        end)
        return success and canCarry or false
    elseif sys == 'tgiann' then
        local success, canCarry = pcall(function()
            return exports['tgiann-inventory']:CanCarryItem(source, item, count)
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
-- METADATA LAYER
-- ----------------------------------------------------------------------------
-- Every inventory contributes exactly THREE primitives:
--
--   readSlot(source, slot)                       -> raw item table | nil
--   listByName(source, itemName)                 -> array of raw items (.slot set)
--   writeMetadata(source, itemName, slot, meta)  -> truthy on success
--
-- Everything else (metadata filters, per-slot reads, slot resolution) is derived
-- from those in ONE place. Previously each of those operations was written out
-- separately for all seven inventories, so the same bug had to be fixed eight
-- times — and reading `item.metadata` instead of `ItemMetadata(item)` survived
-- in the branches nobody touched. That shape is gone: adding an inventory is a
-- table entry, not eight new `elseif` blocks.
--
-- Adapters may raise; the generic layer wraps every call in pcall.
-- ============================================================================

local Adapters = {}

Adapters.ox_inventory = {
    readSlot = function(src, slot)
        return exports.ox_inventory:GetSlot(src, slot)
    end,
    listByName = function(src, itemName)
        return exports.ox_inventory:Search(src, 'slots', itemName)
    end,
    writeMetadata = function(src, itemName, slot, meta)
        exports.ox_inventory:SetMetadata(src, slot, meta)
        return true
    end,
}

Adapters.one_inventory = {
    readSlot = function(src, slot)
        return exports.one_inventory:GetSlot(src, slot)
    end,
    listByName = function(src, itemName)
        local slotIds = exports.one_inventory:GetSlotIdsWithItem(src, itemName)
        if type(slotIds) ~= 'table' then return nil end

        local items = {}
        for _, slotId in ipairs(slotIds) do
            local slotData = exports.one_inventory:GetSlot(src, slotId)
            if slotData then
                slotData.slot = slotData.slot or slotId
                items[#items + 1] = slotData
            end
        end
        return items
    end,
    writeMetadata = function(src, itemName, slot, meta)
        return exports.one_inventory:SetItemMetadata(src, slot, meta) == true
    end,
}

Adapters.jaksam = {
    readSlot = function(src, slot)
        return exports['jaksam_inventory']:getItemFromSlot(src, slot)
    end,
    listByName = function(src, itemName)
        return exports['jaksam_inventory']:getItemsByName(src, itemName)
    end,
    writeMetadata = function(src, itemName, slot, meta)
        return exports['jaksam_inventory']:setItemMetadataInSlot(src, slot, meta)
    end,
}

Adapters.tgiann = {
    readSlot = function(src, slot)
        return exports['tgiann-inventory']:GetItemBySlot(src, slot)
    end,
    -- GetItemsByName is documented but not exported server-side by older
    -- releases (1.58.1 raises "No such export"); GetPlayerItems exists in all.
    listByName = function(src, itemName)
        local inventory = exports['tgiann-inventory']:GetPlayerItems(src)
        if type(inventory) ~= 'table' then return nil end

        local items = {}
        for key, item in pairs(inventory) do
            if type(item) == 'table' and item.name == itemName then
                item.slot = item.slot or tonumber(key)
                items[#items + 1] = item
            end
        end
        return items
    end,
    -- Verified write: tgiann accepts the call and can persist nothing without
    -- raising. TgiannWriteMetadata checks the result and remembers the call
    -- shape that works. See the block near the top of this file.
    writeMetadata = function(src, itemName, slot, meta)
        return TgiannWriteMetadata(src, itemName, slot, meta)
    end,
}

Adapters.codem = {
    readSlot = function(src, slot)
        return exports['codem-inventory']:GetItemBySlot(src, slot)
    end,
    listByName = function(src, itemName)
        return exports['codem-inventory']:GetItemsByName(src, itemName)
    end,
    writeMetadata = function(src, itemName, slot, meta)
        exports['codem-inventory']:SetItemMetadata(src, slot, meta)
        return true
    end,
}

Adapters['qb-inventory'] = {
    readSlot = function(src, slot)
        return exports['qb-inventory']:GetItemBySlot(src, slot)
    end,
    listByName = function(src, itemName)
        return exports['qb-inventory']:GetItemsByName(src, itemName)
    end,
    -- qb keeps per-slot data under `info` (docs.qbcore.org, verified)
    writeMetadata = function(src, itemName, slot, meta)
        exports['qb-inventory']:SetItemData(src, itemName, 'info', meta, slot)
        return true
    end,
}

Adapters.core_inventory = {
    readSlot = function(src, slot)
        return exports['core_inventory']:getItemBySlot(src, slot)
    end,
    listByName = function(src, itemName)
        return exports['core_inventory']:getItems(src, itemName)
    end,
    writeMetadata = function(src, itemName, slot, meta)
        exports['core_inventory']:setMetadata(src, slot, meta)
        return true
    end,
}

-- Framework-native fallback: no standalone inventory, or a fork we do not
-- recognise by resource name.
local FrameworkAdapter = {
    readSlot = function(src, slot)
        local player = GetQBLikePlayer(src)
        if not player then return nil end
        return player.Functions.GetItemBySlot(slot)
    end,
    listByName = function(src, itemName)
        local inventory = Bridge.Inventory.GetInventory(src)
        if type(inventory) ~= 'table' then return nil end

        local items = {}
        for _, item in pairs(inventory) do
            if item and item.name == itemName then
                items[#items + 1] = item
            end
        end
        return items
    end,
    -- qb-like player object: mutate the in-memory item and persist it.
    writeMetadata = function(src, itemName, slot, meta)
        local fw = FrameworkNative()
        if fw ~= 'qbcore' and fw ~= 'qbox' then return false end

        local player = GetQBLikePlayer(src)
        if not player then return false end

        local invItem = player.Functions.GetItemBySlot(slot)
        if not invItem then return false end

        invItem.info = meta

        -- Older qb-core exposes SetInventory on the player; fall back to
        -- SetPlayerData when it does not.
        local saved = pcall(function()
            player.Functions.SetInventory(player.PlayerData.items)
        end)
        if not saved then
            pcall(function()
                player.Functions.SetPlayerData('items', player.PlayerData.items)
            end)
        end

        return true
    end,
}

local function Adapter()
    return Adapters[System()] or FrameworkAdapter
end

-- A broken adapter would otherwise log on every single call (reads happen per
-- message and per call). Report each distinct failure once — enough to notice,
-- not enough to drown the console.
local reportedFailures = {}

--- Call an adapter primitive. Returns nil when the inventory is missing the
--- primitive or the call raised — never throws at the caller.
local function callAdapter(name, ...)
    local fn = Adapter()[name]
    if type(fn) ~= 'function' then return nil end

    local ok, result = pcall(fn, ...)
    if not ok then
        local key = ('%s.%s:%s'):format(tostring(System()), name, tostring(result))
        if not reportedFailures[key] then
            reportedFailures[key] = true
            print(('^1[Bridge Inventory] %s.%s failed: %s^7')
                :format(tostring(System()), name, tostring(result)))
        end
        return nil
    end
    return result
end

--- Does this item's metadata match every key of the filter?
--- String-compared on purpose: numbers arriving from the DB and strings coming
--- from the NUI must match (phone numbers are stored both ways in the wild).
local function matchesFilter(item, filter)
    if not filter then return true end

    local meta = Bridge.Inventory.ItemMetadata(item)
    for key, value in pairs(filter) do
        if tostring(meta[key]) ~= tostring(value) then
            return false
        end
    end
    return true
end

-- ============================================================================
-- METADATA FUNCTIONS
-- ============================================================================

--- All items of a name the player carries, normalised to
--- { slot, name, metadata } — metadata already resolved from metadata/info.
function Bridge.Inventory.GetAllItemsByName(source, itemName)
    EnsureReady()

    local raw = callAdapter('listByName', source, itemName)
    local results = {}
    if type(raw) ~= 'table' then return results end

    -- Some inventories key the result by slot instead of returning an array,
    -- so the key is the slot fallback when the entry carries none.
    for key, item in pairs(raw) do
        if type(item) == 'table' then
            local slot = item.slot or (type(key) == 'number' and key or nil)
            if slot ~= nil then
                results[#results + 1] = {
                    slot = slot,
                    name = item.name or itemName,
                    metadata = Bridge.Inventory.ItemMetadata(item),
                }
            end
        end
    end

    return results
end

--- First item of this name, optionally filtered by metadata.
--- Returns item, slot — the item carries a resolved `metadata` field.
function Bridge.Inventory.GetItemWithMetadata(source, itemName, metadataFilter)
    EnsureReady()

    for _, item in ipairs(Bridge.Inventory.GetAllItemsByName(source, itemName)) do
        if matchesFilter(item, metadataFilter) then
            return item, item.slot
        end
    end

    return nil
end

--- Raw item at a slot, exactly as the inventory returns it (callers may need
--- the untouched fields). Read its data with Bridge.Inventory.ItemMetadata.
function Bridge.Inventory.GetItemFromSlot(source, slot)
    EnsureReady()

    if slot == nil then return nil end
    return callAdapter('readSlot', source, slot)
end

--- Metadata of a specific item. With a slot it reads that slot (and verifies
--- the item name), otherwise the first item of that name. Always a table.
function Bridge.Inventory.GetItemMetadata(source, itemName, slot)
    EnsureReady()

    if slot ~= nil then
        local item = Bridge.Inventory.GetItemFromSlot(source, slot)
        if item and (item.name == itemName or itemName == nil) then
            return Bridge.Inventory.ItemMetadata(item)
        end
        return {}
    end

    local item = Bridge.Inventory.GetItemWithMetadata(source, itemName)
    return Bridge.Inventory.ItemMetadata(item)
end

--- Write metadata onto an item. Without a slot the first matching item is used.
--- Returns whether the inventory accepted the write.
function Bridge.Inventory.UpdateItemMetadata(source, itemName, slot, newMetadata)
    EnsureReady()

    if not slot then
        local _, foundSlot = Bridge.Inventory.GetItemWithMetadata(source, itemName)
        slot = foundSlot
    end

    if not slot then return false end

    return callAdapter('writeMetadata', source, itemName, slot, newMetadata) and true or false
end

--- Kept for callers using the older name/argument order.
function Bridge.Inventory.SetItemMetadata(source, item, slot, metadata)
    return Bridge.Inventory.UpdateItemMetadata(source, item, slot, metadata)
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
            metadata = Bridge.Inventory.ItemMetadata(item),
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

