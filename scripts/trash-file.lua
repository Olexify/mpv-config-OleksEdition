-- trash-file.lua
--
-- DEL          → move the playing file to the Recycle Bin, confirm with Enter
-- Shift+DEL    → delete the playing file permanently, confirm with Enter
-- Esc          → cancel a pending confirmation
-- Ctrl+Z       → undo the last trash operation (up to 5 levels)
--
-- Enter and Esc are only captured while a confirmation is on screen; the rest
-- of the time they keep whatever bindings they normally have.
--
-- Note: mpv turns "-" into "_" in script names, so the binding prefix is
-- trash_file even though the file is trash-file.lua.
--
-- Bindings:
--   script-binding trash_file/trash
--   script-binding trash_file/delete
--   script-binding trash_file/undo

local mp    = require('mp')
local msg   = require('mp.msg')
local utils = require('mp.utils')

local CONFIRM_SECS = 8

-- ── platform ─────────────────────────────────────────────────────────────────
local platform = (function()
    local p = mp.get_property_native('platform')
    if p then return p end
    if os.getenv('windir') ~= nil then return 'windows' end
    local home = os.getenv('HOME')
    if home and home:sub(1, 6) == '/Users' then return 'darwin' end
    return 'linux'
end)()

-- ── helpers ──────────────────────────────────────────────────────────────────
local function get_local_path()
    local path = mp.get_property('path')
    if not path then return nil end
    if path:match('^%a[%a%d+%-%.]*://') then return nil end
    local cwd = mp.get_property('working-directory', '')
    if platform == 'windows' then
        if not path:match('^%a:[/\\]') and not path:match('^\\\\') then
            path = utils.join_path(cwd, path)
        end
    else
        if not path:match('^/') then
            path = utils.join_path(cwd, path)
        end
    end
    return path
end

local function basename(p)
    return p:match('[^/\\]+$') or p
end

local function navigate_away()
    local count = mp.get_property_native('playlist-count', 0)
    if count > 1 then
        local pos = mp.get_property_native('playlist-pos', 0)
        if pos < count - 1 then
            mp.command('playlist-next force')
        else
            mp.command('playlist-prev force')
        end
    else
        mp.command('stop')
    end
end

local function ass_safe(s)
    return tostring(s):gsub('\\', '\\\\'):gsub('{', '\\{'):gsub('}', '\\}')
end

