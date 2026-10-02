-- Server Player Module

Bridge = Bridge or {}
Bridge.Player = {}

-- Helper: Wait for framework
local function EnsureFrameworkReady()
    if not Bridge.Ready then
        if Bridge.WaitForReady then
            Bridge.WaitForReady()
        else
            while not Bridge.Framework do
                Wait(100)
            end
        end
    end
end

-- Get player by source ID
-- Returns player object with consistent .source property across all frameworks
function Bridge.Player.GetPlayerBySource(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        return Bridge.FrameworkObject.GetPlayerFromId(source)
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            player.source = source
        end
        return player
    elseif Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayer(source)
        if player then
            player.source = source
        end
        return player
    elseif Bridge.Framework == 'standalone' then
        return {
            source = source,
            identifier = GetPlayerIdentifier(source, 0),
            name = GetPlayerName(source)
        }
    end
    return nil
end

-- Get player by identifier
-- Returns player object with consistent .source property across all frameworks
function Bridge.Player.GetPlayerByIdentifier(identifier)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        return Bridge.FrameworkObject.GetPlayerFromIdentifier(identifier)
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayerByCitizenId(identifier)
        if player then
            player.source = player.PlayerData.source
        end
        return player
    elseif Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayerByCitizenId(identifier)
        if player then
            player.source = player.PlayerData.source
        end
        return player
    elseif Bridge.Framework == 'standalone' then
        for _, playerId in ipairs(GetPlayers()) do
            if GetPlayerIdentifier(playerId, 0) == identifier then
                return {
                    source = playerId,
                    identifier = identifier,
                    name = GetPlayerName(playerId)
                }
            end
        end
        return nil
    end
    return nil
end

-- Get player identifier
function Bridge.Player.GetIdentifier(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        return xPlayer and xPlayer.identifier or nil
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        return player and player.PlayerData.citizenid or nil
    elseif Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayer(source)
        return player and player.PlayerData.citizenid or nil
    elseif Bridge.Framework == 'standalone' then
        return GetPlayerIdentifier(source, 0)
    end
    return nil
end

-- Helper: QBCore/Qbox character name. charinfo is missing while a player is
-- still loading, so guard it instead of raising on the concatenation.
local function GetCharinfoName(player)
    local charinfo = player and player.PlayerData and player.PlayerData.charinfo
    if not charinfo or not charinfo.firstname or not charinfo.lastname then
        return nil
    end
    return charinfo.firstname .. ' ' .. charinfo.lastname
end

-- Get player name
function Bridge.Player.GetName(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        return xPlayer and xPlayer.getName() or GetPlayerName(source)
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        return GetCharinfoName(player) or GetPlayerName(source)
    elseif Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayer(source)
        return GetCharinfoName(player) or GetPlayerName(source)
    elseif Bridge.Framework == 'standalone' then
        return GetPlayerName(source)
    end
    return GetPlayerName(source)
end

-- Get all online players (returns array of source IDs for consistency)
function Bridge.Player.GetPlayers()
    EnsureFrameworkReady()

    local result = {}

    if Bridge.Framework == 'esx' then
        local xPlayers = Bridge.FrameworkObject.GetExtendedPlayers()
        for _, xPlayer in pairs(xPlayers) do
            table.insert(result, xPlayer.source)
        end
    elseif Bridge.Framework == 'qbcore' then
        local qbPlayers = Bridge.FrameworkObject.Functions.GetQBPlayers()
        for src, _ in pairs(qbPlayers) do
            table.insert(result, src)
        end
    elseif Bridge.Framework == 'qbox' then
        local qbPlayers = Bridge.FrameworkExport:GetQBPlayers()
        for src, _ in pairs(qbPlayers) do
            table.insert(result, src)
        end
    elseif Bridge.Framework == 'standalone' then
        for _, playerId in ipairs(GetPlayers()) do
            table.insert(result, tonumber(playerId))
        end
    end

    return result
end

-- Add money to player
-- Normalize money type across frameworks
-- QBCore uses 'cash', ESX uses 'money' for the same thing
local function normalizeMoneyType(moneyType)
    if Bridge.Framework == 'esx' and moneyType == 'cash' then
        return 'money'
    end
    return moneyType
end

function Bridge.Player.AddMoney(source, moneyType, amount)
    EnsureFrameworkReady()
    moneyType = normalizeMoneyType(moneyType)

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addAccountMoney(moneyType, amount)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.Functions.AddMoney(moneyType, amount) ~= false
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            return Bridge.FrameworkExport:AddMoney(identifier, moneyType, amount)
        end
        return false
    elseif Bridge.Framework == 'standalone' then
        -- Custom implementation can be added here
        print('[Bridge] Standalone: AddMoney not implemented')
        return false
    end
    return false
end

-- Remove money from player
function Bridge.Player.RemoveMoney(source, moneyType, amount)
    EnsureFrameworkReady()
    moneyType = normalizeMoneyType(moneyType)

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeAccountMoney(moneyType, amount)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.Functions.RemoveMoney(moneyType, amount) == true
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            return Bridge.FrameworkExport:RemoveMoney(identifier, moneyType, amount)
        end
        return false
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: RemoveMoney not implemented')
        return false
    end
    return false
end

-- Get player money
function Bridge.Player.GetMoney(source, moneyType)
    EnsureFrameworkReady()
    moneyType = normalizeMoneyType(moneyType)

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            local account = xPlayer.getAccount(moneyType)
            return account and account.money or 0
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.money[moneyType] or 0
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            local money = Bridge.FrameworkExport:GetMoney(identifier, moneyType)
            return money or 0
        end
        return 0
    elseif Bridge.Framework == 'standalone' then
        return 0
    end
    return 0
end

-- Normalizes the sex/gender value of every framework to 'm' / 'f' / nil.
local function NormalizeSex(value)
    if value == nil then return nil end
    if type(value) == 'number' then
        return value == 1 and 'f' or 'm'
    end
    local v = tostring(value):lower()
    if v == 'm' or v == 'male' or v == '0' then return 'm' end
    if v == 'f' or v == 'female' or v == '1' then return 'f' end
    return nil
end

-- Character identity as printed on an ID card. Missing values stay nil.
function Bridge.Player.GetIdentity(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if not xPlayer then return nil end
        -- xPlayer methods are function references into es_extended: a nil result
        -- arrives as no value at all, which tonumber() rejects. A local turns it into nil.
        local height = xPlayer.get('height')
        local identity = {
            firstname = xPlayer.get('firstname'),
            lastname = xPlayer.get('lastname'),
            dateofbirth = xPlayer.get('dateofbirth'),
            sex = NormalizeSex(xPlayer.get('sex')),
            height = tonumber(height),
            nationality = nil
        }
        if not identity.firstname or not identity.lastname then
            local rows = MySQL.Sync.fetchAll(
                'SELECT firstname, lastname, dateofbirth, sex, height FROM ' .. Bridge.UserTable ..
                ' WHERE ' .. Bridge.IdentifierColumn .. ' = @identifier',
                { ['@identifier'] = xPlayer.identifier })
            local row = rows and rows[1]
            if row then
                identity.firstname = row.firstname
                identity.lastname = row.lastname
                identity.dateofbirth = row.dateofbirth
                identity.sex = NormalizeSex(row.sex)
                identity.height = tonumber(row.height)
            end
        end
        return identity
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local player = Bridge.Player.GetPlayerBySource(source)
        local charinfo = player and player.PlayerData and player.PlayerData.charinfo
        if not charinfo then return nil end
        return {
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            dateofbirth = charinfo.birthdate,
            sex = NormalizeSex(charinfo.gender),
            height = nil,
            nationality = charinfo.nationality
        }
    end

    local name = GetPlayerName(source)
    return { firstname = name, lastname = nil, dateofbirth = nil, sex = nil, height = nil, nationality = nil }
end

-- Set of license keys the character holds, e.g. { drive = true, weapon = true }.
function Bridge.Player.GetLicenses(source)
    EnsureFrameworkReady()
    local result = {}

    if Bridge.Framework == 'esx' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if not identifier then return result end
        local rows = MySQL.Sync.fetchAll('SELECT type FROM user_licenses WHERE owner = @owner',
            { ['@owner'] = identifier })
        for _, row in ipairs(rows or {}) do
            if row.type then result[row.type] = true end
        end
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local player = Bridge.Player.GetPlayerBySource(source)
        local licences = player and player.PlayerData and player.PlayerData.metadata
            and player.PlayerData.metadata.licences
        if type(licences) == 'table' then
            for key, value in pairs(licences) do
                if value == true or value == 1 then result[key] = true end
            end
        end
    end

    return result
end

-- Gang membership. Only QBCore/Qbox have a standard source; ESX returns nil.
function Bridge.Player.GetGang(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local player = Bridge.Player.GetPlayerBySource(source)
        local gang = player and player.PlayerData and player.PlayerData.gang
        if not gang or not gang.name or gang.name == 'none' then return nil end
        local grade = gang.grade
        return {
            name = gang.name,
            label = gang.label or gang.name,
            grade = type(grade) == 'table' and grade.level or grade,
            gradeLabel = type(grade) == 'table' and grade.name or nil
        }
    end

    return nil
end
