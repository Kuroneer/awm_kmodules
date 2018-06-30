local awful = require("awful")
local beautiful = require("beautiful")

return function(commands, timeout, text, fg_color, bg_color)
    local state = {
        text = text or "!",
        fg_color = fg_color or beautiful.fg_urgent,
        bg_color = bg_color or beautiful.bg_urgent,

        commands = setmetatable(commands or {}, {__index = {
            check = "pacman -Qu",
            update = terminal .. " -e sudo pacman -Syu"
        }}),
    }
    function state.update_function(widget, stdout, _stderr, _exitreason, exitcode)
        widget:set_markup_silently(stdout and stdout:len() > 0 and '<span size="larger" weight="bold" color="'..state.fg_color..'" bgcolor="'..state.bg_color..'">'..state.text..'</span>' or "")
    end

    local widget = awful.widget.watch(state.commands.check, timeout or 7200, state.update_function)

    state.pending_action = false
    widget:buttons(awful.util.table.join(awful.button({}, 1, function()
        state.pending_action = state.pending_action or type(awful.spawn.with_line_callback(state.commands.update,
        {exit = function()
            if type(awful.spawn.easy_async(state.commands.check,
                function(stdout, stderr, exitreason, exitcode)
                    state.update_function(widget, stdout, stderr, exitreason, exitcode)
                    state.pending_action = false
                end)) ~= "number" then
                state.pending_action = false
            end
        end})) == "number"
    end)))

    return widget
end

