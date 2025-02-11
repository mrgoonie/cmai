#!/bin/bash

CONFIG_DIR="$HOME/.config/git-commit-ai"
CONFIG_FILE="$CONFIG_DIR/config"
MODEL_FILE="$CONFIG_DIR/model"
BASE_URL_FILE="$CONFIG_DIR/base_url"
PROVIDER_FILE="$CONFIG_DIR/provider"

# Debug mode flag
DEBUG=false
# Push flag
PUSH=false
# Default providers and URLs
PROVIDER_OPENROUTER="openrouter"
PROVIDER_OLLAMA="ollama"
PROVIDER_CUSTOM="custom"

OPENROUTER_URL="https://openrouter.ai/api/v1"
OLLAMA_URL="http://localhost:11434/api"

# Default provider and base URL
PROVIDER="$PROVIDER_OPENROUTER"
BASE_URL="$OPENROUTER_URL"

# Default models for providers
OLLAMA_MODEL="codellama"

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

# Function to save provider
save_provider() {
    echo "$1" >"$PROVIDER_FILE"
    chmod 600 "$PROVIDER_FILE"
    debug_log "Provider saved to config file"
}

# Function to get provider
get_provider() {
    if [ -f "$PROVIDER_FILE" ]; then
        cat "$PROVIDER_FILE"
    else
        echo "$PROVIDER_OPENROUTER"
    fi
}

# Function to get base URL
get_base_url() {
    if [ -f "$BASE_URL_FILE" ]; then
        cat "$BASE_URL_FILE"
    else
        echo "$OPENROUTER_URL"  # Default base URL
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
    --use-ollama)
        PROVIDER="$PROVIDER_OLLAMA"
        BASE_URL="$OLLAMA_URL"
        save_provider "$PROVIDER"
        save_base_url "$BASE_URL"
        shift
        ;;
    --use-openrouter)
        PROVIDER="$PROVIDER_OPENROUTER"
        BASE_URL="$OPENROUTER_URL"
        save_provider "$PROVIDER"
        save_base_url "$BASE_URL"
        shift
        ;;
    --use-custom)
        if [ -z "$2" ]; then
            echo "Error: --use-custom requires a base URL"
            exit 1
        fi
        PROVIDER="$PROVIDER_CUSTOM"
        BASE_URL="$2"
        save_provider "$PROVIDER"
        save_base_url "$BASE_URL"
        shift 2
        ;;
    --push | -p)
        PUSH=true
        shift
        ;;
    -h | --help)
        echo "Usage: cmai [options] [api_key]"
        echo ""
        echo "Options:"
        echo "  --debug               Enable debug mode"
        echo "  --push, -p            Push changes after commit"
        echo "  --model <model>       Use specific model (default: google/gemini-flash-1.5-8b)"
        echo "  --use-ollama          Use Ollama as provider (saves for future use)"
        echo "  --use-openrouter      Use OpenRouter as provider (saves for future use)"
        echo "  --use-custom <url>    Use custom provider with base URL (saves for future use)"
        echo "  -h, --help            Show this help message"
        echo ""
        echo "Examples:"
        echo "  cmai your_api_key                    # First time setup with API key"
        echo "  cmai --use-ollama                    # Switch to Ollama provider"
        echo "  cmai --use-openrouter                # Switch back to OpenRouter"
        echo "  cmai --use-custom http://my-api.com  # Use custom provider"
        exit 0
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

if [ -z "$API_KEY" ] && [ "$PROVIDER" = "$PROVIDER_OPENROUTER" ]; then
    echo "No API key found. Please provide the OpenRouter API key as an argument"
    echo "Usage: cmai [--debug] [--push|-p] [--use-ollama] [--model <model_name>] [--base-url <url>] <api_key>"
    exit 1
fi

# Set default model based on provider
if [ "$PROVIDER" = "$PROVIDER_OLLAMA" ]; then
    [ -z "$MODEL" ] && MODEL="$OLLAMA_MODEL"
    # Check if Ollama is running
    if ! pgrep ollama >/dev/null; then
        echo "Error: Ollama server not running. Please start Ollama first:"
        echo "ollama serve"
        exit 1
    fi
    # Check if model exists using ollama ls
    if ! ollama ls | awk '{print $1}' | grep -q "^${MODEL}$"; then
        echo "Error: Model '$MODEL' not found in Ollama. Please pull it first:"
        echo "ollama pull $MODEL"
        exit 1
    fi
fi

# Stage all changes
debug_log "Staging all changes"
git add .

# Get git changes and clean up any tabs
# Get changes and format them appropriately for the provider
if [ "$PROVIDER" = "$PROVIDER_OLLAMA" ]; then
    CHANGES=$(git diff --cached --name-status | tr '\t' ' ' | tr '\n' ' ' | sed 's/  */ /g')
else
    CHANGES=$(git diff --cached --name-status | tr '\t' ' ' | sed 's/  */ /g')
fi
# Get git diff for context
DIFF_CONTENT=$(git diff --cached)
debug_log "Git changes detected" "$CHANGES"

if [ -z "$CHANGES" ]; then
    echo "No staged changes found. Please stage your changes using 'git add' first."
    exit 1
fi

