-- Voice Plugin Bridge (Client)
-- Wraps mumble-voip / pma-voice / saltychat / yaca-voice behind a single API.
-- Call channels and the phone mute are kept on the server (voice/server.lua).

Bridge.Voice = Bridge.Voice or {}

local function isServerSide()
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

-- Call screen buttons the voice plugin can serve; the NUI disables the rest.
function Bridge.Voice.Features()
    return {
        mute = (Config.UseMumbleVoip or Config.UsePmaVoice or Config.UseYacaVoice) == true,
        speaker = (Config.UseSaltyChat or Config.UseYacaVoice) == true,
    }
end

-- pma-voice and mumble-voip: the server is told after the plugin joined and
-- before it leaves, so a member's mute lands on top of the call volume and a
-- lifted mute never hides the plugin's own clean-up.
function Bridge.Voice.AddPlayerToCall(channel)
    if isMumbleLike() then
        local exp = getMumbleExport()
        if exp then exp:addPlayerToCall(channel) end
        TriggerServerEvent("roadphone:server:voice:joinCall", channel)
    elseif isServerSide() then
        TriggerServerEvent("roadphone:server:voice:joinCall", channel)
    end
end

function Bridge.Voice.RemovePlayerFromCall(channel)
    if isMumbleLike() then
        TriggerServerEvent("roadphone:server:voice:leaveCall", channel)
        local exp = getMumbleExport()
        if exp then exp:removePlayerFromCall() end
    elseif isServerSide() then
        TriggerServerEvent("roadphone:server:voice:leaveCall", channel)
    end
end

function Bridge.Voice.SetSpeaker(state)
    if isServerSide() then
        TriggerServerEvent("roadphone:server:voice:speaker", state == true)
    end
    -- Mumble/PMA: speaker not natively supported; no-op
end

local phoneMuted = {} -- server id -> true while turned down here because they muted their call

-- A call member muted their phone: only the members of that call stop hearing
-- them. pma-voice keeps a player in toggleMutePlayer out of its own volume
-- changes; mumble-voip only sets the call volume (1.0) when someone joins.
local function setMemberMuted(serverId, state, inCall)
    if state == (phoneMuted[serverId] == true) then return end

    if Config.UsePmaVoice then
        local pma = exports[Config.PMAVoiceExport]
        if state then
            -- muted by someone else already; that mute is not the phone's to lift
            if pma:isPlayerMuted(serverId) then return end
            pma:toggleMutePlayer(serverId)
        else
            if pma:isPlayerMuted(serverId) then pma:toggleMutePlayer(serverId) end
            -- toggleMutePlayer drops the volume override, which leaves a call
            -- partner who is far away inaudible
            if inCall then MumbleSetVolumeOverrideByServerId(serverId, pma:getCallVolume() / 100) end
        end
    elseif Config.UseMumbleVoip then
        MumbleSetVolumeOverrideByServerId(serverId, state and 0.0 or (inCall and 1.0 or -1.0))
    end

    phoneMuted[serverId] = state or nil
end

RegisterNetEvent('roadphone:client:voice:memberMuted', setMemberMuted)
