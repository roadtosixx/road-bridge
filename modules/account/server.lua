-- Server Account Module

Bridge = Bridge or {}
Bridge.Account = {}

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

-- Get account balance
function Bridge.Account.GetBalance(source, accountType)
    EnsureFrameworkReady()
    accountType = accountType or 'bank'

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            local account = xPlayer.getAccount(accountType)
            return account and account.money or 0
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.money[accountType] or 0
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            local money = Bridge.FrameworkExport:GetMoney(identifier, accountType)
            return money or 0
        end
        return 0
    elseif Bridge.Framework == 'standalone' then
        return 0
    end
    return 0
end

-- Add money to account
function Bridge.Account.AddMoney(source, accountType, amount, reason)
    EnsureFrameworkReady()
    accountType = accountType or 'bank'
    reason = reason or 'Unknown'

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addAccountMoney(accountType, amount, reason)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            player.Functions.AddMoney(accountType, amount, reason)
            return true
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            return Bridge.FrameworkExport:AddMoney(identifier, accountType, amount, reason)
        end
        return false
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: AddMoney not implemented')
        return false
    end
    return false
end

-- Remove money from account
function Bridge.Account.RemoveMoney(source, accountType, amount, reason)
    EnsureFrameworkReady()
    accountType = accountType or 'bank'
    reason = reason or 'Unknown'

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeAccountMoney(accountType, amount, reason)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            player.Functions.RemoveMoney(accountType, amount, reason)
            return true
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            return Bridge.FrameworkExport:RemoveMoney(identifier, accountType, amount, reason)
        end
        return false
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: RemoveMoney not implemented')
        return false
    end
    return false
end

-- Set account balance
function Bridge.Account.SetMoney(source, accountType, amount)
    EnsureFrameworkReady()
    accountType = accountType or 'bank'

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.setAccountMoney(accountType, amount)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            player.Functions.SetMoney(accountType, amount)
            return true
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            return Bridge.FrameworkExport:SetMoney(identifier, accountType, amount)
        end
        return false
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: SetMoney not implemented')
        return false
    end
    return false
end

-- Check if enough money is available
function Bridge.Account.HasMoney(source, accountType, amount)
    EnsureFrameworkReady()
    return Bridge.Account.GetBalance(source, accountType) >= amount
end

-- Transfer money between accounts
function Bridge.Account.TransferMoney(source, fromAccount, toAccount, amount)
    EnsureFrameworkReady()

    if not Bridge.Account.HasMoney(source, fromAccount, amount) then
        return false
    end
    
    if Bridge.Account.RemoveMoney(source, fromAccount, amount, 'Transfer to ' .. toAccount) then
        return Bridge.Account.AddMoney(source, toAccount, amount, 'Transfer from ' .. fromAccount)
    end
    
    return false
end

