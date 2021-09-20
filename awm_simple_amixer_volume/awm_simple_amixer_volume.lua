--[[
    AWM simple amixer volume is a module for awesomewm 4 that provides a
    volume widget tied to amixer

    local volume_widget = require("awm_simple_amixer_volume")


    Version: 1.1.0
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.06

    Copyright (C) <2018-2021> Jose Maria Perez Ramos

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

local awful = require("awful")
local timer = require("gears.timer")
local wibox = require("wibox")

local bars  = {"▁","▂","▃","▄","▅","▆","▇","█"}
local commands = {
    decrease = "amixer -q -D pulse sset Master 5%-",
    increase = "amixer -q -D pulse sset Master 5%+",
    toggle_mute = "amixer -D pulse set Master 1+ toggle",
    update = "amixer -D pulse get Master"
}
local widget = wibox.widget{
    markup = '',
    align  = 'center',
    valign = 'center',
    widget = wibox.widget.textbox,
}

local update_pending = false
local update_ongoing = false
local update
update = function()
    if update_ongoing then
        update_pending = true
        return
    end

    update_ongoing = type(awful.spawn.easy_async(commands.update, function(stdout)
        update_ongoing = false

        if update_pending then
            update_pending = false
            update()
            return
        end

        local sum_percentage, count, off = 0, 0, false
        for percentage, onoff in stdout:gmatch("(%d+)%%.*%[(%S*)%]") do
            off = off or onoff == "off"
            sum_percentage = sum_percentage + tonumber(percentage)
            count = count + 1
        end
        if off then
            widget:set_text(" ♬ M ")
        elseif count > 0 then
            widget:set_text(string.format(" ♬ %s ", sum_percentage > 0 and bars[math.floor(sum_percentage/count*(#bars-1) / 100)+1] or "X"))
        end
    end)) == "number"
end

local check_timer = timer{
    timeout   = 45,
    call_now  = false,
    autostart = true,
    callback  = update,
}

timer.delayed_call(function()
    update()

    local pending_action = false -- This "mutex" is needed because otherwise L and R get out of sync with concurrent calls
    local callbacks = {exit = function()
        update()
        pending_action = false
    end}
    local create_action = function(command_key)
        return function()
            pending_action = pending_action or type(awful.spawn.with_line_callback(commands[command_key], callbacks)) == "number"
        end
    end

    root.keys(awful.util.table.join(root.keys(), awful.util.table.join(
    -- Volume Keys from https://wiki.archlinux.org/index.php/awesome
    awful.key({}, "XF86AudioLowerVolume", create_action("decrease")),
    awful.key({}, "XF86AudioRaiseVolume", create_action("increase")),
    awful.key({}, "XF86AudioMute", create_action("toggle_mute"))
    )))

    widget:buttons(awful.util.table.join(
    awful.button({}, 1, create_action("toggle_mute")),
    awful.button({}, 4, create_action("increase")),
    awful.button({}, 5, create_action("decrease"))
    ))
end)

return widget

