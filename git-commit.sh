#!/bin/bash

CONFIG_DIR="$HOME/.config/git-commit-ai"
CONFIG_FILE="$CONFIG_DIR/config"
MODEL_FILE="$CONFIG_DIR/model"
BASE_URL_FILE="$CONFIG_DIR/base_url"
PROVIDER_FILE="$CONFIG_DIR/provider"
TEMPERATURE_FILE="$CONFIG_DIR/temperature"
TOP_P_FILE="$CONFIG_DIR/top_p"
TOP_K_FILE="$CONFIG_DIR/top_k"
PRESENCE_PENALTY_FILE="$CONFIG_DIR/presence_penalty"
MAX_TOKENS_FILE="$CONFIG_DIR/max_tokens"
REASONING_EFFORT_FILE="$CONFIG_DIR/reasoning_effort"
EXTRA_BODY_FILE="$CONFIG_DIR/extra_body"

# Debug mode flag
DEBUG=false
# Push flag
PUSH=false
# Message only flag
MESSAGE_ONLY=false
# Branch name flag
BRANCH_NAME_ONLY=false
# Unstaged flag
UNSTAGED=false
# Explicit git diff target
DIFF_SPEC=""
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

debug_log_file() {
    if [ "$DEBUG" = true ]; then
        echo "DEBUG: $1"
        echo "DEBUG: Content >>>"
        if [ -f "${2:-}" ] && [ -r "${2:-}" ]; then
            cat "$2"
        else
            echo "(empty, missing, or unreadable file)"
        fi
        echo "DEBUG: <<<"
    fi
}

fail() {
    echo "Error: $1" 1>&2
    exit 1
}

save_setting() {
    local file="$1"
    local value="$2"

    printf '%s\n' "$value" >"$file"
    chmod 600 "$file"
}

get_setting() {
    local file="$1"

    if [ -f "$file" ]; then
        cat "$file"
    fi
}

validate_decimal_range() {
    local value="$1"
    local minimum="$2"
    local maximum="$3"
    local option="$4"

    if ! [[ "$value" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] ||
        ! awk -v value="$value" -v minimum="$minimum" -v maximum="$maximum" \
            'BEGIN { exit !(value >= minimum && value <= maximum) }'; then
        fail "$option must be between $minimum and $maximum"
    fi
}

validate_positive_integer() {
    local value="$1"
    local option="$2"

    if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
        fail "$option must be a positive integer"
    fi
}

validate_nonnegative_integer() {
    local value="$1"
    local option="$2"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        fail "$option must be a non-negative integer"
    fi
}

validate_signed_decimal_range() {
    local value="$1"
    local minimum="$2"
    local maximum="$3"
    local option="$4"

    if ! [[ "$value" =~ ^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] ||
        ! awk -v value="$value" -v minimum="$minimum" -v maximum="$maximum" \
            'BEGIN { exit !(value >= minimum && value <= maximum) }'; then
        fail "$option must be between $minimum and $maximum"
    fi
}

validate_reasoning_effort() {
    case "$1" in
    none | minimal | low | medium | high | xhigh | max) ;;
    *) fail "--reasoning-effort must be one of: none, minimal, low, medium, high, xhigh, max" ;;
    esac
}

validate_extra_body() {
    if ! printf '%s' "$1" | jq -e 'type == "object"' >/dev/null 2>&1; then
        fail "--extra-body must be a valid JSON object"
    fi
}

cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ "$TEMP_DIR" != "/" ] && [ -d "$TEMP_DIR" ]; then
        rm -f "$TEMP_DIR/prompt" "$TEMP_DIR/request.json" "$TEMP_DIR/extra-body.json"
        rmdir "$TEMP_DIR" 2>/dev/null || true
    fi
}

