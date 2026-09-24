-- playlist_repeat.lua
--
-- Up / Down: previous / next file. Hold to keep skipping: it starts at about
-- eight files a second and speeds up the longer you hold, up to 40 a second.
--
-- At the top or end of the playlist the arrows either stop or wrap round to
-- the other end; toggle with Sort > Wrap Up/Down (remembered in
-- script-opts/playlist_repeat.conf). loop-playlist still decides what happens
-- when a file simply finishes.
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
--        script-binding playlist_repeat/wrap          toggle wrapping at the ends

local mp      = require 'mp'
local options = require 'mp.options'

local o = { wrap = false }
options.read_options(o, 'playlist_repeat')

local HOLD      = 0.4    -- seconds held before repeating starts
local RATE      = 8      -- skips per second when repeating starts
local RATE_GAIN = 24     -- extra skips per second, for every second held
local RATE_MAX  = 40     -- mpv repeats a held key 40 times a second (input-ar-rate)

local pressed_at, last = 0, 0

-- For the wheel menu, which marks the option with a dot when it is on.
local function publish()
    mp.set_property_native('user-data/playlist_repeat', { wrap = o.wrap })
end

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

-- One step up (-1) or down (+1).
local function step(dir)
    local pos   = mp.get_property_number('playlist-pos', 0)
    local count = mp.get_property_number('playlist-count', 0)
    local at_end = (dir < 0 and pos <= 0) or (dir > 0 and pos >= count - 1)
    if not at_end then
        return mp.command(dir < 0 and 'playlist-prev' or 'playlist-next')
    end
    if not o.wrap then
        return mp.osd_message(dir < 0 and 'Top of the playlist' or 'End of the playlist', 1)
    end
    if count > 1 then mp.commandv('playlist-play-index', dir < 0 and count - 1 or 0) end
end

local function binding(dir)
    return function(e)
        local now = mp.get_time()
        if e.event == 'down' or e.event == 'press' then
            pressed_at, last = now, now
            when_sorted(function() step(dir) end)
        elseif e.event == 'repeat' then
            local held = now - pressed_at
            if held < HOLD then return end
            local rate = math.min(RATE_MAX, RATE + RATE_GAIN * (held - HOLD))
            -- Repeat events arrive every 25 ms; the small slack keeps them from
            -- being skipped by jitter once the rate reaches their pace.
            if now - last >= 1 / rate - 0.005 then
                last = now
                step(dir)
            end
        end
    end
end

local function toggle_wrap()
    o.wrap = not o.wrap
    local path = mp.command_native({ 'expand-path', '~~/script-opts/playlist_repeat.conf' })
    local f = io.open(path, 'w')
    if f then
        f:write('# Up/Down wrap round from the top of the playlist to the end and back.\n',
                '# Toggled from Sort > Wrap Up/Down, which rewrites this file.\n',
                'wrap=', o.wrap and 'yes' or 'no', '\n')
        f:close()
    end
    publish()
    mp.osd_message('Up/Down wrap at the ends: ' .. (o.wrap and 'on' or 'off'), 2)
end

mp.add_key_binding(nil, 'pl-prev-hold', binding(-1), { complex = true, repeatable = true })
mp.add_key_binding(nil, 'pl-next-hold', binding(1),  { complex = true, repeatable = true })
mp.add_key_binding(nil, 'wrap', toggle_wrap)
publish()
