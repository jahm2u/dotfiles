# Setup Remote Mac

Set up dotfiles on a remote Mac via SSH. The target hostname is: $ARGUMENTS

## Steps

### 1. Validate SSH connectivity

Run `ssh $ARGUMENTS "echo ok"` to confirm the host is reachable. If it fails, stop and tell the user to check their SSH config (`~/.ssh/config`).

### 2. Detect remote state

SSH to the host and run a detection script that checks:

```bash
ssh $ARGUMENTS 'bash -s' << 'DETECT'
echo "=== HOSTNAME ==="
scutil --get ComputerName 2>/dev/null || hostname
echo "=== BREW ==="
command -v brew &>/dev/null && echo "installed" || echo "missing"
echo "=== DOTFILES ==="
[[ -d "$HOME/dotfiles" ]] && echo "exists" || echo "missing"
echo "=== MAC_MONITOR ==="
[[ -f "/Library/LaunchDaemons/com.user.mac-monitor.plist" ]] && [[ -d "$HOME/.local/share/mac-monitor/venv" ]] && echo "installed" || echo "not_installed"
echo "=== MAC_ADDR ==="
ifconfig en0 2>/dev/null | awk '/ether/{print $2}' || echo "unknown"
echo "=== LAUNCH_AGENTS ==="
launchctl list 2>/dev/null | grep -c "com.user\." || echo "0"
echo "=== ENV_FILE ==="
[[ -f "$HOME/dotfiles/.env" ]] && echo "exists" || echo "missing"
DETECT
```

### 3. Report findings to user

Summarize what was detected:
- Hostname and MAC address
- Whether dotfiles repo exists (if not, tell user to clone it first: `git clone git@github.com:jahm2u/dotfiles.git ~/dotfiles`)
- Whether brew is installed (if not, warn that deps install will be skipped)
- Whether mac-monitor is already installed
- Whether .env exists

### 4. Decide what to install

Based on detection results, determine the flags needed. Key rules:
- If mac-monitor is NOT installed, ask the user: "Do you want to install Mac Monitor on this host? If yes, I need the MQTT password."
- MQTT password is the **only value that must come from the user**. Everything else is auto-detected or has safe defaults.
- If dotfiles repo is missing, stop and instruct the user to clone it first.

### 5. Build and confirm the command

Construct the install.sh command with appropriate flags. Example:

```
ssh $ARGUMENTS "cd ~/dotfiles && ./scripts/install.sh --yes --verbose \
    --mac-monitor --node-id <detected_hostname> --mqtt-pass '<user_provided>'"
```

Show the full command to the user and ask for confirmation before running it.

### 6. Execute and report

Run the command via SSH. After completion:
- Show a summary of what was installed
- If mac-monitor was installed, remind the user to check Home Assistant for the new device
- Report any errors or warnings from the output