# Collect untracked files and represent them as added files in the prompt context.
get_untracked_changes() {
    local files=""
    local diffs=""
    local file=""

    while IFS= read -r -d '' file; do
        files+="A $file"$'\n'
        diffs+=$(git diff --no-index -- /dev/null "$file" 2>/dev/null || true)
        diffs+=$'\n'
    done < <(git ls-files --others --exclude-standard -z)

    printf '%s\n__CMAI_SPLIT__\n%s' "$files" "$diffs"
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

# Function to print config
print_config() {
    echo "Current configuration:"
    echo "  Provider:  $(get_provider)"
    echo "  Base URL:  $(get_base_url)"
    echo "  Model:     $(get_model)"
    echo "  Temperature:      ${TEMPERATURE:-Not set}"
    echo "  Top P:            ${TOP_P:-Not set}"
    echo "  Top K:            ${TOP_K:-Not set}"
    echo "  Presence penalty: ${PRESENCE_PENALTY:-Not set}"
    echo "  Max tokens:       ${MAX_TOKENS:-Not set}"
    echo "  Reasoning effort: ${REASONING_EFFORT:-Not set}"
    if [ -z "$EXTRA_BODY" ]; then
        echo "  Extra body:       Not set"
    else
        echo "  Extra body:       Set"
    fi
    API_KEY=$(get_api_key)
    if [ -z "$API_KEY" ]; then
        echo "  API Key:   Not set"
    else
        echo "  API Key:   ****"
    fi
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
TEMPERATURE=$(get_setting "$TEMPERATURE_FILE")
TOP_P=$(get_setting "$TOP_P_FILE")
TOP_K=$(get_setting "$TOP_K_FILE")
PRESENCE_PENALTY=$(get_setting "$PRESENCE_PENALTY_FILE")
MAX_TOKENS=$(get_setting "$MAX_TOKENS_FILE")
REASONING_EFFORT=$(get_setting "$REASONING_EFFORT_FILE")
EXTRA_BODY=$(get_setting "$EXTRA_BODY_FILE")
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
    --message-only)
        MESSAGE_ONLY=true
        shift
        ;;
    --branch-name-only)
        BRANCH_NAME_ONLY=true
        shift
        ;;
    --unstaged)
        UNSTAGED=true
        shift
        ;;
    --diff)
        if [[ -n "$2" && "$2" != -* ]]; then
            DIFF_SPEC="$2"
            shift 2
        else
            echo "Error: --diff requires a diff argument"
            exit 1
        fi
        ;;
    --print-config)
        print_config
        exit 0
        ;;
    -h | --help)
        echo "Usage: cmai [options] [api_key]"
        echo ""
        echo "Options:"
        echo "  --debug               Enable debug mode"
        echo "  --push, -p            Push changes after commit"
        echo "  --message-only        Generate message only, no git add/commit/push"
        echo "  --branch-name-only    Generate branch name only, no git add/commit/push"
        echo "  --unstaged            Use unstaged and untracked changes for diff"
        echo "  --diff <diff>         Use a custom git diff target for message/branch-only"
        echo "  --model <model>       Use specific model (default: google/gemini-flash-1.5-8b)"
        echo "  --temperature <n>     Set sampling temperature (0-2; saves for future use)"
        echo "  --top-p <n>           Set nucleus sampling probability (0-1; saves for future use)"
        echo "  --top-k <n>           Set top-k sampling count (non-negative integer)"
        echo "  --presence-penalty <n>  Set presence penalty (-2 to 2; saves for future use)"
        echo "  --max-tokens <n>      Set maximum generated tokens (saves for future use)"
        echo "  --reasoning-effort <level>  Set none/minimal/low/medium/high/xhigh/max"
        echo "  --extra-body <json>   Merge arbitrary JSON object into request body"
        echo "  --reset-generation-options  Clear saved generation options"
        echo "  --use-ollama          Use Ollama as provider (saves for future use)"
        echo "  --use-openrouter      Use OpenRouter as provider (saves for future use)"
        echo "  --use-lmstudio        Use LMStudio as provider (saves for future use)"
        echo "  --use-custom <url>    Use custom provider with base URL (saves for future use)"
        echo "  --print-config        Print the current config"
        echo "  -h, --help            Show this help message"
        echo ""
        echo "Examples:"
        echo "  cmai --api-key your_api_key          # First time setup with API key"
        echo "  cmai --use-ollama                    # Switch to Ollama provider"
        echo "  cmai --use-openrouter                # Switch back to OpenRouter"
        echo "  cmai --use-lmstudio                  # Switch to LMStudio provider"
        echo "  cmai --use-custom http://my-api.com  # Use custom provider"
        echo "  cmai --message-only                  # Generate message only, no commit"
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
    --temperature)
        [ -n "${2:-}" ] && [[ "$2" != -* ]] || fail "--temperature requires a value"
        validate_decimal_range "$2" 0 2 "--temperature"
        TEMPERATURE="$2"
        save_setting "$TEMPERATURE_FILE" "$TEMPERATURE"
        shift 2
        ;;
    --top-p)
        [ -n "${2:-}" ] && [[ "$2" != -* ]] || fail "--top-p requires a value"
        validate_decimal_range "$2" 0 1 "--top-p"
        TOP_P="$2"
        save_setting "$TOP_P_FILE" "$TOP_P"
        shift 2
        ;;
    --top-k)
        [ -n "${2:-}" ] && [[ "$2" != -* ]] || fail "--top-k requires a value"
        validate_nonnegative_integer "$2" "--top-k"
        TOP_K="$2"
        save_setting "$TOP_K_FILE" "$TOP_K"
        shift 2
        ;;
    --presence-penalty)
        [ -n "${2:-}" ] || fail "--presence-penalty requires a value"
        validate_signed_decimal_range "$2" -2 2 "--presence-penalty"
        PRESENCE_PENALTY="$2"
        save_setting "$PRESENCE_PENALTY_FILE" "$PRESENCE_PENALTY"
        shift 2
        ;;
    --max-tokens)
        [ -n "${2:-}" ] && [[ "$2" != -* ]] || fail "--max-tokens requires a value"
        validate_positive_integer "$2" "--max-tokens"
        MAX_TOKENS="$2"
        save_setting "$MAX_TOKENS_FILE" "$MAX_TOKENS"
        shift 2
        ;;
    --reasoning-effort)
        [ -n "${2:-}" ] && [[ "$2" != -* ]] || fail "--reasoning-effort requires a value"
        REASONING_EFFORT=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
        validate_reasoning_effort "$REASONING_EFFORT"
        save_setting "$REASONING_EFFORT_FILE" "$REASONING_EFFORT"
        shift 2
        ;;
    --extra-body)
        [ -n "${2:-}" ] || fail "--extra-body requires a JSON object"
        validate_extra_body "$2"
        EXTRA_BODY=$(printf '%s' "$2" | jq -c '.')
        save_setting "$EXTRA_BODY_FILE" "$EXTRA_BODY"
        shift 2
        ;;
    --reset-generation-options)
        rm -f "$TEMPERATURE_FILE" "$TOP_P_FILE" "$TOP_K_FILE" \
            "$PRESENCE_PENALTY_FILE" "$MAX_TOKENS_FILE" \
            "$REASONING_EFFORT_FILE" "$EXTRA_BODY_FILE"
        TEMPERATURE=""
        TOP_P=""
        TOP_K=""
        PRESENCE_PENALTY=""
        MAX_TOKENS=""
        REASONING_EFFORT=""
        EXTRA_BODY=""
        shift
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

