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
PROVIDER_LMSTUDIO="lmstudio"
PROVIDER_CUSTOM="custom"

OPENROUTER_URL="https://openrouter.ai/api/v1"
OLLAMA_URL="http://localhost:11434/api"
LMSTUDIO_URL="http://localhost:1234/v1"

# Default models for providers
OLLAMA_MODEL="codellama"
OPENROUTER_MODEL="google/gemini-flash-1.5-8b"
LMSTUDIO_MODEL="default"

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
    mkdir -p "$CONFIG_DIR"
    # Remove any quotes or extra arguments from the API key
    API_KEY=$(echo "$1" | cut -d' ' -f1)
    echo "$API_KEY" >"$CONFIG_FILE"
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
        echo "" # Return empty string to let provider-specific default be used
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
        echo "$OPENROUTER_URL" # Default base URL
    fi
}

# Replace all linebreaks with proper JSON escaping
function replace_linebreaks() {
    local input="$1"
    printf '%s' "$input" | tr '\n' '\\n' | sed 's/\n$//'
}

# Load saved provider and base URL or use defaults
PROVIDER=$(get_provider)
BASE_URL=$(get_base_url)

# If no saved provider, use defaults
if [ -z "$PROVIDER" ]; then
    PROVIDER="$PROVIDER_OPENROUTER"
    BASE_URL="$OPENROUTER_URL"
fi

# Default models for providers
OLLAMA_MODEL="codellama"
OPENROUTER_MODEL="google/gemini-flash-1.5-8b"
LMSTUDIO_MODEL="default"

# Get saved model or use default based on provider
MODEL=$(get_model)
if [ -z "$MODEL" ]; then
    case "$PROVIDER" in
    "$PROVIDER_OLLAMA")
        MODEL="$OLLAMA_MODEL"
        ;;
    "$PROVIDER_OPENROUTER")
        MODEL="$OPENROUTER_MODEL"
        ;;
    esac
fi

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
        MODEL="$OLLAMA_MODEL"
        save_provider "$PROVIDER"
        save_base_url "$BASE_URL"
        save_model "$MODEL"
        shift
        ;;
    --use-openrouter)
        PROVIDER="$PROVIDER_OPENROUTER"
        BASE_URL="$OPENROUTER_URL"
        MODEL="$OPENROUTER_MODEL"
        save_provider "$PROVIDER"
        save_base_url "$BASE_URL"
        save_model "$MODEL"
        shift
        ;;
    --use-lmstudio)
        PROVIDER="$PROVIDER_LMSTUDIO"
        BASE_URL="$LMSTUDIO_URL"
        MODEL="$LMSTUDIO_MODEL"
        save_provider "$PROVIDER"
        save_base_url "$BASE_URL"
        save_model "$MODEL"
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
        echo "  --use-lmstudio        Use LMStudio as provider (saves for future use)"
        echo "  --use-custom <url>    Use custom provider with base URL (saves for future use)"
        echo "  -h, --help            Show this help message"
        echo ""
        echo "Examples:"
        echo "  cmai --api-key your_api_key          # First time setup with API key"
        echo "  cmai --use-ollama                    # Switch to Ollama provider"
        echo "  cmai --use-openrouter                # Switch back to OpenRouter"
        echo "  cmai --use-lmstudio                  # Switch to LMStudio provider"
        echo "  cmai --use-custom http://my-api.com  # Use custom provider"
        exit 0
        ;;
    --model)
        # Check if next argument exists and doesn't start with -
        if [[ -n "$2" && "$2" != -* ]]; then
            # Remove any quotes from model name and save it
            MODEL=$(echo "$2" | tr -d '"')
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
    --api-key)
        # Check if next argument exists and doesn't start with -
        if [[ -n "$2" && "$2" != -* ]]; then
            save_api_key "$2"
            debug_log "New API key saved"
            shift 2
        else
            echo "Error: --api-key requires a valid API key"
            exit 1
        fi
        ;;
    *)
        echo "Error: Unknown argument $1"
        exit 1
        ;;
    esac
done

# Get API key from config
API_KEY=$(get_api_key)
debug_log "API key retrieved from config"

if [ -z "$API_KEY" ] && [ "$PROVIDER" = "$PROVIDER_OPENROUTER" ]; then
    echo "No API key found. Please provide the OpenRouter API key using --api-key flag"
    echo "Usage: cmai [--debug] [--push|-p] [--use-ollama] [--model <model_name>] [--base-url <url>] [--api-key <key>]"
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

# Remove all linebreaks from CHANGES
CHANGES=$(replace_linebreaks "$CHANGES")

# Set model based on provider if not explicitly specified
if [ -z "$MODEL" ]; then
    case "$PROVIDER" in
    "$PROVIDER_OLLAMA")
        MODEL="$OLLAMA_MODEL"
        ;;
    "$PROVIDER_OPENROUTER")
        MODEL="$OPENROUTER_MODEL"
        ;;
    esac
fi

# Format changes into a single line
FORMATTED_CHANGES=$(echo "$CHANGES" | tr '\n' ' ' | sed 's/  */ /g')
FORMATTED_DIFF=$(echo "$DIFF_CONTENT" | tr '\n' '\\n' | sed 's/"/\\"/g')

