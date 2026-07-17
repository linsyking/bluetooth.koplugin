local logger = require("logger")

local VolumeBackend = {
    publisher = "com.lab126.audiomgrd",
    appname = "com.github.koreader.kindleaudio",
    min = 1,
    max = 8,
}

function VolumeBackend:_withHandle(callback)
    local ok, lipc = pcall(require, "liblipclua")
    if not ok then
        return nil, "liblipclua is not available"
    end

    local handle = lipc.init(self.appname)
    if not handle then
        return nil, "Unable to open LIPC handle"
    end

    local success, result, err = pcall(callback, handle)
    handle:close()

    if not success then
        logger.warn("KindleAudio: Volume LIPC call failed:", result)
        return nil, result
    end
    return result, err
end

function VolumeBackend:getIntProperty(prop)
    return self:_withHandle(function(handle)
        return handle:get_int_property(self.publisher, prop)
    end)
end

function VolumeBackend:setIntProperty(prop, value)
    return self:_withHandle(function(handle)
        handle:set_int_property(self.publisher, prop, value)
        return true
    end)
end

function VolumeBackend:getStatus()
    local is_started = self:getIntProperty("isStarted")
    if is_started == nil then
        return {
            available = false,
            message = "Audio manager is not available.",
        }
    end

    return {
        available = true,
        is_started = is_started,
        output_connected = self:getIntProperty("audioOutputConnected") or 0,
        current_output = self:getIntProperty("audioCurrentOutput") or 0,
        volume = self:getVolume(),
    }
end

function VolumeBackend:getVolume()
    local raw = self:getRawVolume()
    if raw == nil then return nil end
    return math.max(self.min, math.min(self.max, math.floor((raw + 5) / 10)))
end

function VolumeBackend:getRawVolume()
    return self:getIntProperty("speakerVolume")
end

function VolumeBackend:setVolume(volume)
    volume = tonumber(volume)
    if not volume then
        return false, "Invalid volume."
    end
    volume = math.max(self.min, math.min(self.max, math.floor(volume + 0.5)))

    local raw_volume = volume * 10
    local ok, err = self:setIntProperty("speakerVolume", volume)
    if not ok then
        return false, err or "Failed to set audio volume."
    end

    local actual_raw = self:getRawVolume()
    if actual_raw == nil then
        return false, "Volume was set, but readback failed."
    end

    local actual = math.max(self.min, math.min(self.max, math.floor((actual_raw + 5) / 10)))
    if actual_raw ~= raw_volume then
        return true, nil, actual
    end

    return true, nil, actual
end

return VolumeBackend
