--[[
    AWM playerctl is a module for AwesomeWM 4 that monitors the list of players
    reported by playerctl and directs the XF86 media keys to the most recently
    used player.

    To use it:

    require("awm_playerctl")

    Version: 1.0.0
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2020.01.10

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

local unlocalize = function(command)
    return 'bash -c "LC_MESSAGES=C '..command..'"'
end

-- State
local state = {
    last_player = nil,
    subscriber_pid = nil,
}

-- Scehdule state update with subscription
do
    local kill_subscriber = function()
        if state.subscriber_pid then
            local SIGTERM = 15
            awesome.kill(state.subscriber_pid, SIGTERM)
            state.subscriber_pid = nil
        end
    end
    awesome.connect_signal("exit", kill_subscriber)

    local subscribe
    local schedule_subscribe = function()
        state.subscriber_pid = nil
        timer.start_new(60, subscribe)
    end

    subscribe = function()
        kill_subscriber()
        state.subscriber_pid = awful.spawn.with_line_callback(unlocalize('playerctl --follow status -f \\"{{playerName}} {{lc(status)}}\\"'), {
            stdout = function(line)
                local player, status = line:match("(%w+) (%w+)")
                if status ~= 'stopped' then
                    state.last_player = player
                end
            end,
            exit = schedule_subscribe
        })

        if type(state.subscriber_pid) ~= "number" then
            state.subscriber_pid = nil
            return true
        else
            return false
        end
    end

    if subscribe() then
        schedule_subscribe()
    end
end

timer.delayed_call(function()
    local pending_action = false
    local create_action = function(playerctl_verb)
        return function()
            local playerctl_command = string.format('playerctl --player %s %s', state.last_player, playerctl_verb)
            pending_action = pending_action or type(
                awful.spawn.with_line_callback(playerctl_command, {exit = function() pending_action = false end})
            ) == "number"
        end
    end

    root.keys(awful.util.table.join(root.keys(), awful.util.table.join(
    -- https://wiki.archlinux.org/index.php/awesome
    awful.key({}, "XF86AudioPlay", create_action('play-pause'), {description = "play-pause media", group = "media"}),
    awful.key({}, "XF86AudioNext", create_action('next')      , {description = "next media"      , group = "media"}),
    awful.key({}, "XF86AudioPrev", create_action('previous')  , {description = "previous media"  , group = "media"})
    )))
end)

return state

