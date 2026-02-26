#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────
#  Positional args — same for both modes, unused ones are ""
#
#  $1  MODE            "notify" | "release"
#  $2  DEVICE          e.g. LH8n
#  $3  BRANCH          e.g. android-12.1
#  $4  BUILD_DATE      e.g. 2025-01-01
#  $5  COMMIT_ID       full SHA (release only)
#  $6  RELEASE_URL     GitHub release URL (release only)
#  $7  DEVICE_TREE     raw git URL (release only, .git stripped inside)
#  $8  CHAT_ID         Telegram chat/channel ID
#  $9  TOKEN           Telegram bot token
#  $10 WORKFLOW_NAME   ${{ github.workflow }}
#  $11 WORKFLOW_RUN_URL full actions run URL
#  $12 GITHUB_TOKEN    ${{ secrets.GITHUB_TOKEN }} (release only)
#  $13 REPO            ${{ github.repository }}    (release only)
#  $14 RUN_ID          ${{ github.run_id }}        (release only)
# ─────────────────────────────────────────────────────────────

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
GITHUB_TOKEN="${12}"
REPO="${13}"
RUN_ID="${14}"

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────
escape_md() {
  # Escapes all MarkdownV2 reserved characters
  printf '%s' "$1" | sed 's/[_*\[\]()~`>#+\-=|{}.!\\]/\\&/g'
}

send_message() {
  local TEXT="$1"
  RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode text="$TEXT" \
    -d parse_mode="MarkdownV2")
  echo "Telegram response: $RESPONSE"
  if echo "$RESPONSE" | grep -q '"ok":false'; then
    echo "❌ Failed to send Telegram message"
    echo "$RESPONSE"
    exit 1
  fi
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

  if (( SIZE > 50000000 )); then
    echo "⚠️ $FILE_PATH exceeds 50 MB — splitting"
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
  find "$OUT_DIR" -name "*.txt" | sort | xargs cat > "$MERGED"
  echo "$MERGED"
}

# ─────────────────────────────────────────────
#  Validate required args
# ─────────────────────────────────────────────
if [[ -z "$CHAT_ID" || -z "$TOKEN" ]]; then
  echo "❌ CHAT_ID or TOKEN is empty — check argument positions!"
  echo "    CHAT_ID=[$CHAT_ID]"
  echo "    TOKEN=[$TOKEN]"
  exit 1
fi

echo "🔍 Debug: MODE=$MODE DEVICE=$DEVICE BRANCH=$BRANCH CHAT_ID=[set] TOKEN=[set]"

# ─────────────────────────────────────────────
#  MODE: notify
# ─────────────────────────────────────────────
if [[ "$MODE" == "notify" ]]; then
  text=$(cat << EOF
⚙️ *Build Started*
📋 *Workflow*: \`$(escape_md "${WORKFLOW_NAME}")\`
📱 *Device*: \`$(escape_md "${DEVICE}")\`
🌿 *Branch*: \`$(escape_md "${BRANCH}")\`
🔍 [Watch on GitHub Actions](${WORKFLOW_RUN_URL})
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
  CLEAN_TREE=$(echo "${DEVICE_TREE}" | sed 's/\.git$//')

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

  LOG_FILE=$(download_github_logs)
  if [[ -f "$LOG_FILE" ]]; then
    send_file "$LOG_FILE" "🪵 *Workflow Log* \`$(escape_md "${DEVICE}")\`"
  fi

  echo "✅ Release notification sent."
  exit 0
fi

echo "❌ Unknown mode: '$MODE'. Use 'notify' or 'release'."
exit 1
