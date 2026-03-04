--
--
--
--  Variables 
--  
--
--
--
-- Specify your combination (your hyperkey)
local hyper = {"ctrl", "alt" }
local cmdshift = { "cmd", "shift" }


-- Get variables for active position timer
local tActive = hs.timer.secondsSinceEpoch()
local tLastMousePos = hs.mouse.absolutePosition()

--
--
--
--  Functions
--  
--
--
--

-- Load environment variables from .env file
local env = {}
local function loadEnv()
    local envPath = os.getenv("HOME") .. "/dotfiles/.env"
    local envFile = io.open(envPath, "r")
    if envFile then
        for line in envFile:lines() do
            -- Skip comments and empty lines
            if not line:match("^#") and not line:match("^%s*$") then
                local key, value = line:match("^([^=]+)=(.+)$")
                if key and value then
                    -- Trim whitespace
                    key = key:gsub("^%s*(.-)%s*$", "%1")
                    value = value:gsub("^%s*(.-)%s*$", "%1")
                    -- Remove quotes if present
                    value = value:gsub("^[\"'](.-)[\"']$", "%1")
                    env[key] = value
                end
            end
        end
        envFile:close()
        return true
    end
    return false
end

-- Load the .env file
local envLoaded = loadEnv()

-- Get API key from loaded environment or system environment
local OPENAI_API_KEY = env["OPENAI_API_KEY"] or os.getenv("OPENAI_API_KEY")
if not OPENAI_API_KEY then
    if not envLoaded then
        hs.alert.show("Warning: .env file not found. Copy .env.example to .env and add your API key")
    else
        hs.alert.show("Warning: OPENAI_API_KEY not found in .env file")
    end
end

local MAX_RETRIES = 3
local RETRY_DELAY = 2 -- seconds between retries

local function isInputField()
  local app = hs.application.frontmostApplication()
  if not app then return false end

  local focused = app:focusedWindow()
  if not focused then return false end

  local ui = hs.uielement.focusedElement()
  if not ui then return false end
  
  -- Check if the UI element supports the attributeValue method
  if not ui.attributeValue then return false end
  
  -- Try to get roles safely
  local role, subrole
  local status, result = pcall(function() return ui:attributeValue("AXRole") end)
  if status then role = result or "" else role = "" end
  
  status, result = pcall(function() return ui:attributeValue("AXSubrole") end)
  if status then subrole = result or "" else subrole = "" end

  -- AXTextField or AXTextArea are typical input types
  if role == "AXTextField" or role == "AXTextArea" then
    return true
  end

  -- Sometimes the element is a group but subrole is text field
  if subrole == "AXTextField" then
    return true
  end

  return false
end

