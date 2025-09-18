# Telegram Hook Implementation Plan

## Overview
Create a sophisticated Telegram bot hook for Claude Code that supports:
- Multiple Claude instances communicating through one Telegram chat
- Dual-input mode (respond via Terminal OR Telegram)
- Session-based message correlation
- First-response-wins logic

## Implementation Checklist

### Phase 1: Setup and Core Structure
- [x] Create `telegram_interactive.py` hook script
- [x] Add required imports and environment variables
- [x] Set up bot token and chat ID configuration
- [x] Create session directory structure

### Phase 2: Session Management
- [x] Implement `create_session()` function
- [x] Implement `save_session()` for JSON storage
- [x] Implement `load_session()` for retrieval
- [x] Implement `cleanup_old_sessions()` with 1-hour expiry

### Phase 3: Telegram Communication
- [x] Implement `send_telegram_message()` with retry logic
- [x] Implement `get_telegram_updates()` for polling
- [x] Implement `poll_for_telegram_reply()` with message correlation
- [x] Add error handling for network failures

### Phase 4: Terminal Input
- [x] Implement `display_terminal_prompt()` with formatting
- [x] Implement `poll_for_terminal_input()` function
- [x] Add terminal UI formatting and colors
- [x] Handle terminal input validation

### Phase 5: Dual-Input Logic
- [x] Implement threading for concurrent input monitoring
- [x] Create queue-based first-response-wins system
- [x] Add proper thread cleanup and cancellation
- [ ] Test race conditions between inputs

### Phase 6: Message Formatting
- [x] Create `format_message()` for different tool types
- [x] Add session ID and instance ID to messages
- [x] Implement response parsing (yes/no/custom)
- [ ] Add special command support (/info, /list)

### Phase 7: Hook Integration
- [x] Update `.claude/settings.json` configuration
- [x] Add environment variable support
- [ ] Test with PreToolUse hooks
- [ ] Document configuration options

### Phase 8: Testing
- [x] Test basic message sending
- [x] Test terminal input functionality
- [x] Test Telegram reply correlation
- [x] Test with single Claude instance
- [ ] Test with multiple concurrent instances
- [ ] Test timeout scenarios
- [ ] Test network failure recovery

### Phase 9: Documentation
- [ ] Write usage documentation
- [ ] Add configuration examples
- [ ] Document troubleshooting steps
- [ ] Create example workflows

## Configuration

### Environment Variables
Credentials are stored in `~/.claude/.env` file:
```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
CLAUDE_TERMINAL_INPUT=true
CLAUDE_TELEGRAM_ONLY=false
```

### Hook Configuration
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "uv run ~/.claude/hooks/telegram_interactive.py"
          }
        ]
      }
    ]
  }
}
```

### Python Implementation
The Python script loads environment variables using:
```python
from dotenv import load_dotenv
import os

# Load environment variables from ~/.claude/.env
load_dotenv(os.path.expanduser("~/.claude/.env"))

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
```

## Testing Scenarios

1. **Single Instance Test**
   - Send a bash command
   - Verify terminal prompt appears
   - Verify Telegram message sent
   - Test both response methods

2. **Concurrent Instance Test**
   - Launch two Claude instances
   - Trigger hooks simultaneously
   - Verify correct message routing
   - Test response correlation

3. **Error Handling Test**
   - Disable network and test
   - Test timeout scenarios
   - Test invalid responses
   - Verify graceful degradation

## Notes
- Session files stored in `~/.claude/telegram_sessions/`
- Sessions auto-expire after 1 hour
- First response (terminal or Telegram) wins
- Thread cleanup happens automatically