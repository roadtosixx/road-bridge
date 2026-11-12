-- Server Job Module

Bridge = Bridge or {}
Bridge.Job = {}
Bridge.Job.UnemployedJob = 'unemployed'

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
            name = Bridge.Job.UnemployedJob,
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

-- Set job for offline player via database (by identifier)
function Bridge.Job.SetJobOffline(identifier, jobName, grade)
    EnsureFrameworkReady()
    grade = grade or 0

    if Bridge.Framework == 'esx' then
        Bridge.DB.Async.execute(
            'UPDATE ' .. Bridge.UserTable .. ' SET job = @job, job_grade = @grade WHERE ' .. Bridge.IdentifierColumn .. ' = @identifier',
            { ['@job'] = jobName, ['@grade'] = grade, ['@identifier'] = identifier }
        )
        return true
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        Bridge.DB.Async.execute(
            'UPDATE ' .. Bridge.UserTable .. ' SET job = JSON_SET(job, "$.name", @job, "$.grade.level", @grade) WHERE ' .. Bridge.IdentifierColumn .. ' = @identifier',
            { ['@job'] = jobName, ['@grade'] = grade, ['@identifier'] = identifier }
        )
        return true
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

-- Check if player is boss/management
function Bridge.Job.IsBoss(source)
    EnsureFrameworkReady()
    local job = Bridge.Job.GetJob(source)

    if not job then return false end

    if Bridge.Framework == 'esx' then
        return job.grade_name == 'boss'
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        return job.isboss or false
    end

    return false
end

-- Set job duty status
function Bridge.Job.SetDuty(source, onDuty)
    EnsureFrameworkReady()

    if Bridge.Framework == 'esx' then
        -- ESX Legacy 1.11+ keeps a duty flag on the job and sets it through setJob;
        -- older versions have no duty system at all
        local xPlayer = Bridge.FrameworkObject.GetPlayerFromId(source)
        local job = xPlayer and xPlayer.getJob()
        if not job or job.onDuty == nil then return false end
        xPlayer.setJob(job.name, job.grade, onDuty == true)
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
        local qbPlayers = Bridge.FrameworkObject.Functions.GetQBPlayers()
        for source, player in pairs(qbPlayers) do
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
        local qbPlayers = Bridge.FrameworkObject.Functions.GetQBPlayers()
        for source, player in pairs(qbPlayers) do
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

-- Count online players per job: { [jobName] = count }.
-- Every player object fetched from the framework is copied across the resource
-- boundary, so this reads ESX's own counter where it exists and otherwise makes
-- a single pass without per-player lookups.
function Bridge.Job.CountPlayersByJobs(jobNames)
    EnsureFrameworkReady()
    local counts = {}
    for _, jobName in ipairs(jobNames) do counts[jobName] = 0 end
    if #jobNames == 0 then return counts end

    if Bridge.Framework == 'esx' then
        local getNumPlayers = Bridge.FrameworkObject.GetNumPlayers
        local ok, result = false, nil
        if getNumPlayers then ok, result = pcall(getNumPlayers, 'job', jobNames) end
        if ok and type(result) == 'table' then
            for _, jobName in ipairs(jobNames) do counts[jobName] = tonumber(result[jobName]) or 0 end
            return counts
        end
        for _, jobName in ipairs(jobNames) do
            for _ in pairs(Bridge.FrameworkObject.GetExtendedPlayers('job', jobName)) do
                counts[jobName] = counts[jobName] + 1
            end
        end
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local qbPlayers = Bridge.Framework == 'qbcore'
            and Bridge.FrameworkObject.Functions.GetQBPlayers()
            or Bridge.FrameworkExport:GetQBPlayers()
        for _, player in pairs(qbPlayers) do
            local job = player and player.PlayerData and player.PlayerData.job
            local jobName = job and job.name
            if jobName and counts[jobName] then counts[jobName] = counts[jobName] + 1 end
        end
    end

    return counts
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
        local qbPlayers = Bridge.FrameworkObject.Functions.GetQBPlayers()
        for _, player in pairs(qbPlayers) do
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

-- The job in one shape for every framework, or nil for an unknown source.
-- @return table? { name, label, grade, gradeLabel, onDuty }
function Bridge.Job.GetInfo(source)
    EnsureFrameworkReady()
    local job = Bridge.Job.GetJob(source)
    if type(job) ~= 'table' or not job.name then return nil end

    if Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local grade = job.grade
        return {
            name = job.name,
            label = job.label or job.name,
            grade = type(grade) == 'table' and (tonumber(grade.level) or 0) or (tonumber(grade) or 0),
            gradeLabel = type(grade) == 'table' and grade.name or nil,
            onDuty = job.onduty == true,
        }
    end

    -- ESX (no duty flag before Legacy 1.11 = always on duty) and standalone
    return {
        name = job.name,
        label = job.label or job.name,
        grade = tonumber(job.grade) or 0,
        gradeLabel = job.grade_label or job.grade_name,
        onDuty = job.onDuty ~= false,
    }
