-- Voice Plugin Bridge (Server)
-- Call channel members for YaCA, pma-voice and mumble-voip; SaltyChat keeps
-- its own. YaCA itself only connects two players (callPlayer), so every member
-- is paired with every other one here and YaCA's SaltyChat bridge is not
-- needed. pma-voice and mumble-voip connect the call on the client and only
-- learn about the phone mute from here.

Bridge.Voice = Bridge.Voice or {}

local YACA = 'yaca-voice'

local channels = {}  -- channel -> { [source] = true }
local channelOf = {} -- source -> channel
local muted = {}     -- source -> true while muted on the phone, also before the call connects
local speaker = {}   -- source -> true while the speaker is on, also before the call connects

local function tracksChannels()
    return Config.UseYacaVoice or Config.UsePmaVoice or Config.UseMumbleVoip
end

local function otherMembers(channel, src)
    local others = {}
    for member in pairs(channels[channel] or {}) do
        if member ~= src then others[#others + 1] = member end
    end
    return others
end

-- Mute and speaker only mean something while the player is connected to
-- someone: unmuting a YaCA player in no call claims a phone device for nobody.
local function hasPeers(src)
    local channel = channelOf[src]
    return channel ~= nil and #otherMembers(channel, src) > 0
end

-- pma-voice and mumble-voip have no call-only mute, so the muted player is
-- turned down on the clients of the other members. inCall is false once the
-- two are no longer in a call together and the call volume must not return.
local function relayMute(listener, mutedSource, state, inCall)
    TriggerClientEvent('roadphone:client:voice:memberMuted', listener, mutedSource, state, inCall)
end

-- callPlayer(false) unmutes both players and turns their speaker off, even
-- when one of them stays in a group call; callPlayer(true) lets a new member
-- hear a muted one. Re-apply both for everyone left in the channel.
local function reapplyYacaState(channel)
    for member in pairs(channels[channel] or {}) do
        if hasPeers(member) then
            if muted[member] then exports[YACA]:muteOnPhone(member, true) end
            if speaker[member] then exports[YACA]:enablePhoneSpeaker(member, true) end
        end
    end
end

local function leave(src)
    local channel = channelOf[src]
    if not channel then return end

    local others = otherMembers(channel, src)
    local wasMuted = muted[src]
    channelOf[src] = nil
    channels[channel][src] = nil
    if not next(channels[channel]) then channels[channel] = nil end
    muted[src] = nil
    speaker[src] = nil

    if Config.UseYacaVoice then
        for _, member in ipairs(others) do
            exports[YACA]:callPlayer(src, member, false)
        end
        reapplyYacaState(channel)
        return
    end

    for _, member in ipairs(others) do
        if wasMuted then relayMute(member, src, false, false) end
        if muted[member] then relayMute(src, member, false, false) end
    end
end

local function join(src, channel)
    if channelOf[src] == channel then return end
    leave(src)

    local others = otherMembers(channel, src)
    channels[channel] = channels[channel] or {}
    channels[channel][src] = true
    channelOf[src] = channel

    if Config.UseYacaVoice then
        for _, member in ipairs(others) do
            exports[YACA]:callPlayer(src, member, true)
        end
        reapplyYacaState(channel)
        return
    end

    for _, member in ipairs(others) do
        if muted[src] then relayMute(member, src, true, true) end
        if muted[member] then relayMute(src, member, true, true) end
    end
end

function Bridge.Voice.JoinCall(src, channel)
    if Config.UseSaltyChat then
        exports[Config.SaltyExport]:AddPlayerToCall(channel, src)
    elseif tracksChannels() then
        join(src, channel)
    end
end

function Bridge.Voice.LeaveCall(src, channel)
    if Config.UseSaltyChat then
        if channel then exports[Config.SaltyExport]:RemovePlayerFromCall(channel, src) end
    elseif tracksChannels() then
        leave(src)
    end
end

function Bridge.Voice.SetSpeaker(src, state)
    if Config.UseSaltyChat then
        exports[Config.SaltyExport]:SetPhoneSpeaker(src, state)
    elseif Config.UseYacaVoice then
        speaker[src] = state or nil
        if hasPeers(src) then exports[YACA]:enablePhoneSpeaker(src, state) end
    end
end

-- Without a peer the state is kept for the next join.
function Bridge.Voice.SetCallMuted(src, state)
    if not tracksChannels() then return end
    muted[src] = state or nil
    if not hasPeers(src) then return end

    if Config.UseYacaVoice then
        exports[YACA]:muteOnPhone(src, state)
        return
    end

    for _, member in ipairs(otherMembers(channelOf[src], src)) do
        relayMute(member, src, state, true)
    end
end

-- Group ids arrive as 12 or "12" depending on the path; both mean one channel.
local function readChannel(channel)
    if type(channel) == 'number' then
        channel = tostring(math.tointeger(channel) or channel)
    end
    if type(channel) ~= 'string' or channel == '' or #channel > 64 then return nil end
    return channel
end

RegisterNetEvent('roadphone:server:voice:joinCall', function(channel)
    channel = readChannel(channel)
    if channel then Bridge.Voice.JoinCall(source, channel) end
end)

RegisterNetEvent('roadphone:server:voice:leaveCall', function(channel)
    Bridge.Voice.LeaveCall(source, readChannel(channel))
end)

RegisterNetEvent('roadphone:server:voice:speaker', function(state)
    Bridge.Voice.SetSpeaker(source, state == true)
end)

AddEventHandler('playerDropped', function()
    local src = source
    leave(src)
    muted[src] = nil
    speaker[src] = nil
end)