local function translateText(text, attempt, callback)
  attempt = attempt or 1

  -- Improved prompt using best practices:
  -- 1. Clear task description with explicit instructions
  -- 2. Format with clear separation of input and desired output
  -- 3. Example-based instructions for clarity
  local prompt = [[
Translate the text below:

- If it's in English → translate to Portuguese (informal "você", not "o senhor")
- If it's in Portuguese → translate to English

Important rules:
1. Match capitalization (don't add capitals where none exist)
2. Match punctuation style (don't add periods or commas)
3. Keep the same informal/casual tone
4. Preserve abbreviations and slang with equivalents
5. PRESERVE ALL LINE BREAKS AND PARAGRAPH FORMATTING exactly as in the original
6. Keep spacing, indentation and line structure intact
7. Return ONLY the translation with no explanations

Text: "]] .. text:gsub('"', '\\"') .. [["
]]

  local body = {
    model = "gpt-4.1-nano",  -- Updated to GPT-4.1-ultra
    messages = {
      {role = "system", content = "You are a high-quality translator that provides accurate translations between English and Portuguese."}, -- Added system role for better context
      {role = "user", content = prompt}
    }
  }

  local jsonBody = hs.json.encode(body)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. OPENAI_API_KEY
  }

  hs.http.asyncPost(
    "https://api.openai.com/v1/chat/completions",
    jsonBody,
    headers,
    function(status, body, headers)
      if status == 200 then
        local response = hs.json.decode(body)
        local translated = response and response.choices and response.choices[1].message.content
        if translated and translated:match("%S") then
          callback(translated)
          return
        else
          hs.alert.show("OpenAI returned empty translation")
          callback(nil)
          return
        end
      else
        if attempt < MAX_RETRIES then
          hs.timer.doAfter(RETRY_DELAY, function()
            translateText(text, attempt + 1, callback)
          end)
        else
          hs.alert.show("OpenAI API error: " .. tostring(status))
          callback(nil)
        end
      end
    end
  )
end

-- Create a styled floating window for translations
local translationWebview = nil

-- Function to show translation in a floating webview

-- Function to handle translation and replacing text
function replaceWithTranslatedText()
  local originalClipboard = hs.pasteboard.getContents()

  -- Copy selected text without showing alert
  hs.eventtap.keyStroke({"cmd"}, "c")
  
  hs.timer.doAfter(0.3, function()
    local selectedText = hs.pasteboard.getContents()
    if not selectedText or selectedText == "" then
      hs.alert.show("No text selected or copy failed")
      return
    end

    translateText(selectedText, 1, function(translatedText)
      if not translatedText then
        hs.pasteboard.setContents(originalClipboard)
        return
      end

      -- Always try to replace selected text, regardless of input field detection
      -- Delete original selection (if possible)
      hs.eventtap.keyStroke({}, "delete")
      
      -- Paste translation
      hs.pasteboard.setContents(translatedText)
      hs.eventtap.keyStroke({"cmd"}, "v")
      
      -- Restore original clipboard after pasting
      hs.timer.doAfter(0.1, function()
        hs.pasteboard.setContents(originalClipboard)
      end)
    end)
  end)
end

-- Bind to both hyper and option keys
hs.hotkey.bind(hyper, "D", replaceWithTranslatedText)
hs.hotkey.bind({"alt"}, "d", replaceWithTranslatedText)

-- Map Option+Space to Command+Space (Spotlight/Alfred)
hs.hotkey.bind({"alt"}, "space", function()
  hs.eventtap.keyStroke({"cmd"}, "space")
end)

-- Map Option+Tab to Command+Tab (App Switcher)
hs.hotkey.bind({"alt"}, "tab", function()
  hs.eventtap.keyStroke({"cmd"}, "tab")
end)

--
--
--
--  Testing Zone
--  
--
--
--

-- function testFunction()
--     hs.application.open("Discord")
--     -- focus on discord
--     hs.eventtap.keyStroke( nil,"escape")
-- end



-- hs.hotkey.bind(hyper, "1", testFunction)


--
--
--
--  Testing Zone
--  
--
--
--


---
---  Open SSH Config
---


-- Create a styled floating window for translations
local translationWebview = nil

-- Function to show translation in a floating webview""


mouseCircle = nil
mouseCircleTimer = nil

function mouseHighlight()
    -- Delete an existing highlight if it exists
    if mouseCircle then
        mouseCircle:delete()
        if mouseCircleTimer then
            mouseCircleTimer:stop()
        end
    end
    -- Get the current co-ordinates of the mouse pointer
    mousepoint = hs.mouse.absolutePosition()
    -- Prepare a big red circle around the mouse pointer
    mouseCircle = hs.drawing.circle(hs.geometry.rect(mousepoint.x-40, mousepoint.y-40, 80, 80))
    mouseCircle:setStrokeColor({["red"]=1,["blue"]=0,["green"]=0,["alpha"]=1})
    mouseCircle:setFill(false)
    mouseCircle:setStrokeWidth(5)
    mouseCircle:show()

    -- Set a timer to delete the circle after 3 seconds
    mouseCircleTimer = hs.timer.doAfter(3, function()
      mouseCircle:delete()
      mouseCircle = nil
    end)
end

function activeCheck()
    -- Get current mouse position
    local currentPos = hs.mouse.absolutePosition()
    
    -- If position hasn't changed, we might be AFK
    if currentPos.x == tLastMousePos.x and currentPos.y == tLastMousePos.y then
        -- Check how long since last activity
        local idleTime = hs.timer.secondsSinceEpoch() - tActive
        if idleTime > 300 then -- 5 minutes
            -- User is AFK, can add actions here
        end
    else
        -- Mouse moved, update activity time
        tActive = hs.timer.secondsSinceEpoch()
        tLastMousePos = currentPos
    end
end

-- Timer that checks to see if we are afk every 5 seconds
alertTimer = hs.timer.doEvery(5, activeCheck)
alertTimer:start()

-- hs.hotkey.bind(hyper, "D", mouseHighlight)





function pingResult(object, message, seqnum, error)
    if message == "didFinish" then
        local avg = math.floor(tonumber(string.match(object:summary(), '/(%d+.%d+)/')))
        if avg == 0.0 then
            hs.alert.show("No network")
        elseif avg < 200.0 then
            hs.alert.show("Network good (" .. avg .. "ms)")
        elseif avg < 500.0 then
            hs.alert.show("Network poor(" .. avg .. "ms)")
        else
            hs.alert.show("Network bad(" .. avg .. "ms)")
        end
    end
end

hs.hotkey.bind(hyper, "G", function()
    hs.network.ping.ping("8.8.8.8", 1, 0.01, 1.0, "any", pingResult)
end)


hs.hotkey.bind(cmdshift, "E", function()
    hs.shortcuts.run("Inbox")
end)
  
hs.hotkey.bind("shift", "delete", function()
    hs.eventtap.keyStroke({}, "forwarddelete", 1000)
end)
function PopupTranslateSelection()
    local text = hs.pasteboard.readString()
    if text then
        -- Removed reference to undefined service variable
        -- If you want to use a translation service, define it first
        translateText(text, 1, function(translatedText)
            if translatedText then
                hs.alert.show(translatedText, 5)
            end
        end)
    end
end



-- translate popup text

-- Move window around screen


-- auto reload config on save (exclude claude-sync.log to prevent loops)

hs.loadSpoon("ReloadConfiguration")
spoon.ReloadConfiguration.watch_paths = {os.getenv("HOME") .. "/.hammerspoon/init.lua"}
spoon.ReloadConfiguration:start()

-- Canvas for translation display
local translationCanvas = nil

-- Function to show translation in a floating canvas
function showTranslation(originalText, translatedText)
  -- Close any existing canvas
  if translationCanvas then
    translationCanvas:delete()
    translationCanvas = nil
  end
  
  -- Use the active screen
  local activeScreen = hs.screen.mainScreen()
  local screenFrame = activeScreen:frame()
  local width = 550  -- Slightly wider for better text presentation
  
  -- Position on the top-right corner of the active screen
  local xPos = screenFrame.x + screenFrame.w - width - 30
  local yPos = screenFrame.y + 60
  
  -- Set up text properties
  local titleSize = 15  -- Title size
  local textSize = 16   -- Content size
  local paddingX = 20   -- More padding for better readability
  local paddingY = 20
  local maxWidth = width - (paddingX * 2)
  
  -- Better estimate text height - count newlines and approximate wrapping
  local approxCharsPerLine = 65 -- Adjusted characters per line for our width
  local lineCount = 0 -- Start with zero lines
  
  -- Count explicit newlines
  for _ in string.gmatch(translatedText, "\n") do
    lineCount = lineCount + 1
  end
  
  -- Adjust line count based on text length - more precise calculation
  local textLength = string.len(translatedText)
  if textLength > 0 then
    -- At least one line if there's any text
    lineCount = math.max(1, lineCount)
    
    -- Add wrapped lines estimate based on actual character count
    -- Using a more conservative estimate for wrapping
    local estimatedWrappedLines = math.ceil(textLength / approxCharsPerLine) * 0.85
    lineCount = lineCount + estimatedWrappedLines - 1 -- Subtract 1 since we counted the first line already
  end
  
  -- Add space for the header/title section
  local headerHeight = 24 -- Slightly smaller header
  
  -- Calculate height more precisely based on line count
  local lineHeight = textSize * 1.3  -- Reduced line height for snugger fit
  local estimatedTextHeight = lineCount * lineHeight
  -- Add just enough padding and make minimum height smaller
  local height = math.max(estimatedTextHeight + headerHeight + (paddingY * 1.5), 80)
  
  -- Create the canvas with initial estimated height
  translationCanvas = hs.canvas.new({x = xPos, y = yPos, w = width, h = height})
  
  -- Create a more elegant shadow effect
  local shadowBlur = 20
  
  -- Add elements to the canvas
  translationCanvas:appendElements({
    -- Element 1: Shadow effect (softer and more spread out)
    {
      type = "rectangle",
      action = "fill",
      fillColor = {hex = "#000000", alpha = 0.15},
      roundedRectRadii = {xRadius = 14, yRadius = 14},
      frame = {x = shadowBlur/2, y = shadowBlur/2, w = width - shadowBlur, h = height - shadowBlur},
      shadow = {blurRadius = shadowBlur, color = {hex = "#000000", alpha = 0.25}}
    },
    -- Element 2: Dark background with complete border and rounded corners
    {
      type = "rectangle",
      action = "fill",
      fillColor = {hex = "#2C3E50", alpha = 0.97},  -- Dark blue-gray background
      strokeColor = {hex = "#4a6fa5"},  -- Blue border
      strokeWidth = 1,  -- Full border
      roundedRectRadii = {xRadius = 12, yRadius = 12},  -- Rounded corners
      frame = {x = 0, y = 0, w = "100%", h = "100%"}
    },
    -- Element 3: Bottom accent with subtle gradient
    {
      type = "rectangle",
      action = "fill",
      fillColor = {gradient = {
        start = {x = 0, y = 1},  -- Start from bottom
        stops = {
          {color = {hex = "#3498DB", alpha = 0.9}, position = 0},
          {color = {hex = "#2980B9", alpha = 0.9}, position = 1}
        }
      }},
      frame = {x = 0, y = "100%", w = "100%", h = 3}  -- Bottom accent at the very bottom
    },
    -- Element 4: Title section with language indication
    {
      type = "text",
      text = (string.match(originalText, "[%z\1-\127]") and "English → Portuguese" or "Portuguese → English"),
      textSize = titleSize,
      textColor = {hex = "#78A7E8"},  -- Lighter blue color for title on dark background
      textAlignment = "left",  -- Left align to match side accent
      textFont = "Helvetica Bold",  -- Using a standard macOS font with explicit weight
      frame = {x = paddingX + 7, y = paddingY, w = maxWidth - 7, h = 25}
    },
    -- Element 5: Text content
    {
      type = "text",
      text = translatedText,
      textSize = textSize,
      textColor = {hex = "#ECF0F1"},  -- Light text color for dark background
      textFont = "Helvetica",  -- Using a standard macOS font
      textLineBreak = "wordWrap",
      frame = {x = paddingX + 8, y = paddingY + headerHeight, w = maxWidth - 8, h = estimatedTextHeight}
    }
  })
  
  -- Show the canvas with a fade-in animation
  translationCanvas:behavior({"canJoinAllSpaces", "stationary"})
  translationCanvas:level(hs.canvas.windowLevels.overlay)
  
  -- Apply a subtle fade-in animation
  translationCanvas:alpha(0)
  translationCanvas:show()
  
  -- Animate from fully transparent to visible
  hs.timer.doAfter(0.05, function()
    if translationCanvas then
      hs.timer.doUntil(function() 
        return translationCanvas == nil
      end, function()
        local currentAlpha = translationCanvas:alpha()
        if currentAlpha < 1 then
          translationCanvas:alpha(math.min(currentAlpha + 0.1, 1))
          return true
        else
          return false
        end
      end, 0.02)
    end
  end)
  
  -- Make the canvas clickthrough (no interaction)
  translationCanvas:behavior({"canJoinAllSpaces", "stationary", "transient"})
  
  -- Set up autoclose timer that checks for mouse position
  local closeTimer = nil
  closeTimer = hs.timer.doAfter(10, function()  -- Increased display time
    if translationCanvas then
      -- Get current mouse position
      local mousePos = hs.mouse.absolutePosition()
      local canvasFrame = translationCanvas:frame()
      
      -- Check if mouse is over the canvas
      local mouseIsOver = mousePos.x >= canvasFrame.x and 
                         mousePos.x <= canvasFrame.x + canvasFrame.w and
                         mousePos.y >= canvasFrame.y and
                         mousePos.y <= canvasFrame.y + canvasFrame.h
      
      -- Only close if mouse is not over the canvas
      if not mouseIsOver then
        translationCanvas:delete()
        translationCanvas = nil
      else
        -- If mouse is over, check again in 1 second
        closeTimer = hs.timer.doAfter(1, function() 
          if translationCanvas then
            local mousePos = hs.mouse.absolutePosition()
            local canvasFrame = translationCanvas:frame()
            local mouseIsOver = mousePos.x >= canvasFrame.x and 
                             mousePos.x <= canvasFrame.x + canvasFrame.w and
                             mousePos.y >= canvasFrame.y and
                             mousePos.y <= canvasFrame.y + canvasFrame.h
            if not mouseIsOver then
              translationCanvas:delete()
              translationCanvas = nil
            end
          end
        end)
      end
    end
  end)
end

-- Function to translate selected text and show it on the top-right corner
function translateAndShowPopup()
  local originalClipboard = hs.pasteboard.getContents()
  
  -- Copy selected text to clipboard
  hs.eventtap.keyStroke({"cmd"}, "c")
  
  -- Wait a bit for clipboard to update
  hs.timer.usleep(20000)
  
  -- Get text from clipboard
  local text = hs.pasteboard.getContents()
  
  -- Restore original clipboard
  if originalClipboard then
    hs.pasteboard.setContents(originalClipboard)
  end
  
  if text and text:match("%S") then
    -- Translate the text
    translateText(text, 1, function(translatedText)
      if translatedText then
        -- Show translation in a floating webview
        showTranslation(text, translatedText)
      end
    end)
  else
    hs.alert.show("No text selected")
  end
end

-- Bind Alt+S and Hyper+S to translate and show popup
hs.hotkey.bind({"alt"}, "s", translateAndShowPopup)
-- hs.hotkey.bind(hyper, "s", translateAndShowPopup)  -- Disabled for AeroSpace

-- Brightness toggle functionality
local previousBrightness = nil

function toggleBrightness()
    local currentBrightness = hs.brightness.get()
    
    if previousBrightness == nil or currentBrightness > 0.01 then
        -- Store current brightness and set to 0
        previousBrightness = currentBrightness
        hs.brightness.set(0)
    else
        -- Restore previous brightness
        if previousBrightness and previousBrightness > 0.01 then
            hs.brightness.set(previousBrightness)
        else
            -- Fallback to 50% if we don't have a valid previous brightness
            hs.brightness.set(0.5)
        end
        previousBrightness = nil
    end
end

-- Bind Ctrl+Shift+B to toggle brightness
hs.hotkey.bind(hyper, "b", toggleBrightness)

-- Function to toggle dock visibility
function toggleDock()
    local task = hs.task.new("/usr/bin/osascript", nil, {"-e", "tell application \"System Events\" to set autohide of dock preferences to not autohide of dock preferences"})
    task:start()
end

-- Bind Hyper+Cmd+O to toggle dock
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "o", toggleDock)

