local resource = GetCurrentResourceName()
local source = assert(LoadResourceFile(resource, 'bridge/vendor/require.lua'), 'Missing bridge/vendor/require.lua')

-- Keep ox_lib's module cache and helpers intact; Bridge modules still share globals.
local environment = setmetatable({
    package = false,
    require = require,
    runtime = {},
    loadfile = false,
    dofile = false,
    json = setmetatable({}, { __index = json }),
}, { __index = _ENV, __newindex = _ENV })

local require = assert(load(source, '@@' .. resource .. '/bridge/vendor/require.lua', 't', environment))()
require('bridge.main')
Bridge.Require = require
require('bridge.modules.helpers')
require('bridge.modules.callback.shared')
require('bridge.modules.events.shared')
require('bridge.modules.locale.shared')
require('bridge.modules.voice.shared')
