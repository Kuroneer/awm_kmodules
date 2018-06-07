--[[
    AWM KBorderless: A simple module for AwesomeWM 4 that removes borders
    from clients when they are redundant (for example, when maximized or
    when that client is the only visible one)

    You can provide callbacks to this module so it won't change anything
    about a client if it returns true for on its manage signal

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
    Date: 2018.06.07
    Version: 2.0.0
]]

local awful = require("awful")
local beautiful = require("beautiful")

-- //////////////////////////////////////////////////////////////////////
local managed_list = {
    clients = {},
    unmanaged_callbacks = {},
}
function managed_list:check(c)
    self.clients[c.window] = false
    for _,f in pairs(self.unmanaged_callbacks) do
        if type(f) == "function" and f(c) then
            return
        end
    end
    self.clients[c.window] = true
    return true
end
function managed_list:delete(c)
    self.clients[c.window] = nil
end
function managed_list:is_managed(c)
    return self.clients[c.window]
end
-- //////////////////////////////////////////////////////////////////////

-- //////////////////////////////////////////////////////////////////////
-- Aux functions
local function isMaximized(c) return c.maximized or (c.maximized_horizontal and c.maximized_vertical) end --fullscreen removes borders, fullscreen layout does not
-- Removes borders every time a client is displayed alone
local function update_border_width(c, screen)
    local screen = (c and c.screen) or screen;
    if not screen then return end
    local layout = awful.layout.get(screen)
    local maxedLayout = layout == awful.layout.suit.max
    local floatLayout = layout == awful.layout.suit.floating
    local fullLayout  = layout == awful.layout.suit.max.fullscreen
    local reserved = nil;
    local too_many = false;

    for _,c in pairs(screen.clients) do
        if c.fullscreen or not managed_list:is_managed(c) then
        elseif isMaximized(c) or ((maxedLayout or fullLayout) and not c.floating) then
            -- Max and Full layouts do not max floating clients
            c.border_width = 0
        elseif too_many or floatLayout or c.floating then
            c.border_width = beautiful.border_width
        elseif (not reserved) or reserved == c then
            reserved = c;
        else
            too_many = true
            c.border_width = beautiful.border_width
        end
    end

    if reserved then
        reserved.border_width = (too_many and beautiful.border_width) or 0
    end
end

local handlers = { -- request::geometry for these triggers before actual redraw (and before property::X)
    maximized = update_border_width,
    maximized_vertical = update_border_width,
    maximized_horizontal = update_border_width,
    fullscreen = update_border_width,
}

-- Control when client is maximized
client.connect_signal("manage", function (c, _startup)
    -- Schedule cleanup
    c:connect_signal("unmanage", function()
        managed_list:delete(c)
    end)

    -- Check if should manage
    if managed_list:check(c) then
        update_border_width(c)

        -- Maximized signals (need to check every client in the screen)
        c:connect_signal("request::geometry", function(client, event, args)
            if handlers[event] then handlers[event](client) end
        end)

        c:connect_signal("property::minimized", update_border_width) -- Check other clients
        c:connect_signal("property::floating", update_border_width)
        c:connect_signal("property::hidden", update_border_width)
    end
end)

tag.connect_signal("tagged", function(t, c)
    if c:isvisible() and t.selected then
        update_border_width(nil, t.screen)
    end
end)
tag.connect_signal("untagged", function(t, c)
    if not c:isvisible() and t.selected then
        update_border_width(nil, t.screen)
    end
end)
tag.connect_signal("property::selected", function(t)
    update_border_width(nil, t.screen)
end)
tag.connect_signal("property::layout", function(t)
    update_border_width(nil, t.screen)
end)

for s in screen do
    update_border_width(nil, s)
end
-- //////////////////////////////////////////////////////////////////////

return setmetatable({}, {__call = function(t, name)
        local callback =  (type(name) == "function" and name)
        or (type(name) == "string" and function(c) return c.instance == name end)

        table.insert(managed_list.unmanaged_callbacks, callback)

        return #(managed_list.unmanaged_callbacks)
    end
})