-- Get all accounts of a player
function Bridge.Account.GetAccounts(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getAccounts()
        end
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayer(source)
        if player then
            return player.PlayerData.money
        end
    elseif Bridge.Framework == 'standalone' then
        return {}
    end
    return {}
end

-- ============================================
-- Society Account Functions
-- ============================================

-- Get society account balance
-- @param accountName string - The society account name (e.g., 'society_taxi', 'taxi')
-- @return number - The balance of the society account
function Bridge.Account.GetSocietyBalance(accountName)
    EnsureFrameworkReady()

    -- Normalize account name (ensure 'society_' prefix for ESX)
    local function normalizeName(name)
        if Bridge.Framework == 'esx' then
            if not string.find(name, 'society_') then
                return 'society_' .. name
            end
        else
            -- QBCore/Qbox use job name without prefix
            return name:gsub('society_', '')
        end
        return name
    end

    local normalizedName = normalizeName(accountName)

    if Bridge.Framework == 'esx' then
        local account = nil
        local p = promise.new()

        TriggerEvent('esx_addonaccount:getSharedAccount', normalizedName, function(acc)
            account = acc
            p:resolve(acc)
        end)

        -- Wait for callback with timeout
        local result = Citizen.Await(p)

        if result then
            return result.money or 0
        end
        return 0

    elseif Bridge.Framework == 'qbcore' then
        -- QBCore uses qb-management or qb-bossmenu
        local success, result = pcall(function()
            return exports['qb-management']:GetAccount(normalizedName)
        end)

        if success and result then
            return result
        end

        -- Fallback: Try qb-banking society accounts
        success, result = pcall(function()
            return exports['qb-banking']:GetAccountBalance(normalizedName)
        end)

        if success and result then
            return result
        end

        return 0

    elseif Bridge.Framework == 'qbox' then
        -- Qbox uses ox_core or has its own management system
        local success, result = pcall(function()
            return exports['qbx_management']:GetAccount(normalizedName)
        end)

        if success and result then
            return result
        end

        -- Fallback to qb-management (often used with Qbox)
        success, result = pcall(function()
            return exports['qb-management']:GetAccount(normalizedName)
        end)

        if success and result then
            return result
        end

        return 0

    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: GetSocietyBalance not implemented')
        return 0
    end

    return 0
end

-- Add money to society account
-- @param accountName string - The society account name
-- @param amount number - Amount to add
-- @param reason string? - Optional reason for the transaction
-- @return boolean - Success status
function Bridge.Account.AddSocietyMoney(accountName, amount, reason)
    EnsureFrameworkReady()
    reason = reason or 'Phone Payment'

    -- Normalize account name
    local function normalizeName(name)
        if Bridge.Framework == 'esx' then
            if not string.find(name, 'society_') then
                return 'society_' .. name
            end
        else
            return name:gsub('society_', '')
        end
        return name
    end

    local normalizedName = normalizeName(accountName)

    if Bridge.Framework == 'esx' then
        local success = false
        local p = promise.new()

        TriggerEvent('esx_addonaccount:getSharedAccount', normalizedName, function(account)
            if account then
                account.addMoney(amount)
                success = true
            end
            p:resolve(success)
        end)

        return Citizen.Await(p)

    elseif Bridge.Framework == 'qbcore' then
        local success, result = pcall(function()
            return exports['qb-management']:AddMoney(normalizedName, amount)
        end)

        if success then
            return result ~= false
        end

        -- Fallback: Try qb-banking
        success, result = pcall(function()
            return exports['qb-banking']:AddMoney(normalizedName, amount, reason)
        end)

        return success and result ~= false

    elseif Bridge.Framework == 'qbox' then
        local success, result = pcall(function()
            return exports['qbx_management']:AddMoney(normalizedName, amount)
        end)

        if success then
            return result ~= false
        end

        -- Fallback to qb-management
        success, result = pcall(function()
            return exports['qb-management']:AddMoney(normalizedName, amount)
        end)

        return success and result ~= false

    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: AddSocietyMoney not implemented')
        return false
    end

    return false
end

-- Remove money from society account
-- @param accountName string - The society account name
-- @param amount number - Amount to remove
-- @param reason string? - Optional reason for the transaction
-- @return boolean - Success status
function Bridge.Account.RemoveSocietyMoney(accountName, amount, reason)
    EnsureFrameworkReady()
    reason = reason or 'Phone Payment'

    -- Normalize account name
    local function normalizeName(name)
        if Bridge.Framework == 'esx' then
            if not string.find(name, 'society_') then
                return 'society_' .. name
            end
        else
            return name:gsub('society_', '')
        end
        return name
    end

    local normalizedName = normalizeName(accountName)

    if Bridge.Framework == 'esx' then
        local success = false
        local p = promise.new()

        TriggerEvent('esx_addonaccount:getSharedAccount', normalizedName, function(account)
            if account and account.money >= amount then
                account.removeMoney(amount)
                success = true
            end
            p:resolve(success)
        end)

        return Citizen.Await(p)

    elseif Bridge.Framework == 'qbcore' then
        local success, result = pcall(function()
            return exports['qb-management']:RemoveMoney(normalizedName, amount)
        end)

        if success then
            return result ~= false
        end

        -- Fallback: Try qb-banking
        success, result = pcall(function()
            return exports['qb-banking']:RemoveMoney(normalizedName, amount, reason)
        end)

        return success and result ~= false

    elseif Bridge.Framework == 'qbox' then
        local success, result = pcall(function()
            return exports['qbx_management']:RemoveMoney(normalizedName, amount)
        end)

        if success then
            return result ~= false
        end

        -- Fallback to qb-management
        success, result = pcall(function()
            return exports['qb-management']:RemoveMoney(normalizedName, amount)
        end)

        return success and result ~= false

    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: RemoveSocietyMoney not implemented')
        return false
    end

    return false
end

-- Check if society account has enough money
-- @param accountName string - The society account name
-- @param amount number - Amount to check
-- @return boolean - True if account has enough money
function Bridge.Account.HasSocietyMoney(accountName, amount)
    return Bridge.Account.GetSocietyBalance(accountName) >= amount
end