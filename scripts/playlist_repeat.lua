local hold_timer = nil
local interval = 0.01  -- seconds between skips when holding
local hold_delay = 0.25 -- seconds before rapid switching starts

local function start_hold(cmd)
    mp.command(cmd)
    hold_timer = mp.add_timeout(hold_delay, function()
        hold_timer = mp.add_periodic_timer(interval, function()
            mp.command(cmd)
        end)
    end)
end

local function stop_hold()
    if hold_timer then
        hold_timer:kill()
        hold_timer = nil
    end
end

mp.add_forced_key_binding("UP", "pl-prev-hold", function(e)
    if e.event == "down" then
        start_hold("playlist-prev")
    elseif e.event == "up" then
        stop_hold()
    end
end, {complex = true})

mp.add_forced_key_binding("DOWN", "pl-next-hold", function(e)
    if e.event == "down" then
        start_hold("playlist-next")
    elseif e.event == "up" then
        stop_hold()
    end
end, {complex = true})