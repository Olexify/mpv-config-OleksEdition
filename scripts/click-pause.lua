-- click-pause.lua
--
-- Left-click on the video toggles pause, but only for a click: pressing and
-- dragging moves the window (window-dragging) without pausing. The decision is
-- made on release, when we know whether the mouse moved.
--
-- Binding (mpv turns "-" into "_" in script names, hence click_pause):
--   MBTN_LEFT script-binding click_pause/click

local mp = require 'mp'

local DEADZONE = 3       -- pixels; same as mpv's --input-dragging-deadzone default

local down_x, down_y = nil, nil

local function mouse()
    local p = mp.get_property_native('mouse-pos') or {}
    return p.x or 0, p.y or 0
end

mp.add_key_binding(nil, 'click', function(e)
    if e.event == 'down' then
        down_x, down_y = mouse()
    elseif e.event == 'up' and down_x then
        local x, y = mouse()
        local moved = math.abs(x - down_x) > DEADZONE or math.abs(y - down_y) > DEADZONE
        down_x, down_y = nil, nil
        if not moved then
            mp.command('cycle pause')
            mp.commandv('script-message-to', 'uosc', 'flash-pause-indicator')
        end
    elseif e.event == 'press' then
        mp.command('cycle pause')
        mp.commandv('script-message-to', 'uosc', 'flash-pause-indicator')
    end
end, { complex = true })