# Make the API request
case "$PROVIDER" in
"$PROVIDER_OLLAMA")
    debug_log "Making API request to Ollama"
    ENDPOINT="api/generate"
    HEADERS=(-H "Content-Type: application/json")
    BASE_URL="http://localhost:11434"
    REQUEST_BODY=$(
        cat <<EOF
{
  "model": "$MODEL",
  "prompt": "Generate a conventional commit message for these changes: \n<file_changes>\n$FORMATTED_CHANGES.\n</file_changes>\n\n## Instructions:\n- Format should be: <type>(<scope>): <subject>\n\n<body>\n\nRules:\n- Type: feat, fix, docs, style, refactor, perf, test, chore\n- Scope: max 3 words.\n- Subject: max 70 characters, imperative mood, no period.\n- Body: list changes to explain what and why\n- Use 'fix' for minor changes\n- Do not wrap your response in triple backticks\n- Response should be the commit message only, no explanations.",
  "stream": false
}
EOF
    )
    ;;
"$PROVIDER_LMSTUDIO")
    debug_log "Making API request to LMStudio"
    ENDPOINT="chat/completions"
    HEADERS=(-H "Content-Type: application/json")
    
    # Create a simplified message for LMStudio
    # Looking at the error, we need to simplify the request to avoid parsing issues
    REQUEST_BODY=$(
        cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {
      "role": "system",
      "content": "You are a git commit message generator. Create conventional commit messages."
    },
    {
      "role": "user",
      "content": "Generate a commit message for these git changes. Follow the conventional commits format: <type>(<scope>): <subject>\n\n<body>\n\nWhere type is one of: feat, fix, docs, style, refactor, perf, test, chore. Keep the subject under 70 chars."
    }
  ]
}
EOF
    )
    debug_log "LMStudio request body:" "$REQUEST_BODY"
    ;;
"$PROVIDER_OPENROUTER")
    debug_log "Making API request to OpenRouter"
    ENDPOINT="chat/completions"
    HEADERS=(
        "HTTP-Referer: https://github.com/mrgoonie/cmai"
        "Authorization: Bearer $API_KEY"
        "Content-Type: application/json"
        "X-Title: cmai - AI Commit Message Generator"
    )
    REQUEST_BODY=$(
        cat <<EOF
{
  "model": "$MODEL",
  "stream": false,
  "messages": [
    {
      "role": "system",
      "content": "You are a git commit message generator. Create conventional commit messages."
    },
    {
      "role": "user",
      "content": "Generate a commit message for these changes:\n\n## File changes:\n<file_changes>\n$CHANGES\n</file_changes>\n\n## Diff:\n<diff>\n$DIFF_CONTENT\n</diff>\n\n## Format:\n<type>(<scope>): <subject>\n\n<body>\n\nImportant:\n- Type must be one of: feat, fix, docs, style, refactor, perf, test, chore\n- Subject: max 70 characters, imperative mood, no period\n- Body: list changes to explain what and why, not how\n- Scope: max 3 words\n- For minor changes: use 'fix' instead of 'feat'\n- Do not wrap your response in triple backticks\n- Response should be the commit message only, no explanations."
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
      "content": "Generate a commit message for these changes:\n\n## File changes:\n<file_changes>\n$CHANGES\n</file_changes>\n\n## Diff:\n<diff>\n$DIFF_CONTENT\n</diff>\n\n## Format:\n<type>(<scope>): <subject>\n\n<body>\n\nImportant:\n- Type must be one of: feat, fix, docs, style, refactor, perf, test, chore\n- Subject: max 70 characters, imperative mood, no period\n- Body: list changes to explain what and why, not how\n- Scope: max 3 words\n- For minor changes: use 'fix' instead of 'feat'\n- Do not wrap your response in triple backticks\n- Response should be the commit message only, no explanations."
    }
  ]
}
EOF
    )
    ;;
esac

# Debug
debug_log "Using provider: $PROVIDER"
debug_log "Provider endpoint: $ENDPOINT"
debug_log "Request headers: ${HEADERS}"
debug_log "Request model: ${MODEL}"
debug_log "Request body: $REQUEST_BODY"

# Convert headers array to proper curl format
CURL_HEADERS=()
for header in "${HEADERS[@]}"; do
    CURL_HEADERS+=(-H "$header")
done

RESPONSE=$(curl -s -X POST "$BASE_URL/$ENDPOINT" \
    "${CURL_HEADERS[@]}" \
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
"$PROVIDER_LMSTUDIO")
    # For LMStudio, extract content from response
    debug_log "LMStudio raw response:" "$RESPONSE"
    
    # Check if response is HTML error page
    if echo "$RESPONSE" | grep -q "<!DOCTYPE html>"; then
        echo "Error: LMStudio API returned HTML error. Make sure LMStudio is running and the API is accessible."
        echo "Response: $RESPONSE"
        exit 1
    fi
    
    # Check for JSON error
    if echo "$RESPONSE" | grep -q "error"; then
        ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error' 2>/dev/null)
        echo "Error from LMStudio: $ERROR"
        exit 1
    fi
    
    # Try to extract content with proper error handling
    COMMIT_FULL=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$COMMIT_FULL" ] || [ "$COMMIT_FULL" = "null" ]; then
        echo "Error: Failed to parse LMStudio response. Response format may be unexpected."
        echo "Response: $RESPONSE"
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
