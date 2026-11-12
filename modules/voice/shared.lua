-- Voice Plugin Bridge (Shared)

Bridge.Voice = Bridge.Voice or {}

-- YaCA keys a radio channel by its frequency string, so 100, "100" and 100.0
-- have to become the same text on the client and on the server.
function Bridge.Voice.RadioFrequency(value)
    local frequency = tonumber(value)
    if not frequency then return nil end
    local text = ('%.3f'):format(frequency):gsub('0+$', ''):gsub('%.$', '')
    return text
end
