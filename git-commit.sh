#!/bin/bash

CONFIG_DIR="$HOME/.config/git-commit-ai"
CONFIG_FILE="$CONFIG_DIR/config"

# Debug mode flag
DEBUG=false
# Push flag
PUSH=false
# Model selection
MODEL="google/gemini-flash-1.5-8b"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    --debug)
        DEBUG=true
        shift
        ;;
    --push | -p)
        PUSH=true
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
    *)
        API_KEY_ARG="$1"
        shift
        ;;
    esac
done

# Debug function
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo "DEBUG: $1"
        if [ ! -z "$2" ]; then
            echo "DEBUG: Content >>>"
            echo "$2"
            echo "DEBUG: <<<"
        fi
    fi
}

debug_log "Script started"
debug_log "Config directory: $CONFIG_DIR"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
debug_log "Config directory created/checked"

# Function to save API key
save_api_key() {
    echo "$1" >"$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    debug_log "API key saved to config file"
}

# Function to get API key
get_api_key() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo ""
    fi
}

# Check if API key is provided as argument or exists in config
if [ ! -z "$API_KEY_ARG" ]; then
    debug_log "New API key provided as argument"
    save_api_key "$API_KEY_ARG"
fi

API_KEY=$(get_api_key)
debug_log "API key retrieved from config"

if [ -z "$API_KEY" ]; then
    echo "No API key found. Please provide the OpenRouter API key as an argument"
    echo "Usage: ./git-commit.sh [--debug] [--push|-p] [--model <model_name>] <api_key>"
    exit 1
fi

# Stage all changes
debug_log "Staging all changes"
git add .

# Get git changes
CHANGES=$(git diff --cached --name-status)
debug_log "Git changes detected" "$CHANGES"

if [ -z "$CHANGES" ]; then
    echo "No staged changes found. Please stage your changes using 'git add' first."
    exit 1
fi

# Prepare the request body
REQUEST_BODY=$(
    cat <<EOF
{
  "stream": false,
  "model": "$MODEL",
  "messages": [
    {
      "role": "system",
      "content": "Provide a detailed commit message with a title and description. The title should be a concise summary (max 50 characters). The description should provide more context about the changes, explaining why the changes were made and their impact. Use bullet points if multiple changes are significant. If it's just a minor change, use 'fix' in the title. Do not include any explanation in your response, only return a commit message content, do not wrap it in backticks"
    },
    {
      "role": "user",
      "content": "Generate a commit message in conventional commit standard format based on the following file changes:\n\`\`\`\n${CHANGES}\n\`\`\`\n- Commit message title must be a concise summary (max 100 characters)\n- If it's just a minor change, use 'fix' in the title\n- IMPORTANT: Do not include any explanation in your response, only return a commit message content, do not wrap it in backticks"
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
COMMIT_FULL=$(echo "$COMMIT_FULL" |
    sed 's/\\n/\n/g' |
    sed 's/\\r//g' |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
    sed 's/\\[[:alpha:]]//g')

debug_log "Extracted commit message" "$COMMIT_FULL"

if [ -z "$COMMIT_FULL" ]; then
    echo "Failed to generate commit message. API response:"
    echo "$RESPONSE"
    exit 1
fi

# Execute git commit
debug_log "Executing git commit"
git commit -m "$COMMIT_FULL"

if [ $? -ne 0 ]; then
    echo "Failed to commit changes"
    exit 1
fi

# Push to origin if flag is set
if [ "$PUSH" = true ]; then
    debug_log "Pushing to origin"
    git push origin

    if [ $? -ne 0 ]; then
        echo "Failed to push changes"
        exit 1
    fi
    echo "Successfully pushed changes to origin"
fi

echo "Successfully committed and pushed changes with message:"
echo "$COMMIT_FULL"
debug_log "Script completed successfully"
