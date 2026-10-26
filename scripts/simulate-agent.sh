#!/bin/sh
# Sends a fake Claude Code session through the installed hook relay, for trying DotDesk without a real agent.
# Usage: scripts/simulate-agent.sh [session-id] [cwd]
SID="${1:-sim-$$}"
CWD="${2:-$PWD}"
HOOK="$HOME/.dotdesk/dotdesk-hook.sh"
send() { # event json-fields
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"%s"%s}' "$SID" "$CWD" "$1" "$2" | "$HOOK" claude "$1"
}
send SessionStart ',"source":"startup"'; sleep 2
send UserPromptSubmit ',"prompt":"README를 정리해줘"'; sleep 2
send PreToolUse ',"tool_name":"Read","tool_input":{"file_path":"'"$CWD"'/README.md"}'; sleep 3
send PostToolUse ',"tool_name":"Read","tool_input":{}'
send PreToolUse ',"tool_name":"Grep","tool_input":{"pattern":"TODO"}'; sleep 3
send SubagentStart ',"agent_id":"sub-1","agent_type":"Explore"'
send PreToolUse ',"agent_id":"sub-1","agent_type":"Explore","tool_name":"Glob","tool_input":{"pattern":"**/*.md"}'; sleep 3
send SubagentStop ',"agent_id":"sub-1","agent_type":"Explore"'
send PreToolUse ',"tool_name":"Edit","tool_input":{"file_path":"'"$CWD"'/README.md"}'; sleep 3
send PreToolUse ',"tool_name":"Bash","tool_input":{"command":"npm test","description":"테스트 실행"}'; sleep 3
send Stop ''
