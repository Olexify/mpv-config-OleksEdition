-- radial-menu.lua
--
-- Right-click wheel menu, in the style of the GTA weapon wheel or the VRChat
-- action menu. Built from the same "Folder > Item" menu entries in input.conf
-- that the uosc menu uses, so both menus always match.
--
-- Folders expand outward: pointing at a folder fans its contents out as a new
-- ring just beyond it, while the rings you came through stay on screen with
-- your path highlighted. Everything is sized up front so the deepest folder
-- still fits on screen.
--
--   Hold right button    the wheel opens; point at a slice
--   Point at a folder    its contents fan out next to it, no click needed
--   Release              runs the slice under the pointer; releasing on a
--                        folder keeps the wheel open, releasing in the
--                        middle closes it
--   Quick right-click    the wheel stays open: left-click picks a slice,
--                        right-click, Esc or a click in the middle closes
--
-- Options that are currently on (toggles, loaded shaders, the chosen sort
-- order) are shown in amber with a dot.
--
-- Also provides a keyboard shortcuts screen listing every keyed entry.
--
-- Bindings (mpv turns "-" into "_" in script names, hence radial_menu):
--   MBTN_RIGHT script-binding radial_menu/open
--   ?          script-binding radial_menu/shortcuts

local mp = require 'mp'

local TAP      = 0.30    -- right-clicks shorter than this keep the wheel open
local RING     = 3.0     -- ring thickness, in units of the label font size
local ARC      = 9.5     -- room each slice gets along its ring, same units
local ARC_TOP  = 5.2     -- the same for the top ring, whose labels are short
local TOP_FONT = 0.9     -- top ring labels are a bit smaller to fit that

local atan2 = math.atan2 or math.atan
local cos, sin, pi, floor = math.cos, math.sin, math.pi, math.floor

-- Colours are ASS &HBBGGRR&.
local C_SLICE, C_PATH, C_HOVER = '&H2A2522&', '&H3A6E9C&', '&HF5F2F0&'
local C_TEXT, C_TEXT_HOVER, C_DIM, C_ACCENT = '&HF5F2F0&', '&H1B1716&', '&HA8A09A&', '&H20B0FF&'

