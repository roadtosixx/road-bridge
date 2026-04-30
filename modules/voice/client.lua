-- Voice Plugin Bridge (Client)
-- Wraps mumble-voip / pma-voice / saltychat / yaca-voice behind a single API.

Bridge.Voice = Bridge.Voice or {}

local function isSaltyLike()
    return Config.UseSaltyChat or Config.UseYacaVoice
end

local function isMumbleLike()
    return Config.UseMumbleVoip or Config.UsePmaVoice
end

local function getMumbleExport()
    if Config.UseMumbleVoip then return exports[Config.MumbleExport] end
    if Config.UsePmaVoice then return exports[Config.PMAVoiceExport] end
    return nil
end

function Bridge.Voice.IsAnyEnabled()
    return Config.UseMumbleVoip or Config.UsePmaVoice or Config.UseSaltyChat or Config.UseYacaVoice
end

function Bridge.Voice.AddPlayerToCall(channel)
    if isMumbleLike() then
        local exp = getMumbleExport()
        if exp then exp:addPlayerToCall(channel) end
    elseif isSaltyLike() then
        TriggerServerEvent("roadphone:server:call:saltychat", channel)
    end
end

function Bridge.Voice.RemovePlayerFromCall(channel)
    if isMumbleLike() then
        local exp = getMumbleExport()
        if exp then exp:removePlayerFromCall() end
    elseif isSaltyLike() then
        TriggerServerEvent("roadphone:server:call:saltychat:end", channel)
    end
end

function Bridge.Voice.SetSpeaker(state)
    if isSaltyLike() then
        TriggerServerEvent("roadphone:server:call:saltychat:speaker", state)
    end
    -- Mumble/PMA: speaker not natively supported; no-op
end

-- Resets mute state both server-side (for mumble/pma) and locally
function Bridge.Voice.ResetMute(currentMuteState)
    if not currentMuteState then return false end
    if isMumbleLike() then
        TriggerServerEvent("roadphone:call:mute", GetPlayerServerId(PlayerId()), false)
    end
    return false
end
