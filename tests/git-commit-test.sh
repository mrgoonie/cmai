#!/bin/bash

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/git-commit.sh"
TEST_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEST_DIR"
}

fail_test() {
    echo "FAIL: $1" 1>&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"

    grep -Fq -- "$expected" "$file" || fail_test "$file does not contain: $expected"
}

trap cleanup EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home/.config/git-commit-ai" "$TEST_DIR/repo" "$TEST_DIR/state"
printf '%s\n' custom >"$TEST_DIR/home/.config/git-commit-ai/provider"
printf '%s\n' https://provider.test/v1 >"$TEST_DIR/home/.config/git-commit-ai/base_url"
printf '%s\n' test-model >"$TEST_DIR/home/.config/git-commit-ai/model"
printf '%s\n' 999999 >"$TEST_DIR/home/.config/git-commit-ai/max_tokens"

export HOME="$TEST_DIR/home"
export PATH="$TEST_DIR/bin:$PATH"
export TEST_STATE="$TEST_DIR/state"

"$SCRIPT" --print-config >"$TEST_DIR/output" 2>"$TEST_DIR/error" ||
    fail_test "print config with legacy setting failed"
assert_contains "$TEST_DIR/output" "Max output tokens:  Not set"

cat >"$TEST_DIR/bin/curl" <<'EOF'
#!/bin/bash

output_file=""
request_file=""

