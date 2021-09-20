--[[
    AWM Simple Pacman is a widget for AwesomeWM 4 that monitors the pacman
    status, displaying a ! if your system is out of date

    To use it:

    local pacman_update = my_modules("awm_simple_pacman_widget")()

    Version: 1.0.2
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.05

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
local beautiful = require("beautiful")
local gears = require("gears")
local wibox = require("wibox")

local defaults, sync_timer = {
    text = "!",
    timeout_no_update = 7200, -- On start and once each 2h
    timeout_with_update = 300, -- On start and once each 5m
    sync_interval = 24 * 3600, -- On start and once a day
    fg_color = beautiful.fg_urgent,
    bg_color = beautiful.bg_urgent,
    sync_command = "sudo pacman -Sy", -- Command used to refresh pacman's local db (-y == --refresh)
    check_command = "pacman -Qu", -- Command used to check if local packages require updates, checked against local db
}

return function(options)
    local options, pending_action = setmetatable(options or {}, {__index = defaults}), 0
    local widget = wibox.widget{
        markup = '',
        align  = 'center',
        valign = 'center',
        widget = wibox.widget.textbox,
    }
    local check_timer

    local function update(widget, stdout, _stderr, _exitreason, exitcode)
        if stdout and stdout:len() > 0 then
            widget:set_markup_silently('<span size="larger" weight="bold" color="'..options.fg_color..'" bgcolor="'..options.bg_color..'">'..options.text..'</span>')
            check_timer.timeout = options.timeout_with_update
            check_timer:again()
        else
            widget:set_markup_silently("")
            check_timer.timeout = options.timeout_no_update
            check_timer:again()
        end
    end

    local function check()
        if pending_action == 0 then -- 0 == nothing running
            if type(awful.spawn.easy_async(options.check_command,
                function(stdout, stderr, exitreason, exitcode)
                    update(widget, stdout, stderr, exitreason, exitcode)
                    pending_action = pending_action - 1
                    if pending_action > 0 then
                        pending_action = pending_action - 1
                        check()
                    end
                end)) == "number" then
                pending_action = 1
            end
        elseif pending_action == 1 then -- 1 == already running
            pending_action = 2 -- 2 == already running and something scheduled
        end
    end

    widget:buttons(awful.util.table.join(awful.button({}, 1, check)))
    if options.sync_command then
        gears.timer{
            timeout   = options.sync_interval,
            call_now  = true,
            autostart = true,
            callback  = function()
                awful.spawn.easy_async(options.sync_command, check)
            end,
        }
    end
    check_timer = gears.timer{
        timeout   = options.timeout_with_update,
        call_now  = true,
        autostart = true,
        callback  = check,
    }
    return widget
end

