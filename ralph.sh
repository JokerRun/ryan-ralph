#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude|copilot] [max_iterations]

set -e

# Parse arguments
TOOL="amp"  # Default to amp for backwards compatibility
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "copilot" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'copilot'."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Log directory (XDG spec)
LOG_DIR="$HOME/.share/log/ralph"
mkdir -p "$LOG_DIR"

# Get branch name for log file
BRANCH_NAME=""
if [ -f "$PRD_FILE" ]; then
  BRANCH_NAME=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null | sed 's|/|_|g' || echo "")
fi
if [ -z "$BRANCH_NAME" ]; then
  BRANCH_NAME="unknown"
fi

# Log file: YYYY-MM-DD-BRANCH_NAME.log
LOG_DATE=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/${LOG_DATE}-${BRANCH_NAME}.log"

# Logging function: output to both console and log file
log() {
  echo "$@" | tee -a "$LOG_FILE"
}

log "SCRIPT_DIR: $SCRIPT_DIR"
log "PRD_FILE: $PRD_FILE"
log "PROGRESS_FILE: $PROGRESS_FILE"
log "ARCHIVE_DIR: $ARCHIVE_DIR"
log "LAST_BRANCH_FILE: $LAST_BRANCH_FILE"
log "LOG_FILE: $LOG_FILE"
log ""
log "=== Ralph session started at $(date) ==="

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    log "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    log "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

log "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  log ""
  log "==============================================================="
  log "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  log "==============================================================="

  # Run the selected tool with the ralph prompt (output to console and log)
  echo "$PWD"
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true
  elif [[ "$TOOL" == "copilot" ]]; then
    PROMPT_CONTENT=$(cat "$SCRIPT_DIR/AGENTS.md")
    OUTPUT=$(copilot --yolo -p "$PROMPT_CONTENT" 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true
  else
    # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true
  fi
  
  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    log ""
    log "Ralph completed all tasks!"
    log "Completed at iteration $i of $MAX_ITERATIONS"
    log "=== Ralph session ended at $(date) ==="
    exit 0
  fi
  
  log "Iteration $i complete. Continuing..."
  sleep 2
done

log ""
log "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
log "Check $PROGRESS_FILE for status."
log "=== Ralph session ended at $(date) ==="
exit 1
