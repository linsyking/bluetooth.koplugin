local logger = require("logger")

local BtBackend = {
    publisher = "com.lab126.btfd",
    appname = "com.github.koreader.bluetooth",
}

local ADDRESS_KEYS = { "address", "bdaddr", "bdAddr", "mac", "deviceAddress", "addr", "id" }
local NAME_KEYS = { "name", "deviceName", "friendlyName", "displayName", "BTconnectedDevName" }

local function normalizeAddress(address)
    if type(address) ~= "string" then return nil end
    address = address:gsub("-", ":"):upper()
    if address:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return address
    end
end

local function firstField(row, keys)
    for _, key in ipairs(keys) do
        if row[key] ~= nil and row[key] ~= "" then
            return tostring(row[key])
        end
    end
end

function BtBackend:_withHandle(callback)
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
        logger.warn("KindleAudio: Bluetooth LIPC call failed:", result)
        return nil, result
    end
    return result, err
end

function BtBackend:_withHashHandle(callback)
    local ok, lipc = pcall(require, "libopenlipclua")
    if not ok then
        return nil, "libopenlipclua is not available"
    end

    local handle = lipc.open_no_name()
    if not handle then
        return nil, "Unable to open LIPC hash handle"
    end

    local success, result, err = pcall(callback, handle)
    handle:close()

    if not success then
        logger.warn("KindleAudio: Bluetooth LIPC hash call failed:", result)
        return nil, result
    end
    return result, err
end

function BtBackend:getIntProperty(prop)
    return self:_withHandle(function(handle)
        return handle:get_int_property(self.publisher, prop)
    end)
end

function BtBackend:getStringProperty(prop)
    return self:_withHandle(function(handle)
        return handle:get_string_property(self.publisher, prop)
    end)
end

function BtBackend:setIntProperty(prop, value)
    return self:_withHandle(function(handle)
        handle:set_int_property(self.publisher, prop, value)
        return true
    end)
end

function BtBackend:setStringProperty(prop, value)
    return self:_withHandle(function(handle)
        handle:set_string_property(self.publisher, prop, value)
        return true
    end)
end

function BtBackend:isAvailable()
    return self:getIntProperty("BTstate") ~= nil
end

function BtBackend:getStatus()
    local state = self:getIntProperty("BTstate")
    if state == nil then
        return { available = false }
    end
    return {
        available = true,
        state = state,
        connected_name = self:getStringProperty("BTconnectedDevName"),
        operating_mode = self:getIntProperty("currentBTOperatingMode"),
        has_never_paired = self:getIntProperty("hasNeverPaired"),
        is_btch_running = self:getIntProperty("isBtchRunning"),
        audio_manager_running = self:isAudioManagerRunning(),
    }
end

function BtBackend:isAudioManagerRunning()
    local handle, err = io.popen("initctl status audiomgrd 2>/dev/null", "r")
    if not handle then
        logger.warn("KindleAudio: failed to query audiomgrd:", err)
        return false
    end
    local output = handle:read("*a") or ""
    handle:close()
    return output:find("start/running") ~= nil
end

function BtBackend:readHashProperty(prop)
    return self:_withHashHandle(function(handle)
        local input = handle:new_hasharray()
        local result = handle:access_hash_property(self.publisher, prop, input)
        input:destroy()
        if result == nil then return {} end
        local rows = result:to_table() or {}
        result:destroy()
        return rows
    end)
end

function BtBackend:normalizeDevice(row, source)
    local address = normalizeAddress(firstField(row, ADDRESS_KEYS))
    if not address then
        for _, value in pairs(row) do
            address = normalizeAddress(tostring(value))
            if address then break end
        end
    end

    local name = firstField(row, NAME_KEYS) or address or "Unknown device"

    return {
        name = name,
        address = address,
        source = source,
        raw = row,
    }
end

function BtBackend:getDevices(prop, source)
    local rows, err = self:readHashProperty(prop)
    if rows == nil then
        return nil, err
    end

    local devices = {}
    for _, row in ipairs(rows) do
        table.insert(devices, self:normalizeDevice(row, source))
    end
    return devices
end

function BtBackend:getPairedDevices()
    return self:getDevices("ListPaired", "paired")
end

function BtBackend:getConnectedDevices()
    return self:getDevices("ListConnected", "connected")
end

function BtBackend:getDiscoveredDevices()
    return self:getDevices("ListDiscovered", "discovered")
end

function BtBackend:scan()
    local ok = self:setIntProperty("triggerBTscan", 1)
    if not ok then
        ok = self:setIntProperty("DiscoverA2DP", 1)
    end
    return ok ~= nil
end

function BtBackend:enable()
    -- Format is <enable-value>:<mode>. Mode 2 matches Kindle Settings audio output.
    return self:setStringProperty("BTenable", "1:2")
end

function BtBackend:disable()
    return self:setStringProperty("BTenable", "0:2")
end

function BtBackend:connect(device)
    if not device or not device.address then
        return false, "No Bluetooth address found for this device."
    end
    local ok, err = self:setStringProperty("Connect", device.address)
    if not ok then return false, err end
    return true
end

function BtBackend:disconnect(device)
    if not device or not device.address then
        return false, "No Bluetooth address found for this device."
    end
    local ok, err = self:setStringProperty("Disconnect", device.address)
    if not ok then return false, err end
    return true
end

function BtBackend:bond(device)
    if not device or not device.address then
        return false, "No Bluetooth address found for this device."
    end
    local ok, err = self:setStringProperty("Bond", device.address)
    if not ok then return false, err end
    return true
end

function BtBackend:unbond(device)
    if not device or not device.address then
        return false, "No Bluetooth address found for this device."
    end
    local ok, err = self:setStringProperty("Unbond", device.address)
    if not ok then return false, err end
    return true
end

function BtBackend:ensureConnection(device)
    if not device or not device.address then
        return false, "No Bluetooth address found for this device."
    end
    local ok, err = self:setStringProperty("ensureBTconnection", device.address)
    if not ok then return false, err end
    return true
end

return BtBackend
