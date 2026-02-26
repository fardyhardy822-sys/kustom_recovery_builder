#!/bin/bash
set -e

# ─────────────────────────────────────────────
#  Usage:
#   notify  → sent at workflow start
#   release → sent after build completes
# ─────────────────────────────────────────────
MODE="$1"
DEVICE="$2"
BRANCH="$3"
BUILD_DATE="$4"
COMMIT_ID="$5"
RELEASE_URL="$6"
DEVICE_TREE="$7"
CHAT_ID="$8"
TOKEN="$9"
WORKFLOW_NAME="${10}"
WORKFLOW_RUN_URL="${11}"
GITHUB_TOKEN="${12}"    # ${{ secrets.GITHUB_TOKEN }} — needed to download logs
REPO="${13}"            # ${{ github.repository }}  e.g. "naden01/kustom_recovery_builder"
RUN_ID="${14}"          # ${{ github.run_id }}

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────
escape_md() {
  echo "$1" | sed 's/[_*\[\]()~`>#+\-=|{}.!\\]/\\&/g'
}

send_message() {
  local TEXT="$1"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode text="$TEXT" \
    -d parse_mode="MarkdownV2"
}

send_file() {
  local FILE_PATH="$1"
  local CAPTION="$2"

  if [[ ! -f "$FILE_PATH" ]]; then
    echo "⚠️ Skipping: $FILE_PATH (not found)"
    return 0
  fi

  local SIZE
  SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || stat -f%z "$FILE_PATH")

  # Telegram bot limit is 50 MB — split if needed
  if (( SIZE > 50000000 )); then
    echo "⚠️ $FILE_PATH exceeds 50 MB — splitting before upload"
    split -b 45M "$FILE_PATH" "${FILE_PATH}.part_"
    local PART_NUM=1
    for PART in "${FILE_PATH}.part_"*; do
      send_file "$PART" "${CAPTION} (part ${PART_NUM})"
      (( PART_NUM++ ))
    done
    rm -f "${FILE_PATH}.part_"*
    return 0
  fi

  echo "📤 Uploading: $FILE_PATH"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendDocument" \
    -F chat_id="${CHAT_ID}" \
    -F document=@"${FILE_PATH}" \
    -F caption="${CAPTION}" \
    -F parse_mode="MarkdownV2"
}

download_github_logs() {
  local OUT_ZIP="/tmp/run_logs.zip"
  local OUT_DIR="/tmp/run_logs"
  local MERGED="/tmp/workflow_build.log"

  echo "📥 Downloading workflow logs from GitHub API..."
  HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$OUT_ZIP" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -L "https://api.github.com/repos/${REPO}/actions/runs/${RUN_ID}/logs")

  if [[ "$HTTP_STATUS" != "200" ]]; then
    echo "⚠️ Failed to download logs (HTTP $HTTP_STATUS)"
    return 1
  fi

  mkdir -p "$OUT_DIR"
  unzip -q "$OUT_ZIP" -d "$OUT_DIR"

  # Merge all .txt log files into one clean file, sorted by step number
  find "$OUT_DIR" -name "*.txt" | sort | xargs cat > "$MERGED"

  echo "$MERGED"
}

# ─────────────────────────────────────────────
#  Clean device tree URL
# ─────────────────────────────────────────────
CLEAN_TREE=$(echo "${DEVICE_TREE}" | sed 's/\.git$//')

# ─────────────────────────────────────────────
#  MODE: notify
# ─────────────────────────────────────────────
if [[ "$MODE" == "notify" ]]; then
  text=$(cat << EOF
⚙️ *Build Started*
📋 *Workflow*: \`$(escape_md "${WORKFLOW_NAME}")\`
📱 *Device*: \`$(escape_md "${DEVICE}")\`
🌿 *Branch*: \`$(escape_md "${BRANCH}")\`
📅 *Date*: \`$(escape_md "${BUILD_DATE}")\`
🔍 [Watch Live on GitHub Actions](${WORKFLOW_RUN_URL})
EOF
)
  send_message "$text"
  echo "✅ Start notification sent."
  exit 0
fi

# ─────────────────────────────────────────────
#  MODE: release
# ─────────────────────────────────────────────
if [[ "$MODE" == "release" ]]; then
  text=$(cat << EOF
🚀 *Unofficial Custom Recovery Build Released*
📋 *Workflow*: \`$(escape_md "${WORKFLOW_NAME}")\`
📱 *Device*: \`$(escape_md "${DEVICE}")\`
🌿 *Branch*: \`$(escape_md "${BRANCH}")\`
📅 *Build Date*: \`$(escape_md "${BUILD_DATE}")\`
📝 *Commit*: [${COMMIT_ID:0:7}](${CLEAN_TREE}/commit/${COMMIT_ID})
🔗 [View Release on GitHub](${RELEASE_URL})
🪵 [Full Workflow Log](${WORKFLOW_RUN_URL})
EOF
)
  send_message "$text"

  # Download and send the actual GitHub Actions logs
  LOG_FILE=$(download_github_logs)
  if [[ -f "$LOG_FILE" ]]; then
    send_file "$LOG_FILE" "🪵 *Workflow Log* \`$(escape_md "${DEVICE}")\`"
  fi

  echo "✅ Release notification sent."
  exit 0
fi

echo "❌ Unknown mode: '$MODE'. Use 'notify' or 'release'."
exit 1