if [ -n "$DIFF_SPEC" ] && [ "$UNSTAGED" = true ]; then
    echo "Error: --diff and --unstaged cannot be used together"
    exit 1
fi

if [ -n "$DIFF_SPEC" ] && [ "$MESSAGE_ONLY" = false ] && [ "$BRANCH_NAME_ONLY" = false ]; then
    echo "Error: --diff can only be used with --message-only or --branch-name-only"
    exit 1
fi

if [ "$PROVIDER" = "$PROVIDER_OLLAMA" ] && [ -n "$REASONING_EFFORT" ]; then
    case "$REASONING_EFFORT" in
    none | low | medium | high) ;;
    *) fail "Ollama supports reasoning effort none, low, medium, or high" ;;
    esac
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

# Only stage changes and check for changes if not using message-only, branch-name mode, or unstaged mode
if [ "$MESSAGE_ONLY" = false ] && [ "$BRANCH_NAME_ONLY" = false ] && [ "$UNSTAGED" = false ]; then
    # Stage all changes
    debug_log "Staging all changes"
    git add .
fi

# Use a single, readable format for all providers (jq will handle JSON escaping)
DIFF_ARGS=()
if [ -n "$DIFF_SPEC" ]; then
    read -ra DIFF_ARGS <<< "$DIFF_SPEC"
elif [ "$UNSTAGED" = false ]; then
    DIFF_ARGS+=(--cached)
fi

CHANGES=$(git diff --name-status "${DIFF_ARGS[@]}" | tr '\t' ' ' | sed 's/  */ /g')
# Get git diff for context
DIFF_CONTENT=$(git diff "${DIFF_ARGS[@]}")

