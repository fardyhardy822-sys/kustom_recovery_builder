#!/bin/bash
set -e

DEVICE="$1"
BRANCH="$2"
BUILD_DATE="$3"
COMMIT_ID="$4"
RELEASE_URL="$5"
DEVICE_TREE="$6"
CHAT_ID="$7"
TOKEN="$8"
WORKFLOW_NAME="$9"   # New parameter

send_file() {
  local FILE_PATH="$1"
  local CAPTION="$2"

  if [[ ! -f "$FILE_PATH" ]]; then
    echo "⚠️ Skipping: $FILE_PATH (not found)"
    return 0
  fi

  echo "📤 Uploading: $FILE_PATH"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendDocument" \
    -F chat_id="${CHAT_ID}" \
    -F document=@"${FILE_PATH}" \
    -F caption="${CAPTION}" \
    -F parse_mode="MarkdownV2"
}

# Clean the device tree URL (removes .git if present)
CLEAN_TREE=$(echo "${DEVICE_TREE}" | sed 's/\.git$//')

# === Build Telegram message ===
text=$(
  cat << EOF
🚀 *Unofficial Custom Recovery Build Released*
📋 *Workflow*: \`${WORKFLOW_NAME}\`
📱 *Device*: \`${DEVICE}\`
🌿 *Branch*: \`${BRANCH}\`
📅 *Build Date*: \`${BUILD_DATE}\`
📝 *Commit*: [${COMMIT_ID:0:7}](${CLEAN_TREE}/commit/${COMMIT_ID})
🔗 [View Release on GitHub](${RELEASE_URL})
EOF
)

# === Send message ===
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$text" \
  -d parse_mode="MarkdownV2"

# === Send build log if available ===
if [[ -f build.log ]]; then
  send_file "build.log" "🪵 *Build Log*"
fi
