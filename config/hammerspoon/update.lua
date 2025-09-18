-- Function to show translation in a floating webview
function showTranslation(originalText, translatedText)
  -- Close any existing windows
  if translationWebview then
    translationWebview:delete()
    translationWebview = nil
  end
  
  -- Use the active screen instead of mainScreen
  local activeScreen = hs.screen.mainScreen()
  local screenFrame = activeScreen:frame()
  local width = 500
  local height = 200
  
  -- Position on the top-right corner of the active screen
  local xPos = screenFrame.x + screenFrame.w - width - 20
  local yPos = screenFrame.y + 50
  
  -- Create a new webview window
  translationWebview = hs.webview.new({x = xPos, y = yPos, w = width, h = height})
    :windowStyle({"titled", "closable", "resizable"})
    :windowTitle("Translation")
    :closeOnEscape(true)
    :html([[<!DOCTYPE html>
<html>
<head>
<style>
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  margin: 10px;
  background-color: #f8f8f8;
  color: #333;
}
.container {
  display: flex;
  flex-direction: column;
  height: 100%;
}
.box {
  padding: 15px;
  border-radius: 5px;
  overflow-wrap: break-word;
  background-color: #e8f5e9;
  border-left: 4px solid #43a047;
}
.content {
  font-size: 18px;
  white-space: pre-wrap;
}
</style>
</head>
<body>
<div class="container">
  <div class="box">
    <div class="content">]] .. translatedText .. [[</div>
  </div>
</div>
</body>
</html>]])
    :allowTextEntry(true)
    :show()
  
  -- Set up autoclose timer that checks for mouse position
  local closeTimer = nil
  closeTimer = hs.timer.doAfter(7, function()
    if translationWebview then
      -- Get current mouse position
      local mousePos = hs.mouse.absolutePosition()
      local webviewFrame = translationWebview:frame()
      
      -- Check if mouse is over the webview
      local mouseIsOver = mousePos.x >= webviewFrame.x and 
                          mousePos.x <= webviewFrame.x + webviewFrame.w and
                          mousePos.y >= webviewFrame.y and
                          mousePos.y <= webviewFrame.y + webviewFrame.h
      
      -- Only close if mouse is not over the webview
      if not mouseIsOver then
        translationWebview:delete()
        translationWebview = nil
      else
        -- If mouse is over, check again in 1 second
        closeTimer = hs.timer.doAfter(1, function() 
          if translationWebview then
            local mousePos = hs.mouse.absolutePosition()
            local webviewFrame = translationWebview:frame()
            local mouseIsOver = mousePos.x >= webviewFrame.x and 
                              mousePos.x <= webviewFrame.x + webviewFrame.w and
                              mousePos.y >= webviewFrame.y and
                              mousePos.y <= webviewFrame.y + webviewFrame.h
            if not mouseIsOver then
              translationWebview:delete()
              translationWebview = nil
            end
          end
        end)
      end
    end
  end)
end
