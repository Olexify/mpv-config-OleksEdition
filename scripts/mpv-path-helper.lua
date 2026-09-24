-- mpv-path-helper.lua  ── place in your mpv/scripts/ folder ─────────────────
--
-- Fixes: "thumbfast: ERROR! cannot create mpv subprocess"
-- Cause: portable/bundled mpv is not in system PATH, so thumbfast cannot find
--        mpv.exe when it tries to spawn a subprocess for thumbnail generation.
-- Fix:   detects mpv.exe location and sets user-data/frontend/process-path
--        before thumbfast reads it at init.
--
-- MUST be alphabetically before thumbfast.lua (m < t), which it is.
-- Drop into scripts/ folder. No config needed.

if mp.get_property_native('platform') ~= 'windows' then return end
-- Already set by a frontend (e.g. mpv.net) → nothing to do
if mp.get_property_native('user-data/frontend/process-path') then return end

local utils = require('mp.utils')

local function file_exists(path)
    if not path or path == '' then return false end
    local info = utils.file_info(path)
    return info ~= nil and not info.is_dir
end

local function try_set(path)
    if file_exists(path) then
        mp.set_property('user-data/frontend/process-path', path)
        return true
    end
    return false
end

-- ── Method 1: portable_config layout ─────────────────────────────────────────
-- portable mpv structure:
--   my-mpv/
--     mpv.exe          ← here
--     portable_config/ ← config-dir points here
--       scripts/
local config_dir = mp.get_property_native('config-dir') or ''
local parent_dir = type(config_dir) == 'string'
    and config_dir:match('^(.+)[/\\][^/\\]+$') or ''

if try_set(parent_dir .. '\\mpv.exe') then return end

-- ── Method 2: mpv.exe in working directory ────────────────────────────────────
local cwd = mp.get_property('working-directory') or ''
if try_set(cwd .. '\\mpv.exe') then return end

-- ── Method 3: ask PowerShell for the parent process (mpv) path ───────────────
-- The subprocess (powershell) is spawned BY mpv, so mpv PID = PS parent PID.
local res = mp.command_native({
    name = 'subprocess',
    playback_only = false,
    capture_stdout = true,
    args = {
        'powershell', '-NoProfile', '-NonInteractive', '-Command',
        'try{$ppid=(Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId;' ..
        '(Get-Process -Id $ppid).MainModule.FileName}catch{exit 1}'
    }
})
if res and res.status == 0 and res.stdout then
    local path = res.stdout:match('^(.-)%s*$')
    try_set(path)
end