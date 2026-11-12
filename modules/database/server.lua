local DB = { Sync = {}, Async = {} }
Bridge.DB = DB

local methods = {
    fetchAll = 'query', fetchSingle = 'single', fetchScalar = 'scalar',
    execute = 'update', insert = 'insert', transaction = 'transaction',
}

local datetimeLabels = {
    created = true, date = true, time = true, timestamp = true, last_active = true,
    last_seen = true, last_update = true, session_start = true, streak_last = true,
}

local function provider()
    if GetResourceState('oxmysql') == 'started' then return 'oxmysql' end
    if MySQL and MySQL.Sync and MySQL.Async then return 'mysql-async' end
    return nil
end

function DB.GetProvider()
    return provider()
end

local function queryName(method, query, options)
    if options and type(options.name) == 'string' then return options.name:gsub('[^%w_.:/-]', '_'):sub(1, 100) end
    if type(query) ~= 'string' then return method .. ':transaction' end
    local tableName = query:match('[Ff][Rr][Oo][Mm]%s+`?([%w_]+)')
        or query:match('[Ii][Nn][Tt][Oo]%s+`?([%w_]+)') or query:match('[Uu][Pp][Dd][Aa][Tt][Ee]%s+`?([%w_]+)')
    return method .. ':' .. (tableName or 'query')
end

local function failure(method, query, options, reason)
    local message = ('[Bridge.DB] %s (%s): %s'):format(queryName(method, query, options), provider() or 'unavailable', reason)
    print('^1' .. message .. '^7')
    return message
end

local function validateSql(query, parameters)
    assert(type(query) == 'string' and query ~= '', 'SQL must be a nonempty string')
    assert(parameters == nil or type(parameters) == 'table', 'SQL parameters must be a table')
    if parameters then
        for key in pairs(parameters) do assert(type(key) == 'string', 'Use named SQL parameters') end
    end
    local quote, index = nil, 1
    while index <= #query do
        local char, nextChar = query:sub(index, index), query:sub(index + 1, index + 1)
        if quote then
            if char == '\\' then index = index + 1
            elseif char == quote then
                if nextChar == quote then index = index + 1 else quote = nil end
            end
        elseif char == "'" or char == '"' or char == '`' then quote = char
        elseif char == '?' then error('Use named SQL parameters', 0)
        elseif (char == '-' and nextChar == '-') or (char == '/' and nextChar == '*') or char == '#' then
            error('SQL comments are not allowed', 0)
        end
        index = index + 1
    end
end

local function validate(method, query, parameters)
    if method ~= 'transaction' then return validateSql(query, parameters) end
    assert(type(query) == 'table' and #query > 0, 'A transaction needs queries')
    for _, entry in ipairs(query) do
        if type(entry) == 'string' then validateSql(entry, parameters)
        else
            assert(type(entry) == 'table', 'Invalid transaction entry')
            validateSql(entry.query, entry.parameters or entry.values or parameters)
        end
    end
end

local function connectionTimezone()
    local connection = GetConvar('mysql_connection_string', '')
    local value = (';' .. connection):match('[?&;][Tt][Ii][Mm][Ee][Zz][Oo][Nn][Ee]%s*=%s*([^;&]+)')
    if not value then return 'local' end
    return value:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end):gsub('^%s+', ''):gsub('%s+$', '')
end

local function offsetMinutes(zone)
    if zone == 'Z' or zone == 'UTC' or zone == '+00:00' then return 0 end
    local sign, hour, minute = zone:match('^([+-])(%d%d):(%d%d)$')
    if not sign or tonumber(hour) > 14 or tonumber(minute) > 59 then return nil end
    return (tonumber(hour) * 60 + tonumber(minute)) * (sign == '-' and -1 or 1)
end

local function utcDays(year, month, day)
    if month <= 2 then year = year - 1 end
    local era = math.floor(year / 400)
    local y = year - era * 400
    local m = month + (month > 2 and -3 or 9)
    return era * 146097 + y * 365 + math.floor(y / 4) - math.floor(y / 100)
        + math.floor((153 * m + 2) / 5) + day - 1 - 719468
end

local function datetime(value, zone)
    local y, m, d, h, minute, sec, suffix = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d):(%d%d)(.*)$')
    if not y then return value end
    y, m, d, h, minute, sec = tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(minute), tonumber(sec)
    if y == 0 and m == 0 and d == 0 then return nil end
    local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
    local days = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if m < 1 or m > 12 or d < 1 or d > days[m] or h > 23 or minute > 59 or sec > 59 then return value end
    local fraction = ''
    if suffix:sub(1, 1) == '.' then
        fraction, suffix = suffix:match('^%.(%d+)(.*)$')
        if not fraction then return value end
    end
    local millis = tonumber((fraction .. '000'):sub(1, 3))
    local offset = offsetMinutes(suffix ~= '' and suffix or zone)
    if offset then return ((utcDays(y, m, d) * 24 + h) * 3600 + minute * 60 + sec - offset * 60) * 1000 + millis end
    if suffix ~= '' or zone ~= 'local' then return value end
    local seconds = os.time({ year = y, month = m, day = d, hour = h, min = minute, sec = sec })
    return seconds and seconds * 1000 + millis or value