-- Function to toggle Sketchybar privacy mode (hides meetings/Todoist)
function toggleSketchybarPrivacy()
    local task = hs.task.new("/bin/bash", nil, {"-c", "$HOME/.config/sketchybar/config_manager.sh toggle-privacy"})
    task:start()
end

-- Bind Ctrl+Alt+Cmd+P to toggle privacy mode (same hotkey as before)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "p", toggleSketchybarPrivacy)

-- Removed automatic AeroSpace gap configuration
-- Gaps are now managed directly in the AeroSpace config file

-- Removed Hammerspoon calendar sync (Story 2.1)
-- Calendar sync is now handled via LaunchAgent calling sync-calendars.sh helper

-- Audio output switching with visual preview and volume control
-- Phase 1: ] and [ browse devices; auto-applies after 2s
-- Phase 2: after device applies, ] and [ adjust volume; auto-applies after 2s
-- Mic always pinned to right (main) monitor
local sasPath = "/opt/homebrew/bin/SwitchAudioSource"
local audioCycleIndex = 0       -- current ACTIVE device in audioDevices
local audioDevices = {}         -- built at init, rebuilt on display changes
local rightMonitorInputUid = nil -- mic always on right monitor

-- Preview state
local audioPreviewIndex = 0     -- device being previewed (0 = no preview active)
local audioPreviewTimer = nil   -- auto-apply timer


-- Balance offset for LG Dual mode (range: -20 to +20)
-- Positive = boost left monitor, Negative = boost right monitor
-- Adjust if one monitor sounds quieter in dual mode
local DUAL_BALANCE_OFFSET = 0

-- Glass overlay (hs.canvas) for audio controls
local audioCanvas = nil
local audioHideTimer = nil

local function hideAudioOverlay()
    if audioHideTimer then audioHideTimer:stop(); audioHideTimer = nil end
    if audioCanvas then
        audioCanvas:delete()
        audioCanvas = nil
    end
end

-- Build the device list using UIDs to distinguish identical-name LG displays
local function buildAudioDeviceList()
    if not hs.fs.attributes(sasPath) then
        hs.alert.show("SwitchAudioSource not found")
        return
    end

    audioDevices = {}
    rightMonitorInputUid = nil

    local jsonOutput = hs.execute(sasPath .. " -a -t output -f json")
    local currentJson = hs.execute(sasPath .. " -c -t output -f json")
    local currentOutputUid = currentJson:match('"uid"%s*:%s*"([^"]+)"')

    -- The main display is whichever LG is the current default output
    local mainSerial = nil
    if currentOutputUid and currentOutputUid:find("LG UltraFine") then
        mainSerial = currentOutputUid:match(":(%d+):%d+$")
    end

    local lgDevices = {}
    local otherDevices = {}

    for line in jsonOutput:gmatch("[^\r\n]+") do
        local name = line:match('"name"%s*:%s*"([^"]+)"')
        local uid = line:match('"uid"%s*:%s*"([^"]+)"')

        if name and uid then
            if not name:find("Microsoft Teams") and
               not name:find("Jump Desktop") and
               not name:find("krisp") and
               not name:find("LG Dual") and
               not name:find("Multi%-Output") and
               not name:find("Aggregate") then

                if name:find("LG UltraFine") then
                    local serial = uid:match(":(%d+):%d+$")
                    local inputUid = uid:gsub(":%d+$", ":1")
                    table.insert(lgDevices, {
                        label = (mainSerial and serial == mainSerial) and "LG Right" or "LG Left",
                        outputUid = uid,
                        inputUid = inputUid,
                        serial = serial
                    })
                else
                    table.insert(otherDevices, {
                        label = name,
                        outputUid = uid
                    })
                end
            end
        end
    end

    -- Fallback if current output isn't LG
    if not mainSerial and #lgDevices == 2 then
        lgDevices[1].label = "LG Left"
        lgDevices[2].label = "LG Right"
    end

    -- Sort: Left first, then Right
    table.sort(lgDevices, function(a, b) return a.label < b.label end)

    -- Capture right monitor input UID for mic pinning
    for _, lg in ipairs(lgDevices) do
        if lg.label == "LG Right" then
            rightMonitorInputUid = lg.inputUid
            break
        end
    end

    -- 1) Individual LG devices
    for _, dev in ipairs(lgDevices) do
        table.insert(audioDevices, dev)
    end

    -- 2) Dual mode (if 2 LG displays)
    if #lgDevices == 2 then
        local rightLg, leftLg
        for _, lg in ipairs(lgDevices) do
            if lg.label == "LG Right" then rightLg = lg else leftLg = lg end
        end
        if rightLg and leftLg then
            local multiUid = nil
            -- Prefer our programmatic device by UID
            for _, dev in ipairs(hs.audiodevice.allOutputDevices()) do
                if dev:uid() == "com.user.lg-dual-output" then
                    multiUid = dev:uid()
                    break
                end
            end
            -- Fall back to any multi-output device
            if not multiUid then
                for _, dev in ipairs(hs.audiodevice.allOutputDevices()) do
                    local n = dev:name()
                    if n:find("Multi%-Output") or n:find("Aggregate") or n:find("LG Dual") then
                        multiUid = dev:uid()
                        break
                    end
                end
            end
            if not multiUid then
                local scriptPath = os.getenv("HOME") .. "/dotfiles/scripts/create-multi-output.swift"
                if hs.fs.attributes(scriptPath) then
                    hs.execute("/usr/bin/swift " .. scriptPath)
                    for _, dev in ipairs(hs.audiodevice.allOutputDevices()) do
                        local n = dev:name()
                        if n:find("Multi%-Output") or n:find("Aggregate") or n:find("LG Dual") then
                            multiUid = dev:uid()
                            break
                        end
                    end
                end
            end
            table.insert(audioDevices, {
                label = "LG Dual",
                isDual = true,
                outputUids = {leftLg.outputUid, rightLg.outputUid},
                multiOutputUid = multiUid,
                primaryOutputUid = rightLg.outputUid,
                inputUid = rightLg.inputUid
            })
        end
    end

    -- 3) Other devices (Mac mini Speakers, etc.)
    for _, dev in ipairs(otherDevices) do
        table.insert(audioDevices, dev)
    end
