--[[
    AWM Brightness: A simple module for AwesomeWM 4 to handle brightness with
    xbacklight, reporting the value with a highly customizable notification

    Copyright (C) <2018> Jose Maria Perez Ramos

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.    See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.    If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.08
    Version: 1.1.0
]]

local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local screen, setmetatable, math = screen, setmetatable, math

local brightness = {
    current_brightness = nil,
    acc_steps = 0,
    brightness_step = 5,
    notification_id = {},
    notification_text = {
        head = '☼ <span weight="bold">[',
        symbol_active = "#",
        symbol_inactive = " ",
        tail = "]</span> "
    },
    notification_defaults = {
        timeout = 2,
        border_width = 1,
        ignore_suspend = true,
    },
    symbols_cache = setmetatable({}, {
      __index = function(t, symbol)
        t[symbol] = setmetatable({symbol = symbol}, {
          __index = function(t, num)
            local text = ""
            for i=1,num do
              text=text..t.symbol
            end

            t[num] = text
            return text
          end,
        })
        return t[symbol]
      end,
    }),
}

brightness.timer = gears.timer{
    timeout = brightness.notification_defaults.timeout,
    single_shot = true,
    callback = function()
        brightness.current_brightness = nil
        brightness.acc_steps = 0
    end,
}

local update_ongoing = false
local next_value
local set_brigthness
set_brigthness = function(value)
    if not update_ongoing then
        update_ongoing = type(awful.spawn.easy_async(string.format("xbacklight =%3d", value), function()
            update_ongoing = false
            if next_value then
                set_brigthness(next_value)
                next_value =  nil
            end
        end)) == "number"
    else
        next_value = value
    end
end

local getting_value = false
local function get_brightness(finishCallback)
    getting_value = getting_value or type(awful.spawn.easy_async("xbacklight -get", function(stdout, stderr, exit_reason, exit_code)
        getting_value = false
        finishCallback(stdout, exit_code)
    end)) == "number"
    return getting_value
end

function brightness:change_brightness(nsteps)
    self.acc_steps = self.acc_steps + nsteps

    local value = self.current_brightness
    if value then
        local min_steps = 1 - value / self.brightness_step
        local max_steps = (100 - value) / self.brightness_step
        self.acc_steps = math.max(min_steps, math.min(max_steps, self.acc_steps))

        value = math.floor(value + self.acc_steps * self.brightness_step)
        set_brigthness(value)

        local num_symbols = math.floor(100/self.brightness_step)
        local active_symbols = math.floor(value/self.brightness_step)
        local text = self.notification_text.head
        ..self.symbols_cache[self.notification_text.symbol_active][active_symbols]
        ..self.symbols_cache[self.notification_text.symbol_inactive][num_symbols - active_symbols]
        ..self.notification_text.tail
        ..string.format("%3d%%", value)

        for s in screen do
            local notification = naughty.getById(self.notification_id[s.index])
            if notification then
                naughty.replace_text(notification, nil, text)
                naughty.reset_timeout(notification, 0)
            else
                self.notification_id[s.index] = naughty.notify(setmetatable({
                    text = text,
                    screen = s,
                    replaces_id = self.notification_id[s.index],
                },{__index = self.notification_defaults})).id
            end
        end
        self.timer:again()

    elseif not get_brightness(function(stdout, exit_code)
            if exit_code == 0 then
                self.current_brightness = stdout and tonumber(stdout)
                if self.current_brightness then
                    self.current_brightness = math.floor(self.current_brightness +.5)
                    self:change_brightness(0)
                else
                    error("Error in stdout from 'xbacklight -get':"..stdout)
                end
            else
                error("Error code from 'xbacklight -get': "..exit_code)
            end
        end) then
        error("Error spawning 'xbacklight -get'")
    end
end

root.keys(awful.util.table.join(root.keys(),
awful.key({ }, "XF86MonBrightnessDown", function() brightness:change_brightness(-1) end),
awful.key({ }, "XF86MonBrightnessUp", function() brightness:change_brightness(1) end)
))

return setmetatable(brightness, {__call = function(t, value) t:change_brightness(value) end})

