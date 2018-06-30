local awful = require("awful")

local bars  = {"▁","▂","▃","▄","▅","▆","▇","█"}
local commands = {
    decrease = "amixer -q -D pulse sset Master 5%-",
    increase = "amixer -q -D pulse sset Master 5%+",
    toggle_mute = "amixer -D pulse set Master 1+ toggle",
    update = "amixer -D pulse get Master"
}
local update_function = function(widget, stdout)
    local sum_percentage, count, off = 0, 0, false
    for percentage, onoff in stdout:gmatch("(%d+)%%.*%[(%S*)%]") do
        off = off or onoff == "off"
        sum_percentage = sum_percentage + tonumber(percentage)
        count = count + 1
    end
    if off then
        widget:set_text(" ♬ M ")
    elseif count > 0 then
        widget:set_text(string.format(" ♬ %s ", sum_percentage > 0 and bars[math.floor(sum_percentage/count*(#bars-1) / 100)+1] or "X"))
    end
end

local widget = awful.widget.watch(commands.update, 45, update_function)

require("gears.timer").delayed_call(function()
    local pending_action = false
    local callbacks = {exit = function()
        if type(awful.spawn.easy_async(commands.update, function(stdout)
            update_function(widget, stdout)
            pending_action = false
        end)) ~= "number" then
            pending_action = false
        end
    end}
    local create_action = function(command_key)
        return function()
            pending_action = pending_action or type(awful.spawn.with_line_callback(commands[command_key], callbacks)) == "number"
        end
    end

    root.keys(awful.util.table.join(root.keys(), awful.util.table.join(
    -- Volume Keys from https://wiki.archlinux.org/index.php/awesome
    awful.key({}, "XF86AudioLowerVolume", create_action("decrease")),
    awful.key({}, "XF86AudioRaiseVolume", create_action("increase")),
    awful.key({}, "XF86AudioMute", create_action("toggle_mute"))
    )))

    widget:buttons(awful.util.table.join(
    awful.button({}, 1, create_action("toggle_mute")),
    awful.button({}, 4, create_action("increase")),
    awful.button({}, 5, create_action("decrease"))
    ))
end)

return widget

