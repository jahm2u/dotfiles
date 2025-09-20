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
    local envPath = os.getenv("HOME") .. "/.hammerspoon/.env"
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

-- Auto-sync calendars every hour for Sketchybar meeting widget
function syncCalendars()
    local task = hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            print("Calendar sync completed successfully")
        else
            print("Calendar sync failed: " .. (stdErr or "unknown error"))
        end
    end, {"-c", "$HOME/.config/sketchybar/plugins/sync_calendars.sh 2>&1"})
    task:start()
end

-- Run calendar sync on startup
syncCalendars()

-- Schedule calendar sync every hour (3600 seconds)
calendarSyncTimer = hs.timer.doEvery(3600, syncCalendars)

