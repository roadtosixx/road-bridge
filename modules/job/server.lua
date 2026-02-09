-- Server Job Module

Bridge = Bridge or {}
Bridge.Job = {}

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

-- Get player job
function Bridge.Job.GetJob(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getJob()
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.job
        end
    elseif Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayer(source)
        if player then
            return player.PlayerData.job
        end
    elseif Bridge.Framework == 'standalone' then
        return {
            name = 'unemployed',
            label = 'Unemployed',
            grade = 0
        }
    end
    return nil
end

-- Set player job
function Bridge.Job.SetJob(source, jobName, grade)
    EnsureFrameworkReady()
    grade = grade or 0

    if Bridge.Framework == 'esx' then
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.setJob(jobName, grade)
            return true
        end
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.Functions.SetJob(jobName, grade)
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            return Bridge.FrameworkExport:SetJob(identifier, jobName, grade)
        end
        return false
    elseif Bridge.Framework == 'standalone' then
        print('[Bridge] Standalone: SetJob not implemented')
        return false
    end
    return false
end

-- Check if player has job
function Bridge.Job.HasJob(source, jobName, minGrade)
    EnsureFrameworkReady()
    minGrade = minGrade or 0
    local job = Bridge.Job.GetJob(source)

    if not job then return false end

    local grade = 0
    if Bridge.Framework == 'esx' then
        grade = job.grade or 0
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        grade = job.grade and job.grade.level or 0
    end

    return job.name == jobName and grade >= minGrade
end

-- Get job grade
function Bridge.Job.GetGrade(source)
    EnsureFrameworkReady()
    local job = Bridge.Job.GetJob(source)

    if not job then return 0 end

    if Bridge.Framework == 'esx' then
        return job.grade or 0
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        return job.grade and job.grade.level or 0
    end

    return 0
end

-- Set job duty status
function Bridge.Job.SetDuty(source, onDuty)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        -- ESX has no duty system by default
        TriggerClientEvent('esx:setJob', source, onDuty)
        return true
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            player.Functions.SetJobDuty(onDuty)
            return true
        end
    elseif Bridge.Framework == 'qbox' then
        local identifier = Bridge.Player.GetIdentifier(source)
        if identifier then
            return Bridge.FrameworkExport:SetJobDuty(identifier, onDuty)
        end
        return false
    elseif Bridge.Framework == 'standalone' then
        return false
    end
    return false
end

-- Get job duty status
function Bridge.Job.GetDutyStatus(source)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        -- ESX has no duty system by default, always on duty
        return true
    elseif Bridge.Framework == 'qbcore' then
        local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.job.onduty or false
        end
    elseif Bridge.Framework == 'qbox' then
        local player = Bridge.FrameworkExport:GetPlayer(source)
        if player then
            return player.PlayerData.job.onduty or false
        end
    elseif Bridge.Framework == 'standalone' then
        return true
    end
    return false
end

-- Get all players with specific job (source IDs only)
function Bridge.Job.GetPlayersWithJob(jobName, minGrade)
    EnsureFrameworkReady()
    minGrade = minGrade or 0
    local players = {}

    if Bridge.Framework == 'esx' then
        local xPlayers = Bridge.FrameworkObject.GetExtendedPlayers('job', jobName)
        for _, xPlayer in pairs(xPlayers) do
            if xPlayer.job.grade >= minGrade then
                table.insert(players, xPlayer.source)
            end
        end
    elseif Bridge.Framework == 'qbcore' then
        local allPlayers = Bridge.FrameworkObject.Functions.GetPlayers()
        for _, source in ipairs(allPlayers) do
            local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
            if player and player.PlayerData.job.name == jobName then
                local grade = player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0
                if grade >= minGrade then
                    table.insert(players, source)
                end
            end
        end
    elseif Bridge.Framework == 'qbox' then
        local qbPlayers = Bridge.FrameworkExport:GetQBPlayers()
        for source, player in pairs(qbPlayers) do
            if player.PlayerData.job.name == jobName then
                local grade = player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0
                if grade >= minGrade then
                    table.insert(players, source)
                end
            end
        end
    elseif Bridge.Framework == 'standalone' then
        return {}
    end

    return players
end

-- Get all player objects with specific job (compatible with getPlayersByJob)
-- Returns players with a consistent .source property across all frameworks
function Bridge.Job.GetPlayersByJob(jobName, minGrade)
    EnsureFrameworkReady()
    minGrade = minGrade or 0
    local players = {}

    if Bridge.Framework == 'esx' then
        local xPlayers = Bridge.FrameworkObject.GetExtendedPlayers('job', jobName)
        for _, xPlayer in pairs(xPlayers) do
            if xPlayer.job.grade >= minGrade then
                table.insert(players, xPlayer)
            end
        end
    elseif Bridge.Framework == 'qbcore' then
        local allPlayers = Bridge.FrameworkObject.Functions.GetPlayers()
        for _, source in ipairs(allPlayers) do
            local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
            if player and player.PlayerData.job.name == jobName then
                local grade = player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0
                if grade >= minGrade then
                    -- Add .source property for consistency with ESX
                    player.source = source
                    table.insert(players, player)
                end
            end
        end
    elseif Bridge.Framework == 'qbox' then
        local qbPlayers = Bridge.FrameworkExport:GetQBPlayers()
        for source, player in pairs(qbPlayers) do
            if player.PlayerData.job.name == jobName then
                local grade = player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0
                if grade >= minGrade then
                    -- Add .source property for consistency with ESX
                    player.source = source
                    table.insert(players, player)
                end
            end
        end
    elseif Bridge.Framework == 'standalone' then
        return {}
    end

    return players
end

-- Get count of players on duty for job
function Bridge.Job.GetOnDutyCount(jobName)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        -- ESX has no duty system, count all with job
        local count = 0
        local xPlayers = Bridge.FrameworkObject.GetExtendedPlayers('job', jobName)
        for _ in pairs(xPlayers) do
            count = count + 1
        end
        return count
    elseif Bridge.Framework == 'qbcore' then
        local count = 0
        local allPlayers = Bridge.FrameworkObject.Functions.GetPlayers()
        for _, source in ipairs(allPlayers) do
            local player = Bridge.FrameworkObject.Functions.GetPlayer(source)
            if player and player.PlayerData.job.name == jobName and player.PlayerData.job.onduty then
                count = count + 1
            end
        end
        return count
    elseif Bridge.Framework == 'qbox' then
        local result = Bridge.FrameworkExport:GetDutyCountJob(jobName)
        return result or 0
    elseif Bridge.Framework == 'standalone' then
        return 0
    end
    return 0
end

-- Create new job (runtime)
function Bridge.Job.CreateJob(jobName, jobData)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        -- ESX jobs must be created in the database
        print('[Bridge] ESX: Jobs can only be created via database')
        return false
    elseif Bridge.Framework == 'qbcore' then
        Bridge.FrameworkObject.Shared.Jobs[jobName] = jobData
        return true
    elseif Bridge.Framework == 'qbox' then
        return Bridge.FrameworkExport:CreateJob(jobName, jobData)
    elseif Bridge.Framework == 'standalone' then
        return false
    end
    return false
end

-- Remove job (runtime)
function Bridge.Job.RemoveJob(jobName)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        print('[Bridge] ESX: Jobs can only be removed via database')
        return false
    elseif Bridge.Framework == 'qbcore' then
        Bridge.FrameworkObject.Shared.Jobs[jobName] = nil
        return true
    elseif Bridge.Framework == 'qbox' then
        return Bridge.FrameworkExport:RemoveJob(jobName)
    elseif Bridge.Framework == 'standalone' then
        return false
    end
    return false
end