-- Escape for a PowerShell single-quoted string (only ' → '')
local function ps_sq(s)
    return s:gsub("'", "''")
end

local function simple_osd(text, secs)
    mp.osd_message(text, secs or 3)
end

-- ── overlay ──────────────────────────────────────────────────────────────────
-- Virtual 1280x720 canvas. Colours are ASS &HBBGGRR&.

local RES_X, RES_Y = 1280, 720
local CARD_X1, CARD_X2 = 240, 1040
local CARD_Y1, CARD_Y2 = 244, 476
local PAD = 44

local C_CARD   = '&H1B1716&'
local C_TEXT   = '&HF5F2F0&'
local C_DIM    = '&HA8A09A&'
local C_TRASH  = '&H20B0FF&'   -- amber
local C_DELETE = '&H4444FF&'   -- red

local function rect(x1, y1, x2, y2)
    return ('m %d %d l %d %d l %d %d l %d %d')
        :format(x1, y1, x2, y1, x2, y2, x1, y2)
end

local function shape(colour, alpha, x1, y1, x2, y2)
    return ('{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\1a&H%02X&\\p1}%s{\\p0}')
        :format(colour, alpha, rect(x1, y1, x2, y2))
end

-- Keep the start and the end of the name, drop the middle.
local function fit(name, limit)
    if #name <= limit then return name end
    local head = math.floor((limit - 3) * 0.45)
    local tail = limit - 3 - head
    return name:sub(1, head) .. '...' .. name:sub(-tail)
end

local overlay = nil

local function draw(action_type, name, remaining)
    if not overlay then
        overlay = mp.create_osd_overlay('ass-events')
        overlay.res_x, overlay.res_y = RES_X, RES_Y
        overlay.z = 3000                             -- above uosc (z = 2000)
    end

    local accent, title
    if action_type == 'trash' then
        accent, title = C_TRASH, 'Move to Recycle Bin'
    else
        accent, title = C_DELETE, 'Delete permanently'
    end

    local inner_x = CARD_X1 + PAD
    local inner_w = (CARD_X2 - PAD) - inner_x
    local frac    = remaining / CONFIRM_SECS
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    local lines = {
        -- dimmed backdrop
        shape('&H000000&', 0x78, 0, 0, RES_X, RES_Y),
        -- card
        shape(C_CARD, 0x10, CARD_X1, CARD_Y1, CARD_X2, CARD_Y2),
        -- accent bar down the left edge
        shape(accent, 0x00, CARD_X1, CARD_Y1, CARD_X1 + 6, CARD_Y2),
        -- title
        ('{\\an1\\pos(%d,%d)\\fs40\\b1\\bord0\\shad0\\1c%s}%s')
            :format(inner_x, CARD_Y1 + 84, accent, ass_safe(title)),
        -- file name
        ('{\\an1\\pos(%d,%d)\\fs26\\bord0\\shad0\\1c%s}%s')
            :format(inner_x, CARD_Y1 + 128, C_TEXT, ass_safe(fit(name, 58))),
        -- separator
        shape(C_DIM, 0xC0, inner_x, CARD_Y1 + 150, CARD_X2 - PAD, CARD_Y1 + 151),
        -- key hints
        ('{\\an1\\pos(%d,%d)\\fs24\\bord0\\shad0\\1c%s}{\\b1\\1c%s}Enter{\\b0\\1c%s}  confirm       {\\b1\\1c%s}Esc{\\b0\\1c%s}  cancel')
            :format(inner_x, CARD_Y1 + 196, C_DIM, C_TEXT, C_DIM, C_TEXT, C_DIM),
        -- countdown track and fill
        shape(C_DIM, 0xD0, CARD_X1, CARD_Y2 - 4, CARD_X2, CARD_Y2),
        shape(accent, 0x00, CARD_X1, CARD_Y2 - 4,
              CARD_X1 + math.floor((CARD_X2 - CARD_X1) * frac), CARD_Y2),
    }

    -- right-aligned seconds remaining
    lines[#lines + 1] = ('{\\an3\\pos(%d,%d)\\fs24\\bord0\\shad0\\1c%s}%ds')
        :format(CARD_X2 - PAD, CARD_Y1 + 196, C_DIM, math.ceil(remaining))

    overlay.data = table.concat(lines, '\n')
    overlay:update()
end

local function hide()
    if overlay then overlay:remove(); overlay = nil end
end

-- ── undo stack ───────────────────────────────────────────────────────────────
local undo_stack = {}

local function push_undo(path)
    table.insert(undo_stack, path)
    if #undo_stack > 5 then table.remove(undo_stack, 1) end
end

-- ── restore from trash ───────────────────────────────────────────────────────
local function restore_from_trash(path)
    if platform == 'windows' then
        local ps = string.format([[
$target = '%s'
$target = $target.Replace('/', '\')
$shell  = New-Object -ComObject Shell.Application
$bin    = $shell.Namespace(10)
$found  = $false
foreach ($item in $bin.Items()) {
    $dir  = ($bin.GetDetailsOf($item, 1)).Trim().TrimEnd('\')
    $full = [System.IO.Path]::Combine($dir, $item.Name)
    if ([string]::Equals($full, $target, [System.StringComparison]::OrdinalIgnoreCase)) {
        $binPath  = $item.Path
        $binDir   = [System.IO.Path]::GetDirectoryName($binPath)
        $binName  = [System.IO.Path]::GetFileName($binPath)
        $infoPath = [System.IO.Path]::Combine($binDir, '$I' + $binName.Substring(2))

        $destDir = [System.IO.Path]::GetDirectoryName($target)
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Move-Item -LiteralPath $binPath -Destination $target -Force
        if (Test-Path -LiteralPath $infoPath) {
            Remove-Item -LiteralPath $infoPath -Force
        }
        $found = $true
        break
    }
}
if (-not $found) { exit 1 }
]], ps_sq(path))
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'powershell', '-NoProfile', '-NonInteractive', '-Command', ps},
        })
        return res.status == 0

    elseif platform == 'darwin' then
        local escaped = path:gsub('"', '\\"')
        local script = string.format([[
tell application "Finder"
    repeat with ti in (every item of trash)
        try
            if POSIX path of (ti as alias) contains "%s" then
                put back ti
                exit repeat
            end if
        end try
    end repeat
end tell]], escaped)
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'osascript', '-e', script},
        })
        return res.status == 0

    else
        local uri = 'trash:///' .. basename(path)
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'gio', 'trash', '--restore', uri},
        })
        return res.status == 0
    end
end

-- ── operations ───────────────────────────────────────────────────────────────

local function trash_now(path)
    local name = basename(path)
    local ok

    if platform == 'windows' then
        local ps = string.format(
            "Add-Type -AssemblyName Microsoft.VisualBasic; " ..
            "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(" ..
            "'%s', 'OnlyErrorDialogs', 'SendToRecycleBin')",
            ps_sq(path))
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'powershell', '-NoProfile', '-NonInteractive', '-Command', ps},
        })
        ok = res.status == 0

    elseif platform == 'darwin' then
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'osascript', '-e', string.format(
                'tell application "Finder" to move POSIX file %q to trash', path)},
        })
        ok = res.status == 0

    else
        local res = mp.command_native({
            name = 'subprocess', playback_only = false,
            args = {'gio', 'trash', '--', path},
        })
        if res.status ~= 0 then
            res = mp.command_native({
                name = 'subprocess', playback_only = false,
                args = {'trash-put', '--', path},
            })
        end
        ok = res.status == 0
    end

    if ok then
        push_undo(path)
        simple_osd('Moved to Recycle Bin: ' .. name .. '\nCtrl+Z to undo', 4)
    else
        simple_osd('Could not move to Recycle Bin: ' .. name, 4)
    end