end

-- Detect current active device index from system state
local function initAudioCycleIndex()
    local current = hs.audiodevice.defaultOutputDevice()
    if not current then
        audioCycleIndex = 1
        return
    end
    local currentUid = current:uid()

    for i, device in ipairs(audioDevices) do
        if not device.isDual and device.outputUid == currentUid then
            audioCycleIndex = i
            return
        end
    end
    for i, device in ipairs(audioDevices) do
        if device.isDual and device.multiOutputUid == currentUid then
            audioCycleIndex = i
            return
        end
    end

    audioCycleIndex = 1
end


-- Draw a flat geometric speaker icon on the canvas
-- level: 0=muted, 1=low, 2=high
local function drawSpeakerIcon(canvas, x, y, size, level, color)
    local c = color or {white = 0.65, alpha = 0.8}
    local s = size
    -- Speaker body + cone
    canvas:appendElements({
        type = "segments",
        action = "fill",
        fillColor = c,
        closed = true,
        coordinates = {
            {x = x,           y = y + s*0.35},
            {x = x + s*0.28,  y = y + s*0.35},
            {x = x + s*0.48,  y = y + s*0.15},
            {x = x + s*0.48,  y = y + s*0.85},
            {x = x + s*0.28,  y = y + s*0.65},
            {x = x,           y = y + s*0.65},
        },
    })
    if level == 0 then
        -- Mute X
        canvas:appendElements({
            type = "segments", action = "stroke",
            strokeColor = c, strokeWidth = 1.5,
            coordinates = {
                {x = x + s*0.56, y = y + s*0.35},
                {x = x + s*0.78, y = y + s*0.65},
            },
        })
        canvas:appendElements({
            type = "segments", action = "stroke",
            strokeColor = c, strokeWidth = 1.5,
            coordinates = {
                {x = x + s*0.56, y = y + s*0.65},
                {x = x + s*0.78, y = y + s*0.35},
            },
        })
    end
    if level >= 1 then
        -- Small wave
        canvas:appendElements({
            type = "segments", action = "stroke",
            strokeColor = c, strokeWidth = 1.2,
            coordinates = {
                {x = x + s*0.58, y = y + s*0.33},
                {x = x + s*0.58, y = y + s*0.67,
                 c1x = x + s*0.74, c1y = y + s*0.33,
                 c2x = x + s*0.74, c2y = y + s*0.67},
            },
        })
    end
    if level >= 2 then
        -- Large wave
        canvas:appendElements({
            type = "segments", action = "stroke",
            strokeColor = c, strokeWidth = 1.2,
            coordinates = {
                {x = x + s*0.70, y = y + s*0.20},
                {x = x + s*0.70, y = y + s*0.80,
                 c1x = x + s*0.92, c1y = y + s*0.20,
                 c2x = x + s*0.92, c2y = y + s*0.80},
            },
        })
    end
