local Device = require("device")

if not Device:isKindle() then
    return { disabled = true }
end

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local BtBackend = require("bt_backend")
local VolumeBackend = require("volume_backend")

local KindleAudio = WidgetContainer:extend{
    name = "bluetooth",
    is_doc_only = false,
}

local function deviceLabel(device)
    if device.address and device.name and device.name ~= device.address then
        return string.format("%s\n%s", device.name, device.address)
    end
    return device.name or device.address or _("Unknown device")
end

local function stateLabel(state)
    if state == 0 then
        return _("off")
    elseif state == 1 then
        return _("on")
    elseif state == 2 then
        return _("connected")
    end
    return T(_("unknown (%1)"), state or _("nil"))
end

local function operatingModeLabel(mode)
    if mode == 0 then
        return _("none")
    elseif mode == 1 then
        return _("non-audio")
    elseif mode == 2 then
        return _("audio")
    end
    return T(_("unknown (%1)"), mode or _("nil"))
end

local function refreshMenu(touchmenu_instance)
    if not touchmenu_instance then return end
    touchmenu_instance:updateItems()
    UIManager:scheduleIn(1, function()
        touchmenu_instance:updateItems()
    end)
    UIManager:scheduleIn(3, function()
        touchmenu_instance:updateItems()
    end)
end

local function formatRawDevice(device)
    local lines = {
        T(_("Name: %1"), device.name or _("unknown")),
        T(_("Address: %1"), device.address or _("unknown")),
        T(_("Source: %1"), device.source or _("unknown")),
    }
    if device.raw then
        table.insert(lines, "")
        table.insert(lines, _("Raw fields:"))
        for key, value in pairs(device.raw) do
            table.insert(lines, string.format("%s=%s", tostring(key), tostring(value)))
        end
    end
    return table.concat(lines, "\n")
end

function KindleAudio:init()
    self.ui.menu:registerToMainMenu(self)
end

function KindleAudio:addToMainMenu(menu_items)
    menu_items.bluetooth_manager = {
        text = _("Bluetooth"),
        sorting_hint = "network",
        sub_item_table = {
            {
                text_func = function()
                    local status = BtBackend:getStatus()
                    if not status.available then
                        return _("Status: unavailable")
                    end
                    if status.connected_name and status.connected_name ~= "" then
                        return T(_("Status: connected to %1"), status.connected_name)
                    end
                    return T(_("Status: %1"), stateLabel(status.state))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    refreshMenu(touchmenu_instance)
                    self:showStatus()
                end,
            },
            {
                text = _("Scan for audio devices"),
                keep_menu_open = true,
                callback = function(touchmenu_instance) self:scanDevices(touchmenu_instance) end,
            },
            {
                text = _("Paired devices"),
                keep_menu_open = true,
                callback = function() self:showDeviceList("paired") end,
            },
            {
                text = _("Connected devices"),
                keep_menu_open = true,
                callback = function() self:showDeviceList("connected") end,
            },
            {
                text = _("Discovered devices"),
                keep_menu_open = true,
                callback = function() self:showDeviceList("discovered") end,
            },
            {
                text = _("Enable Bluetooth"),
                keep_menu_open = true,
                callback = function(touchmenu_instance) self:enableBluetooth(touchmenu_instance) end,
            },
            {
                text = _("Disable Bluetooth"),
                keep_menu_open = true,
                callback = function(touchmenu_instance) self:disableBluetooth(touchmenu_instance) end,
            },
        },
    }

    menu_items.audio_volume = {
        text = _("Audio volume"),
        sorting_hint = "screen",
        callback = function()
            self:showVolumePanel()
        end,
    }
end

function KindleAudio:checkAvailable()
    if BtBackend:isAvailable() then
        return true
    end

    UIManager:show(InfoMessage:new{
        text = _("Bluetooth service is not available."),
    })
    return false
end

function KindleAudio:showStatus()
    local status = BtBackend:getStatus()
    if not status.available then
        UIManager:show(InfoMessage:new{ text = _("Bluetooth service is not available.") })
        return
    end

    local text = T(_([[Bluetooth state: %1
Operating mode: %2
Connected device: %3
Pairing helper running: %4
Audio manager running: %5]]),
        stateLabel(status.state),
        operatingModeLabel(status.operating_mode),
        (status.connected_name and status.connected_name ~= "") and status.connected_name or _("none"),
        status.is_btch_running or 0,
        status.audio_manager_running and _("yes") or _("no"))

    UIManager:show(InfoMessage:new{ text = text })
end

function KindleAudio:enableBluetooth(touchmenu_instance)
    local ok, err = BtBackend:enable()
    refreshMenu(touchmenu_instance)
    UIManager:show(InfoMessage:new{
        text = ok and _("Bluetooth enable requested.") or tostring(err or _("Failed to enable Bluetooth.")),
        timeout = 3,
    })
end

function KindleAudio:disableBluetooth(touchmenu_instance)
    UIManager:show(ConfirmBox:new{
        text = _("Disable Bluetooth?"),
        ok_text = _("Disable"),
        ok_callback = function()
            local ok, err = BtBackend:disable()
            refreshMenu(touchmenu_instance)
            UIManager:show(InfoMessage:new{
                text = ok and _("Bluetooth disable requested.") or tostring(err or _("Failed to disable Bluetooth.")),
                timeout = 3,
            })
        end,
    })
