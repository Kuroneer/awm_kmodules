--[[
    Module for AwesomeWM 4 to show a terminal client as launcher with fzf

    To use it:

    local fzf_launcher_function = require("awm_fzf_launcher")
    fzf_launcher_function()

    Version: 1.0.1
    Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
    Date: 2021.09.05

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

local module  = ...
local Gio     = require("lgi").Gio
local awful   = require("awful")
local naughty = require("naughty")
local timer   = require("gears.timer")

local HEREDOCTAG = '///////////////WMFZFLAUNCHER_HERECODTAG'
local launcher = {
    started = false,
    client = nil,
    client_pid = nil,
    default_options = {
        include_clients = true,
        terminal = (terminal or "urxvt") .. " -e ",
        reading_fifo_path = '/tmp/.awm_fzf_launcher.out',
        notitle = true,
        command = 'basename --multiple $(find -L $(sed "s/:/ /g" <<< $PATH ) -type f -executable -maxdepth 1 2>/dev/null) | fzf +m -1 -0 -e',
        command_with_clients = '( cat <<'..HEREDOCTAG.."\n",
        command_with_clients_tail = HEREDOCTAG.."\n basename --multiple $(find -L $(sed \"s/:/ /g\" <<< $PATH ) -type f -executable -maxdepth 1 2>/dev/null)) | fzf +m -1 -0 -e",
        width = .3,
        height = .3,
    }
}

function launcher:launch(program, clients)
    if not program then
        return
    end

    if clients[program] then
        local c = clients[program]
        if not c:isvisible() then
            c.minimized = false
            for _, t in pairs(c:tags()) do
                if t.selected then
                    client.focus = c
                    c:raise()
                    return
                end
            end
            awful.tag.viewonly(c.first_tag)
        end
        client.focus = c
        c:raise()
        return
    end

    if program:find("^rm") then
        naughty.notify{
            title = "AWM FZF Launcher",
            text = "Dangerous command: Refusing to launch '"..program.."'"
        }
        return
    end

    naughty.notify{
        title = "AWM FZF Launcher",
        text = "Launch '"..program.."'"
    }
    awful.spawn(program)
end

function launcher:spawn(path, file_out)
    local flags = self.options
    local clients = {}
    local command = flags.terminal .. " bash -c '" ..flags.command.." > "..path.."'"
    if flags.include_clients then
        command = flags.terminal .. " bash -c '" ..flags.command_with_clients
        for _, c in ipairs(client.get()) do
            if c.name and not c.skip_taskbar then
                local name = "> "..c.name:gsub('\'', '"') --FIXME escape '
                clients[name] = c
                command = command..name.."\n"
            end
        end
        command = command .. flags.command_with_clients_tail.." > "..path.."'"
    end
    return awful.spawn(command, true,
    function(c)
        -- Triggers before "manage" event, but there are some client
        -- properties that need to be set on "manage"
        self.client = c;
        c.skip_taskbar = true
        c.name = "AWM FZF LAUNCHER"

        -- Get output
        local program = nil
        awful.spawn.read_lines(file_out:read(), function(line) program = line end,
        function() self:launch(program, clients) end, nil, true)
    end)
end

function launcher:spawn_with_fifo()
    if self.client_pid then
        return
    end

    local path = self.options.reading_fifo_path
    local file = Gio.File.new_for_path(path)
    local gfileinfo = file:query_info("standard::type,access::can-read,access::can-write", Gio.FileQueryInfoFlags.NONE)
    if gfileinfo and gfileinfo:get_file_type() == "SPECIAL" and gfileinfo:get_attribute_boolean("access::can-read") and gfileinfo:get_attribute_boolean("access::can-write") then
        self.client_pid = self:spawn(path, file)
        return
    end

    self.client_pid = awful.spawn.with_line_callback("mkfifo --mode=og-rwx "..path, {
        exit = function(reason, code)
            if code ~= 0 then
                naughty.notify{
                    title = "Error while launching "..module,
                    text = "Cannot create FIFO at "..path,
                    timeout = 0,
                }
                self.client_pid = nil
            elseif self.client_pid then
                self.client_pid = self:spawn_with_fifo()
            end
        end
    })
end

-- Create the terminal display
function launcher:init(options)
    if not self.has_fzf then
        self.has_fzf = type(awful.spawn("fzf")) == "number"
        if not self.has_fzf then
            return
        end
    end
    self.options = setmetatable(options or {}, { __index = self.default_options })

    if not self.started then
        self.started = true
        client.connect_signal("manage", function(c)
            if c and c == self.client then
                c:connect_signal("unmanage", function()
                    self.client = nil
                    self.client_pid = nil
                end)

                c:connect_signal("unfocus", function()
                    c:kill()
                end)

                c.sticky = true
                c.urgent = false
                c.ontop = true
                c.floating = true
                c.size_hints_honor = false
                c:buttons{}
                c:keys{}
                c.is_fixed = true
                client.focus = c
                if self.options.notitle then
                    awful.titlebar.hide(c)
                end

                local no_tags = function() c:tags{} end
                c:connect_signal("tagged", no_tags)
                timer.delayed_call(no_tags)

                local geom = c.screen.workarea
                local width, height = self.options.width, self.options.height
                width = width <= 1 and geom.width * width or width
                height = height <= 1 and geom.height * height or height
                c:geometry{
                    x = geom.x + .5 * (geom.width - width),
                    y = geom.y + .5 * (geom.height - height),
                    width = width - 2 * (client.border_width or 0),
                    height = height - 2 * (client.border_width or 0),
                }
            end
        end)

        awesome.connect_signal("exit", function()
            if self.client then
                self.client:kill()
            end
        end)
    end

    self:spawn_with_fifo()
    return true
end

return setmetatable(launcher, { __call = function(t, ...) return t:init(...) end })

