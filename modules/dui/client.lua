-- DUI pools for in-world screens. A pool owns a fixed number of slots; a slot
-- is one DUI plus one runtime texture that replaces a model's screen texture
-- for the whole resource lifetime (recreating them crashes the client). A
-- released slot navigates to about:blank and reloads its page on the next
-- acquire. Pages report readiness by posting the NUI callback 'bridgeDuiReady'
-- with { pool, slot, gen } taken from their URL query. Nothing is registered
-- at load time: RoadPhone loads every bridge module, so the first pool
-- registers the callback and the stop handler.

Bridge = Bridge or {}
Bridge.DUI = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end
local function add(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
local function sub(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
local function scale(a, s) return vec(a.x * s, a.y * s, a.z * s) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

local function cross(a, b)
    return vec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function normalize(a)
    local length = math.sqrt(dot(a, a))
    if length == 0 then return a end
    return scale(a, 1 / length)
end

--- World ray through a cursor pixel. camRot is a GTA rotation in degrees
--- (pitch x, yaw z, rotation order 2, roll ignored); fov is vertical.
function Bridge.DUI.CursorRay(camPos, camRot, fov, cursorX, cursorY, screenW, screenH)
    local pitch, yaw = math.rad(camRot.x), math.rad(camRot.z)
    local forward = vec(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local right = vec(math.cos(yaw), math.sin(yaw), 0.0)
    local up = cross(right, forward)
    local tanHalf = math.tan(math.rad(fov) / 2)
    local nx = (cursorX / screenW) * 2 - 1
    local ny = 1 - (cursorY / screenH) * 2
    local dir = add(forward, add(scale(right, nx * tanHalf * (screenW / screenH)), scale(up, ny * tanHalf)))
    return vec(camPos.x, camPos.y, camPos.z), normalize(dir)
end

--- u, v in 0..1 (top-left origin) where the ray hits the rectangle given by its
--- world corners { tl, tr, bl }; nil when it misses or the screen is behind.
function Bridge.DUI.RayToScreen(origin, dir, corners)
    local e1, e2 = sub(corners.tr, corners.tl), sub(corners.bl, corners.tl)
    local normal = cross(e1, e2)
    local denom = dot(normal, dir)
    if math.abs(denom) < 1e-9 then return nil end
    local t = dot(normal, sub(corners.tl, origin)) / denom
    if t <= 0 then return nil end
    local offset = sub(add(origin, scale(dir, t)), corners.tl)
    local u, v = dot(offset, e1) / dot(e1, e1), dot(offset, e2) / dot(e2, e2)
    if u < 0 or u > 1 or v < 0 or v > 1 then return nil end
    return u, v
end

local pools = {}
local registered = false

-- Runtime txd names must be unique per resource start; a name that existed
-- before a restart crashes CreateRuntimeTxd.
local START_SUFFIX = (tostring({}):match('%x+$') or 'x'):sub(-8)

local Pool = {}
Pool.__index = Pool

local function slotUrl(pool, slot)
    local separator = pool.url:find('?', 1, true) and '&' or '?'
    return ('%s%spool=%s&slot=%d&gen=%d'):format(pool.url, separator, pool.name, slot.index, slot.generation)
end

local function emptyPending(pool)
    if pool.queue then return {} end
    return nil
end

local function flush(slot)
    if type(slot.pending) == 'table' then
        for _, message in ipairs(slot.pending) do SendDuiMessage(slot.dui, message) end
        slot.pending = {}
    elseif slot.pending then
        SendDuiMessage(slot.dui, slot.pending)
        slot.pending = nil
    end
end

-- (Re)loads the slot's page under a new generation; a page that does not
-- report ready before the timeout is passed to onFailed.
local function beginLoad(pool, slot)
    slot.generation = slot.generation + 1
    slot.ready = false
    slot.pending = emptyPending(pool)
    slot.lastX, slot.lastY = nil, nil
    local url = slotUrl(pool, slot)
    if slot.dui then
        SetDuiUrl(slot.dui, url)
    else
        slot.dui = CreateDui(url, pool.width, pool.height)
    end
    local generation = slot.generation
    local deadline = GetGameTimer() + pool.readyTimeout
    CreateThread(function()
        while not slot.ready and slot.generation == generation and GetGameTimer() < deadline do
            Wait(100)
        end
        if not slot.ready and slot.generation == generation and pool.onFailed then
            pool.onFailed(slot.index, slot.owner)
        end
    end)
end

local function createSlot(pool, index, owner)
    local slot = { index = index, owner = owner, generation = 0, ready = false }
    pool.slots[index] = slot
    beginLoad(pool, slot)
    slot.runtime = ('%s_%02d_%s'):format(pool.name, index, START_SUFFIX)
    slot.txd = pool.txd(index)
    slot.texture = pool.texture(index)
    local runtimeTxd = CreateRuntimeTxd(slot.runtime)
    CreateRuntimeTextureFromDuiHandle(runtimeTxd, slot.runtime, GetDuiHandle(slot.dui))
    AddReplaceTexture(slot.txd, slot.texture, slot.runtime, slot.runtime)
    return slot
end

local function readySlot(pool, index)
    local slot = pool.slots[index]
    if slot and slot.ready then return slot end
    return nil
end

function Pool:Acquire(owner)
    assert(owner ~= nil, 'Bridge.DUI: Acquire needs an owner')
    for index = 1, self.count do
        local slot = self.slots[index]
        if slot and slot.owner == owner then return index end
    end
    for index = 1, self.count do
        local slot = self.slots[index]
        if not slot then
            createSlot(self, index, owner)
            return index
        end
        if slot.owner == nil then
            slot.owner = owner
            beginLoad(self, slot)
            return index
        end
    end
    return nil
end

function Pool:Release(index)
    local slot = self.slots[index]
    if not slot or slot.owner == nil then return end
    slot.owner = nil
    slot.ready = false
    slot.generation = slot.generation + 1
    slot.pending = emptyPending(self)
    SetDuiUrl(slot.dui, 'about:blank')
end

function Pool:Send(index, message)
    local slot = self.slots[index]
    if not slot or slot.owner == nil then return false end
    if type(message) ~= 'string' then message = json.encode(message) end
    if slot.ready then
        SendDuiMessage(slot.dui, message)
    elseif self.queue then
        if #slot.pending >= self.maxPending then table.remove(slot.pending, 1) end
        slot.pending[#slot.pending + 1] = message
    else
        slot.pending = message
    end
    return true
end

function Pool:MouseMove(index, x, y)
    local slot = readySlot(self, index)
    if not slot then return end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if slot.lastX == x and slot.lastY == y then return end
    slot.lastX, slot.lastY = x, y
    SendDuiMouseMove(slot.dui, x, y)
end

function Pool:MouseMoveUV(index, u, v)
    self:MouseMove(index, u * (self.width - 1), v * (self.height - 1))
end

function Pool:MouseDown(index, button)
    local slot = readySlot(self, index)
    if slot then SendDuiMouseDown(slot.dui, button) end
end

function Pool:MouseUp(index, button)
    local slot = readySlot(self, index)
    if slot then SendDuiMouseUp(slot.dui, button) end
end

function Pool:MouseWheel(index, deltaY, deltaX)
    local slot = readySlot(self, index)
    if slot then SendDuiMouseWheel(slot.dui, deltaY, deltaX or 0) end
end

function Pool:Owner(index)
    local slot = self.slots[index]
    return slot and slot.owner
end

function Pool:IsReady(index)
    return readySlot(self, index) ~= nil
end

function Pool:Model(index)
    return self.model(index)
end

function Pool:Count()
    return self.count
end

function Pool:Destroy()
    for _, slot in pairs(self.slots) do
        SetDuiUrl(slot.dui, 'about:blank')
        DestroyDui(slot.dui)
        RemoveReplaceTexture(slot.txd, slot.texture)
    end
    self.slots = {}
    pools[self.name] = nil
end

local function handleReady(data, cb)
    cb('ok')
    if type(data) ~= 'table' then return end
    local pool = pools[data.pool]
    local slot = pool and pool.slots[tonumber(data.slot or 0)]
    if not slot or slot.owner == nil or slot.ready or tonumber(data.gen or 0) ~= slot.generation then return end
    slot.ready = true
    flush(slot)
    if pool.onReady then pool.onReady(slot.index, slot.owner) end
end

local function handleResourceStop(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, pool in pairs(pools) do pool:Destroy() end
end

local function ensureRegistered()
    if registered then return end
    registered = true
    RegisterNUICallback('bridgeDuiReady', handleReady)
    AddEventHandler('onResourceStop', handleResourceStop)
end

function Bridge.DUI.CreatePool(name, opts)
    assert(type(name) == 'string' and pools[name] == nil, 'Bridge.DUI: pool name missing or already used')
    ensureRegistered()
    local pool = setmetatable({
        name = name,
        count = opts.count,
        width = opts.width,
        height = opts.height,
        url = opts.url,
        model = opts.model,
        txd = opts.txd or function(index) return opts.model(index) .. '_t' end,
        texture = opts.texture,
        queue = opts.pending == 'queue',
        maxPending = opts.maxPending or 256,
        readyTimeout = opts.readyTimeout or 8000,
        onReady = opts.onReady,
        onFailed = opts.onFailed,
        slots = {},
    }, Pool)
    pools[name] = pool
    return pool
end