end

function KindleAudio:scanDevices(touchmenu_instance)
    if not self:checkAvailable() then return end

    local info = InfoMessage:new{ text = _("Scanning for Bluetooth audio devices…") }
    UIManager:show(info)
    UIManager:forceRePaint()

    local ok = BtBackend:scan()
    UIManager:close(info)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Failed to start Bluetooth scan.") })
        return
    end
    refreshMenu(touchmenu_instance)

    UIManager:show(InfoMessage:new{
        text = _("Bluetooth scan requested. Open discovered devices after a few seconds."),
        timeout = 3,
    })
end

function KindleAudio:getDevices(kind)
    if kind == "connected" then
        return BtBackend:getConnectedDevices()
    elseif kind == "discovered" then
        return BtBackend:getDiscoveredDevices()
    end
    return BtBackend:getPairedDevices()
end

function KindleAudio:showDeviceList(kind)
    if not self:checkAvailable() then return end

    local devices, err = self:getDevices(kind)
    if devices == nil then
        UIManager:show(InfoMessage:new{ text = tostring(err or _("Failed to read Bluetooth devices.")) })
        return
    end

    if #devices == 0 then
        UIManager:show(InfoMessage:new{ text = _("No Bluetooth devices found."), timeout = 3 })
        return
    end

    local items = {}
    for _, device in ipairs(devices) do
        table.insert(items, {
            text = deviceLabel(device),
            callback = function()
                self:showDeviceActions(device, kind)
            end,
        })
    end

    local title = kind == "connected" and _("Connected Bluetooth devices")
        or kind == "discovered" and _("Discovered Bluetooth devices")
        or _("Paired Bluetooth devices")

    UIManager:show(Menu:new{
        title = title,
        item_table = items,
        parent = self.ui,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        show_captions = true,
        multilines_show_more_text = true,
        onMenuSelect = function(_, item)
            if item.callback then item.callback() end
        end,
    })
end

function KindleAudio:showDeviceActions(device, kind)
    local buttons = {}
    local dialog
    local closeAndRun = function(progress_text, action)
        if dialog then
            UIManager:close(dialog)
        end
        self:runDeviceAction(progress_text, action)
    end

    if kind ~= "connected" then
        table.insert(buttons, {
            {
                text = _("Connect"),
                callback = function()
                    closeAndRun(_("Connecting…"), function() return BtBackend:connect(device) end)
                end,
            },
            {
                text = _("Ensure connection"),
                callback = function()
                    closeAndRun(_("Connecting…"), function() return BtBackend:ensureConnection(device) end)
                end,
            },
        })
    else
        table.insert(buttons, {
            {
                text = _("Disconnect"),
                callback = function()
                    closeAndRun(_("Disconnecting…"), function() return BtBackend:disconnect(device) end)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("Pair"),
            callback = function()
                closeAndRun(_("Pairing…"), function() return BtBackend:bond(device) end)
            end,
        },
        {
            text = _("Forget"),
            callback = function()
                if dialog then
                    UIManager:close(dialog)
                end
                self:confirmUnbond(device)
            end,
        },
    })

    table.insert(buttons, {
        {
            text = _("Details"),
            callback = function()
                UIManager:show(InfoMessage:new{ text = formatRawDevice(device) })
            end,
        },
    })

    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                if dialog then
                    UIManager:close(dialog)
                end
            end,
        },
    })

    dialog = ButtonDialog:new{
        title = deviceLabel(device),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function KindleAudio:confirmUnbond(device)
    UIManager:show(ConfirmBox:new{
        text = T(_("Forget Bluetooth device %1?"), device.name or device.address or _("Unknown device")),
        ok_text = _("Forget"),
        ok_callback = function()
            self:runDeviceAction(_("Forgetting…"), function() return BtBackend:unbond(device) end)
        end,
    })
end

function KindleAudio:runDeviceAction(progress_text, action)
    local info = InfoMessage:new{ text = progress_text }
    UIManager:show(info)
    UIManager:forceRePaint()

    local ok, err = action()
    UIManager:close(info)
    if ok then
        if self.ui and self.ui.menu and self.ui.menu.updateItems then
            self.ui.menu:updateItems()
        end
        UIManager:show(InfoMessage:new{ text = _("Bluetooth request sent."), timeout = 3 })
    else
        logger.warn("KindleAudio Bluetooth action failed:", err)
        UIManager:show(InfoMessage:new{ text = tostring(err or _("Bluetooth request failed.")) })
    end
end

function KindleAudio:showVolumePanel()
    local status = VolumeBackend:getStatus()
    if not status.available then
        UIManager:show(InfoMessage:new{
            text = _("Audio manager is not available. Enable Bluetooth audio first."),
        })
        return
    end

    local VolumeWidget = require("volume_widget")
    UIManager:show(VolumeWidget:new{ backend = VolumeBackend })
end

return KindleAudio
