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
    Date: 2021.09.06
    Version: 1.0.1
]]

local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local screen, setmetatable, math = screen, setmetatable, math

-- AUX: Get output from command
local getting_value = false
local function get_value(command, finishCallback)
    getting_value = getting_value or type(awful.spawn.easy_async(command, function(stdout, stderr, exit_reason, exit_code)
        getting_value = false
        finishCallback(stdout, stderr, exit_reason, exit_code)
    end)) == "number"
    return getting_value
end

local brightness = {
    target_brightness = nil,
    acc = 0,
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
    callback = function() brightness.target_brightness = nil end,
}

function brightness:change_brightness(nsteps)
    local value = self.target_brightness
    if value then
        value = math.floor(math.max(math.min(value + nsteps * self.brightness_step, 100), self.brightness_step))
        awful.util.spawn(string.format("xbacklight =%3d", value))
        self.target_brightness = value

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

    elseif not get_value("xbacklight -get",
        function(stdout, _stderr, _exit_reason, exit_code)
            if exit_code == 0 then
                self.target_brightness = stdout and tonumber(stdout)
                if self.target_brightness then
                    self.target_brightness = self.target_brightness +.5
                    self:change_brightness(nsteps + self.acc)
                    self.acc = 0
                else
                    error("Error in stdout from 'xbacklight -get':"..stdout)
                end
            else
                error("Error code from 'xbacklight -get': "..exit_code)
            end
        end) then
        error("Error spawning 'xbacklight -get'")
    else
        self.acc = self.acc + nsteps
    end
end

root.keys(awful.util.table.join(root.keys(),
awful.key({ }, "XF86MonBrightnessDown", function() brightness:change_brightness(-1) end),
awful.key({ }, "XF86MonBrightnessUp", function() brightness:change_brightness(1) end)
))

return setmetatable(brightness, {__call = function(t, value) t:change_brightness(value) end})