-- ── menu tree from input.conf ────────────────────────────────────────────────

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- Lines look like either of:
--   KEY command ...            #! Folder > Sub > Title
--   # command ...              #! Folder > Title      (menu entry, no key)
-- Keyed lines that end in a plain "# description" instead are collected in
-- `general`, for the shortcuts screen.
local function load_tree()
    local root = { title = 'Menu', items = {}, general = {} }
    local f = io.open(mp.command_native({ 'expand-path', '~~/input.conf' }), 'r')
    if not f then return root end
    for line in f:lines() do
        local left, spec = line:match('^(.-)#!(.*)$')
        if left then
            left = trim(left)
            local key, cmd
            if left:sub(1, 1) == '#' then
                cmd = trim(left:sub(2))
            else
                key, cmd = left:match('^(%S+)%s+(.+)$')
            end
            local parts = {}
            for p in spec:gmatch('[^>]+') do parts[#parts + 1] = trim(p) end
            if cmd and cmd ~= '' and #parts > 0 and parts[#parts] ~= '---' then
                local node = root
                for i = 1, #parts - 1 do
                    local child
                    for _, it in ipairs(node.items) do
                        if it.items and it.title == parts[i] then child = it end
                    end
                    if not child then
                        child = { title = parts[i], items = {} }
                        node.items[#node.items + 1] = child
                    end
                    node = child
                end
                node.items[#node.items + 1] = { title = parts[#parts], cmd = cmd, key = key }
            end
        else
            local key, desc = line:match('^([^#%s]%S*)%s+.-%s#%s*([^!@%s].-)%s*$')
            if key then root.general[#root.general + 1] = { key = key, title = desc } end
        end
    end
    f:close()
    return root
end

-- Whether an entry's option is currently on, so the wheel can mark it:
-- plain "cycle <flag>" toggles, shader toggles, and the sort choices that
-- sort-playlist.lua publishes.
local function is_on(cmd)
    local b = cmd:match('^script%-binding%s+sort_playlist/([%w%-]+)')
    if b then
        local s = mp.get_property_native('user-data/sort_playlist') or {}
        if b == 'subfolders' then return s.subfolders == true end
        return s.mode == (b:gsub('%-', '_'))
    end
    local prop = cmd:match('^cycle%s+([%w%-]+)%s*$')
    if prop then return mp.get_property_native(prop) == true end
    local shader = cmd:match('^change%-list%s+glsl%-shaders%s+toggle%s+(%S+)')
    if shader then
        local full = mp.command_native({ 'expand-path', shader })
        for _, s in ipairs(mp.get_property_native('glsl-shaders') or {}) do
            if s == shader or s == full then return true end
        end
    end
    return false
end

local function mark_on(node)
    for _, it in ipairs(node.items) do
        if it.items then mark_on(it) else it.on = is_on(it.cmd) end
    end
end

-- Number of rings needed to show the deepest folder.
local function depth(node)
    local d = 0
    for _, it in ipairs(node.items) do
        if it.items then d = math.max(d, depth(it)) end
    end
    return d + 1
end

-- ── drawing helpers ──────────────────────────────────────────────────────────

local function esc(s) return (s:gsub('[{}\\]', '')) end

-- Long labels go on two lines, split at the space nearest the middle.
local function wrap(s, width)
    if #s <= width then return s end
    local best
    for i in s:gmatch('() ') do
        if not best or math.abs(i - #s / 2) < math.abs(best - #s / 2) then best = i end
    end
    if not best then return s:sub(1, width - 1) .. '…' end
    local a, b = s:sub(1, best - 1), s:sub(best + 1)
    if #b > width + 2 then b = b:sub(1, width + 1) .. '…' end
    return a .. '\\N' .. b
end

local function pt(x, y) return floor(x + 0.5) .. ' ' .. floor(y + 0.5) end

-- Ring segment between radii r1 < r2 and angles a0 < a1 (r1 = 0 gives a disc).
local function wedge(cx, cy, r1, r2, a0, a1)
    local steps = math.max(2, math.ceil((a1 - a0) / 0.05))
    local out = {}
    for s = 0, steps do
        local a = a0 + (a1 - a0) * s / steps
        out[#out + 1] = pt(cx + r2 * cos(a), cy + r2 * sin(a))
    end
    for s = steps, 0, -1 do
        local a = a0 + (a1 - a0) * s / steps
        out[#out + 1] = pt(cx + r1 * cos(a), cy + r1 * sin(a))
    end
    return 'm ' .. out[1] .. ' l ' .. table.concat(out, ' ', 2)
end

local function shape(colour, alpha, path)
    return ('{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\1a&H%02X&\\p1}%s{\\p0}')
        :format(colour, alpha, path)
end

-- Rotation that lays a label along the ring at angle theta, flipped on the
-- lower half so it never reads upside down. Along the ring a label only needs
-- its slice's arc length, instead of running sideways into the next ring.
local function along(theta)
    local deg = theta * 180 / pi + 90
    if sin(theta) > 0 then deg = deg + 180 end
    return ('\\frz%.1f'):format(-deg)
end

local function label(x, y, size, colour, s, tags)
    return ('{\\an5\\pos(%d,%d)\\fs%d\\q2\\bord0\\shad0\\1c%s%s}%s')
        :format(floor(x + 0.5), floor(y + 0.5), size, colour, tags or '', s)
end

-- ── geometry ─────────────────────────────────────────────────────────────────

local W = nil            -- the open wheel, nil when closed
local update, close      -- forward declarations

local function mouse()
    local p = mp.get_property_native('mouse-pos') or {}
    return p.x or 0, p.y or 0
end

-- Size everything from the label font size f: the top ring sits far enough
-- out that its slices have room for their labels, and every deeper ring adds
-- one more RING of thickness. f is then picked so the deepest ring fits.
local function place(x, y)
    local w, h = mp.get_osd_size()
    local mid1  = math.max(#W.tree.items * ARC_TOP / (2 * pi), 3)
    local units = mid1 + RING / 2 + (W.depth - 1) * RING
    local f     = math.max(12, math.min(30, math.min(w, h) * 0.48 / units))
    W.f, W.t    = f, RING * f
    W.c         = (mid1 - RING / 2) * f             -- inner edge of the top ring
    local m     = units * f + 8
    W.cx = math.max(m, math.min(w - m, x))
    W.cy = math.max(m, math.min(h - m, y))
end

-- The rings on screen: the top ring all the way round, then one fan per
-- selected folder, centred on the slice it grew out of.
local function rings()
    local list = {}
    local node, from = W.tree, nil
    for k = 1, W.depth do
        local n    = #node.items
        local r_in = W.c + (k - 1) * W.t
        local a, start
        if k == 1 then
            a = 2 * pi / n
            start = -pi / 2 - a / 2
        else
            a = math.min(2 * pi / n, ARC * W.f / (r_in + W.t / 2))
            start = from - n * a / 2
        end
        list[k] = { node = node, r_in = r_in, a = a, start = start }
        local i  = W.sel[k]
        local it = i and node.items[i]
        if not (it and it.items and #it.items > 0) then break end
        node, from = it, start + (i - 0.5) * a
    end
    return list
end

-- Ring and slice under (x, y). Anywhere past the small hub picks from the top
-- ring by direction alone, like a GTA wheel. Further out, the ring at that
-- distance is used; if its fan does not reach that direction, the rings
-- inside it are tried, so overshooting past the edge still lands somewhere
-- sensible.
local function hit(x, y, list)
    local dx, dy = x - W.cx, y - W.cy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1.5 * W.f then return nil end
    local ang = atan2(dy, dx)
    local k = dist < W.c and 1 or math.min(#list, floor((dist - W.c) / W.t) + 1)
    for j = k, 1, -1 do
        local R, n = list[j], #list[j].node.items
        local i = floor(((ang - R.start) % (2 * pi)) / R.a) + 1
        if j == 1 then i = math.min(i, n) end        -- float slack at 360°
        if i <= n then return j, i end
    end
end

local function hovered()
    if not W or not W.hover then return nil end
    local R = rings()[W.hover[1]]
    return R and R.node.items[W.hover[2]]
end

-- ── render ───────────────────────────────────────────────────────────────────

local function render(list)
    local w, h = mp.get_osd_size()
    local cx, cy, f, t = W.cx, W.cy, W.f, W.t
    local out = { shape('&H000000&', 0x90, ('m 0 0 l %d 0 %d %d 0 %d'):format(w, w, h, h)) }

    for k, R in ipairs(list) do
        local mid = R.r_in + t / 2
        local gap = 3 / mid                                 -- ~3px between slices
        for i, it in ipairs(R.node.items) do
            local c   = R.start + (i - 0.5) * R.a
            local hov = W.hover and W.hover[1] == k and W.hover[2] == i
            local fill, alpha = C_SLICE, 0x20
            if hov then fill, alpha = C_HOVER, 0x00
            elseif W.sel[k] == i then fill, alpha = C_PATH, 0x10 end
            out[#out + 1] = shape(fill, alpha, wedge(cx, cy, R.r_in + 2, R.r_in + t - 2,
                                                     c - R.a / 2 + gap, c + R.a / 2 - gap))
            local text = wrap(esc(it.title), 11)
            if it.on then text = '● ' .. text end            -- option that is on
            if it.items then
                text = text .. ('{\\1c%s} ›'):format(hov and C_TEXT_HOVER or C_ACCENT)
            end
            local colour = hov and C_TEXT_HOVER or it.on and C_ACCENT or C_TEXT
            out[#out + 1] = label(cx + mid * cos(c), cy + mid * sin(c),
                                  floor(f * (k == 1 and TOP_FONT or 1)), colour, text,
                                  along(c) .. ((hov or it.on) and '\\b1' or ''))
        end
    end

    -- Hub: what the pointer is on, and what letting go would do.
    out[#out + 1] = shape(C_SLICE, 0x30, wedge(cx, cy, 0, W.c - 4, 0, 2 * pi))
    local it = hovered()
    local title = it and it.title or 'Menu'
    local hint = not it and 'close' or it.items and 'folder'
                 or ((it.on and '● on   ' or '') .. (it.key or ''))
    out[#out + 1] = label(cx, cy - f * 0.5, floor(f * 1.15), C_TEXT, wrap(esc(title), 14), '\\b1')
    out[#out + 1] = label(cx, cy + f * 1.2, floor(f * 0.85), C_DIM, esc(hint))

    W.overlay.res_x, W.overlay.res_y = w, h
    W.overlay.data = table.concat(out, '\n')
    W.overlay:update()
end

update = function()
    if not W then return end
    local x, y = mouse()
    local j, i = hit(x, y, rings())
    if j then
        for k = #W.sel, j + 1, -1 do W.sel[k] = nil end  -- drop deeper choices
        W.sel[j], W.hover = i, { j, i }
    else
        W.sel, W.hover = {}, nil
    end
    render(rings())
end

-- Runs the slice under the pointer if it is an entry. Returns false for a
-- folder or for nothing, so the caller decides whether to stay open.
local function activate()
    local it = hovered()
    if not it or it.items then return false end
    close()
    mp.command(it.cmd)
    return true
end

-- ── open / close ─────────────────────────────────────────────────────────────

local CAPTURE = {
    { 'MBTN_LEFT',     function() if not activate() and not hovered() then close() end end },
    { 'MBTN_LEFT_DBL', function() end },
    { 'ENTER',         function() activate() end },
    { 'ESC',           function() close() end },
    { 'BS',            function() close() end },
    { 'WHEEL_UP',      function() end },
    { 'WHEEL_DOWN',    function() end },
}

local function open()
    local tree = load_tree()
    if #tree.items == 0 then return end
    mark_on(tree)
    W = {
        tree     = tree,
        depth    = depth(tree),
        sel      = {},
        held     = true,
        opened   = mp.get_time(),
        overlay  = mp.create_osd_overlay('ass-events'),
        autohide = mp.get_property('cursor-autohide'),
    }
    W.overlay.z = 3000                               -- above uosc (z = 2000)
    mp.set_property('cursor-autohide', 'no')
    place(mouse())
    for _, b in ipairs(CAPTURE) do
        mp.add_forced_key_binding(b[1], 'radial-' .. b[1], b[2])
    end
    mp.observe_property('mouse-pos', 'native', update)
    update()
end

close = function()
    if not W then return end
    mp.unobserve_property(update)
    for _, b in ipairs(CAPTURE) do mp.remove_key_binding('radial-' .. b[1]) end
    W.overlay:remove()
    mp.set_property('cursor-autohide', W.autohide)
    W = nil
end

local function on_right(e)
    if e.event == 'down' or e.event == 'press' then
        if W then return close() end                 -- right-click closes it
        open()
        if W and e.event == 'press' then W.held = false end
    elseif e.event == 'up' and W and W.held then
        W.held = false
        local it = hovered()
        if it and not it.items then
            activate()
        elseif not it and mp.get_time() - W.opened >= TAP then
            close()
        end                  -- released on a folder, or a quick tap: stay open
    end
end

mp.add_key_binding(nil, 'open', on_right, { complex = true })

-- ── shortcuts screen ─────────────────────────────────────────────────────────
-- Every keyed entry from input.conf on one screen, grouped by the wheel's top
-- level folders. Bind:  ? script-binding radial_menu/shortcuts

local K = nil            -- the open shortcuts screen

local function pretty(key)
    return (key:gsub('MBTN_LEFT', 'Left click'):gsub('MBTN_RIGHT', 'Right click')
               :gsub('ALT', 'Alt'):gsub('CTRL', 'Ctrl'):gsub('SHIFT', 'Shift'))
end

local function keyed(node, prefix, out)
    for _, it in ipairs(node.items) do
        if it.items then
            keyed(it, prefix .. it.title .. ' › ', out)
        elseif it.key then
            out[#out + 1] = { key = pretty(it.key), title = prefix .. it.title }
        end
    end
    return out
end

-- Rows for the screen: a heading per group, then its keys, then a gap.
local function shortcut_rows(tree)
    local general = {}
    for _, g in ipairs(tree.general) do general[#general + 1] = { key = pretty(g.key), title = g.title } end
    local groups = { { 'General', general } }
    for _, it in ipairs(tree.items) do
        if it.items then
            groups[#groups + 1] = { it.title, keyed(it, '', {}) }
        elseif it.key then
            general[#general + 1] = { key = pretty(it.key), title = it.title }
        end
    end
    local rows = {}
    for _, g in ipairs(groups) do
        if #g[2] > 0 then
            rows[#rows + 1] = { head = g[1] }
            for _, r in ipairs(g[2]) do rows[#rows + 1] = r end
            rows[#rows + 1] = { gap = true }
        end
    end
    return rows
end

-- Flow rows into columns top to bottom. Headings never sit at the bottom of a
-- column on their own, and columns never start with a gap. Widths assume the
-- monospace OSD font (about 0.6 em per character).
local function flow(rows, fs, top, bottom)
    local per = math.max(4, floor((bottom - top) / (fs * 1.45)))
    local cols, col = {}, nil
    for _, r in ipairs(rows) do
        if not col or #col.rows >= per or (r.head and #col.rows >= per - 2) then
            col = { rows = {}, kw = 0, tw = 0 }
            cols[#cols + 1] = col
        end
        if not (r.gap and #col.rows == 0) then
            col.rows[#col.rows + 1] = r
            col.kw = math.max(col.kw, r.key and #r.key or 0)
            col.tw = math.max(col.tw, #(r.title or r.head or ''))
        end
    end
    local total = 0
    for _, c in ipairs(cols) do
        c.w = (c.kw + 2 + c.tw) * 0.6 * fs
        total = total + c.w + 2 * fs
    end
    return cols, total - 2 * fs
end

local function close_keys()
    if not K then return end
    for _, k in ipairs(K.keys) do mp.remove_key_binding('shortcuts-' .. k) end
    K.overlay:remove()
    K = nil
end

local function show_keys()
    if K then return close_keys() end
    local w, h = mp.get_osd_size()
    local rows = shortcut_rows(load_tree())
    local fs = math.max(11, math.min(24, h / 36))
    local top, bottom = fs * 4.5, h - fs * 3
    local cols, total = flow(rows, fs, top, bottom)
    while total > w * 0.94 and fs > 11 do              -- shrink until it fits
        fs = fs * 0.9
        top, bottom = fs * 4.5, h - fs * 3
        cols, total = flow(rows, fs, top, bottom)
    end

    local out = {
        shape('&H000000&', 0x14, ('m 0 0 l %d 0 %d %d 0 %d'):format(w, w, h, h)),
        label(w / 2, fs * 2.2, floor(fs * 1.5), C_TEXT, 'Keyboard shortcuts', '\\b1'),
        label(w / 2, h - fs * 1.5, floor(fs * 0.9), C_DIM, 'Esc, ? or any click to close'),
    }
    local x = math.max(fs, (w - total) / 2)
    for _, c in ipairs(cols) do
        local y = top
        for _, r in ipairs(c.rows) do
            if r.head then
                out[#out + 1] = ('{\\an7\\pos(%d,%d)\\fs%d\\b1\\bord0\\shad0\\1c%s}%s')
                    :format(x, y, floor(fs), C_ACCENT, esc(r.head))
            elseif r.key then
                out[#out + 1] = ('{\\an7\\pos(%d,%d)\\fs%d\\b1\\bord0\\shad0\\1c%s}%s')
                    :format(x, y, floor(fs), C_TEXT, esc(r.key))
                out[#out + 1] = ('{\\an7\\pos(%d,%d)\\fs%d\\bord0\\shad0\\1c%s}%s')
                    :format(x + (c.kw + 2) * 0.6 * fs, y, floor(fs), C_DIM, esc(r.title))
            end
            y = y + fs * 1.45
        end
        x = x + c.w + 2 * fs
    end

    K = { overlay = mp.create_osd_overlay('ass-events'),
          keys = { 'ESC', '?', 'MBTN_LEFT', 'MBTN_RIGHT', 'ENTER' } }
    K.overlay.z = 3000
    K.overlay.res_x, K.overlay.res_y = w, h
    K.overlay.data = table.concat(out, '\n')
    K.overlay:update()
    for _, k in ipairs(K.keys) do mp.add_forced_key_binding(k, 'shortcuts-' .. k, close_keys) end
end

mp.add_key_binding(nil, 'shortcuts', show_keys)
