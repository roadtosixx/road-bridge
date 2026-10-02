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

-- Normalize money type across frameworks
-- QBCore uses 'cash', ESX uses 'money' for the same thing
local function normalizeMoneyType(moneyType)
    if Bridge.Framework == 'esx' and moneyType == 'cash' then
        return 'money'
    end
    return moneyType
end

-- Get account balance
function Bridge.Account.GetBalance(source, accountType)
    EnsureFrameworkReady()
    accountType = normalizeMoneyType(accountType or 'bank')

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
        -- qbx_core money exports accept Source|string directly
        local money = Bridge.FrameworkExport:GetMoney(source, accountType)
        return money or 0
    elseif Bridge.Framework == 'standalone' then
        return 0
    end
    return 0
end

-- Add money to account
function Bridge.Account.AddMoney(source, accountType, amount, reason)
    EnsureFrameworkReady()
    accountType = normalizeMoneyType(accountType or 'bank')
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
            return player.Functions.AddMoney(accountType, amount, reason) == true
        end
    elseif Bridge.Framework == 'qbox' then
        -- qbx_core money exports accept Source|string directly
        return Bridge.FrameworkExport:AddMoney(source, accountType, amount, reason)
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: AddMoney not implemented')
        return false
    end
    return false
end

-- Remove money from account
function Bridge.Account.RemoveMoney(source, accountType, amount, reason)
    EnsureFrameworkReady()
    accountType = normalizeMoneyType(accountType or 'bank')
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
            return player.Functions.RemoveMoney(accountType, amount, reason) == true
        end
    elseif Bridge.Framework == 'qbox' then
        -- qbx_core money exports accept Source|string directly
        return Bridge.FrameworkExport:RemoveMoney(source, accountType, amount, reason)
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: RemoveMoney not implemented')
        return false
    end
    return false
end

-- Set account balance
function Bridge.Account.SetMoney(source, accountType, amount)
    EnsureFrameworkReady()
    accountType = normalizeMoneyType(accountType or 'bank')

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.setAccountMoney(accountType, amount)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.Functions.SetMoney(accountType, amount) == true
        end
    elseif Bridge.Framework == 'qbox' then
        -- qbx_core money exports accept Source|string directly
        return Bridge.FrameworkExport:SetMoney(source, accountType, amount)
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
        if Bridge.Account.AddMoney(source, toAccount, amount, 'Transfer from ' .. fromAccount) then
            return true
        end
        -- Rollback: re-add to the source account if the deposit failed
        Bridge.Account.AddMoney(source, fromAccount, amount, 'Transfer rollback')
        return false
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
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.money
        end
    elseif Bridge.Framework == 'qbox' then
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

-- okokBanking keys societies by the bare job name — both its own
-- Config.Societies and the okokbanking_societies table use 'police', not
-- 'society_police'. With Config.UseAddonAccount = true it proxies to
-- esx_addonaccount instead, which DOES use the prefix, so on ESX both spellings
-- are tried and the one okok actually knows wins.
local function okokSocietyNames(accountName)
    local bare = (accountName:gsub('^society_', ''))
    if Bridge.Framework == 'esx' then
        return { bare, 'society_' .. bare }
    end
    return { bare }
end

-- okokBanking's GetAccount returns the balance directly on some versions and the
-- okokbanking_societies row (or a one-row result set) on others. That row keeps
-- the balance in `value` — the same column bank.lua already reads for
-- transactions. Returns nil when no balance could be read, which is what
-- separates "society unknown" from "society is empty".
local okokAccountBalance
okokAccountBalance = function(account)
    if type(account) == 'number' then
        return account
    elseif type(account) == 'string' then
        return tonumber(account)
    elseif type(account) == 'table' then
        if type(account[1]) == 'table' then
            return okokAccountBalance(account[1])
        end
        return tonumber(account.value or account.money or account.amount or account.balance)
    end
    return nil
end

-- Resolve a society to the name okokBanking knows plus its balance. A name that
-- reports actual money wins; otherwise the first name that answered at all is
-- kept so deposits still land on an empty-but-existing account.
-- @return string?, number? - resolved name and balance, nil when unresolvable
local function okokResolveSociety(accountName)
    local fallbackName, fallbackBalance, firstError

    for _, name in ipairs(okokSocietyNames(accountName)) do
        local ok, account = pcall(function()
            return exports['okokBanking']:GetAccount(name)
        end)

        if ok then
            local balance = okokAccountBalance(account)
            if balance and balance > 0 then
                return name, balance
            end
            if balance and not fallbackName then
                fallbackName, fallbackBalance = name, balance
            end
        elseif not firstError then
            firstError = account
        end
    end

    if fallbackName then
        return fallbackName, fallbackBalance
    end

    print(('[RoadPhone] okokBanking: could not read society "%s"%s'):format(
        accountName, firstError and (' - ' .. tostring(firstError)) or ''))
    return nil
end

-- Get society account balance
-- @param accountName string - The society account name (e.g., 'society_taxi', 'taxi')
-- @return number - The balance of the society account
function Bridge.Account.GetSocietyBalance(accountName)
    EnsureFrameworkReady()

    -- okokBanking is the society source of truth when enabled (overrides the
    -- per-framework management/banking resources below).
    if Config.okokBanking then
        local _, balance = okokResolveSociety(accountName)
        return balance or 0
    end

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

        -- Guard: resolve nil if esx_addonaccount never answers (resource absent)
        SetTimeout(2000, function()
            p:resolve(nil)
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

    -- okokBanking is the society source of truth when enabled.
    if Config.okokBanking then
        local name = okokResolveSociety(accountName) or okokSocietyNames(accountName)[1]
        local ok, result = pcall(function()
            return exports['okokBanking']:AddMoney(name, amount)
        end)
        return ok and result ~= false
    end

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
        local settled = false
        local p = promise.new()

        TriggerEvent('esx_addonaccount:getSharedAccount', normalizedName, function(account)
            if settled then return end
            settled = true
            if account then
                account.addMoney(amount)
                success = true
            end
            p:resolve(success)
        end)

        -- Guard: resolve false if esx_addonaccount never answers (resource absent)
        SetTimeout(2000, function()
            if settled then return end
            settled = true
            p:resolve(false)
        end)

        return Citizen.Await(p) or false

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

    -- okokBanking is the society source of truth when enabled.
    if Config.okokBanking then
        local name = okokResolveSociety(accountName) or okokSocietyNames(accountName)[1]
        local ok, result = pcall(function()
            return exports['okokBanking']:RemoveMoney(name, amount)
        end)
        return ok and result ~= false
    end

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
        local settled = false
        local p = promise.new()

        TriggerEvent('esx_addonaccount:getSharedAccount', normalizedName, function(account)
            if settled then return end
            settled = true
            if account and account.money >= amount then
                account.removeMoney(amount)
                success = true
            end
            p:resolve(success)
        end)

        -- Guard: resolve false if esx_addonaccount never answers (resource absent)
        SetTimeout(2000, function()
            if settled then return end
            settled = true
            p:resolve(false)
        end)

        return Citizen.Await(p) or false

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