# Prepare the request body based on provider
if [ "$PROVIDER" = "$PROVIDER_OLLAMA" ]; then
    # For Ollama, prepare a simpler JSON without escapes
    REQUEST_BODY=$(
        cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {
      "role": "system",
      "content": "Provide a detailed commit message with a title and description. The title should be a concise summary (max 50 characters). The description should provide more context about the changes, explaining why the changes were made and their impact. Use bullet points if multiple changes are significant. If it's just some minor changes, use 'fix' instead of 'feat'. Do not include any explanation in your response, only return a commit message content, do not wrap it in backticks"
    },
    {
      "role": "user",
      "content": "Generate a commit message in conventional commit standard format based on the following file changes: $CHANGES. Commit message title must be a concise summary (max 100 characters). If it's just some minor changes, use 'fix' instead of 'feat'. Do not include any explanation in your response, only return a commit message content, do not wrap it in backticks"
    }
  ]
}
EOF
    )
else
    # For OpenRouter and custom providers
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
fi
debug_log "Request body prepared with model: $MODEL" "$REQUEST_BODY"

# Make the API request
case "$PROVIDER" in
"$PROVIDER_OLLAMA")
    debug_log "Making API request to Ollama"
    ENDPOINT="api/generate"
    HEADERS=(-H "Content-Type: application/json")
    BASE_URL="http://localhost:11434"
    # Format changes into a single line
    FORMATTED_CHANGES=$(echo "$CHANGES" | tr '\n' ' ' | sed 's/  */ /g')
    FORMATTED_DIFF=$(echo "$DIFF_CONTENT" | tr '\n' '\\n' | sed 's/"/\\"/g')
    REQUEST_BODY=$(cat <<EOF
{
  "model": "$MODEL",
  "prompt": "Generate a conventional commit message for these changes: $FORMATTED_CHANGES. Format should be: <type>(<scope>): <subject>\n\n<body>\n\nRules:\n- Type: feat, fix, docs, style, refactor, perf, test, chore\n- Subject: 50-70 chars, imperative mood, no period\n- Body: explain what and why\n- Use fix for minor changes",
  "stream": false
}
EOF
)
    ;;
"$PROVIDER_OPENROUTER")
    debug_log "Making API request to OpenRouter"
    ENDPOINT="chat/completions"
    HEADERS=(-H "Authorization: Bearer ${API_KEY}")
    REQUEST_BODY=$(
        cat <<EOF
{
  "stream": false,
  "model": "$MODEL",
  "messages": [
    {
      "role": "system",
      "content": "You are a git commit message generator. Create conventional commit messages."
    },
    {
      "role": "user",
      "content": "Generate a commit message for these changes:\n\nFile changes:\n$CHANGES\n\nDiff:\n$DIFF_CONTENT\n\nFormat:\n<type>(<scope>): <subject>\n\n<body>\n\nImportant:\n- Type must be one of: feat, fix, docs, style, refactor, perf, test, chore\n- Subject line should be 50-70 characters\n- Use imperative mood in subject line\n- Do not end subject line with period\n- Body should explain what and why, not how\n- For minor changes, use fix instead of feat\n\nResponse should be the commit message only, no explanations."
    }
  ]
}
EOF
    )
    ;;
"$PROVIDER_CUSTOM")
    debug_log "Making API request to custom provider"
    ENDPOINT="chat/completions"
    [ ! -z "$API_KEY" ] && HEADERS=(-H "Authorization: Bearer ${API_KEY}")
    REQUEST_BODY=$(
        cat <<EOF
{
  "stream": false,
  "model": "$MODEL",
  "messages": [
    {
      "role": "system",
      "content": "You are a git commit message generator. Create conventional commit messages."
    },
    {
      "role": "user",
      "content": "Generate a commit message for these changes:\n\nFile changes:\n$CHANGES\n\nDiff:\n$DIFF_CONTENT\n\nFormat:\n<type>(<scope>): <subject>\n\n<body>\n\nImportant:\n- Type must be one of: feat, fix, docs, style, refactor, perf, test, chore\n- Subject line should be 50-70 characters\n- Use imperative mood in subject line\n- Do not end subject line with period\n- Body should explain what and why, not how\n- For minor changes, use fix instead of feat\n\nResponse should be the commit message only, no explanations."
    }
  ]
}
EOF
    )
    ;;
esac

RESPONSE=$(curl -s -X POST "$BASE_URL/$ENDPOINT" \
    "${HEADERS[@]}" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY")
debug_log "API response received" "$RESPONSE"

# Extract and clean the commit message
case "$PROVIDER" in
"$PROVIDER_OLLAMA")
    # For Ollama, extract content from non-streaming response
    if echo "$RESPONSE" | grep -q "404 page not found"; then
        echo "Error: Ollama API endpoint not found. Make sure Ollama is running and try again."
        echo "Run: ollama serve"
        exit 1
    fi
    if echo "$RESPONSE" | grep -q "error"; then
        ERROR=$(echo "$RESPONSE" | jq -r '.error')
        echo "Error from Ollama: $ERROR"
        exit 1
    fi
    COMMIT_FULL=$(echo "$RESPONSE" | jq -r '.response // empty')
    if [ -z "$COMMIT_FULL" ]; then
        echo "Error: Failed to get response from Ollama. Response: $RESPONSE"
        exit 1
    fi
    ;;
"$PROVIDER_OPENROUTER" | "$PROVIDER_CUSTOM")
    # For OpenRouter and custom providers
    COMMIT_FULL=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
    
    # If jq fails or returns null, fallback to grep method
    if [ -z "$COMMIT_FULL" ] || [ "$COMMIT_FULL" = "null" ]; then
        COMMIT_FULL=$(echo "$RESPONSE" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
    fi
    ;;
esac

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
