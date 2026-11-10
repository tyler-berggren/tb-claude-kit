-- dictate-around — dictate into one text field while you click and navigate anywhere else.
--
-- A Hammerspoon module, installed by scripts/install-dictate-around.
--
--   hotkey          remember the focused text field, start recording from the configured mic
--   (move around)   click, scroll, switch apps; nothing is typed while you talk
--   hotkey again    stop, transcribe on this Mac with whisper.cpp, paste into the field
--                   where you started, restore the clipboard
--
-- Settings: ~/.config/claude-kit/dictate-around.json (every key optional)
--   hotkey           "double-fn" (default), "double-rightcmd", "double-ctrl", ... or a combination
--                    such as "ctrl+alt+d" or "f13"; see bindHotkey below
--   mic              input device name, as in System Settings > Sound; default: the system input
--   model            whisper.cpp model file; default: ~/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin
--   language         spoken language code; default "en"
--   returnToCurrent  after pasting, go back to where you were when you stopped; default false
--   tapMax           longest Fn press, in seconds, that counts as a tap; default 0.30
--   doubleTapWindow  longest gap, in seconds, between the two taps; default 0.40
--   ffmpeg, whisper  binary paths; default /opt/homebrew/bin/ffmpeg and /opt/homebrew/bin/whisper-cli

require("hs.ipc") -- lets `hs -c` (and install-dictate-around --status) talk to Hammerspoon

local M = {}

local HOME = os.getenv("HOME")
M.configPath = HOME .. "/.config/claude-kit/dictate-around.json"

local defaults = {
  hotkey          = "double-fn",
  mic             = nil,
  model           = HOME .. "/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin",
  language        = "en",
  returnToCurrent = false,
  tapMax          = 0.30,
  doubleTapWindow = 0.40,
  ffmpeg          = "/opt/homebrew/bin/ffmpeg",
  whisper         = "/opt/homebrew/bin/whisper-cli",
}

local function loadConfig()
  local cfg = {}
  for k, v in pairs(defaults) do cfg[k] = v end
  if hs.fs.attributes(M.configPath) then
    local user = hs.json.read(M.configPath)
    if type(user) == "table" then
      for k, v in pairs(user) do cfg[k] = v end
    else
      hs.alert.show("dictate-around: couldn't read " .. M.configPath .. ", using defaults", 4)
    end
  end
  if type(cfg.model) == "string" then cfg.model = cfg.model:gsub("^~", HOME) end
  return cfg
end

local cfg = loadConfig()
local wav = (os.getenv("TMPDIR") or "/tmp/") .. "dictate-around.wav"
local state = "idle"   -- idle | recording | stopping | transcribing
local origin = nil     -- { app, win, el } captured when recording starts
local recTask, indicator = nil, nil

local function micName()
  if cfg.mic and cfg.mic ~= "" then return cfg.mic end
  local d = hs.audiodevice.defaultInputDevice()
  return d and d:name() or nil
end

local function focusedElement()
  local ok, el = pcall(function()
    return hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  end)
  return ok and el or nil
end

local function showIndicator(title)
  if not indicator then indicator = hs.menubar.new() end
  indicator:setTitle(title)
end

local function hideIndicator()
  if indicator then indicator:delete(); indicator = nil end
end

local function reset(msg)
  state, origin, recTask = "idle", nil, nil
  hideIndicator()
  if msg then hs.alert.show(msg, 3) end
end

local function sameWindow(a, b)
  return a and b and a:id() == b:id()
end

