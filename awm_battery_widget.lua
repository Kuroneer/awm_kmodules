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
local command = "acpi -V"

local function update_widget_text(widget, stdout)
    local batteries = {}
    local all_ok = true
    for battery_index, battery in stdout:gmatch("Battery (%d+): ([^\r\n]+)[\r\n]Battery %1: [^\r\n]+") do
        local battery_formatted, battery_ok = widget:format_battery_output(battery_index, battery)
        all_ok = all_ok and battery_ok
        table.insert(batteries, battery_formatted)
    end
    widget:set_markup_silently(" "..table.concat(batteries, " ").." ")

    local widget_should_be_visible = #batteries > 0
    if widget.visible ~= widget_should_be_visible then
        widget:set_visible(widget_should_be_visible)
        if widget.on_visible_callback then
            widget:on_visible_callback(widget_should_be_visible)
        end
    end

    return all_ok
end

local widget = awful.widget.watch(command, 60, update_widget_text)
widget.update_widget_text = update_widget_text

local bars  = setmetatable({"X","▁","▂","▂","▃","▃","▄","▄","▅","▅","▆","▆","▇","▇","█","█"}, {__index = function() return "X" end})
function widget:format_battery_output(battery_index, battery)
    local state, percentage, rest = battery:match("(%w+), (%d+)%%(.*)")
    local time = rest:match(" (%d+:%d+):%d+")
    local battery_ok = state == "Full" or (time and state ~= "Unknown")
    time = time or (state ~= "Full" and "??:??")
    percentage = tonumber(percentage)
    local text = string.format(
        '<span size="larger">⚡</span>%s %s%s',
        tonumber(battery_index) > 0 and battery_index or "",
        bars[math.floor(percentage * #bars / 100)],
        time and " "..time or ""
    )
    return '<span color="'..self:color(state, percentage)..'">'..text..'</span>', battery_ok
end

local beautiful = require("beautiful")
function widget:color(state, percentage)
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

local timer = require("gears.timer")
function widget:update()
    self.pending_action = self.pending_action or type(awful.spawn.easy_async(command, function(stdout)
        local ok = self:update_widget_text(stdout)
        self.pending_action = false
        if not ok then
            timer.start_new(5, function() widget:update() end)
        end
    end)) == "number"
    return self.pending_action
end

local dbus_interface = "org.freedesktop.DBus.Properties"
local dbus_member = "PropertiesChanged"
local dbus_path = "/org/freedesktop/UPower"
dbus.add_match("system", "type='signal',interface='"..dbus_interface.."',member='"..dbus_member.."',path='"..dbus_path.."'" )
dbus.connect_signal(dbus_interface, function(args)
    if args.member == dbus_member and args.path == dbus_path then
        widget:update()
        timer.start_new(10, function() widget:update() end)
    end
end)

return widget

