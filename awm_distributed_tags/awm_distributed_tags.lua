--[[
    AWM Distributed Tags: A simple module for AwesomeWM 4 to redistribute the
    tags among the available screens and move them when new screens are
    added or removed.

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
    Date: 2018.07.01
    Version: 1.0.0
]]

local awful = require("awful")

local state = {
    tags_by_name = {},
    names = {},
}

local function reorg_tags()
    state.tags_by_name = {}
    state.names = {}

    -- Get all tags with unique names
    for _,t in pairs(root.tags()) do
        local name = t.name
        if state.tags_by_name[name] == t then
        elseif state.tags_by_name[name] then
            t:delete(state.tags_by_name[name], true)
        else
            table.insert(state.names, name)
            state.tags_by_name[name] = t
        end
    end

    -- Get all screens and sort them by size
    local screens = {}
    local screen_res = {}
    for s in screen do
        table.insert(screens, s)

        local bestsize = 0
        for _name, values in pairs(s.outputs) do
            if values.mm_width and values.mm_height then
                local size = values.mm_width * values.mm_height
                if bestsize < size then
                    bestsize = size
                end
            end
        end
        screen_res[s] = {resolution = s.geometry.width * s.geometry.height, size = bestsize}
    end

    table.sort(screens, function(sa, sb)
        local resa = screen_res[sa]
        local resb = screen_res[sb]
        return resa.resolution > resb.resolution or (resa.resolution == resb.resolution and resa.size > resb.size)
    end)

    -- Add tags to screens by order
    local nscreens = screen:count()
    local ntags = #state.names
    local tags_left = ntags
    local screens_left = nscreens

    for _,s in ipairs(screens) do
        local stags = math.ceil(tags_left / screens_left)
        local current_tag_index = ntags - tags_left

        for i = 1,stags do
            local tag = state.tags_by_name[state.names[current_tag_index+i]]
            tag.screen = s
            tag.index = i
        end
        state.tags_by_name[state.names[current_tag_index+1]]:view_only()

        screens_left = screens_left -1
        tags_left = tags_left - stags
    end
end
screen.connect_signal("list", reorg_tags)
reorg_tags()
tag.connect_signal("request::screen", function(t) for s in screen do t.screen = s return end end)

-- Modify keybindings
local new_keys = {}
for i = 1, 9 do
    new_keys = awful.util.table.join(new_keys,
        -- View tag only.
        awful.key({ modkey }, "#" .. i + 9,
                  function ()
                      local tag = state.tags_by_name[state.names[i]]
                      if tag then
                          tag:view_only()
                          awful.screen.focus(tag.screen)
                      end
                  end,
                  {description = "view tag #"..i, group = "tag"}),
        -- Toggle tag display.
        awful.key({ modkey, "Control" }, "#" .. i + 9,
                  function ()
                      local tag = state.tags_by_name[state.names[i]]
                      if tag then
                         awful.tag.viewtoggle(tag)
                      end
                  end,
                  {description = "toggle tag #" .. i, group = "tag"}),
        -- Move client to tag.
        awful.key({ modkey, "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = state.tags_by_name[state.names[i]]
                          if tag then
                              client.focus:move_to_tag(tag)
                          end
                     end
                  end,
                  {description = "move focused client to tag #"..i, group = "tag"}),
        -- Toggle tag on focused client.
        awful.key({ modkey, "Control", "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = state.tags_by_name[state.names[i]]
                          if tag then
                              client.focus:toggle_tag(tag)
                          end
                      end
                  end,
                  {description = "toggle focused client on tag #" .. i, group = "tag"})
    )
end

local keys = {}
for _,k in pairs(root.keys()) do
    local found = false
    for i =1,9 do
        if k.key == "#" .. (i + 9) then
            found = true
            break
        end
    end
    if not found then
        table.insert(keys, k)
    end
end

root.keys(awful.util.table.join(keys, new_keys))

