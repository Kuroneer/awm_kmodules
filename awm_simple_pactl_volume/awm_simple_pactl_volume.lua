--[[
    AWM Simple Pactl Volume is a widget for AwesomeWM 4 that monitors and
    lets you control the volume of the current pulseaudio sink. It hooks to
    the XF86 keys.

    To use it:

    local volume_widget = require("awm_simple_pactl_volume")


    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.10
    Version: 1.0.2

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
]]
-- Modules
local awful = require("awful")
local naughty = require("naughty")
local timer = require("gears.timer")
local wibox = require("wibox")

-- Constants
local commands = {
    decrease = "pactl -- set-sink-volume %i -5%%",
    increase = "pactl -- set-sink-volume %i +5%%",
    toggle_mute = "pactl -- set-sink-mute %i toggle",
}

-- Utils
local ongoing_action = false
local scheduled_action = false
local function async_run_generator(command, callback)
    local call
    call = function()
        if ongoing_action then
            scheduled_action = true
            return
        end

        scheduled_action = false
        ongoing_action = type(awful.spawn.easy_async(command, function(stdout)
            ongoing_action = false
            if scheduled_action then
                call()
            else
                callback(stdout)
            end
        end)) == "number"
    end
    return call
end

local unlocalize = function(command)
    return 'bash -c "LC_ALL=C '..command..'"'
end

-- State
local state = {
    current_sink = nil,
    current_port = nil,
    sinks = {},
    pactl_subscribe_pid = nil,
    text_widget = wibox.widget{
        markup = "M ",
        align  = 'center',
        valign = 'center',
        widget = wibox.widget.textbox,
    },
    symbol_widget = wibox.widget{
        markup = ' ♬ ',
        align  = 'left',
        valign = 'center',
        widget = wibox.widget.textbox,
    },
}
state.widget = wibox.widget{
    state.symbol_widget,
    state.text_widget,
    layout = wibox.layout.align.horizontal
}

-- Update state information
local process_sinks = async_run_generator(unlocalize("pactl list sinks"), function(stdout)
    local sinks = state.sinks
    local current_sinks = {}
    local sink = {}

    for line in stdout:gmatch("([^\r\n]+)") do
        if line:match("^Sink") then
            local sink_index = line:match("^Sink #(%d+)")
            if sink_index then
                sinks[sink_index] = sinks[sink_index] or {
                    index = sink_index,
                    disabled = false,
                    description = nil,
                    state_running = 0,
                    volume = 0,
                    muted = false,
                    ports = {},
                    active_port = nil,
                    name = nil
                }
                sink = sinks[sink_index]
                current_sinks[sink_index] = true
            end
        elseif line:match("State: ") then
            local running_state = line:match("State: ([^\r\n]+)")
            if running_state == "RUNNING" then
                sink.state_running = 2
            elseif running_state == "IDLE" then
                sink.state_running = 1
            else
                sink.state_running = 0
            end
        elseif line:match("Description: ") then
            sink.description = sink.description or line:match("Description: ([^\r\n]+)")
        elseif line:match("Name: ") then
            sink.name = sink.name or line:match("Name: ([^\r\n]+)")
        elseif line:match("Mute: ") then
            sink.muted = line:match("Mute: (%w+)") ~= "no"
        elseif line:match("^[ \t]*Volume: ") then
            local count = 0
            local sum = 0
            for vol in line:gmatch("(%d+)%%") do
                count = count +1
                sum = sum + vol
            end
            sink.volume = count > 0 and sum/count or 0
        elseif line:match("priority: %d+.*%)$") then
            local port_key, port_name, port_priority = line:match("([^%s]+): ([^%(]+) %(.*priority: (%d+).*%)")
            sink.ports[port_key] = {
                key = port_key,
                name = port_name,
                priority = port_priority
            }
        elseif line:match("Active Port: ") then
            sink.active_port = line:match("Active Port: ([^\r\n]+)")
        end
    end

    -- Remove old sinks
    for k in pairs(sinks) do
        if not current_sinks[k] then
            sinks[k] = nil
        end
    end

    -- Get best sink
    local sink_count = 0
    local best_sink = nil
    for _, sink in pairs(sinks) do
        if not sink.disabled then
            sink_count = sink_count +1
            if
                (not best_sink) or
                (best_sink.state_running < sink.state_running) or
                ((best_sink.state_running == sink.state_running) and best_sink.ports[best_sink.active_port].priority > sink.ports[sink.active_port].priority)
                then
                    best_sink = sink
            end
        end
    end

    -- Notify if best sink has changed
    if
        (state.current_sink ~= best_sink) or
        (state.current_port ~= best_sink.active_port) then

        if sink_count > 1 or state.current_sink then
            local text = '<span weight="bold"> Audio: '..best_sink.description..'</span> '..best_sink.ports[best_sink.active_port].name
            local notification = naughty.getById(state.notification_id)

            if notification then
                naughty.replace_text(notification, nil, text)
                naughty.reset_timeout(notification, 0)
            else
                state.notification_id = naughty.notify(setmetatable({
                    text = text,
                    timeout = 5,
                    replaces_id = state.notification_id,
                }, { __index = state.notification_defaults})).id
            end
        end
    end
    state.current_sink = best_sink
    state.current_port = best_sink and best_sink.active_port or nil

    -- Update widget with current_sink info
    if state.current_sink then
        if best_sink.muted then
            state.text_widget:set_text("M ")
        else
            state.text_widget:set_text(string.format("%s ", best_sink.volume > 0 and math.floor(best_sink.volume) or "X"))
        end
    else
        state.text_widget:set_text("? ")
    end
end)

