local esxCallbacks

function Bridge.GetESXCallbacks()
    if esxCallbacks then return esxCallbacks end
    if GetResourceState('esx_lib') ~= 'started' then return nil end
    local version = GetResourceMetadata('es_extended', 'version', 0) or ''
    local major, minor = version:match('^(%d+)%.(%d+)')
    major, minor = tonumber(major), tonumber(minor)
    if not major or major < 1 or (major == 1 and minor < 15) then return nil end

    -- Import ESX's callback library into this resource so its handlers are
    -- removed on restart. Keep its require/global setup away from other libs.
    local source = assert(LoadResourceFile('esx_lib', 'imports.lua'), 'Missing esx_lib/imports.lua')
    local environment = setmetatable({}, { __index = _ENV })
    environment.load = function(chunk, name, mode, customEnvironment)
        return load(chunk, name, mode, customEnvironment or environment)
    end
    assert(load(source, '@@esx_lib/imports.lua', 't', environment))()
    esxCallbacks = environment.xLib.callback
    return esxCallbacks
end

function Bridge.ESXCallbackName(name)
    -- Avoid legacy ESX-owned handlers left behind by previous resource runs.
    return 'roadphone:bridge:' .. name
end
