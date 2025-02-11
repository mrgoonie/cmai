#!/bin/bash

CONFIG_DIR="$HOME/.config/git-commit-ai"
CONFIG_FILE="$CONFIG_DIR/config"
MODEL_FILE="$CONFIG_DIR/model"
BASE_URL_FILE="$CONFIG_DIR/base_url"

# Debug mode flag
DEBUG=false
# Push flag
PUSH=false
# Default base URL
BASE_URL="https://openrouter.ai/api/v1"

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

# Function to save model
save_model() {
    echo "$1" >"$MODEL_FILE"
    chmod 600 "$MODEL_FILE"
    debug_log "Model saved to config file"
}

# Function to get model
get_model() {
    if [ -f "$MODEL_FILE" ]; then
        cat "$MODEL_FILE"
    else
        echo "google/gemini-flash-1.5-8b"  # Default model
    fi
}

# Function to save base URL
save_base_url() {
    echo "$1" >"$BASE_URL_FILE"
    chmod 600 "$BASE_URL_FILE"
    debug_log "Base URL saved to config file"
}

# Function to get base URL
get_base_url() {
    if [ -f "$BASE_URL_FILE" ]; then
        cat "$BASE_URL_FILE"
    else
        echo "https://openrouter.ai/api/v1"  # Default base URL
    fi
}

# Get saved model or use default
MODEL=$(get_model)

# Get saved base URL or use default
BASE_URL=$(get_base_url)

debug_log "Script started"
debug_log "Config directory: $CONFIG_DIR"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
debug_log "Config directory created/checked"

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
            save_model "$MODEL"
            debug_log "New model saved: $MODEL"
            shift 2
        else
            echo "Error: --model requires a valid model name"
            exit 1
        fi
        ;;
    --base-url)
        # Check if next argument exists and doesn't start with -
        if [[ -n "$2" && "$2" != -* ]]; then
            BASE_URL="$2"
            save_base_url "$BASE_URL"
            debug_log "New base URL saved: $BASE_URL"
            shift 2
        else
            echo "Error: --base-url requires a valid URL"
            exit 1
        fi
        ;;
    *)
        API_KEY_ARG="$1"
        shift
        ;;
    esac
done

# Check if API key is provided as argument or exists in config
if [ ! -z "$API_KEY_ARG" ]; then
    debug_log "New API key provided as argument"
    save_api_key "$API_KEY_ARG"
fi

API_KEY=$(get_api_key)
debug_log "API key retrieved from config"

if [ -z "$API_KEY" ]; then
    echo "No API key found. Please provide the OpenRouter API key as an argument"
    echo "Usage: cmai [--debug] [--push|-p] [--model <model_name>] [--base-url <url>] <api_key>"
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
      "content": "Provide a detailed commit message with a title and description. The title should be a concise summary (max 50 characters). The description should provide more context about the changes, explaining why the changes were made and their impact. Use bullet points if multiple changes are significant. If it's just some minor changes, use 'fix' instead of 'feat'. Do not include any explanation in your response, only return a commit message content, do not wrap it in backticks"
    },
    {
      "role": "user",
      "content": "Generate a commit message in conventional commit standard format based on the following file changes:\\n\`\`\`\\n${CHANGES}\\n\`\`\`\\n- Commit message title must be a concise summary (max 100 characters)\\n- If it's just some minor changes, use 'fix' instead of 'feat'\\n- IMPORTANT: Do not include any explanation in your response, only return a commit message content, do not wrap it in backticks"
    }
  ]
}
EOF
)
debug_log "Request body prepared with model: $MODEL" "$REQUEST_BODY"

# Make the API request
debug_log "Making API request to OpenRouter"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat/completions" \
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