end

-- mpv may still hold the file open for a moment after we navigate away, so
-- give the delete a few tries before reporting failure.
local function delete_now(path, attempt)
    attempt = attempt or 1
    local ok, err = os.remove(path)
    if ok then
        simple_osd('Deleted permanently: ' .. basename(path), 4)
        return
    end
    if attempt < 5 then
        mp.add_timeout(0.2, function() delete_now(path, attempt + 1) end)
        return
    end
    simple_osd('Could not delete: ' .. basename(path) ..
               '\n(' .. tostring(err or '?') .. ')', 5)
end

local function do_undo()
    if #undo_stack == 0 then
        simple_osd('Nothing to undo', 2)
        return
    end
    local path = table.remove(undo_stack)
    local name = basename(path)
    if restore_from_trash(path) then
        simple_osd('Restored: ' .. name ..
            (#undo_stack > 0 and ('\n' .. #undo_stack .. ' more undo(s) available') or ''), 4)
    else
        table.insert(undo_stack, path)
        simple_osd('Could not restore: ' .. name ..
            '\n(was the Recycle Bin emptied?)', 4)
    end
end

-- ── pending confirmation ─────────────────────────────────────────────────────

local pending = { action = nil, path = nil, name = nil, deadline = nil }
local ticker, keys_bound = nil, false
-- The dialog pauses playback so the file cannot end and roll over to the next
-- one underneath it. True when it was playing before, so we resume after.
local resume_after = false

local confirm, cancel   -- forward declarations

local function unbind_keys()
    if not keys_bound then return end
    mp.remove_key_binding('trash-confirm-enter')
    mp.remove_key_binding('trash-confirm-kpenter')
    mp.remove_key_binding('trash-cancel-esc')
    keys_bound = false
end

local function bind_keys()
    if keys_bound then return end
    mp.add_forced_key_binding('ENTER',    'trash-confirm-enter',   function() confirm() end)
    mp.add_forced_key_binding('KP_ENTER', 'trash-confirm-kpenter', function() confirm() end)
    mp.add_forced_key_binding('ESC',      'trash-cancel-esc',      function() cancel(true) end)
    keys_bound = true
end

cancel = function(announce)
    if ticker then ticker:kill(); ticker = nil end
    unbind_keys()
    hide()
    local was = pending.action
    pending.action, pending.path, pending.name, pending.deadline = nil, nil, nil, nil
    if resume_after then mp.set_property_native('pause', false) end
    resume_after = false
    if announce and was then simple_osd('Cancelled', 2) end
end

confirm = function()
    local action, path, resume = pending.action, pending.path, resume_after
    if not action then return end
    resume_after = false             -- resume on the next file, not this one
    cancel(false)
    navigate_away()
    if resume then mp.set_property_native('pause', false) end
    -- Let mpv release the file before touching it.
    mp.add_timeout(0.15, function()
        if action == 'trash' then trash_now(path) else delete_now(path) end
    end)
end

local function arm(action_type)
    local path = get_local_path()
    if not path then simple_osd('Not a local file', 2); return end

    if ticker then ticker:kill(); ticker = nil end
    if not pending.action then                       -- not when switching DEL <-> Shift+DEL
        resume_after = not mp.get_property_native('pause')
        mp.set_property_native('pause', true)
    end
    pending.action   = action_type
    pending.path     = path
    pending.name     = basename(path)
    pending.deadline = mp.get_time() + CONFIRM_SECS
    bind_keys()

    draw(action_type, pending.name, CONFIRM_SECS)
    ticker = mp.add_periodic_timer(0.1, function()
        local remaining = pending.deadline - mp.get_time()
        if remaining <= 0 then
            cancel(true)
        else
            draw(pending.action, pending.name, remaining)
        end
    end)
end

-- A file change invalidates whatever was pending.
mp.register_event('file-loaded', function() cancel(false) end)
mp.register_event('shutdown',    function() cancel(false) end)

-- ── bindings ─────────────────────────────────────────────────────────────────
mp.add_forced_key_binding('DEL',       'trash',  function() arm('trash')  end)
mp.add_forced_key_binding('Shift+DEL', 'delete', function() arm('delete') end)
mp.add_forced_key_binding('ctrl+z',    'undo',   do_undo)
