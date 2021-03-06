--[[
    AWM Ti[t]leless: A really simple module for AwesomeWM 4
    that shows the title only on floating windows (and activates ontop).

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
local function get_titlebar_size(c)
    local _, t = c:titlebar_top()
    local _, b = c:titlebar_bottom()
    local _, l = c:titlebar_left()
    local _, r = c:titlebar_right()
    return t + b + l + r
end

local FLOAT_LAYOUT = awful.layout.suit.floating
local function show_title(c, layout)
    if c and managed_list:is_managed(c) then
        if c.requests_no_titlebar then
            awful.titlebar.hide(c)
            return
        end

        layout = layout or awful.layout.get(c.screen)
        local client_is_normal = c.type == "normal"

        local previous_titlebar_size = get_titlebar_size(c)

        -- Full or Max layouts does not affect floating clients
        if (layout == FLOAT_LAYOUT or (c.floating and (client_is_normal and (not c._implicitly_floating or not c.maximized) or not client_is_normal))) and not c.fullscreen then
            awful.titlebar.show(c)
            c.ontop = true
        else
            awful.titlebar.hide(c)
            c.ontop = false
        end

        return previous_titlebar_size ~= get_titlebar_size(c)
    end
end

local handlers = { -- request::geometry for these triggers before actual redraw (and before property::X)
    fullscreen = show_title,
    maximized = show_title,
    maximized_vertical = show_title,
    maximized_horizontal = show_title,
}

local function show_title_and_trigger(c)
    if show_title(c) then
        for event in pairs(handlers) do
            if c[event] then
                c:emit_signal("request::geometry", event, {store_geometry = false})
                break
            end
        end
    end
end

client.connect_signal("manage", function (c, startup)
    managed_list:check(c)

    -- Schedule cleanup
    c:connect_signal("unmanage", function() managed_list:delete(c) end)

    -- Trigger the geometry placement if the titlebar has been hidden just now
    show_title_and_trigger(c)

    c:connect_signal("property::floating", show_title_and_trigger)
    c:connect_signal("request::geometry", function(client, event, args)
        if handlers[event] then handlers[event](client, args) end
    end)
end)
-- //////////////////////////////////////////////////////////////////////

-- //////////////////////////////////////////////////////////////////////
local screen_layout = {}
local function check_all_clients(t)
    local screen = t.screen
    if not screen then return end

    local current_layout = awful.layout.get(screen)
    local previous_layout = screen_layout[screen]

    if not previous_layout or (previous_layout == FLOAT_LAYOUT) ~= (current_layout == FLOAT_LAYOUT) then
        screen_layout[screen] = current_layout

        for _,c in pairs(screen.all_clients) do
            show_title(c, layout)
        end
    end
end

-- When a visible tag layout changes or a tag is selected or unselected,
-- check all the clients (not only visible and not only in visible tags)
tag.connect_signal("property::selected", check_all_clients)
tag.connect_signal("property::layout", check_all_clients)
-- //////////////////////////////////////////////////////////////////////

return setmetatable({}, {__call = function(t, name)
        local callback =  (type(name) == "function" and name)
        or (type(name) == "string" and function(c) return c.instance == name end)

        table.insert(managed_list.unmanaged_callbacks, callback)

        return #(managed_list.unmanaged_callbacks)
    end
})