local function insert(text)
  local o = origin
  local here = { win = hs.window.focusedWindow(), el = focusedElement() }

  local function originIsFront()
    local f = hs.application.frontmostApplication()
    return f and f:pid() == o.app:pid()
  end

  local function finish()
    if cfg.returnToCurrent and here.win and not sameWindow(here.win, o.win) then
      here.win:focus()
      if here.el then
        hs.timer.doAfter(0.2, function()
          pcall(function() here.el:setAttributeValue("AXFocused", true) end)
        end)
      end
    end
    reset()
  end

  local function paste()
    if o.el then pcall(function() o.el:setAttributeValue("AXFocused", true) end) end
    hs.timer.doAfter(0.1, function()
      local saved = hs.pasteboard.readAllData()
      hs.pasteboard.setContents(text)
      hs.eventtap.keyStroke({ "cmd" }, "v", 0)
      hs.timer.doAfter(0.4, function()
        hs.pasteboard.writeAllData(saved)
        finish()
      end)
    end)
  end

  -- Bring the original window forward and wait (up to 2s) until its app is really frontmost.
  -- Activation is asynchronous on recent macOS; pasting earlier lands in the wrong app.
  if o.win then o.win:focus() else o.app:activate() end
  local waited = 0
  local poll
  poll = hs.timer.doEvery(0.05, function()
    waited = waited + 0.05
    if originIsFront() then
      poll:stop()
      hs.timer.doAfter(0.1, paste)
    elseif waited >= 2 then
      poll:stop()
      hs.pasteboard.setContents(text)
      reset("Couldn't return to " .. o.app:name() .. " — text is on your clipboard")
    elseif o.win and waited > 0.5 and math.fmod(waited, 0.5) < 0.05 then
      o.win:focus() -- nudge again
    end
  end)
end

local function transcribe()
  state = "transcribing"
  showIndicator("✍︎")
  hs.task.new(cfg.whisper, function(code, out, err)
    if code ~= 0 then return reset("Transcription failed: " .. (err or ""):sub(1, 200)) end
    local text = (out or "")
      :gsub("%[[^%]]*%]", "") -- drop [BLANK_AUDIO] and similar
      :gsub("%s+", " ")
      :gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return reset("No speech detected") end
    insert(text)
  end, { "-m", cfg.model, "-f", wav, "-l", cfg.language, "-nt", "-np" }):start()
end

local function startRecording()
  local mic = micName()
  if not mic then return reset("dictate-around: no input device found") end
  origin = {
    app = hs.application.frontmostApplication(),
    win = hs.window.focusedWindow(),
    el  = focusedElement(),
  }
  os.remove(wav)
  state = "recording"
  recTask = hs.task.new(cfg.ffmpeg, function(_, _, err)
    if state == "stopping" then
      transcribe() -- ffmpeg exits 255 on SIGINT; the file is complete
    elseif state == "recording" then
      reset("Recording failed (is \"" .. mic .. "\" connected?)\n" .. (err or ""):sub(-200))
    end
  end, { "-hide_banner", "-loglevel", "error", "-y",
         "-f", "avfoundation", "-i", ":" .. mic,
         "-ac", "1", "-ar", "16000", wav })
  if not recTask:start() then return reset("dictate-around: couldn't start ffmpeg") end
  showIndicator("🎙")
  hs.sound.getByName("Tink"):play()
end

local function stopRecording()
  state = "stopping"
  hs.sound.getByName("Pop"):play()
  recTask:interrupt() -- SIGINT lets ffmpeg finish writing the file
end

local function toggle()
  if state == "idle" then startRecording()
  elseif state == "recording" then stopRecording()
  end -- taps while stopping or transcribing are ignored
end

-- Hotkey. Two forms:
--   "double-<modifier>"  two clean taps of a modifier, nothing else pressed in between:
--                        fn, cmd, alt (option), ctrl, shift, or a side: leftcmd, rightcmd,
--                        leftalt, rightalt, leftctrl, rightctrl, leftshift, rightshift
--   "<mods>+<key>"       a key combination, pressed once to start and again to stop:
--                        "ctrl+alt+d", "cmd+shift+space", "f13"
local MODS = {
  fn    = { flag = "fn" },
  cmd   = { flag = "cmd" },   leftcmd   = { flag = "cmd",   code = 55 }, rightcmd   = { flag = "cmd",   code = 54 },
  alt   = { flag = "alt" },   leftalt   = { flag = "alt",   code = 58 }, rightalt   = { flag = "alt",   code = 61 },
  ctrl  = { flag = "ctrl" },  leftctrl  = { flag = "ctrl",  code = 59 }, rightctrl  = { flag = "ctrl",  code = 62 },
  shift = { flag = "shift" }, leftshift = { flag = "shift", code = 56 }, rightshift = { flag = "shift", code = 60 },
}
local ALIASES = { option = "alt", opt = "alt", command = "cmd", control = "ctrl", globe = "fn",
                  leftoption = "leftalt", rightoption = "rightalt", leftcommand = "leftcmd",
                  rightcommand = "rightcmd", leftcontrol = "leftctrl", rightcontrol = "rightctrl" }
