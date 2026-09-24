-- playlist_repeat.lua
--
-- Up / Down: previous / next file. Hold for half a second to keep skipping,
-- about eight files a second. Stops at the top and end of the playlist.
--
-- Repeats come from mpv's own key repeat, so skipping stops the moment the key
-- is released or the window loses focus; there are no timers here that could
-- keep running on their own.
--
-- Right after a folder is opened, sort-playlist.lua may still be putting it in
-- order. A press made then waits for that (at most 3 s), so each step follows
-- the order you actually see instead of one that gets reshuffled under you.
--
-- Bindings (input.conf):
--   UP   script-binding playlist_repeat/pl-prev-hold
--   DOWN script-binding playlist_repeat/pl-next-hold

local mp = require 'mp'

local HOLD  = 0.5        -- seconds held before repeating starts
local EVERY = 0.12       -- seconds between repeated skips

local pressed_at, last = 0, 0

-- Run fn now, or once sort-playlist.lua reports the playlist is in order.
local function when_sorted(fn)
    local s = mp.get_property_native('user-data/sort_playlist')
    if not (s and s.pending) then return fn() end
    local done, timer, watch = false, nil, nil
    local function go()
        if done then return end
        done = true
        mp.unobserve_property(watch)
        timer:kill()
        fn()
    end
    watch = function(_, v) if not (v and v.pending) then go() end end
    timer = mp.add_timeout(3, go)
    mp.observe_property('user-data/sort_playlist', 'native', watch)
end

-- One step up (-1) or down (+1). The arrows stop at either end instead of
-- wrapping round; loop-playlist still loops when a file simply ends.
local function step(dir)
    local pos   = mp.get_property_number('playlist-pos', 0)
    local count = mp.get_property_number('playlist-count', 0)
    if dir < 0 and pos <= 0 then return mp.osd_message('Top of the playlist', 1) end
    if dir > 0 and pos >= count - 1 then return mp.osd_message('End of the playlist', 1) end
    mp.command(dir < 0 and 'playlist-prev' or 'playlist-next')
end

local function binding(dir)
    return function(e)
        local now = mp.get_time()
        if e.event == 'down' or e.event == 'press' then
            pressed_at, last = now, now
            when_sorted(function() step(dir) end)
        elseif e.event == 'repeat' and now - pressed_at >= HOLD and now - last >= EVERY then
            last = now
            step(dir)
        end
    end
end

mp.add_key_binding(nil, 'pl-prev-hold', binding(-1), { complex = true, repeatable = true })
mp.add_key_binding(nil, 'pl-next-hold', binding(1),  { complex = true, repeatable = true })
