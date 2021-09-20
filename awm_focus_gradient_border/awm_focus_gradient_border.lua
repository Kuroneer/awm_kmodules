--[[
    AWM Focus Gradient Border: A simple module for AwesomeWM 4 that applies a gradient over
    time to the focused client border color

    Copyright (C) <2018> Jose Maria Perez Ramos

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

    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.05
    Version: 1.0.1
]]

--[[
    -- EXAMPLE:
    -- Focus border color gradient with examples:
    local focus_gradient_border_fun = require("awm_focus_gradient_border")

    -- OPTION 1:
    -- Focus starts with color border_focus but fades into border_normal
    -- Fading stays, but faster, when unfocused
    focus_gradient_border_fun("focus", {
        origin_color = beautiful.border_focus,
        target_color = beautiful.border_normal
    })

    -- OPTION 2:
    -- Focus show briefly in blue before turning to border_focus
    focus_gradient_border_fun("focus", {
        origin_color = "#109FFF",
        target_color = beautiful.border_focus,
        elapse_time = .6
    })
    -- When a client loses focus, change to border_normal from its current border color
    focus_gradient_border_fun("unfocus", {target_color = beautiful.border_normal})
]]

local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")

-- AUX
local function set_border_color_from_table_n_steps(c, t, n, step)
    local color = "#"
    for i, v in ipairs(t) do
        v = v - (n and n > 0 and n*step[i] or 0)
        color = color..string.format("%02x", math.floor(v * 255))
    end
    c.border_color = color
end

local function create_step(origin_color_t, target_color_t, nsteps)
    local step_t = {}
    local step_is_zero = true
    for k=1,4 do
        step_t[k] = ((target_color_t[k] or 0) - (origin_color_t[k] or 0)) / nsteps
        step_is_zero = step_is_zero and step_t[k] == 0
    end
    return step_t, step_is_zero
end

local gradient_border = {
    defaults = {
        focus = {
            origin_color = nil, -- Use current border color
            target_color = beautiful.border_focus,
            elapse_time  = 1.3,
            interval     = .1,
            unfocused_factor = .7,
        },
        unfocus = {
            origin_color = nil, -- Use current border color
            target_color = beautiful.border_normal,
            elapse_time  = 1.3,
            interval     = .1,
            unfocused_factor = .7,
        }
    },
    values = {},
    border_timers = {},
    connected = {}
}

function gradient_border:set_values(signal, v)
    self.values[signal] = setmetatable(v, {__index = self.defaults[signal]})

    v.origin_color_t = v.origin_color and {gears.color.parse_color(v.origin_color)}
    if v.origin_color_t then v.origin_color_t[4] = nil end

    if type(v.target_color) == "string" then
        v.target_color_t = {gears.color.parse_color(v.target_color)}
        v.target_color_t[4] = nil
    end

    v.nsteps = math.ceil(v.elapse_time / v.interval)
    if v.origin_color_t and v.target_color_t then
        v.step_t, v.step_is_zero = create_step(v.origin_color_t, v.target_color_t, v.nsteps)
    end
end
gradient_border:set_values(  "focus", {}) -- Create defaults
gradient_border:set_values("unfocus", {}) -- Create defaults

-- Schedule cleanup
client.connect_signal("manage", function (c, _startup)
    c:connect_signal("unmanage", function(c)
        local timer = gradient_border.border_timers[c.window]
        gradient_border.border_timers[c.window] = nil
        if timer and timer.started then
            timer:stop()
        end
    end)
end)

function gradient_border:set_values_and_signals(signal, v)
    if not self.defaults[signal] then
        return false
    end

    self:set_values(signal, v)

    if not self.connected[signal] then
        client.connect_signal(signal, function(c)
            if self.border_timers[c.window] and self.border_timers[c.window].started then
                self.border_timers[c.window]:stop()
            end

            local local_values = self.values[signal]
            local nsteps = local_values.nsteps
            local step_t = local_values.step_t
            local step_is_zero = local_values.step_is_zero
            local target_color_t = local_values.target_color_t
            if not target_color_t then
                target_color_t = {gears.color.parse_color(local_values.target_color(c))}
                target_color_t[4] = nil
            end

            if local_values.origin_color_t then
                set_border_color_from_table_n_steps(c, local_values.origin_color_t)
            else
                local current_color = {gears.color.parse_color(c.border_color)}
                current_color[4] = nil
                step_t, step_is_zero = create_step(current_color, target_color_t, nsteps)
            end

            if not step_is_zero then
                self.border_timers[c.window] = gears.timer.start_new(local_values.interval, function()
                    nsteps = (c == client.focus and 1 or local_values.unfocused_factor)* nsteps -1
                    set_border_color_from_table_n_steps(c, target_color_t, nsteps, step_t)
                    return nsteps > 0
                end)
            end
        end)
        self.connected[signal] = true
    end

    return true
end

return setmetatable(gradient_border, {__call = function(t, signal, values) t:set_values_and_signals(signal, values) end})

