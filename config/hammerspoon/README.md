# Hammerspoon Configuration

## Environment Setup

This Hammerspoon configuration requires an OpenAI API key for the translation feature.

### Setting up the API Key

1. Copy the example environment file:
   ```bash
   cp ~/.config/hammerspoon/.env.example ~/.config/hammerspoon/.env
   ```

2. Edit the `.env` file and add your OpenAI API key:
   ```bash
   OPENAI_API_KEY=your_actual_api_key_here
   ```

3. Reload Hammerspoon config (the .env will be loaded automatically)

### Security Note

The `.env` file is gitignored and will not be committed to the repository. Never commit your actual API keys to version control.

## Features

- **Translation** (Alt+D): Translate selected text between English and Portuguese
- **Translation Popup** (Alt+S): Show translation in a floating window
- **Brightness Toggle** (Ctrl+Alt+Shift+B): Toggle screen brightness between 0% and previous level (no notification shown)
- **Mouse Highlight** (Hyper+D): Draw a circle around the mouse pointer
- **Network Ping** (Hyper+G): Check network latency