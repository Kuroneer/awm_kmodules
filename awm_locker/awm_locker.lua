--[[
    AWM Locker Widget is a widget for AwesomeWM 4 listens to DBus events
    to listen to loginctl lock session event

    To use it:

    require("awm_locker")("slock")

    Version: 1.0.0
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.20

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
local locker_cmd = nil

local function dbus_match(interface, member, path_namespace)
    return "type='signal',interface='"..interface.."',member='"..member.."',path_namespace='"..path_namespace.."'"
end
local interface = 'org.freedesktop.login1.Session'
dbus.add_match('system', dbus_match(interface, 'Lock', '/org/freedesktop/login1/session'))
dbus.connect_signal(interface, function(event, string, values)
    if locker_cmd and event.member == 'Lock' then
        if type(awful.spawn(locker_cmd)) ~= "number" then
            error("Cannot spawn "..locker_cmd)
        end
    end
end)

return function(cmd) locker_cmd = type(cmd) == "string" and cmd end

