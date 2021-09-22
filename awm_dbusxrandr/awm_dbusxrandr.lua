--[[
    AWM DBusXrandr is a module for awesomewm 4 that provides a
    function to iterate over different xrandr configurations and listens
    to dbus events to automatically enable and disable screens upon
    connection.

    It was largely inspired by http://awesome.naquadah.org/wiki/Using_Multiple_Screens
    (it builds the xrandr command and reports the selected setup in a similar way)

    In order to achieve UDEV + DBUS integration, you need a udev rule like this:

    $ cat /etc/udev/rules.d/95-monitor-hotplug.rules
    KERNEL=="card[0-9]*", SUBSYSTEM=="drm", RUN+="/usr/bin/dbus-send --system --type=signal / org.custom.screen_change.screen_changed"

    You can iterate over the configurations by calling the value returned
    when requiring this module:

    require("awm_dbusxrandr")()

    You can also customize the available configurations by populating
      .setup_direction = "horizontal"
      .trigger_command_path = nil, -- Custom script path executed on dbus event
      .trigger_function = nil, -- Custom setup in lua on dbus event
      .get_custom_configurations = nil, -- Custom setup list on call
    see code to check the usage

    You can list the options one by one by disabling show_list:
      .show_list = false


    Version: 1.1.2
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.23

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
local beautiful = require("beautiful")
local gears = require("gears")
local naughty = require("naughty")
local screen = screen

local xrandr = {
    setup_direction = "horizontal",
    trigger_command_path = nil,
    trigger_function = nil,
    get_custom_configurations = nil,
    show_list = true,

    setup_options = nil,
    setup_options_index = nil,
    building_setup_options = false,

    screens_connected = {},

    notification_id = {},
    notification_defaults = {
        position = "top_middle",
        border_width = 1,
        border_color = beautiful.fg_focus,
        timeout = 3,
        font = beautiful.font,
        ignore_suspend = true,
    },
}

xrandr.set_screens_cmd = {}
xrandr.set_screens_on = false
function xrandr:set_screens(cmd, add)
    if not cmd then
        return
    end
    if self.set_screens_on then
        if not add then
            self.set_screens_cmd = {}
        end
        table.insert(self.set_screens_cmd, cmd)
        return
    end
    self.set_screens_on = self.set_screens_on or type(awful.spawn.easy_async("xrandr "..cmd, function()
        cmd = table.remove(self.set_screens_cmd, 1)
        self.set_screens_on = false
        self:set_screens(cmd)
    end)) == "number"
end

function xrandr:update_screens(screens_setup)
    if not screens_setup then
        return
    end

    local cmd = nil
    if type(screens_setup) == "string" then
        cmd = screens_setup
    elseif screens_setup.cmd then
        cmd = screens_setup.cmd
    else
        cmd = ""
        local position = self.setup_direction == "horizontal" and " --right-of " or " --below "
        local active_outputs = {}

        for i, output in ipairs(screens_setup) do
            cmd = cmd.." --output "..output.." --auto"
            if i > 1 then
                cmd = cmd..position..screens_setup[i-1]
            end
            active_outputs[output] = true
        end

        for output in pairs(self.screens_connected) do
            if not active_outputs[output] then
                cmd = " --output "..output.." --off"..cmd
            end
        end
    end

    self:set_screens(cmd)
end

function xrandr:clear_notifications()
    for s in screen do
        local notification = naughty.getById(self.notification_id[s.index])
        if notification then
            naughty.destroy(notification)
        end
    end
    self.setup_options = nil
    self.setup_options_index = nil
end

xrandr.timer = gears.timer{
    timeout = xrandr.notification_defaults.timeout,
    single_shot = true,
    callback = function()
        if xrandr.setup_options_index ~= 0 then
            xrandr:update_screens(xrandr.setup_options[xrandr.setup_options_index])
        end
        xrandr:clear_notifications()
        return false
    end,
}

do
    local original_font = xrandr.notification_defaults.font or beautiful.font
    if original_font then
        local new_font = string.gsub(original_font, " (%d+)$", function(fontsize) return tostring(2*tonumber(fontsize)) end)
        if new_font == original_font then
            xrandr.notification_defaults.font = original_font.." "..math.floor(((beautiful.get_font_height(original_font) or 8)*2))
        else
            xrandr.notification_defaults.font = new_font
        end
    end
end

local function make_label(arg)
    local label
    if type(arg) == "string" then
        label = arg
    elseif arg.name then
        label = arg.name
    else
        for i, output in ipairs(arg) do
            label = label and label.." + " or ""
            label = label..'<span weight="bold">'..output..'</span>'
        end
    end
    return label
end

function xrandr:notify(arg)
    local label = make_label(arg)
    for s in screen do
        local text = '<span weight="bold">⎚</span> '..next(s.outputs)..': '..label
        local notification = naughty.getById(self.notification_id[s.index])

        if notification then
            naughty.replace_text(notification, nil, text)
        else
            self.notification_id[s.index] = naughty.notify(setmetatable({
                text = text,
                screen = s,
                timeout = 0,
                replaces_id = self.notification_id[s.index],
            }, { __index = self.notification_defaults})).id
        end
    end
end

function xrandr:notify_setup_options()
    if self.show_list then
        local options = {}
        for i, v in ipairs(self.setup_options) do
            table.insert(options, make_label(v))
        end
        options[0] = "Keep current configuration"

        for k, v in pairs(options) do
            if k == self.setup_options_index then
                options[k] = "> "..v
            else
                options[k] = "  "..v
            end
        end
        local arg = "\n"..options[0]
        for i, v in ipairs(options) do
            arg = arg .. "\n" .. v
        end
        self:notify(arg)
    elseif self.setup_options_index == 0 then
        self:notify("Keep current configuration")
    else
        self:notify(self.setup_options[self.setup_options_index])
    end
    self.timer:again()
end

-- screens_connected : display -> boolean
-- screens_setup :     i++ -> display (sorted, next to apply)
xrandr.get_connected_screens_callbacks = {}
function xrandr:get_connected_screens(callback, silent)
    if #self.get_connected_screens_callbacks > 0 then
        table.insert(self.get_connected_screens_callbacks, callback)
        return true
    end

    if type(awful.spawn.easy_async("xrandr -q", function(stdout, _stderr, _exitReason, exitCode)
        local screens_setup = {}
        local screens_connected = {}
        if exitCode == 0 then
            local current_setup = {}
            for display, connected, rest in stdout:gmatch("([%w-]+) ([%w]+) ([^\r\n]+)") do
                connected = connected == "connected"

                local offset_w, offset_h = rest:match(".*%d+x%d+%+(%d+)%+(%d+) .*")
                if offset_h and offset_w then
                    screens_connected[display] = connected
                    table.insert(current_setup, {name = display, value = tonumber(offset_h)*100000+tonumber(offset_w)})
                elseif connected then
                    screens_connected[display] = connected
                end
            end
            table.sort(current_setup, function(a,b) return a.value < b.value end)
            for _,v in ipairs(current_setup) do
                table.insert(screens_setup, v.name)
            end
        end
        for _, cb in ipairs(self.get_connected_screens_callbacks) do
            cb(screens_connected, screens_setup)
        end
        self.get_connected_screens_callbacks = {}
    end)) == "number" then
    table.insert(self.get_connected_screens_callbacks, callback)

    if not silent then
        self:notify("Xrandr in progress")
    end
    return true
end
end

if xrandr_nonexhaustive_connected_screen_initialization then
    for s in screen do
        local output = next(s.outputs)
        xrandr.screens_connected[output] = true
    end
else
    xrandr:get_connected_screens(function(screens_connected)
        xrandr.screens_connected = screens_connected
    end, true)
end

local function permgen(screens, start, cb)
    cb(screens, start)
    if start < #screens then
        permgen(screens, start+1, cb)
        for i=start+1,#screens do
            screens[start], screens[i] = screens[i], screens[start]
            cb(screens, start)
            permgen(screens, start+1, cb)
            screens[start], screens[i] = screens[i], screens[start]
        end
    end
end

function xrandr:xrandr()
    if self.setup_options then
        self.setup_options_index = (self.setup_options_index + 1) % (#self.setup_options + 1)
        self:notify_setup_options()
    else
        self.building_setup_options = self.building_setup_options or self:get_connected_screens(function(screens_connected)
            local screens = {}
            for k, v in pairs(screens_connected) do
                if v then
                    table.insert(screens, k)
                end
            end
            self.building_setup_options = false
            self.setup_options_index = 0
            self.setup_options = {}
            self.screens_connected = screens_connected

            if self.get_custom_configurations then
                self.get_custom_configurations(screens, self.setup_options)
            elseif #screens > 0 then
                permgen(screens, 1, function(screens, limit)
                    local setup = {}
                    for i = 1,limit do
                        table.insert(setup, screens[i])
                    end
                    table.insert(self.setup_options, setup)
                end)
            end
            self:notify_setup_options()
        end) or error("Error spawning xrandr")
    end
end

root.keys(awful.util.table.join(root.keys(),
awful.key({}, "XF86Display", xrandr, {description = "Change screen layout", group = "awesome"}))
)

-- UDEV + DBUS integration
--[[ You need a udev rule like this, for example,
$ cat /etc/udev/rules.d/95-monitor-hotplug.rules
KERNEL=="card[0-9]*", SUBSYSTEM=="drm", RUN+="/usr/bin/dbus-send --system --type=signal / org.custom.screen_change.screen_changed"
]]
local dbus_interface = "org.custom.screen_change"
local dbus_member = "screen_changed"
dbus.add_match("system", "type='signal',interface='"..dbus_interface.."',member='"..dbus_member.."'" )
dbus.connect_signal(dbus_interface, function(args)
    if args.member == dbus_member then
        if xrandr.timer.started then
            xrandr.timer:stop()
        end
        xrandr:clear_notifications()

        if not xrandr:get_connected_screens(function(screens_connected, screens_setup)
            if xrandr.trigger_command_path or xrandr.trigger_function then
                xrandr.screens_connected = screens_connected
                local screens = {}
                for k, v in pairs(screens_connected) do
                    if v then
                        table.insert(screens, k)
                    end
                end
                if xrandr.trigger_command_path then
                    awful.spawn.with_shell(xrandr.trigger_command_path .. ' ' .. table.concat(screens, ','))
                elseif xrandr.trigger_function then
                    xrandr:update_screens(xrandr.trigger_function(screens))
                end
                xrandr:clear_notifications()
                return
            end

            local known_connected_screens = xrandr.screens_connected
            local setup_changes = {}

            -- Always add new displays to the setup
            for new_display, new_display_connected in pairs(screens_connected) do
                if new_display_connected and not known_connected_screens[new_display] then
                    local in_setup = false
                    for _, display_in_setup in pairs(screens_setup) do
                        if display_in_setup == new_display then
                            in_setup = true
                            break
                        end
                    end
                    if not in_setup then
                        setup_changes[new_display] = true
                    end
                end
            end

            -- Always remove disconnected displays from the setup
            local to_remove_count = 0
            for new_display, new_display_connected in pairs(screens_connected) do
                if not new_display_connected then
                    setup_changes[new_display] = false
                    to_remove_count = to_remove_count + 1
                end
            end

            xrandr.screens_connected = screens_connected

            -- Try to always have at least one display
            if ((#screens_setup) - to_remove_count) == 0 then
                for k, v in pairs(screens_connected) do
                    if v then
                        setup_changes[k] = true
                        break
                    end
                end
            end

            -- Update it!
            if next(setup_changes) ~= nil then
                local position = xrandr.setup_direction == "horizontal" and " --right-of " or " --below "
                local cmd = ""
                local last_on = nil

                while true do
                    local last_in_setup = table.remove(screens_setup)
                    if not last_in_setup then
                        break
                    end
                    if screens_connected[last_in_setup] then
                        last_on = last_in_setup
                        break
                    end
                end

                for output, v in pairs(setup_changes) do
                    if v then
                        cmd = cmd.." --output "..output.." --auto"
                        if last_on then
                            cmd = cmd..position..last_on
                        end
                        last_on = output
                    else
                        cmd = cmd.." --output "..output.." --off"
                    end
                end
                xrandr:set_screens(cmd, true)
            end
            xrandr:clear_notifications()
        end) then error("Error spawning xrandr") end
    end
end)

return setmetatable(xrandr, { __call = function() xrandr:xrandr() end})