end

-- On duty in the framework's sense; frameworks without a duty system count as on duty.
function Bridge.Job.IsOnDuty(source)
    local info = Bridge.Job.GetInfo(source)
    return info ~= nil and info.onDuty == true
end

local function DecodeJson(text)
    if type(text) == 'table' then return text end
    if type(text) ~= 'string' or text == '' then return nil end
    local ok, value = pcall(json.decode, text)
    return ok and type(value) == 'table' and value or nil
end

local function FullName(firstname, lastname)
    local parts = {}
    if firstname and firstname ~= '' then parts[#parts + 1] = tostring(firstname) end
    if lastname and lastname ~= '' then parts[#parts + 1] = tostring(lastname) end
    return table.concat(parts, ' ')
end

-- Everyone employed in one of `jobNames`, online or not. Database rows give
-- the offline staff; an online player's live job overrides its row (the
-- database is saved only now and then).
-- @return table[] { identifier, name, job, grade, gradeLabel, online }
function Bridge.Job.GetEmployees(jobNames)
    EnsureFrameworkReady()
    local wanted, names = {}, {}
    for _, name in ipairs(jobNames or {}) do
        if type(name) == 'string' and not wanted[name] then
            wanted[name] = true
            names[#names + 1] = name
        end
    end
    if #names == 0 then return {} end

    local params, marks = {}, {}
    for index, name in ipairs(names) do
        params['@job' .. index] = name
        marks[index] = '@job' .. index
    end

    local byId, order = {}, {}
    local function put(entry)
        if byId[entry.identifier] == nil then order[#order + 1] = entry.identifier end
        byId[entry.identifier] = entry
    end
    local function liveJob(identifier, name, info)
        if info and wanted[info.name] then
            put({ identifier = identifier, name = name, job = info.name, grade = info.grade, gradeLabel = info.gradeLabel, online = true })
        elseif byId[identifier] then
            byId[identifier] = false
        end
    end

    if Bridge.Framework == 'esx' then
        local rows = Bridge.DB.Sync.fetchAll(
            ('SELECT u.identifier, u.firstname, u.lastname, u.job, u.job_grade, g.label AS grade_label FROM users u LEFT JOIN job_grades g ON g.job_name = u.job AND g.grade = u.job_grade WHERE u.job IN (%s)')
                :format(table.concat(marks, ', ')),
            params
        ) or {}
        for _, row in ipairs(rows) do
            put({
                identifier = row.identifier,
                name = FullName(row.firstname, row.lastname),
                job = row.job,
                grade = tonumber(row.job_grade) or 0,
                gradeLabel = row.grade_label,
                online = false,
            })
        end
        for _, xPlayer in pairs(Bridge.FrameworkObject.GetExtendedPlayers()) do
            local job = xPlayer.getJob and xPlayer.getJob() or xPlayer.job
            local info = job and { name = job.name, grade = tonumber(job.grade) or 0, gradeLabel = job.grade_label or job.grade_name }
            liveJob(xPlayer.identifier, xPlayer.getName(), info)
        end
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        local rows = Bridge.DB.Sync.fetchAll(
            ("SELECT citizenid, charinfo, job FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) IN (%s)")
                :format(table.concat(marks, ', ')),
            params
        ) or {}
        for _, row in ipairs(rows) do
            local charinfo = DecodeJson(row.charinfo) or {}
            local job = DecodeJson(row.job) or {}
            local grade = type(job.grade) == 'table' and job.grade or {}
            put({
                identifier = row.citizenid,
                name = FullName(charinfo.firstname, charinfo.lastname),
                job = job.name,
                grade = tonumber(grade.level) or 0,
                gradeLabel = grade.name,
                online = false,
            })
        end
        local players = Bridge.Framework == 'qbcore'
            and Bridge.FrameworkObject.Functions.GetQBPlayers()
            or Bridge.FrameworkExport:GetQBPlayers()
        for _, player in pairs(players or {}) do
            local data = player and player.PlayerData
            if data and data.citizenid then
                local job = data.job or {}
                local grade = type(job.grade) == 'table' and job.grade or {}
                local charinfo = data.charinfo or {}
                liveJob(data.citizenid, FullName(charinfo.firstname, charinfo.lastname),
                    job.name and { name = job.name, grade = tonumber(grade.level) or 0, gradeLabel = grade.name } or nil)
            end
        end
    end

    local result = {}
    for _, identifier in ipairs(order) do
        if byId[identifier] then result[#result + 1] = byId[identifier] end
    end
    return result
end