local FLAGS = { "fn", "cmd", "alt", "ctrl", "shift" }

local function norm(word)
  word = word:lower():gsub("%s+", ""):gsub("[-_]", "")
  return ALIASES[word] or word
end

local function doubleTapWatcher(target)
  local types = hs.eventtap.event.types
  local down, dirty, downAt, lastTap = false, false, 0, 0
  local function othersHeld(f)
    for _, name in ipairs(FLAGS) do
      if name ~= target.flag and f[name] then return true end
    end
    return false
  end
  return hs.eventtap.new({ types.flagsChanged, types.keyDown }, function(e)
    if e:getType() == types.keyDown then
      if e:getKeyCode() == 179 then return false end -- the Globe key event macOS sends on Fn release
      if down then dirty = true end
      lastTap = 0
      return false
    end
    local f, code = e:getFlags(), e:getKeyCode()
    local now = hs.timer.secondsSinceEpoch()
    local isTarget = not target.code or code == target.code
    if f[target.flag] and not down and isTarget then
      down, downAt, dirty = true, now, othersHeld(f)
    elseif not f[target.flag] and down then
      down = false
      if not dirty and isTarget and now - downAt <= cfg.tapMax then
        if now - lastTap <= cfg.doubleTapWindow then
          lastTap = 0
          hs.timer.doAfter(0, toggle)
        else
          lastTap = now
        end
      else
        lastTap = 0
      end
    elseif down and (othersHeld(f) or not isTarget) then
      dirty = true
    else
      lastTap = 0 -- some other modifier was used between the taps
    end
    return false
  end)
end

local function bindHotkey(spec)
  spec = (spec or "double-fn"):gsub("^%s+", ""):gsub("%s+$", "")
  local double = spec:lower():match("^double[-_ ]?(.+)$")
  if double then
    local target = MODS[norm(double)]
    if not target then return nil, "unknown modifier \"" .. double .. "\"" end
    local w = doubleTapWatcher(target)
    w:start()
    return w
  end
  local parts = {}
  for part in spec:gmatch("[^+]+") do table.insert(parts, part) end
  local key = table.remove(parts)
  if not key or key == "" then return nil, "no key in \"" .. spec .. "\"" end
  local mods = {}
  for _, m in ipairs(parts) do
    local n = norm(m)
    if not MODS[n] or MODS[n].code then return nil, "unknown modifier \"" .. m .. "\"" end
    table.insert(mods, MODS[n].flag)
  end
  local ok, hk = pcall(hs.hotkey.bind, mods, key:lower(), toggle)
  if not ok or not hk then return nil, "can't bind \"" .. spec .. "\"" end
  return hk
end

local bindError
M.tap, bindError = bindHotkey(cfg.hotkey)

-- One-line health report, for `install-dictate-around --status`.
function M.status()
  local listening = false
  if M.tap then
    -- an eventtap reports isEnabled(); a bound hs.hotkey is live as long as it exists
    if M.tap.isEnabled then listening = M.tap:isEnabled() else listening = true end
  end
  return string.format("listening=%s hotkey=%s accessibility=%s state=%s mic=%s model=%s",
    tostring(listening), bindError and ("ERROR " .. bindError) or cfg.hotkey,
    tostring(hs.accessibilityState()), state,
    tostring(micName()), hs.fs.attributes(cfg.model) and "ok" or "missing")
end

if bindError then
  hs.alert.show("dictate-around: hotkey " .. bindError .. " — check " .. M.configPath, 6)
else
  hs.alert.show("dictate-around ready (" .. cfg.hotkey .. ")", 1.5)
end

return M
