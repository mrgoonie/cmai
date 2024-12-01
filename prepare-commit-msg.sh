#!/usr/bin/env bash

set -euo pipefail

# Debug mode flag
DEBUG=false
# Model selection
MODEL="google/gemini-flash-1.5-8b"
# Commit message filename
COMMIT_MSG_FILENAME=".git/COMMIT_EDITMSG"
# Either send patch or only filenames
OPEN_SOURCE=false
# https://openrouter.ai/ API key
OPENROUTER_API_KEY=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG=true
            shift
            ;;
        --model)
            # Check if next argument exists and doesn't start with -
            if [[ -n "$2" && "$2" != -* ]]; then
                MODEL="$2"
                shift 2
            else
                echo "Error: --model requires a valid model name"
                exit 1
            fi
            ;;
        --commit-msg-filename)
            COMMIT_MSG_FILENAME="$2"
            shift 2
            ;;
        --openrouter-api-key)
            OPENROUTER_API_KEY="$2"
            shift 2
            ;;
        --open-source)
            OPEN_SOURCE=true
            shift 1
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Debug function
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo "DEBUG: $1"
        if [ -n "$2" ]; then
            echo "DEBUG: Content >>>"
            echo "$2"
            echo "DEBUG: <<<"
        fi
    fi
}

debug_log "MODEL=$MODEL"
debug_log "COMMIT_MSG_FILENAME=${COMMIT_MSG_FILENAME}"

# Get git changes
if [ "$OPEN_SOURCE" = true ]; then
    CHANGES=$(git diff --cached | jq -Rsa .)
else
    CHANGES=$(git diff --cached --name-status | jq -Rsa .)
fi
debug_log "Git changes detected" "$CHANGES"

if [ -z "$CHANGES" ]; then
    echo "INFO: No staged changes found. Please stage your changes using 'git add' first."
    exit 0
fi

debug_log "Script started"

if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "ERROR: No API key found. Please provide the OpenRouter API key as an argument or set OPENROUTER_API_KEY environment variable."
    echo "Usage: ./git-commit.sh [--debug] [--model <model_name>] [--commit-msg-filename <filename>] [--openrouter-api-key <key>]"
    exit 1
fi

# Prepare the request body
REQUEST_BODY=$(cat <<EOF
{
  "stream": false,
  "model": "$MODEL",
  "messages": [
    {
      "role": "user",
      "content": "Generate a commit message in conventional commit standard format based on the following file changes:\n\`\`\`\n${CHANGES}\n\`\`\`\n- Commit message title must be a concise summary (max 100 characters)\n- IMPORTANT: Do not include any explanation in your response, only return a commit message content, do not wrap it in backticks"
    },
    {
      "role": "system",
      "content": "Provide a detailed commit message with a title and description. The title should be a concise summary (max 50 characters). The description should provide more context about the changes, explaining why the changes were made and their impact. Use bullet points if multiple changes are significant."
    }
  ]
}
EOF
)
debug_log "Request body prepared with model: $MODEL" "$REQUEST_BODY"

# Make the API request
debug_log "Making API request to OpenRouter"
RESPONSE=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")
debug_log "API response received" "$RESPONSE"

# Extract and clean the commit message
# First, try to parse the response as JSON and extract the content
COMMIT_FULL=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')

# If jq fails or returns null, fallback to grep method
if [ -z "$COMMIT_FULL" ] || [ "$COMMIT_FULL" = "null" ]; then
    COMMIT_FULL=$(echo "$RESPONSE" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
fi

# Clean the message:
# 1. Preserve the structure of the commit message
# 2. Clean up escape sequences
COMMIT_FULL=$(echo "$COMMIT_FULL" | \
    sed 's/\\n/\n/g' | \
    sed 's/\\r//g' | \
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | \
    sed 's/\\[[:alpha:]]//g')

debug_log "Extracted commit message" "$COMMIT_FULL"

if [ -z "$COMMIT_FULL" ]; then
    echo "Failed to generate commit message. API response:"
    echo "$RESPONSE"
    exit 1
fi

debug_log "$COMMIT_FULL"

# Write the commit message to .git/COMMIT_EDITMSG
echo "$COMMIT_FULL" > "$COMMIT_MSG_FILENAME"