end

-- Set volume on dual LG displays with balance offset
local function setDualVolume(device, baseVolume)
    for i, uid in ipairs(device.outputUids) do
        local dev = hs.audiodevice.findDeviceByUID(uid)
        if dev then
            -- outputUids: [1]=left, [2]=right (labels may not match physical)
            local offset = (i == 1) and -DUAL_BALANCE_OFFSET or DUAL_BALANCE_OFFSET
            dev:setVolume(math.max(0, math.min(100, baseVolume + offset)))
        end
    end
end

-- Show the device picker overlay (glass style)
local function showDevicePreview()
    hideAudioOverlay()

    local W, H = 300, 72
    local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
    local sf = screen:frame()

    audioCanvas = hs.canvas.new({
        x = sf.x + (sf.w - W) / 2,
        y = sf.y + sf.h - H - 120,
        w = W, h = H,
    })
    audioCanvas:level(hs.canvas.windowLevels.overlay)
    audioCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Background
    audioCanvas:appendElements({
        type = "rectangle",
        action = "strokeAndFill",
        fillColor = {white = 0.12, alpha = 0.78},
        strokeColor = {white = 0.5, alpha = 0.25},
        strokeWidth = 0.5,
        roundedRectRadii = {xRadius = 16, yRadius = 16},
    })

    -- Device name (centered)
    local idx = audioPreviewIndex > 0 and audioPreviewIndex or audioCycleIndex
    local device = audioDevices[idx]
    local label = device and device.label or "Unknown"
    audioCanvas:appendElements({
        type = "text",
        text = hs.styledtext.new(label, {
            font = {name = ".AppleSystemUIFont", size = 16},
            color = {white = 1, alpha = 0.95},
            paragraphStyle = {alignment = "center"},
        }),
        frame = {x = 40, y = 14, w = W - 80, h = 24},
    })

    -- Left arrow hint
    audioCanvas:appendElements({
        type = "text",
        text = hs.styledtext.new("\u{2039}", {
            font = {name = ".AppleSystemUIFont", size = 26},
            color = {white = 0.6, alpha = 0.75},
            paragraphStyle = {alignment = "center"},
        }),
        frame = {x = 10, y = 8, w = 24, h = 32},
    })

    -- Right arrow hint
    audioCanvas:appendElements({
        type = "text",
        text = hs.styledtext.new("\u{203A}", {
            font = {name = ".AppleSystemUIFont", size = 26},
            color = {white = 0.6, alpha = 0.75},
            paragraphStyle = {alignment = "center"},
        }),
        frame = {x = W - 34, y = 8, w = 24, h = 32},
    })

    -- Position dots
    local n = #audioDevices
    local dotSpacing = 14
    local totalDotsW = (n - 1) * dotSpacing
    local startX = (W - totalDotsW) / 2
    for i = 1, n do
        local isPrev = (audioPreviewIndex > 0 and i == audioPreviewIndex)
        local isAct = (i == audioCycleIndex)
        local r = isPrev and 3.5 or 2.5
        local cx = startX + (i - 1) * dotSpacing
        local cy = H - 16
        audioCanvas:appendElements({
            type = "oval",
            action = "fill",
            fillColor = isPrev and {white = 1, alpha = 1}
                        or isAct and {white = 0.6, alpha = 0.7}
                        or {white = 0.3, alpha = 0.4},
            frame = {x = cx - r, y = cy - r, w = r * 2, h = r * 2},
        })
    end

    audioCanvas:show()