if [ "$UNSTAGED" = true ]; then
    UNTRACKED_DATA=$(get_untracked_changes)
    UNTRACKED_CHANGES=${UNTRACKED_DATA%%$'\n'__CMAI_SPLIT__*}
    UNTRACKED_DIFF=${UNTRACKED_DATA#*__CMAI_SPLIT__$'\n'}

    if [ -n "$UNTRACKED_CHANGES" ]; then
        CHANGES="${CHANGES}${CHANGES:+$'\n'}${UNTRACKED_CHANGES%$'\n'}"
    fi

    if [ -n "$UNTRACKED_DIFF" ]; then
        DIFF_CONTENT="${DIFF_CONTENT}${DIFF_CONTENT:+$'\n'}${UNTRACKED_DIFF%$'\n'}"
    fi
fi

debug_log "Git changes detected" "$CHANGES"

if [ -z "$CHANGES" ]; then
    if [ -n "$DIFF_SPEC" ]; then
        echo "No changes found for git diff $DIFF_SPEC."
    elif [ "$UNSTAGED" = true ]; then
        echo "No unstaged or untracked changes found."
    else
        echo "No staged changes found. Please stage your changes using 'git add' first or use --unstaged flag."
    fi
    exit 1
fi

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

# Assemble the user prompt with raw content; jq will handle JSON escaping
if [ "$BRANCH_NAME_ONLY" = true ]; then
    USER_CONTENT=$(cat <<EOF
Generate a git branch name for these changes:

## File changes:
<file_changes>
$CHANGES
</file_changes>

## Diff:
<diff>
$DIFF_CONTENT
</diff>

## Format:
<type>/<short-description>

Important:
- Type must be one of: feat, fix, docs, style, refactor, perf, test, chore
- Short description: lowercase, hyphen-separated, max 50 chars
- Example: fix/api-error-handling or feat/new-login-page
- Do not wrap your response in triple backticks
- Response should be the branch name only, no explanations.
EOF
)
else
    USER_CONTENT=$(cat <<EOF
Generate a commit message for these changes:

## File changes:
<file_changes>
$CHANGES
</file_changes>

## Diff:
<diff>
$DIFF_CONTENT
</diff>

## Format:
<type>(<scope>): <subject>

<body>

Important:
- Type must be one of: feat, fix, docs, style, refactor, perf, test, chore
- Subject: max 70 characters, imperative mood, no period
- Body: list changes to explain what and why, not how
- Scope: max 3 words
- For minor changes: use 'fix' instead of 'feat'
- Do not wrap your response in triple backticks
- Response should be the commit message only, no explanations.
EOF
)
fi

# Define system prompt
if [ "$BRANCH_NAME_ONLY" = true ]; then
    SYSTEM_PROMPT="You are a git branch name generator. Create concise, standard git branch names."
else
    SYSTEM_PROMPT="You are a git commit message generator. Create conventional commit messages."
fi

# Keep large prompts and request bodies out of command arguments. Passing a
# large diff through `jq --arg` or `curl -d` can exceed the OS argument limit.
TEMP_DIR=""
trap cleanup EXIT
TEMP_DIR=$(mktemp -d) || fail "Failed to create temporary directory"
PROMPT_FILE="$TEMP_DIR/prompt"
REQUEST_FILE="$TEMP_DIR/request.json"
EXTRA_BODY_REQUEST_FILE="$TEMP_DIR/extra-body.json"
printf '%s' "$USER_CONTENT" >"$PROMPT_FILE" || fail "Failed to write prompt to temporary file"
if [ -n "$EXTRA_BODY" ]; then
    printf '%s' "$EXTRA_BODY" >"$EXTRA_BODY_REQUEST_FILE" || fail "Failed to write extra request body"
else
    printf '%s' '{}' >"$EXTRA_BODY_REQUEST_FILE" || fail "Failed to initialize extra request body"
fi

# Make the API request
case "$PROVIDER" in
"$PROVIDER_OLLAMA")
    debug_log "Making API request to Ollama"
    ENDPOINT="api/generate"
    HEADERS=(-H "Content-Type: application/json")
    BASE_URL="http://localhost:11434"
    jq -n \
        --arg model "$MODEL" \
        --rawfile prompt "$PROMPT_FILE" \
        --arg temperature "$TEMPERATURE" \
        --arg top_p "$TOP_P" \
        --arg top_k "$TOP_K" \
        --arg presence_penalty "$PRESENCE_PENALTY" \
        --arg max_tokens "$MAX_TOKENS" \
        --arg reasoning_effort "$REASONING_EFFORT" \
        --slurpfile extra_body "$EXTRA_BODY_REQUEST_FILE" \
        '{model:$model, prompt:$prompt, stream:false}
         | if $temperature == "" then . else .options.temperature = ($temperature | tonumber) end
         | if $top_p == "" then . else .options.top_p = ($top_p | tonumber) end
         | if $top_k == "" then . else .options.top_k = ($top_k | tonumber) end
         | if $presence_penalty == "" then . else .options.presence_penalty = ($presence_penalty | tonumber) end
         | if $max_tokens == "" then . else .options.num_predict = ($max_tokens | tonumber) end
         | if $reasoning_effort != "" then
             .think = (if $reasoning_effort == "none" then false else $reasoning_effort end)
           else . end
         | . + $extra_body[0]' >"$REQUEST_FILE" ||
        fail "Failed to generate request JSON"
    ;;
