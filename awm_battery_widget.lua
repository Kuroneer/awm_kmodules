--[[
    AWM Battery Widget is a widget for AwesomeWM 4 that monitors the
    battery status through acpi. It hooks to the UPower DBus events.

    To use it:

    local battery_widget = require("awm_battery_widget")

    Version: 1.0.0
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2018.07.07

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
local wibox = require("wibox")

local bars  = setmetatable({"X","▁","▁","▂","▂","▃","▃","▄","▄","▅","▅","▆","▆","▇","▇","█","█","█"}, {__index = function() return "X" end})
local command = "acpi -V"
local battery_widget = {
    text_widget = wibox.widget{
        markup = '',
        align  = 'center',
        valign = 'center',
        widget = wibox.widget.textbox,
    },
    symbol_widget = wibox.widget{
        markup = ' <span size="larger">⚡</span> ',
        align  = 'center',
        valign = 'center',
        widget = wibox.widget.textbox,
    },
}
battery_widget.widget = wibox.widget{
    battery_widget.symbol_widget,
    battery_widget.text_widget,
    layout  = wibox.layout.align.horizontal
}

function battery_widget:color(state, percentage)
    if state == "Charging"  then
        return beautiful.battery_fg_charging or "green"
    elseif state == "Full" then
        return beautiful.battery_fg_full or "green"
    elseif percentage < 15 then
        return beautiful.battery_fg_critical or "red"
    else
        return beautiful.battery_fg_normal or beautiful.fg_normal
    end
end

function battery_widget:format_battery_output(battery)
    local state, percentage, rest = battery:match("(%w+), (%d+)%%(.*)")
    local time = rest:match(" (%d+:%d+):%d+")
    local battery_ok = state == "Full" or (time and state ~= "Unknown")
    time = time or (state ~= "Full" and "??:??")
    percentage = tonumber(percentage)

    local color = self:color(state, percentage)

    self.text_widget:set_markup(string.format(
        '<span color="%s">%s %s</span>',
        color,
        bars[math.floor(percentage * (#bars-1) / 100)+1],
        time and string.format("%s ", time) or ''
    ))

    self.symbol_widget:set_markup(string.format(
        ' <span size="larger" color="%s">⚡</span> ',
        color
    ))

    return battery_ok
end


function battery_widget:update_widget_text(stdout)
    local battery_present = false
    local battery_ok = false

    for _, battery_output in stdout:gmatch("Battery (%d+): ([^\r\n]+)[\r\n]Battery %1: [^\r\n]+") do
        battery_ok = battery_widget:format_battery_output(battery_output)
        battery_present = true
        break
    end

    local widget = battery_widget.widget
    if widget.visible ~= battery_present then
        widget:set_visible(battery_present)
        if widget.on_visible_callback then
            widget:on_visible_callback(battery_present)
        end
    end

    return battery_ok
end

battery_widget.watcher = awful.widget.watch(command, 60, function(watcher, stdout)
    battery_widget:update_widget_text(stdout)
end)

local timer = require("gears.timer")
function battery_widget:update()
    self.pending_action = self.pending_action or type(awful.spawn.easy_async(command, function(stdout)
        self.pending_action = false
        if not self:update_widget_text(stdout) then
            timer.start_new(5, function() self:update() end)
        end
    end)) == "number"
end

local dbus_interface = "org.freedesktop.DBus.Properties"
local dbus_member = "PropertiesChanged"
local dbus_path = "/org/freedesktop/UPower"
dbus.add_match("system", "type='signal',interface='"..dbus_interface.."',member='"..dbus_member.."',path='"..dbus_path.."'" )
dbus.connect_signal(dbus_interface, function(args)
    if args.member == dbus_member and args.path == dbus_path then
        battery_widget:update()
        timer.start_new(10, function() battery_widget:update() end)
    end
end)

return battery_widget.widget