end


-- Show quick volume feedback (for hardware keys and apply confirmation)
local function showQuickVolume(vol, label)
    hideAudioOverlay()

    local W, H = 300, 56
    local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
    local sf = screen:frame()

    audioCanvas = hs.canvas.new({
        x = sf.x + (sf.w - W) / 2,
        y = sf.y + sf.h - H - 120,
        w = W, h = H,
    })
    audioCanvas:level(hs.canvas.windowLevels.overlay)
    audioCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Background
    audioCanvas:appendElements({
        type = "rectangle",
        action = "strokeAndFill",
        fillColor = {white = 0.12, alpha = 0.78},
        strokeColor = {white = 0.5, alpha = 0.25},
        strokeWidth = 0.5,
        roundedRectRadii = {xRadius = 14, yRadius = 14},
    })

    -- Label
    audioCanvas:appendElements({
        type = "text",
        text = hs.styledtext.new(label or "Volume", {
            font = {name = ".AppleSystemUIFont", size = 12},
            color = {white = 0.9, alpha = 0.95},
            paragraphStyle = {alignment = "center"},
        }),
        frame = {x = 40, y = 6, w = W - 80, h = 18},
    })

    -- Speaker icon (muted or low)
    drawSpeakerIcon(audioCanvas, 14, 27, 16, (vol == 0) and 0 or 1, {white = 0.7, alpha = 0.9})

    -- Slider track
    local trackX, trackY, trackW, trackH = 42, 32, W - 84, 6
    audioCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = {white = 0.25, alpha = 0.5},
        roundedRectRadii = {xRadius = 3, yRadius = 3},
        frame = {x = trackX, y = trackY, w = trackW, h = trackH},
    })

    -- Slider fill
    local fillW = math.max(0, trackW * vol / 100)
    if fillW > 1 then
        audioCanvas:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = {white = 1, alpha = 0.9},
            roundedRectRadii = {xRadius = 3, yRadius = 3},
            frame = {x = trackX, y = trackY, w = fillW, h = trackH},
        })
    end

    -- Speaker icon (high)
    drawSpeakerIcon(audioCanvas, W - 36, 27, 16, 2, {white = 0.7, alpha = 0.9})

    audioCanvas:show()

    -- Auto-hide after 1 second
    audioHideTimer = hs.timer.doAfter(1, function()
        hideAudioOverlay()
    end)
end