"$PROVIDER_LMSTUDIO")
    debug_log "Making API request to LMStudio"
    ENDPOINT="chat/completions"
    HEADERS=(-H "Content-Type: application/json")
    jq -n \
        --arg model "$MODEL" \
        --rawfile content "$PROMPT_FILE" \
        --arg system_prompt "$SYSTEM_PROMPT" \
        --arg temperature "$TEMPERATURE" \
        --arg top_p "$TOP_P" \
        --arg top_k "$TOP_K" \
        --arg presence_penalty "$PRESENCE_PENALTY" \
        --arg max_tokens "$MAX_TOKENS" \
        --arg reasoning_effort "$REASONING_EFFORT" \
        --slurpfile extra_body "$EXTRA_BODY_REQUEST_FILE" \
        '{
           model: $model,
           stream: false,
           messages: [
             {role:"system", content:$system_prompt},
             {role:"user",   content:$content}
           ]
         }
         | if $temperature == "" then . else .temperature = ($temperature | tonumber) end
         | if $top_p == "" then . else .top_p = ($top_p | tonumber) end
         | if $top_k == "" then . else .top_k = ($top_k | tonumber) end
         | if $presence_penalty == "" then . else .presence_penalty = ($presence_penalty | tonumber) end
         | if $max_tokens == "" then . else .max_tokens = ($max_tokens | tonumber) end
         | if $reasoning_effort == "" then . else .reasoning_effort = $reasoning_effort end
         | . + $extra_body[0]' >"$REQUEST_FILE" ||
        fail "Failed to generate request JSON"
    debug_log_file "LMStudio request body:" "$REQUEST_FILE"
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
    jq -n \
        --arg model "$MODEL" \
        --rawfile content "$PROMPT_FILE" \
        --arg system_prompt "$SYSTEM_PROMPT" \
        --arg temperature "$TEMPERATURE" \
        --arg top_p "$TOP_P" \
        --arg top_k "$TOP_K" \
        --arg presence_penalty "$PRESENCE_PENALTY" \
        --arg max_tokens "$MAX_TOKENS" \
        --arg reasoning_effort "$REASONING_EFFORT" \
        --slurpfile extra_body "$EXTRA_BODY_REQUEST_FILE" \
        '{
           model: $model,
           stream: false,
           messages: [
             {role:"system", content:$system_prompt},
             {role:"user",   content:$content}
           ]
         }
         | if $temperature == "" then . else .temperature = ($temperature | tonumber) end
         | if $top_p == "" then . else .top_p = ($top_p | tonumber) end
         | if $top_k == "" then . else .top_k = ($top_k | tonumber) end
         | if $presence_penalty == "" then . else .presence_penalty = ($presence_penalty | tonumber) end
         | if $max_tokens == "" then . else .max_tokens = ($max_tokens | tonumber) end
         | if $reasoning_effort == "" then . else .reasoning.effort = $reasoning_effort end
         | . + $extra_body[0]' >"$REQUEST_FILE" ||
        fail "Failed to generate request JSON"
    ;;