end

local function isDatetimeColumn(key)
    return type(key) == 'string' and (datetimeLabels[key] or key:match('_at$') or key:match('At$')
        or key:match('_until$') or key:match('_since$'))
end

local function normalizeRow(row, options, zone)
    local types = options and options.types or {}
    for key, value in pairs(row) do
        local kind = types[key]
        if kind ~= 'text' and type(value) == 'boolean' then row[key] = value and 1 or 0
        elseif type(value) == 'string' and kind ~= 'text' and (kind == 'datetime' or kind == 'timestamp' or isDatetimeColumn(key)) then
            row[key] = datetime(value, zone)
        end
    end
    return row
end

local function normalize(method, result, options)
    if method == 'transaction' then
        assert(type(result) == 'boolean', 'Invalid transaction result')
        return result
    elseif method == 'insert' or method == 'execute' then
        if type(result) == 'table' then result = result[method == 'insert' and 'insertId' or 'affectedRows'] end
        local number = type(result) == 'number' and result or type(result) == 'string' and tonumber(result)
        assert(number and number >= 0 and number < math.huge and number == math.floor(number), 'Invalid write result')
        return number
    elseif method == 'fetchScalar' then
        if type(result) == 'boolean' then return result and 1 or 0 end
        if type(result) == 'string' and options and options.type == 'datetime' then return datetime(result, options.timezone or connectionTimezone()) end
        return result
    elseif method == 'fetchSingle' then
        if result == nil then return nil end
        assert(type(result) == 'table', 'Invalid single-row result')
        return normalizeRow(result, options, options and options.timezone or connectionTimezone())
    end
    assert(type(result) == 'table', 'Invalid query result')
    local zone = options and options.timezone or connectionTimezone()
    for _, row in ipairs(result) do assert(type(row) == 'table', 'Invalid SQL row'); normalizeRow(row, options, zone) end
    return result
end

local function oxRequest(method, query, parameters, callback)
    exports.oxmysql[methods[method]](nil, query, parameters or {}, callback, GetCurrentResourceName(), true)
end

local function sync(method, query, parameters, options)
    local valid = pcall(validate, method, query, parameters)
    if not valid then error(failure(method, query, options, 'invalid SQL or parameters'), 0) end
    local selected = provider()
    local ok, result
    if selected == 'oxmysql' then
        local pending = promise.new()
        ok, result = pcall(function()
            oxRequest(method, query, parameters, function(rows, err)
                if err then pending:reject('provider error') else pending:resolve(rows) end
            end)
            return Citizen.Await(pending)
        end)
    elseif selected == 'mysql-async' then
        local fn = MySQL.Sync[method]
        if method == 'fetchSingle' and not fn then
            ok, result = pcall(MySQL.Sync.fetchAll, query, parameters or {})
            if ok then result = result and result[1] end
        else ok, result = pcall(fn, query, parameters or {}) end
    else ok = false end
    if not ok then error(failure(method, query, options, 'provider request failed; check database resource logs'), 0) end
    local normalized, value = pcall(normalize, method, result, options)
    if not normalized then return nil, failure(method, query, options, 'invalid provider result') end
    if method == 'transaction' and value == false then failure(method, query, options, 'transaction rolled back') end
    return value
end

local function async(method, query, parameters, callback, options)
    if type(parameters) == 'function' then options, callback, parameters = callback, parameters, {} end
    local completed = false
    local function finish(rows, err)
        if completed then return end
        completed = true
        if not err then
            local ok, value = pcall(normalize, method, rows, options)
            if ok then rows = value else err = 'invalid provider result' end
        end
        if err then
            local message = failure(method, query, options, 'provider request failed; check database resource logs')
            if callback then callback(nil, message) end
        else
            if method == 'transaction' and rows == false then failure(method, query, options, 'transaction rolled back') end
            if callback then callback(rows) end
        end
    end
    local valid = pcall(validate, method, query, parameters)
    if not valid then return finish(nil, 'invalid SQL or parameters') end
    local selected = provider()
    local ok, err = pcall(function()
        if selected == 'oxmysql' then oxRequest(method, query, parameters, finish)
        elseif selected == 'mysql-async' then
            local fn = MySQL.Async[method]
            if method == 'fetchSingle' and not fn then
                MySQL.Async.fetchAll(query, parameters or {}, function(rows) finish(rows and rows[1]) end)
            else fn(query, parameters or {}, finish) end
        else error('database resource unavailable', 0) end
    end)
    if not ok and not completed then finish(nil, 'provider request failed')
    elseif not ok then error(err, 0) end
end

for method in pairs(methods) do
    DB.Sync[method] = function(query, parameters, options) return sync(method, query, parameters, options) end
    DB.Async[method] = function(query, parameters, callback, options) return async(method, query, parameters, callback, options) end
end

function DB.ready(callback)
    assert(type(callback) == 'function', 'A database ready callback is required')
    assert(MySQL and MySQL.ready, '[Bridge.DB] database library is unavailable')
    return MySQL.ready(callback)
end

return DB
