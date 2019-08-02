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


    Version: 1.0.0
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2018.06.06

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

--[[
    TODO list:
        - Add option to display all configurations and iterate over them
        - Add option to filter configurations in the iteration
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local naughty = require("naughty")
local screen = screen

local xrandr = {
    setup_direction = "horizontal",
    trigger_command_path = nil,

    screens_connected = {},
    screens_setup = {},
    screens_to_be_removed = {},
    screens_setup_limit = 0,

    notification_id = {},
    notification_defaults = {
        position = "top_middle",
        border_width = 1,
        border_color = beautiful.fg_focus,
        timeout = 3,
        font = beautiful.font,
        ignore_suspend = true,
    },

    coroutine = nil,
    buildingCoroutine = false,
    action = nil,
}

function xrandr:update_screens()
    local position = self.setup_direction == "horizontal" and " --right-of " or " --below "
    local cmd = "xrandr"
    local active_outputs = {}

    for i, output in ipairs(self.screens_setup) do
        if i > self.screens_setup_limit then
            break
        end

        cmd = cmd.." --output "..output.." --auto"
        if i > 1 then
            cmd = cmd..position..self.screens_setup[i-1]
        end
        active_outputs[output] = true
    end

    for output in pairs(self.screens_connected) do
        if not active_outputs[output] then
            cmd = cmd.." --output "..output.." --off"
        end
    end

    for output in pairs(self.screens_to_be_removed) do
        cmd = cmd.." --output "..output.." --off"
    end
    self.screens_to_be_removed = {}

    awful.spawn(cmd)
    self.coroutine = nil
end

xrandr.timer = gears.timer{
    timeout = xrandr.notification_defaults.timeout,
    single_shot = true,
    callback = function() xrandr:update_screens() end,
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

function xrandr:notify(label)
    if not label then
        for i, output in ipairs(self.screens_setup) do
            if i > self.screens_setup_limit then
                break
            end
            label = label and label.." + " or ""
            label = label..'<span weight="bold">'..output..'</span>'
        end
    end

    for s in screen do
        local text = '<span weight="bold">⎚</span> '..next(s.outputs)..': '..label
        local notification = naughty.getById(self.notification_id[s.index])

        if notification then
            naughty.replace_text(notification, nil, text)
            naughty.reset_timeout(notification, 0)
        else
            self.notification_id[s.index] = naughty.notify(setmetatable({
                text = text,
                screen = s,
                replaces_id = self.notification_id[s.index],
            }, { __index = self.notification_defaults})).id
        end
    end
end

function xrandr:get_connected_screens(callback)
    return type(awful.spawn.easy_async("xrandr -q", function(stdout, stderr, exitReason, exitCode)
        local previous_setup = xrandr.screens_setup
        local all_displays = nil
        if exitCode == 0 then
            local current_setup = {}
            self.screens_connected = {}
            all_displays = {}
            for display, rest in stdout:gmatch("([%w-]+) connected ([^\r\n]+)") do
                self.screens_connected[display] = true
                table.insert(all_displays, display)

                local offset_w, offset_h = rest:match(".*%d+x%d+%+(%d+)%+(%d+) .*")
                if offset_h and offset_w then
                    table.insert(current_setup, {name = display, value = tonumber(offset_h)*100000+tonumber(offset_w)})
                end
            end
            table.sort(current_setup, function(a,b) return a.value < b.value end)
            xrandr.screens_setup = {}
            for _,v in ipairs(current_setup) do
                table.insert(xrandr.screens_setup, v.name)
            end
            xrandr.screens_setup_limit = #xrandr.screens_setup
        end

        if callback then
            callback(all_displays, previous_setup)
        end
    end)) == "number"
end


if xrandr_nonexhaustive_connected_screen_initialization then
    xrandr.screens_setup_limit = 0
    for s in screen do
        local output = next(s.outputs)
        xrandr.screens_connected[output] = true
        xrandr.screens_setup_limit = xrandr.screens_setup_limit +1
        table.insert(xrandr.screens_setup, output)
    end
else
    xrandr:get_connected_screens()
end

function xrandr:permgen(start)
    local a = self.screens_setup
    start = start or 1
    if start < #a then
        self.screens_setup_limit = start
        coroutine.yield(a, start)
        self:permgen(start+1)

        for i=start+1,#a do
            a[start], a[i] = a[i], a[start]
            self.screens_setup_limit = start
            coroutine.yield(a, start)
            self:permgen(start+1)
            a[start], a[i] = a[i], a[start]
        end
    else
        self.screens_setup_limit = start
        coroutine.yield(a, start)
    end
end

function xrandr:xrandr()
    if self.timer.started then
        self.timer:stop()
    end

    if not self.coroutine then
        if self.buildingCoroutine then
            return
        end
        self.buildingCoroutine = self:get_connected_screens(function(all_displays)
            self.buildingCoroutine = false
            self.screens_setup = all_displays
            self.coroutine = coroutine.wrap(function() self:permgen() end)
            self:xrandr()
        end)
        if not self.buildingCoroutine then
            error("Error spawning xrandr")
        end
    elseif self.coroutine() then
        self:notify()
        self.timer:start()
    else
        self:notify("Keep the current configuration")
        self.coroutine = nil
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
        xrandr.coroutine = nil

        local known_connected_screens = xrandr.screens_connected
        if not xrandr:get_connected_screens(function(displays)

            if xrandr.trigger_command_path then
                awful.spawn.with_shell(xrandr.trigger_command_path .. ' ' .. table.concat(displays or {}, ','))
                return
            end

            local current_displays = xrandr.screens_connected
            local setup_changed = false

            -- Always add new displays to the setup
            for new_display in pairs(current_displays) do
                if not known_connected_screens[new_display] then
                    local in_setup = false
                    for _, display_in_setup in pairs(xrandr.screens_setup) do
                        if display_in_setup == new_display then
                            in_setup = true
                            break
                        end
                    end
                    if not in_setup then
                        setup_changed = true
                        -- print("Must add to setup", new_display)
                        xrandr.screens_setup_limit = xrandr.screens_setup_limit +1
                        table.insert(xrandr.screens_setup, xrandr.screens_setup_limit, new_display)
                    end
                end
            end

            -- Always remove disconnected displays from the setup
            for old_display in pairs(known_connected_screens) do
                if not current_displays[old_display] then
                    -- Added to ephemeral to have them disabled in xrandr command:
                    setup_changed = true
                    xrandr.screens_to_be_removed[old_display] = true
                    -- print("Must remove from known", old_display)
                    -- Must remove screen
                    for i=#xrandr.screens_setup,1,-1 do
                        if xrandr.screens_setup[i] == old_display then
                            -- print("Must remove from setup", old_display)
                            table.remove(xrandr.screens_setup, i)
                            if i <= xrandr.screens_setup_limit then
                                -- print("Must remove from active", old_display)
                                xrandr.screens_setup_limit = xrandr.screens_setup_limit -1
                            end
                        end
                    end
                end
            end

            -- Always have at least one display
            if xrandr.screens_setup_limit < 1 then
                local default_display = next(current_displays)
                if default_display then
                    setup_changed = true
                    xrandr.screens_setup = {default_display}
                    xrandr.screens_setup_limit = 1
                end
            end

            -- Update it!
            if setup_changed then
                xrandr:update_screens()
            end
        end) then error("Error spawning xrandr") end
    end
end)

return setmetatable(xrandr, { __call = function() xrandr:xrandr() end})

