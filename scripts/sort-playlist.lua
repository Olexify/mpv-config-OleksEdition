-- sort-playlist.lua
--
-- Keeps the mpv playlist in the same order Windows Explorer shows the folder.
--
-- Default mode "explorer": asks the open Explorer window for that folder which
-- column it is sorted by (Name, Date modified, Date created, Size, Type) and in
-- which direction, and sorts the playlist the same way. If no Explorer window
-- has the folder open (drag-and-drop from elsewhere, reopening from history),
-- the `fallback` order is used.
--
-- Name sorting reproduces StrCmpLogicalW, the comparison Explorer uses:
--   * runs of digits compare as numbers, so "Ep 2" comes before "Ep 10"
--   * comparison is case-insensitive
--   * punctuation sorts before digits, which sort before letters
--     (space ! " # $ % & ( ) * , . / : ; ? @ [ \ ] ^ _ ` { | } ~ + < = >)
--   * "-" and "'" are ignored on the first pass, so "-dash" files land under
--     "d", and are only consulted to break an otherwise exact tie
--   * on equal numeric value, more leading zeros sorts first: 007 before 7
-- The tables below were derived by calling the real StrCmpLogicalW through
-- shlwapi.dll and reading back the resulting order.
--
-- Configure in script-opts/sort-playlist.conf:
--   auto=explorer      explorer, name_asc, name_desc, date_new, date_old, off
--   fallback=name_asc  used by "explorer" when no Explorer window is found
-- Picking a mode from a menu writes it back to that file, so it is remembered.
--
-- "Include subfolders" switches autoload between leaving subfolders out and
-- adding the videos inside them; it is remembered in script-opts/autoload.conf.
--
-- Bindings (mpv turns "-" into "_" in script names, hence sort_playlist):
--   script-binding sort_playlist/menu        open the sort menu (uosc)
--   script-binding sort_playlist/cycle       cycle through the modes
--   script-binding sort_playlist/explorer
--   script-binding sort_playlist/name-asc
--   script-binding sort_playlist/name-desc
--   script-binding sort_playlist/date-new
--   script-binding sort_playlist/date-old
--   script-binding sort_playlist/subfolders  toggle including subfolders

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'
local options = require 'mp.options'

local o = { auto = 'explorer', fallback = 'name_asc' }
options.read_options(o, 'sort-playlist')

-- Keep labels short: uosc lays the hint out on the same row, and a long label
-- plus a long hint collide instead of wrapping.
local MODES = {
    explorer  = { label = 'Match Explorer' },
    name_asc  = { label = 'Name',           hint = 'A → Z', key = 'name', rev = false },
    name_desc = { label = 'Name reversed',  hint = 'Z → A', key = 'name', rev = true  },
    date_new  = { label = 'Newest first',   hint = 'date',  key = 'date', rev = true  },
    date_old  = { label = 'Oldest first',   hint = 'date',  key = 'date', rev = false },
}
local CYCLE  = { 'explorer', 'name_asc', 'name_desc', 'date_new', 'date_old' }
local SCRIPT = mp.get_script_name()

-- Explorer column (property name in SortColumns) → our sort key.
local EXPLORER_KEYS = {
    ['System.ItemNameDisplay']                  = 'name',
    ['System.ItemNameDisplayWithoutExtension']  = 'name',
    ['System.FileName']                         = 'name',
    ['System.DateModified']                     = 'date',
    ['System.DateCreated']                      = 'created',
    ['System.Size']                             = 'size',
    ['System.ItemTypeText']                     = 'ext',
}
local KEY_LABEL = { name = 'name', date = 'date', created = 'created', size = 'size', ext = 'type' }

local platform = mp.get_property('platform')
local current  = MODES[o.auto] and o.auto or 'explorer'
local last_sig = nil

-- ── paths ────────────────────────────────────────────────────────────────────

local function full_path(p)
    if not p or p == '' then return '' end
    if p:find('://', 1, true) then return p end            -- URL, leave as-is
    if platform == 'windows' then
        if p:match('^%a:[/\\]') or p:match('^\\\\') then return p end
    elseif p:match('^/') then
        return p
    end
    return utils.join_path(mp.get_property('working-directory', ''), p)
end

-- Folder of a local file, spelled the way Explorer reports Folder.Self.Path.
local function dir_of(p)
    if not p or p == '' or p:find('://', 1, true) then return nil end
    local d = full_path(p):match('^(.*)[/\\][^/\\]*$')
    if not d then return nil end
    d = d:gsub('/', '\\')
    if d:match('^%a:$') then d = d .. '\\' end              -- drive root
    return d
end

-- ── Explorer (StrCmpLogicalW) name ordering ──────────────────────────────────

-- Punctuation in Explorer's collation order. Everything here sorts before any
-- digit, and digits sort before any letter.
local PUNCT_ORDER = [[ !"#$%&()*,./:;?@[\]^_`{|}~+<=>]]

local PUNCT_WEIGHT = {}
for i = 1, #PUNCT_ORDER do
    PUNCT_WEIGHT[PUNCT_ORDER:sub(i, i)] = 100 + i          -- 101 .. 131
end

local W_NUM     = 1000                                     -- any run of digits
local W_LETTER  = 2000                                     -- + lowercased byte
local W_OTHER   = 3000                                     -- + byte, e.g. UTF-8
local W_APOS    = 9000                                     -- ignorable, tie only
local W_HYPHEN  = 9001

local function char_weight(c)
    local w = PUNCT_WEIGHT[c]
    if w then return w end
    local b = c:byte()
    if b >= 97 and b <= 122 then return W_LETTER + b end        -- a-z
    if b >= 65 and b <= 90  then return W_LETTER + b + 32 end   -- A-Z, folded
    return W_OTHER + b
end

local function enc(w)
    return string.char(math.floor(w / 256), w % 256)
end

-- Encode a name into a byte string whose plain "<" comparison reproduces
-- Explorer's ordering. Every element starts with a 2-byte weight, so element
-- boundaries stay aligned between any two keys.
--
-- A digit run encodes as: weight, 3-digit length, the digits, then an inverted
-- leading-zero count so that more zeros sorts first.
local function build_key(s, keep_ignorable)
    local out, i, n = {}, 1, #s
    while i <= n do
        if s:find('^%d', i) then
            local j = i
            while j <= n and s:find('^%d', j) do j = j + 1 end
            local digits  = s:sub(i, j - 1)
            local trimmed = digits:gsub('^0+', '')
            if trimmed == '' then trimmed = '0' end
            local zeros = #digits - #trimmed
            if zeros > 254 then zeros = 254 end
            out[#out + 1] = enc(W_NUM) .. ('%03d'):format(#trimmed) ..
                            trimmed .. string.char(255 - zeros)
            i = j
        else
            local c = s:sub(i, i)
            if c == "'" or c == '-' then
                if keep_ignorable then
                    out[#out + 1] = enc(c == "'" and W_APOS or W_HYPHEN)
                end
            else
                out[#out + 1] = enc(char_weight(c))
            end
            i = i + 1
        end
    end
    return table.concat(out)
end

local key_cache = {}
local function keys_of(s)
    local k = key_cache[s]
    if not k then
        k = { build_key(s, false), build_key(s, true) }
        key_cache[s] = k
    end
    return k
end

-- Returns true when a sorts before b in Explorer's order.
local function name_less(a, b)
    if a == b then return false end
    local ka, kb = keys_of(a), keys_of(b)
    if ka[1] ~= kb[1] then return ka[1] < kb[1] end         -- ignoring - and '
    if ka[2] ~= kb[2] then return ka[2] < kb[2] end         -- now counting them
    return a < b                                            -- case-only tie
end

local function plain_less(a, b) return a < b end

-- Cheap fingerprint: catches a new folder, and autoload appending entries.
local function signature(pl)
    if not pl or #pl == 0 then return '' end
    return #pl .. '|' .. (pl[1].filename or '') .. '|' .. (pl[#pl].filename or '')
end

-- ── core ─────────────────────────────────────────────────────────────────────

local function sort(key, rev)
    local pl = mp.get_property_native('playlist')
    if not pl or #pl < 2 then return end

    local items = {}
    for i, entry in ipairs(pl) do
        local fp   = full_path(entry.filename)
        local name = (fp:gsub('\\', '/'))
        local v    = name
        if key == 'ext' then
            v = (name:match('%.([^./]+)$') or ''):lower()
        elseif key ~= 'name' then
            local info = utils.file_info(fp)
            v = info and (key == 'date' and info.mtime or
                          key == 'created' and info.ctime or info.size) or 0
        end
        items[i] = { idx = i - 1, name = name, v = v }
    end

    local less = key == 'name' and name_less or plain_less
    table.sort(items, function(a, b)
        if a.v ~= b.v then
            if rev then return less(b.v, a.v) end
            return less(a.v, b.v)
        end
        -- Timestamps only have 1s resolution, so ties are common. Break them on
        -- name so the result does not depend on the order files arrived in.
        if a.name ~= b.name then return name_less(a.name, b.name) end
        return a.idx < b.idx
    end)

    -- Reorder in place. Positions are filled left to right, so the entry we
    -- want next always sits at or after `target` and one forward move does it.
    -- mpv keeps playlist-pos pointing at the same entry across moves, so
    -- playback is never interrupted.
    local pos, moves = {}, 0
    for i = 0, #pl - 1 do pos[i] = i end
    for target = 0, #items - 1 do
        local idx  = items[target + 1].idx
        local from = pos[idx]
        if from ~= target then
            mp.commandv('playlist-move', from, target)
            for k, p in pairs(pos) do
                if p >= target and p < from then pos[k] = p + 1 end
            end
            pos[idx] = target
            moves = moves + 1
        end
    end
    msg.verbose(('%s %s: %d entries, %d moves'):format(key, rev and 'desc' or 'asc', #pl, moves))
end

-- ── Explorer detection ───────────────────────────────────────────────────────

-- dir → { key, rev } when an Explorer window was found, false when none was.
local explorer_order, detecting = {}, {}
local schedule_sort   -- forward declaration

local function detect_explorer(dir)
    detecting[dir] = true
    local ps = ("$t='%s';foreach($w in (New-Object -ComObject Shell.Application).Windows())" ..
                "{try{if([string]::Equals($w.Document.Folder.Self.Path,$t,'OrdinalIgnoreCase'))" ..
                "{$w.Document.SortColumns;break}}catch{}}"):format((dir:gsub("'", "''")))
    mp.command_native_async({
        name = 'subprocess', playback_only = false, capture_stdout = true,
        args = { 'powershell', '-NoProfile', '-NonInteractive', '-Command', ps },
    }, function(ok, res)
        detecting[dir] = nil
        -- SortColumns looks like "prop:-System.DateModified;" ('-' = descending)
        local rev, prop = ((ok and res and res.stdout) or ''):match('prop:(%-?)([%w%.]+)')
        explorer_order[dir] = prop and { key = EXPLORER_KEYS[prop] or 'name', rev = rev == '-' } or false
        msg.verbose(('Explorer for %s: %s'):format(dir, prop and (rev .. prop) or 'no window'))
        last_sig = nil                                      -- re-sort with the answer
        schedule_sort()
    end)
end

-- Returns the key and direction a mode stands for right now, or nil while the
-- Explorer answer for this folder is still on its way.
local function resolve(mode_name)
    if mode_name ~= 'explorer' then
        local m = MODES[mode_name]
        return m.key, m.rev
    end
    local dir = dir_of(mp.get_property('path', ''))
    local e = dir and explorer_order[dir]
    if e then return e.key, e.rev end
    if dir and e == nil then
        if not detecting[dir] then detect_explorer(dir) end
        return nil
    end
    local f = MODES[o.fallback] or MODES.name_asc
    return f.key, f.rev
end

local function describe(key, rev)
    return KEY_LABEL[key] .. (rev and ' ↓' or ' ↑')
end

-- Whether autoload puts the videos inside subfolders into the playlist. Lives
-- in autoload.conf because that is the script that reads it.
local subfolders
do
    local a = { directory_mode = 'ignore' }
    options.read_options(a, 'autoload')
    subfolders = a.directory_mode == 'recursive'
end

-- Published for other scripts: the wheel marks the current choices with a
-- dot, and playlist_repeat.lua holds an Up/Down press while `pending` is set,
-- so you never step through a playlist that is about to be reordered.
local pending = false
local function publish()
    mp.set_property_native('user-data/sort_playlist',
        { mode = current, subfolders = subfolders, pending = pending })
end
local function set_pending(v)
    if pending ~= v then pending = v; publish() end
end

-- autoload appends entries in bursts after the first file is already playing,
-- so sort a moment after the last playlist change rather than once on load.
-- Our own playlist-move calls do not change playlist-count, so this cannot feed
-- back on itself.
local resort_timer = nil
schedule_sort = function()
    if o.auto == 'off' then return end
    if signature(mp.get_property_native('playlist')) == last_sig then return end
    set_pending(true)
    if resort_timer then resort_timer:kill() end
    resort_timer = mp.add_timeout(0.1, function()
        resort_timer = nil
        local key, rev = resolve(current)
        if not key then return end          -- Explorer answer on its way; it reschedules
        sort(key, rev)
        last_sig = signature(mp.get_property_native('playlist'))
        set_pending(false)
    end)
end

-- ── remembered settings ──────────────────────────────────────────────────────

-- Rewrite `key=value` in a script-opts file, keeping every other line.
local function persist(file, key, value)
    local path = mp.command_native({ 'expand-path', '~~/script-opts/' .. file })
    local lines, found = {}, false
    local f = io.open(path, 'r')
    if f then
        for line in f:lines() do
            if line:match('^%s*' .. key .. '%s*=') then
                line, found = key .. '=' .. value, true
            end
            lines[#lines + 1] = line
        end
        f:close()
    end
    if not found then lines[#lines + 1] = key .. '=' .. value end
    local w = io.open(path, 'w')
    if not w then return msg.warn('could not write ' .. path) end
    w:write(table.concat(lines, '\n'), '\n')
    w:close()
end


local function set_subfolders(on)
    subfolders = on
    local mode = on and 'recursive' or 'ignore'
    persist('autoload.conf', 'directory_mode', mode)
    publish()
    -- Keep the playing file, drop the rest, and let autoload scan again.
    mp.commandv('playlist-clear')
    mp.commandv('script-message-to', 'autoload', 'rescan', mode)
    mp.osd_message('Subfolders: ' .. (on and 'included' or 'left out'), 2)
end

local function apply(mode_name)
    if not MODES[mode_name] then return end
    current, o.auto, last_sig = mode_name, mode_name, nil
    persist('sort-playlist.conf', 'auto', mode_name)
    publish()
    local key, rev = resolve(mode_name)
    local label = MODES[mode_name].label
    if key then
        sort(key, rev)
        last_sig = signature(mp.get_property_native('playlist'))
        mp.osd_message(('Sort: %s (%s)'):format(label, describe(key, rev)), 2)
    else
        set_pending(true)
        mp.osd_message('Sort: ' .. label .. ' (asking Explorer...)', 2)
    end
end

-- ── uosc menu ────────────────────────────────────────────────────────────────

local function explorer_hint()
    local dir = dir_of(mp.get_property('path', ''))
    local e = dir and explorer_order[dir]
    if e then return describe(e.key, e.rev) end
    if e == false or not dir then return 'no window' end
    return '...'
end

local function open_menu()
    local items = {}
    for _, name in ipairs(CYCLE) do
        local m = MODES[name]
        items[#items + 1] = {
            title  = m.label,
            hint   = name == 'explorer' and explorer_hint() or m.hint,
            active = (name == current),
            value  = { 'script-message-to', SCRIPT, 'set-mode', name },
        }
    end
    items[#items + 1] = {
        title     = 'Include subfolders',
        hint      = subfolders and 'on' or 'off',
        active    = subfolders,
        value     = { 'script-binding', SCRIPT .. '/subfolders' },
    }
    items[#items - 1].separator = true                      -- line above the toggle
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json({
        type  = 'sort_playlist',
        title = 'Sort playlist',
        items = items,
    }))
end

mp.register_script_message('set-mode', apply)

-- ── events and bindings ──────────────────────────────────────────────────────

mp.observe_property('playlist-count', 'number', function() schedule_sort() end)
mp.register_event('file-loaded', function() schedule_sort() end)

mp.add_key_binding(nil, 'menu', open_menu)
mp.add_key_binding(nil, 'subfolders', function() set_subfolders(not subfolders) end)
publish()

mp.add_key_binding(nil, 'cycle', function()
    local i = 1
    for n, name in ipairs(CYCLE) do
        if name == current then i = n end
    end
    apply(CYCLE[(i % #CYCLE) + 1])
end)

for _, name in ipairs(CYCLE) do
    mp.add_key_binding(nil, (name:gsub('_', '-')), function() apply(name) end)
end
