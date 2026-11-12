-- Server Vehicle Module
-- Owned vehicles read live from the framework's table. Every row comes back
-- as { plate, owner, model, hash, stored, garage, impounded, color }; plates
-- are compared upper case and trimmed, because GTA pads them to 8 characters.

Bridge = Bridge or {}
Bridge.Vehicle = Bridge.Vehicle or {}

local MAX_PLATE = 8

local function EnsureFrameworkReady()
    if Bridge.EnsureReady then
        Bridge.EnsureReady()
    elseif not Bridge.Ready then
        while not Bridge.Framework do
            Wait(100)
        end
    end
end

-- LIKE patterns: backslash is MySQL's default escape character.
local function EscapeLike(text)
    return (text:gsub('[\\%%_]', '\\%0'))
end

local function Decode(text)
    if type(text) ~= 'string' or text == '' then return nil end
    local ok, value = pcall(json.decode, text)
    return ok and type(value) == 'table' and value or nil
end

local function Count(limit, default)
    return math.max(1, math.min(math.floor(tonumber(limit) or default), 500))
end

--- Upper case, trimmed, inner runs of spaces collapsed; '' for anything else.
function Bridge.Vehicle.NormalizePlate(plate)
    if type(plate) ~= 'string' then return '' end
    local text = plate:upper():gsub('%s+', ' '):match('^%s*(.-)%s*$')
    return text:sub(1, 12)
end

local NormalizePlate = Bridge.Vehicle.NormalizePlate

local function EsxRow(row)
    local props = Decode(row.vehicle) or {}
    return {
        plate = NormalizePlate(row.plate),
        owner = row.owner,
        model = nil,
        hash = tonumber(props.model),
        stored = row.stored == true or tonumber(row.stored) == 1,
        garage = nil,
        impounded = false,
        color = tonumber(props.color1),
    }
end

local function QbRow(row)
    local mods = Decode(row.mods) or {}
    local state = tonumber(row.state) or 0
    return {
        plate = NormalizePlate(row.plate),
        owner = row.citizenid,
        model = type(row.vehicle) == 'string' and row.vehicle or nil,
        hash = tonumber(row.hash) or tonumber(mods.model),
        stored = state == 1,
        garage = row.garage,
        impounded = state == 2,
        color = tonumber(mods.color1),
    }
end

-- The SELECT, owner column, stored condition, props column and row converter
-- of the running framework; nil when it keeps no owned vehicles.
local function Source()
    if Bridge.Framework == 'esx' then
        return {
            select = 'SELECT owner, plate, vehicle, stored FROM owned_vehicles',
            table = 'owned_vehicles',
            owner = 'owner',
            stored = 'stored = 1',
            props = 'vehicle',
            convert = EsxRow,
        }
    elseif Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        return {
            select = 'SELECT citizenid, plate, vehicle, hash, mods, garage, state FROM player_vehicles',
            table = 'player_vehicles',
            owner = 'citizenid',
            stored = 'state = 1',
            props = 'mods',
            convert = QbRow,
        }
    end
    return nil
end

local function Rows(source, rows)
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = source.convert(row) end
    return out
end

--- The owned vehicle with this plate, or nil.
function Bridge.Vehicle.FindByPlate(plate)
    EnsureFrameworkReady()
    local source = Source()
    local key = NormalizePlate(plate)
    if not source or key == '' then return nil end
    -- the exact spelling first (primary key), then rows stored with GTA's padding
    local rows = Bridge.DB.Sync.fetchAll(source.select .. ' WHERE plate = @plate LIMIT 1', { ['@plate'] = key }) or {}
    if not rows[1] then
        rows = Bridge.DB.Sync.fetchAll(source.select .. ' WHERE TRIM(plate) = @plate LIMIT 1', { ['@plate'] = key }) or {}
    end
    return rows[1] and source.convert(rows[1]) or nil
end

--- Vehicles whose plate contains `query` or whose owner identifier is `query`.
function Bridge.Vehicle.Search(query, limit)
    EnsureFrameworkReady()
    local source = Source()
    local text = type(query) == 'string' and query:match('^%s*(.-)%s*$') or ''
    if not source or #text < 2 then return {} end
    local rows = Bridge.DB.Sync.fetchAll(
        ('%s WHERE TRIM(plate) LIKE @like OR %s = @owner ORDER BY plate LIMIT %d'):format(source.select, source.owner, Count(limit, 50)),
        { ['@like'] = '%' .. EscapeLike(NormalizePlate(text)) .. '%', ['@owner'] = text }
    )
    return Rows(source, rows)
end

function Bridge.Vehicle.GetOwned(identifier)
    EnsureFrameworkReady()
    local source = Source()
    if not source or type(identifier) ~= 'string' or identifier == '' then return {} end
    local rows = Bridge.DB.Sync.fetchAll(
        ('%s WHERE %s = @owner ORDER BY plate'):format(source.select, source.owner),
        { ['@owner'] = identifier }
    )
    return Rows(source, rows)
end

--- One page of all owned vehicles, ordered by plate.
function Bridge.Vehicle.List(offset, limit)
    EnsureFrameworkReady()
    local source = Source()
    if not source then return {} end
    local skip = math.max(0, math.floor(tonumber(offset) or 0))
    local rows = Bridge.DB.Sync.fetchAll(
        ('%s ORDER BY plate LIMIT %d OFFSET %d'):format(source.select, Count(limit, 100), skip),
        {}
    )
    return Rows(source, rows)
end

--- Gives a stored vehicle a new owner; false when it is out, impounded or unknown.
function Bridge.Vehicle.SetOwner(plate, identifier)
    EnsureFrameworkReady()
    local source = Source()
    local key = NormalizePlate(plate)
    if not source or key == '' or type(identifier) ~= 'string' or identifier == '' then return false end
    local sql
    if Bridge.Framework == 'esx' then
        sql = 'UPDATE owned_vehicles SET owner = @owner WHERE TRIM(plate) = @plate AND stored = 1'
    else
        -- QBCore and Qbox also keep the owner's licence on the vehicle row
        sql = 'UPDATE player_vehicles SET citizenid = @owner, license = COALESCE((SELECT license FROM players WHERE citizenid = @owner LIMIT 1), license) WHERE TRIM(plate) = @plate AND state = 1'
    end
    local affected = Bridge.DB.Sync.execute(sql, { ['@owner'] = identifier, ['@plate'] = key })
    return (tonumber(affected) or 0) >= 1
end

--- Moves a stored vehicle to a new plate (also inside its props); false for a taken plate.
function Bridge.Vehicle.SetPlate(oldPlate, newPlate)
    EnsureFrameworkReady()
    local source = Source()
    local old, new = NormalizePlate(oldPlate), NormalizePlate(newPlate)
    if not source or old == '' or new == '' or #new > MAX_PLATE or old == new then return false end
    local taken = Bridge.DB.Sync.fetchAll(
        ('SELECT plate FROM %s WHERE TRIM(plate) = @new LIMIT 1'):format(source.table),
        { ['@new'] = new }
    ) or {}
    if taken[1] then return false end
    local affected = Bridge.DB.Sync.execute(
        ("UPDATE %s SET plate = @new, %s = IF(JSON_VALID(%s), JSON_SET(%s, '$.plate', @new), %s) WHERE TRIM(plate) = @old AND %s")
            :format(source.table, source.props, source.props, source.props, source.props, source.stored),
        { ['@new'] = new, ['@old'] = old }
    )
    return (tonumber(affected) or 0) >= 1
end
