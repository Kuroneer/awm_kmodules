--[[
    AWM Battery Widget is a widget for AwesomeWM 4 that monitors the
    battery status through upower. It hooks to the UPower DBus events.

    To use it:

    local battery_widget = require("awm_battery_widget")


    Version: 1.1.2
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.16

    Copyright (C) <2018-2020> Jose Maria Perez Ramos

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
local naughty = require("naughty")

local bars  = setmetatable({"X","▁","▁","▂","▂","▃","▃","▄","▄","▅","▅","▆","▆","▇","▇","█","█","█"}, {__index = function() return "X" end})
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
    state = {
        initialized = false,
        event_queue = {},
        devices = {},
    },
    popup_notification = nil,
}
battery_widget.widget = wibox.widget{
    battery_widget.symbol_widget,
    battery_widget.text_widget,
    layout  = wibox.layout.align.horizontal
}

battery_widget.widget:connect_signal("mouse::enter", function() battery_widget.popup = true;  battery_widget:update_popup_notification() end)
battery_widget.widget:connect_signal("mouse::leave", function() battery_widget.popup = false; battery_widget:update_popup_notification() end)

local current_device_path, current_device
function battery_widget:reinitialize()
    if self.state.ongoing_action then
        self.state.pending_action = true
        return true
    end

    self.state.initialized = false
    self.state.event_queue = {}
    self.state.devices = {}

    current_device_path = nil
    current_device = {}

    if type(awful.spawn.with_line_callback('bash -c "LC_ALL=C upower --dump"', {
            output_done = function()
                if current_device_path then
                    self.state.devices[current_device_path] = current_device
                    current_device_path = nil
                    current_device = {}
                end
                for _, device in pairs(self.state.devices) do
                    device.percentage = device.percentage and tonumber(device.percentage)
                    device.present = device.present ~= 'no'
                end

                self.state.ongoing_action = false
                if self.state.pending_action then
                    self.state.pending_action = false
                    self:reinitialize()
                else
                    for _, e in ipairs(self.state.event_queue) do
                        battery_widget:apply_event(e[1], e[2])
                    end
                    self.state.event_queue = {}
                    self.state.initialized = true
                    battery_widget:redraw()
                end
            end,
            stdout = function(line)
                local new_device = line:match("Device: +(/.*)")
                if new_device then
                    if current_device_path then
                        self.state.devices[current_device_path] = current_device
                    end
                    current_device_path = new_device
                    current_device = {}
                    return
                end
                if not current_device_path then return end

                current_device.present       = line:match("^ +present: +(%w+)")         or current_device.present
                current_device.percentage    = line:match("^ +percentage: +(%d+)%%")    or current_device.percentage
                current_device.time_to_full  = line:match("^ +time to full: +(%d+.*)")  or current_device.time_to_full
                current_device.time_to_empty = line:match("^ +time to empty: +(%d+.*)") or current_device.time_to_empty
                current_device.model         = line:match("^ +model: +([^ ].*)")           or current_device.model
                current_device.native_path   = line:match("^ +native%-path: +(.*)")     or current_device.native_path
            end,
            stderr = function() end,
    })) == "number" then
        self.state.ongoing_action = true
        return true
    end
end

function battery_widget:apply_event(event, values)
    local device_path = event.path
    local device = self.state.devices[device_path]
    if not device then return end

    device.percentage = values.Percentage or device.percentage
    device.time_to_empty = values.TimeToEmpty or device.time_to_empty
    device.time_to_full = values.TimeToFull or device.time_to_full
    device.present = values.IsPresent or device.present

    if device.time_to_empty and device.time_to_empty < 1 then device.time_to_empty = nil end
    if device.time_to_full  and device.time_to_full  < 1 then device.time_to_full  = nil end
end

function battery_widget:color(time_to_empty, time_to_full, percentage)
    if time_to_full then
        return beautiful.battery_fg_charging or "green"
    elseif not time_to_empty then
        return beautiful.battery_fg_full or "green"
    elseif percentage < 15 then
        return beautiful.battery_fg_critical or "red"
    else
        return beautiful.battery_fg_normal or beautiful.fg_normal
    end
end

local function stringify_estimation(estimation)
    estimation = estimation / 60
    local minutes = estimation % 60
    estimation = estimation / 60

    return string.format("%.0f:%02.0f", math.floor(estimation), minutes)
end

function battery_widget:redraw()
    local widget = self.widget
    local display_device = self.state.devices['/org/freedesktop/UPower/devices/DisplayDevice']


    local percentage = display_device and display_device.present and display_device.percentage
    local battery_present = percentage ~= nil
    if widget.visible ~= battery_present then
        widget:set_visible(battery_present)
        if widget.on_visible_callback then
            widget:on_visible_callback(battery_present)
        end
    end

    if battery_present then
        local color = self:color(display_device.time_to_empty, display_device.time_to_full, percentage)
        local time = tonumber(display_device.time_to_empty or display_device.time_to_full)
        local timestr = time and string.format("%s ", stringify_estimation(time)) or ''
        if percentage < 100 and not time then -- Fallback to percentage instead of parsing raw_time
            timestr = string.format("%02.0f%% ", percentage)
        end

        self.text_widget:set_markup(string.format(
            '<span color="%s">%s %s</span>',
            color,
            bars[math.floor(percentage * (#bars-1) / 100)+1],
            timestr
        ))

        self.symbol_widget:set_markup(string.format(
            ' <span size="larger" color="%s">⚡</span> ',
            color
        ))
    end

    self:update_popup_notification()
end

function battery_widget:update_popup_notification()
    local notification = naughty.getById(self.popup_notification)

    -- To avoid handling text
    if not self.popup then
        if notification then
            naughty.destroy(notification)
        end
        return
    end

    local text
    for device_path, device in pairs(self.state.devices) do
        if device.native_path and device.present and device.percentage then
            local color = self:color(device.time_to_empty, device.time_to_full, device.percentage)
            local line = string.format('<span color="%s">%s - %.0f%%</span>', color, device.model or device_path:match("^.*/([^/]+)$"), device.percentage)

            if text then
                text = text.."\n"..line
            else
                text = line
            end
        end
    end

    if notification then
        if not text then
            naughty.destroy(notification)
        else
            naughty.replace_text(notification, nil, text)
        end
    elseif text then
        self.popup_notification = naughty.notify({
            text = text,
            timeout = 0,
            ignore_suspend = true,
            replaces_id = self.popup_notification,
        }).id
    end
end

if battery_widget:reinitialize() then
    -- Hook to DBus
    local function dbus_match(interface, member, path_namespace)
        return "type='signal',interface='"..interface.."',member='"..member.."',path_namespace='"..path_namespace.."'"
    end

    local dbus_properties_interface = 'org.freedesktop.DBus.Properties'
    local dbus_upower_interface = 'org.freedesktop.UPower'

    dbus.add_match("system", dbus_match(dbus_properties_interface, 'PropertiesChanged', '/org/freedesktop/UPower/devices'))
    dbus.add_match("system", dbus_match(dbus_upower_interface,     'DeviceAdded'  ,     '/org/freedesktop/UPower'))
    dbus.add_match("system", dbus_match(dbus_upower_interface,     'DeviceRemoved',     '/org/freedesktop/UPower'))

    dbus.connect_signal(dbus_properties_interface, function(event, string, values)
        if battery_widget.state.initialized then
            battery_widget:apply_event(event, values)
            battery_widget:redraw()
        else
            table.insert(battery_widget.state.event_queue, {event, values})
        end
    end)
    dbus.connect_signal(dbus_upower_interface, function(event, string, values)
        battery_widget:reinitialize()
    end)

    return battery_widget.widget
end