"$PROVIDER_CUSTOM")
    debug_log "Making API request to custom provider"
    ENDPOINT="chat/completions"
    HEADERS=(-H "Content-Type: application/json")
    [ -n "$API_KEY" ] && HEADERS+=(-H "Authorization: Bearer ${API_KEY}")
    jq -n \
        --arg model "$MODEL" \
        --rawfile content "$PROMPT_FILE" \
        --arg system_prompt "$SYSTEM_PROMPT" \
        --arg temperature "$TEMPERATURE" \
        --arg top_p "$TOP_P" \
        --arg top_k "$TOP_K" \
        --arg presence_penalty "$PRESENCE_PENALTY" \
        --arg max_tokens "$MAX_TOKENS" \
        --arg reasoning_effort "$REASONING_EFFORT" \
        --slurpfile extra_body "$EXTRA_BODY_REQUEST_FILE" \
        '{
           stream: false,
           model: $model,
           messages: [
             {role:"system", content:$system_prompt},
             {role:"user",   content:$content}
           ]
         }
         | if $temperature == "" then . else .temperature = ($temperature | tonumber) end
         | if $top_p == "" then . else .top_p = ($top_p | tonumber) end
         | if $top_k == "" then . else .top_k = ($top_k | tonumber) end
         | if $presence_penalty == "" then . else .presence_penalty = ($presence_penalty | tonumber) end
         | if $max_tokens == "" then . else .max_tokens = ($max_tokens | tonumber) end
         | if $reasoning_effort == "" then . else .reasoning_effort = $reasoning_effort end
         | . + $extra_body[0]' >"$REQUEST_FILE" ||
        fail "Failed to generate request JSON"
    ;;
esac

# Debug
debug_log "Using provider: $PROVIDER"
debug_log "Provider endpoint: $ENDPOINT"
debug_log "Request headers: ${HEADERS[*]}"
debug_log "Request model: ${MODEL}"
debug_log_file "Request body:" "$REQUEST_FILE"

# Convert headers array to proper curl format
CURL_HEADERS=()
for header in "${HEADERS[@]}"; do
    CURL_HEADERS+=(-H "$header")
done

RESPONSE=$(curl -s -X POST "$BASE_URL/$ENDPOINT" \
    "${CURL_HEADERS[@]}" \
    --data-binary "@$REQUEST_FILE")
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
    RESULT_MESSAGE=$(echo "$RESPONSE" | jq -r '.response // empty')
    if [ -z "$RESULT_MESSAGE" ]; then
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

    # Check for JSON error - only if there's an actual error field with content
    if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
        ERROR=$(echo "$RESPONSE" | jq -r '.error.message // .error' 2>/dev/null)
        echo "Error from LMStudio: $ERROR"
        exit 1
    fi

    # Try to extract content with proper error handling
    RESULT_MESSAGE=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$RESULT_MESSAGE" ] || [ "$RESULT_MESSAGE" = "null" ]; then
        echo "Error: Failed to parse LMStudio response. Response format may be unexpected."
        echo "Response: $RESPONSE"
        exit 1
    fi
    ;;
"$PROVIDER_OPENROUTER" | "$PROVIDER_CUSTOM")
    # For OpenRouter and custom providers
    RESULT_MESSAGE=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')

    # If jq fails or returns null, fallback to grep method
    if [ -z "$RESULT_MESSAGE" ] || [ "$RESULT_MESSAGE" = "null" ]; then
        RESULT_MESSAGE=$(echo "$RESPONSE" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
    fi
    ;;
esac

# Clean the message:
# 1. Preserve the structure of the commit message
# 2. Clean up escape sequences
RESULT_MESSAGE=$(echo "$RESULT_MESSAGE" |
    sed 's/\\n/\n/g' |
    sed 's/\\r//g' |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
    sed 's/\\[[:alpha:]]//g')

debug_log "Extracted commit message" "$RESULT_MESSAGE"

if [ -z "$RESULT_MESSAGE" ]; then
    echo "Failed to generate commit message. API response:"
    echo "$RESPONSE"
    exit 1
fi

if [ "$MESSAGE_ONLY" = true ] || [ "$BRANCH_NAME_ONLY" = true ]; then
    echo "$RESULT_MESSAGE"
    exit 0
fi

# If we were in unstaged mode, we need to stage changes before committing
if [ "$UNSTAGED" = true ]; then
    debug_log "Staging all changes before commit"
    git add .
fi

# Execute git commit
debug_log "Executing git commit"
git commit -m "$RESULT_MESSAGE"

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
echo "$RESULT_MESSAGE"
debug_log "Script completed successfully"
