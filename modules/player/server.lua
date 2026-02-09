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

-- Get player name
function Bridge.Player.GetName(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        return xPlayer and xPlayer.getName() or GetPlayerName(source)
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        return player and player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname or GetPlayerName(source)
    elseif Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayer(source)
        return player and player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname or GetPlayerName(source)
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
function Bridge.Player.AddMoney(source, moneyType, amount)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addAccountMoney(moneyType, amount)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            player.Functions.AddMoney(moneyType, amount)
            return true
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

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeAccountMoney(moneyType, amount)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            player.Functions.RemoveMoney(moneyType, amount)
            return true
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

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getAccount(moneyType).money
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