-- Switch output to the previewed device
local function applyAudioSelection()
    local device = audioDevices[audioPreviewIndex]
    if not device then
        hideAudioOverlay()
        return
    end

    -- Match volume from current device to prevent blaring
    local currentDev = hs.audiodevice.defaultOutputDevice()
    local volume = (currentDev and currentDev:volume()) or 50

    audioCycleIndex = audioPreviewIndex
    audioPreviewIndex = 0

    -- Hide device overlay IMMEDIATELY (before any switching)
    hideAudioOverlay()

    -- Post-switch actions (mic pinning, brief confirmation)
    local function afterSwitch()
        if rightMonitorInputUid then
            local inputDev = hs.audiodevice.findDeviceByUID(rightMonitorInputUid)
            if inputDev then inputDev:setDefaultInputDevice() end
        end
        showQuickVolume(math.floor(volume + 0.5), device.label)
    end

    if device.isDual then
        setDualVolume(device, volume)
        local devToSet = device.multiOutputUid and hs.audiodevice.findDeviceByUID(device.multiOutputUid)
                         or hs.audiodevice.findDeviceByUID(device.primaryOutputUid)
        if devToSet then
            devToSet:setDefaultOutputDevice()
            pcall(function() devToSet:setDefaultSystemDevice() end)
        end
        setDualVolume(device, volume)
        afterSwitch()
    else
        -- Use hs.task (async, no shell quoting) for SwitchAudioSource
        local dev = hs.audiodevice.findDeviceByUID(device.outputUid)
        if dev then dev:setVolume(volume) end
        local task = hs.task.new(sasPath, function(exitCode, stdOut, stdErr)
            local switched = hs.audiodevice.findDeviceByUID(device.outputUid)
            if switched then
                switched:setVolume(volume)
                pcall(function() switched:setDefaultSystemDevice() end)
            end
            afterSwitch()
        end, {"-t", "output", "-u", device.outputUid})
        task:start()
    end
end

-- Cycle through audio devices: direction 1=forward, -1=backward
local function cycleAudio(direction)
    if #audioDevices == 0 then
        buildAudioDeviceList()
        initAudioCycleIndex()
    end
    if #audioDevices == 0 then
        hs.alert.show("No audio devices found")
        return
    end

    if audioPreviewIndex == 0 then
        audioPreviewIndex = audioCycleIndex
    end

    audioPreviewIndex = audioPreviewIndex + direction
    if audioPreviewIndex > #audioDevices then audioPreviewIndex = 1 end
    if audioPreviewIndex < 1 then audioPreviewIndex = #audioDevices end

    showDevicePreview()

    if audioPreviewTimer then audioPreviewTimer:stop() end
    audioPreviewTimer = hs.timer.doAfter(2, function()
        audioPreviewTimer = nil
        applyAudioSelection()
    end)
end

-- Initialize device list and state
buildAudioDeviceList()
initAudioCycleIndex()


-- Intercept system volume keys with modifiers
-- Ctrl+Alt + Volume = adjust volume on current device (with overlay)
-- Cmd+Ctrl+Alt + Volume = cycle through audio devices
-- Plain volume keys = pass through to native macOS
local VOLUME_STEP = 6.25  -- ~16 steps like native macOS
local pendingVolumeFeedback = nil  -- {vol, label} to show after tap returns

local volumeKeyTap = hs.eventtap.new({hs.eventtap.event.types.systemDefined}, function(event)
    local ok, consume = pcall(function()
        local data = event:systemKey()
        if not data then return false end

        if data.key ~= "SOUND_UP" and data.key ~= "SOUND_DOWN" and data.key ~= "MUTE" then
            return false
        end

        local mods = hs.eventtap.checkKeyboardModifiers()

        -- Cmd+Ctrl+Alt + Volume = cycle audio devices
        if mods.cmd and mods.ctrl and mods.alt and data.down then
            if data.key == "SOUND_UP" then
                cycleAudio(1)
            elseif data.key == "SOUND_DOWN" then
                cycleAudio(-1)
            end
            return true
        end

        -- Ctrl+Alt + Volume = adjust volume on current device
        if mods.ctrl and mods.alt and not mods.cmd then
            if not data.down then return true end

            local device = audioDevices[audioCycleIndex]
            if not device then return true end
            local label = device.label or "Unknown"

            if data.key == "SOUND_UP" then
                if device.isDual then
                    for _, uid in ipairs(device.outputUids) do
                        local dev = hs.audiodevice.findDeviceByUID(uid)
                        if dev then dev:setVolume(math.min(100, (dev:volume() or 0) + VOLUME_STEP)) end
                    end
                    local sample = hs.audiodevice.findDeviceByUID(device.outputUids[1])
                    pendingVolumeFeedback = {sample and math.floor(sample:volume() + 0.5) or 0, label}
                else
                    local dev = hs.audiodevice.findDeviceByUID(device.outputUid)
                    if dev then
                        dev:setVolume(math.min(100, (dev:volume() or 0) + VOLUME_STEP))
                        pendingVolumeFeedback = {math.floor(dev:volume() + 0.5), label}
                    end
                end
            elseif data.key == "SOUND_DOWN" then
                if device.isDual then
                    for _, uid in ipairs(device.outputUids) do
                        local dev = hs.audiodevice.findDeviceByUID(uid)
                        if dev then dev:setVolume(math.max(0, (dev:volume() or 0) - VOLUME_STEP)) end
                    end
                    local sample = hs.audiodevice.findDeviceByUID(device.outputUids[1])
                    pendingVolumeFeedback = {sample and math.floor(sample:volume() + 0.5) or 0, label}
                else
                    local dev = hs.audiodevice.findDeviceByUID(device.outputUid)
                    if dev then
                        dev:setVolume(math.max(0, (dev:volume() or 0) - VOLUME_STEP))
                        pendingVolumeFeedback = {math.floor(dev:volume() + 0.5), label}
                    end
                end
            elseif data.key == "MUTE" and not data["repeat"] then
                if device.isDual then
                    for _, uid in ipairs(device.outputUids) do
                        local dev = hs.audiodevice.findDeviceByUID(uid)
                        if dev then dev:setMuted(not dev:muted()) end
                    end
                    local sample = hs.audiodevice.findDeviceByUID(device.outputUids[1])
                    local muted = sample and sample:muted()
                    local vol = muted and 0 or (sample and math.floor(sample:volume() + 0.5) or 50)
                    pendingVolumeFeedback = {vol, muted and label .. " \u{00B7} Muted" or label}
                else
                    local dev = hs.audiodevice.findDeviceByUID(device.outputUid)
                    if dev then
                        dev:setMuted(not dev:muted())
                        local muted = dev:muted()
                        local vol = muted and 0 or math.floor(dev:volume() + 0.5)
                        pendingVolumeFeedback = {vol, muted and label .. " \u{00B7} Muted" or label}
                    end
                end
            end

            if pendingVolumeFeedback then
                local fb = pendingVolumeFeedback
                pendingVolumeFeedback = nil
                hs.timer.doAfter(0, function() showQuickVolume(fb[1], fb[2]) end)
            end
            return true
        end

        -- Plain volume keys: pass through to native macOS
        return false
    end)
    if ok then return consume else return false end
end)
volumeKeyTap:start()