while [ "$#" -gt 0 ]; do
    case "$1" in
    -o)
        output_file="$2"
        shift 2
        ;;
    -w)
        shift 2
        ;;
    --data-binary)
        request_file=${2#@}
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done

jq -r '.messages[1].content' "$request_file" >"$TEST_STATE/prompt"
cp "$request_file" "$TEST_STATE/request.json"
printf '%s' "$FAKE_RESPONSE_BODY" >"$output_file"
printf '%s' "$FAKE_HTTP_STATUS"
EOF
chmod +x "$TEST_DIR/bin/curl"

(
    cd "$TEST_DIR/repo" || exit 1
    git init -q
    : >isenstedt-pg-ph-f3tv6x-a-p3rucw-20260716-103832.log
    awk 'BEGIN { for (i = 0; i < 25000; i++) { printf "[CRITICAL] xx"; for (j = 0; j < 40; j++) printf "€"; print "" } }' \
        >isenstedt-pg-ph-f3tv6x-a-p3rucw-20260716-122750.log
    git add .
) || fail_test "failed to create fixture repository"

# Ensure this fixture would expose byte-wise truncation splitting a UTF-8 code point.
if ! (
    cd "$TEST_DIR/repo" || exit 1
    changes=$(git diff --name-status --cached | tr '\t' ' ' | sed 's/  */ /g')
    changes_bytes=$(printf '%s' "$changes" | wc -c)
    diff_budget=$((131071 * 90 / 100 - 4096 - 4096 - changes_bytes))
    git diff --cached >"$TEST_DIR/state/full-diff"
    head -c "$diff_budget" "$TEST_DIR/state/full-diff" >"$TEST_DIR/state/byte-truncated-diff"
    last_byte=$(tail -c 1 "$TEST_DIR/state/byte-truncated-diff" | od -An -tx1 | tr -d ' \n')
    if [ "$last_byte" != e2 ] && [ "$last_byte" != 82 ]; then
        echo "fixture ended with byte $last_byte" 1>&2
        exit 1
    fi
); then
    fail_test "UTF-8 fixture does not split a code point under byte-wise truncation"
fi

export FAKE_HTTP_STATUS=200
export FAKE_RESPONSE_BODY='{"error":false,"choices":[{"message":{"content":"chore(logs): add diagnostic logs"}}]}'
if ! (
    cd "$TEST_DIR/repo" || exit 1
    "$SCRIPT" --message-only --max-context-tokens 131071
) >"$TEST_DIR/output" 2>"$TEST_DIR/error"; then
    fail_test "large diff request failed"
fi

[ "$(cat "$TEST_DIR/output")" = "chore(logs): add diagnostic logs" ] ||
    fail_test "generated message was not returned"
[ "$(wc -c <"$TEST_DIR/state/prompt")" -lt 112000 ] ||
    fail_test "prompt exceeded bounded diff size"
assert_contains "$TEST_DIR/state/prompt" "isenstedt-pg-ph-f3tv6x-a-p3rucw-20260716-103832.log"
assert_contains "$TEST_DIR/state/prompt" "isenstedt-pg-ph-f3tv6x-a-p3rucw-20260716-122750.log"
assert_contains "$TEST_DIR/state/prompt" "[Diff truncated to "
if grep -Fq '�' "$TEST_DIR/state/prompt"; then
    fail_test "diff truncation introduced invalid UTF-8 replacement character"
fi
if ! jq -e 'has("max_tokens") | not' "$TEST_DIR/state/request.json" >/dev/null; then
    fail_test "default output reserve was sent as an API limit"
fi

if ! (
    cd "$TEST_DIR/repo" || exit 1
    "$SCRIPT" --message-only --max-output-tokens 512 --max-context-tokens 32768
) >"$TEST_DIR/output" 2>"$TEST_DIR/error"; then
    fail_test "explicit token budgets failed"
fi
[ "$(jq -r '.max_tokens' "$TEST_DIR/state/request.json")" = 512 ] ||
    fail_test "max output tokens were not sent to provider"
[ "$(wc -c <"$TEST_DIR/state/prompt")" -lt 26000 ] ||
    fail_test "custom context window did not reduce prompt size"
[ "$(cat "$TEST_DIR/home/.config/git-commit-ai/max_output_tokens")" = 512 ] ||
    fail_test "max output tokens were not saved"
[ "$(cat "$TEST_DIR/home/.config/git-commit-ai/max_context_tokens")" = 32768 ] ||
    fail_test "max context tokens were not saved"

"$SCRIPT" --print-config >"$TEST_DIR/output" 2>"$TEST_DIR/error" ||
    fail_test "print config failed"
assert_contains "$TEST_DIR/output" "Max output tokens:  512"
assert_contains "$TEST_DIR/output" "Max context tokens: 32768"

"$SCRIPT" --help >"$TEST_DIR/output" 2>"$TEST_DIR/error" ||
    fail_test "help failed"
assert_contains "$TEST_DIR/output" "--max-output-tokens <n>"
assert_contains "$TEST_DIR/output" "--max-context-tokens <n>"

if (
    cd "$TEST_DIR/repo" || exit 1
    "$SCRIPT" --message-only --max-output-tokens 40000
) >"$TEST_DIR/output" 2>"$TEST_DIR/error"; then
    fail_test "output budget larger than context unexpectedly succeeded"
fi
assert_contains "$TEST_DIR/error" "--max-output-tokens must be smaller than --max-context-tokens"
[ "$(cat "$TEST_DIR/home/.config/git-commit-ai/max_output_tokens")" = 512 ] ||
    fail_test "invalid output budget overwrote saved value"

if (
    cd "$TEST_DIR/repo" || exit 1
    "$SCRIPT" --message-only --max-tokens 512
) >"$TEST_DIR/output" 2>"$TEST_DIR/error"; then
    fail_test "removed --max-tokens option unexpectedly succeeded"
fi
assert_contains "$TEST_DIR/output" "Unknown argument --max-tokens"

export FAKE_HTTP_STATUS=413
export FAKE_RESPONSE_BODY='Request Entity Too Large'
if (
    cd "$TEST_DIR/repo" || exit 1
    "$SCRIPT" --message-only
) >"$TEST_DIR/output" 2>"$TEST_DIR/error"; then
    fail_test "HTTP error unexpectedly succeeded"
fi
assert_contains "$TEST_DIR/error" "API request failed (HTTP 413): Request Entity Too Large"
if grep -Fq "jq: parse error" "$TEST_DIR/error"; then
    fail_test "raw jq parse error leaked to user"
fi

export FAKE_HTTP_STATUS=200
export FAKE_RESPONSE_BODY='upstream request failed'
if (
    cd "$TEST_DIR/repo" || exit 1
    "$SCRIPT" --message-only
) >"$TEST_DIR/output" 2>"$TEST_DIR/error"; then
    fail_test "invalid JSON response unexpectedly succeeded"
fi
assert_contains "$TEST_DIR/error" "Provider returned invalid JSON (HTTP 200): upstream request failed"
if grep -Fq "jq: parse error" "$TEST_DIR/error"; then
    fail_test "raw jq parse error leaked to user"
fi

# Large untracked files must not be round-tripped through shell pattern matching:
# quadratic matching made a 2MB file take >20 minutes. Guard with a hard timeout.
(
    cd "$TEST_DIR/repo" || exit 1
    awk 'BEGIN { for (i = 0; i < 60000; i++) print "[CRITICAL] untracked noise line for unstaged diff" }' \
        >untracked-large.log
    printf 'small untracked file\n' >untracked-small.txt
) || fail_test "failed to create untracked fixtures"

export FAKE_HTTP_STATUS=200
export FAKE_RESPONSE_BODY='{"error":false,"choices":[{"message":{"content":"chore(logs): add untracked logs"}}]}'
if ! (
    cd "$TEST_DIR/repo" || exit 1
    timeout 60 "$SCRIPT" --message-only --unstaged
) >"$TEST_DIR/output" 2>"$TEST_DIR/error"; then
    fail_test "unstaged run with large untracked file failed or timed out"
fi
[ "$(cat "$TEST_DIR/output")" = "chore(logs): add untracked logs" ] ||
    fail_test "generated message was not returned for unstaged run"
assert_contains "$TEST_DIR/state/prompt" "A untracked-large.log"
assert_contains "$TEST_DIR/state/prompt" "A untracked-small.txt"
assert_contains "$TEST_DIR/state/prompt" "[Diff truncated to "

echo "PASS: git-commit tests"
