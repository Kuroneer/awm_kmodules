local awful = require("awful")
local bars  = {"▁","▂","▃","▄","▅","▆","▇","█"}

local update_command = "amixer -D pulse get Master"
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

local widget = awful.widget.watch(update_command, 45, update_function)

require("gears.timer").delayed_call(function()
    local callbacks = {exit = function()
        awful.spawn.easy_async(update_command, function(stdout)
            update_function(widget, stdout)
        end)
    end}

    root.keys(awful.util.table.join(root.keys(), awful.util.table.join(
    -- Volume Keys from https://wiki.archlinux.org/index.php/awesome
    awful.key({}, "XF86AudioLowerVolume", function ()
        awful.spawn.with_line_callback("amixer -q -D pulse sset Master 5%-", callbacks)
    end),
    awful.key({}, "XF86AudioRaiseVolume", function ()
        awful.spawn.with_line_callback("amixer -q -D pulse sset Master 5%+", callbacks)
    end),
    awful.key({}, "XF86AudioMute", function ()
        awful.spawn.with_line_callback("amixer -D pulse set Master 1+ toggle", callbacks)
    end)
    )))
end)

return widget

