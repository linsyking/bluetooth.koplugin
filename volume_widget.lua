local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local Math = require("optmath")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Screen = Device.screen

local VolumeWidget = FocusManager:extend{
    name = "VolumeWidget",
    backend = nil,
}

function VolumeWidget:init()
    self.font = Font:getFace("ffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    self.width = math.floor(self.screen_width * 0.90)
    self.inner_width = self.width - 2 * Size.padding.large
    self.button_width = math.floor(self.inner_width / 4)
    self.min = self.backend.min or 1
    self.max = self.backend.max or 8
    self.volume = self.backend:getVolume() or self.min
    self.volume = math.max(self.min, math.min(self.max, self.volume))

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self:buildLayout()
end

function VolumeWidget:buildLayout()
    self.progress = ProgressWidget:new{
        width = self.inner_width,
        height = Size.item.height_big,
        percentage = (self.volume - self.min) / (self.max - self.min),
        last = self.max,
    }

    self.level = TextWidget:new{
        text = tostring(self.volume),
        face = self.font,
        max_width = self.inner_width - 2 * self.button_width,
    }

    local level_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.level.max_width,
            h = self.level:getSize().h,
        },
        self.level,
    }

    self.minus = Button:new{
        text = "-",
        width = self.button_width,
        show_parent = self,
        callback = function() self:setVolume(self.volume - 1) end,
    }

    self.plus = Button:new{
        text = "+",
        width = self.button_width,
        show_parent = self,
        callback = function() self:setVolume(self.volume + 1) end,
    }

    local mute = Button:new{
        text = _("Min"),
        width = self.button_width,
        show_parent = self,
        callback = function() self:setVolume(self.min) end,
    }

    local half = Button:new{
        text = "4",
        width = self.button_width,
        show_parent = self,
        callback = function() self:setVolume(4) end,
    }

    local max = Button:new{
        text = _("Max"),
        width = self.button_width,
        show_parent = self,
        callback = function() self:setVolume(self.max) end,
    }

    local spacer = HorizontalSpan:new{ width = math.floor((self.inner_width - 3 * self.button_width) / 2) }
    self.layout = {
        { self.minus, self.plus },
        { mute, half, max },
    }

    local group = VerticalGroup:new{
        align = "center",
        TitleBar:new{
            width = self.inner_width,
            title = _("Audio volume"),
            show_parent = self,
            with_bottom_line = true,
            close_callback = function() UIManager:close(self) end,
        },
        VerticalSpan:new{ width = Size.padding.large },
        self.progress,
        VerticalSpan:new{ width = Size.padding.large },
        HorizontalGroup:new{
            align = "center",
            self.minus,
            level_container,
            self.plus,
        },
        VerticalSpan:new{ width = Size.padding.default },
        HorizontalGroup:new{
            align = "center",
            mute,
            spacer,
            half,
            spacer,
            max,
        },
    }

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        padding = Size.padding.large,
        group,
    }

    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width, h = self.screen_height },
        self.frame,
    }
end

function VolumeWidget:updateButtons()
    self.progress:setPercentage((self.volume - self.min) / (self.max - self.min))
    self.level:setText(tostring(self.volume))
    if self.volume <= self.min then
        self.minus:disable()
    else
        self.minus:enable()
    end
    if self.volume >= self.max then
        self.plus:disable()
    else
        self.plus:enable()
    end
end

function VolumeWidget:setVolume(volume)
    local ok, err, actual = self.backend:setVolume(volume)
    if not ok then
        UIManager:show(InfoMessage:new{ text = err or _("Failed to set audio volume.") })
        return
    end

    self.volume = math.max(self.min, math.min(self.max, actual or volume))
    self:updateButtons()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)

    if actual ~= volume then
        UIManager:show(InfoMessage:new{
            text = _("Audio manager returned a different volume."),
            timeout = 2,
        })
    end
end

function VolumeWidget:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

function VolumeWidget:onClose()
    UIManager:close(self)
    return true
end

function VolumeWidget:onCloseWidget()
    UIManager:setDirty(nil, function() return "flashui", self.frame.dimen end)
end

return VolumeWidget