-- Watchdog: re-enable volume eventtap if macOS disabled it
hs.timer.doEvery(3, function()
    if not volumeKeyTap:isEnabled() then
        volumeKeyTap:start()
    end
end)

-- Shared rebuild function: rebuilds device list and syncs count
local lastKnownDeviceCount = #hs.audiodevice.allOutputDevices()
local audioRebuildTimer = nil

local function rebuildAudioFull()
    buildAudioDeviceList()
    initAudioCycleIndex()
    -- Sync count AFTER rebuild (buildAudioDeviceList may create multi-output device)
    lastKnownDeviceCount = #hs.audiodevice.allOutputDevices()
end

-- Watch for system audio device changes (output switch, device add/remove)
-- dOut with same device count = normal switch → fast re-index
-- Device count changed = hotplug → debounced full rebuild
hs.audiodevice.watcher.setCallback(function(event)
    local currentCount = #hs.audiodevice.allOutputDevices()
    if currentCount ~= lastKnownDeviceCount then
        -- Device added or removed (monitor hotplug)
        lastKnownDeviceCount = currentCount
        if audioRebuildTimer then audioRebuildTimer:stop() end
        audioRebuildTimer = hs.timer.doAfter(2, function()
            audioRebuildTimer = nil
            rebuildAudioFull()
        end)
    elseif event == "dOut" then
        -- Normal switch (menu bar, our picker) — just re-index
        initAudioCycleIndex()
    end
end)
hs.audiodevice.watcher.start()

-- Kensington Expert Mouse: Button logic + scroll-to-arrow
-- Karabiner sends F18 (bottom-left) and F20 (top-left) for Kensington only.
-- Top right: left click (Karabiner: button4 → button1)
-- Bottom right: Enter (Karabiner: button2 → return_or_enter)
-- Top left (F20):    single=right-click (instant) | double=Escape
-- Bottom left (F18): button 5
-- Scroll down: normal scroll + Down arrow key
-- Scroll up: normal scroll + Up arrow key

local DOUBLE_TAP_WINDOW = 0.3

-- Button: top-left (F20): instant right-click, double=Escape
local topLeftState = { lastTapTime = 0 }

local function topLeftDown()
    local now = hs.timer.secondsSinceEpoch()
    if (now - topLeftState.lastTapTime) < DOUBLE_TAP_WINDOW then
        topLeftState.lastTapTime = 0
        hs.eventtap.keyStroke({}, "escape", 0)
    else
        topLeftState.lastTapTime = now
        hs.eventtap.rightClick(hs.mouse.absolutePosition())
    end
end

hs.hotkey.bind({}, "f20", topLeftDown)

-- Bottom-left: Karabiner sends F18, no Hammerspoon interception (passes through to system)

-- Scroll speed detection: slow scroll sends arrow keys, fast scroll passes through as scroll wheel
local SCROLL_FAST_THRESHOLD = 0.3 -- seconds between events; isolated ticks send arrows, continuous = scroll
local lastScrollTime = 0

local scrollArrowTap = hs.eventtap.new({hs.eventtap.event.types.scrollWheel}, function(event)
    local delta = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
    if delta == 0 then return false end

    local now = hs.timer.secondsSinceEpoch()
    local elapsed = now - lastScrollTime
    lastScrollTime = now

    if elapsed > SCROLL_FAST_THRESHOLD then
        -- Slow scroll: send arrow key, block scroll event
        if delta < 0 then
            hs.eventtap.keyStroke({}, "down", 0)
        else
            hs.eventtap.keyStroke({}, "up", 0)
        end
        return true -- block the scroll event
    end

    return false -- fast scroll: pass through as normal scroll
end)
scrollArrowTap:start()

-- Single screen watcher: rebuild audio, sync mic, restart sketchybar
local screenChangeTimer = nil
local screenWatcher = hs.screen.watcher.new(function()
    if screenChangeTimer then
        screenChangeTimer:stop()
        screenChangeTimer = nil
    end
    screenChangeTimer = hs.timer.doAfter(3, function()
        screenChangeTimer = nil
        rebuildAudioFull()
        if rightMonitorInputUid then
            local inputDev = hs.audiodevice.findDeviceByUID(rightMonitorInputUid)
            if inputDev then inputDev:setDefaultInputDevice() end
        end
        hs.execute("/opt/homebrew/bin/brew services restart sketchybar", true)
    end)
end)
screenWatcher:start()