-- Scehdule state update with pactl subscribe
do
    local pactl_resubscribe
    local schedule_restart = function()
        state.pactl_subscribe_pid = nil
        if pactl_resubscribe() then
            timer.start_new(60, pactl_resubscribe)
        end
    end
    pactl_resubscribe = function()
        state.pactl_subscribe_pid = awful.spawn.with_line_callback(unlocalize("pactl --client-name=awesomewm-listener subscribe"), {
            stdout = function(line)
                local operation, sink_index = line:match("Event '(%w+)' on sink #(%d+)")
                if operation then
                    if operation == "remove" then -- For race conditions
                        state.sinks[sink_index].disabled = true
                    end
                    process_sinks()
                end
            end,
            exit = schedule_restart
        })

        if type(state.pactl_subscribe_pid) ~= "number" then
            return true
        else
            return false
        end
    end

    schedule_restart()

    awesome.connect_signal("exit", function()
        if state.pactl_subscribe_pid then
            local SIGTERM = 15
            awesome.kill(state.pactl_subscribe_pid, SIGTERM)
        end
    end)
end

-- Schedule state update
timer.start_new(60, function() process_sinks() return true end)

-- Update state
process_sinks()

timer.delayed_call(function()
    local pending_action = false
    local create_action = function(command_key)
        return function()
            pending_action = pending_action or type(
                awful.spawn.with_line_callback(
                    string.format(commands[command_key], state.current_sink.index),
                    {
                        exit = function()
                            pending_action = false
                            --process_sinks() -- Process sinks will be triggered by pactl subscribe
                        end
                    }
                )
            ) == "number"
        end
    end

    root.keys(awful.util.table.join(root.keys(), awful.util.table.join(
    -- Volume Keys from https://wiki.archlinux.org/index.php/awesome
    awful.key({}, "XF86AudioLowerVolume", create_action("decrease")),
    awful.key({}, "XF86AudioRaiseVolume", create_action("increase")),
    awful.key({}, "XF86AudioMute", create_action("toggle_mute"))
    )))

    state.widget:buttons(awful.util.table.join(
    awful.button({}, 1, create_action("toggle_mute")),
    awful.button({}, 4, create_action("increase")),
    awful.button({}, 5, create_action("decrease"))
    ))
end)

return state.widget

