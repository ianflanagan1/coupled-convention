#!/bin/sh
# Behaviour of scripts/coupled-tags-gate.py. Run with `devbox run -- task test`.
#
# Each test gets its own TMPDIR, so the gate's per-session state starts empty, and its own git
# repository, whose files the tests tag.

root=$(cd "$(dirname "$0")/.." && pwd)
gate=$root/scripts/coupled-tags-gate.py

setUp() {
    sandbox=$(mktemp -d "${SHUNIT_TMPDIR:-${TMPDIR:-/tmp}}/test.XXXXXX")
    sandbox=$(cd "$sandbox" && pwd -P)
    TMPDIR=$sandbox/tmp
    export TMPDIR
    repo=$sandbox/repo
    mkdir -p "$TMPDIR" "$repo"
    git -C "$repo" init --quiet
    printf '%s\n' \
        'import os' \
        'MAX_UPLOAD_MB = 8  # COUPLED:upload-size-limit: <= client_max_body_size' \
        '' \
        '# Header comment.' \
        '# COUPLED:password-rules: same-as' \
        'def validate(value):' \
        '    return len(value) > 8' \
        '' \
        'TIMEOUT = 5' \
        >"$repo/app.py"
    printf '%s\n' 'client_max_body_size 10m;  # COUPLED:upload-size-limit: >= MAX_UPLOAD_MB' >"$repo/nginx.conf"
}

tearDown() {
    rm -rf "$sandbox"
}

# hook session tool input-json: run the gate on a PreToolUse event, printing its output.
hook() {
    printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2" "$3" \
        | python3 -I "$gate"
}

# edit session path old: the gate's output for the Edit tool replacing old in path.
edit() { hook "$1" Edit "{\"file_path\":\"$2\",\"old_string\":\"$3\",\"new_string\":\"x\"}"; }

# write session path content: the gate's output for the Write tool writing content to path.
write() { hook "$1" Write "{\"file_path\":\"$2\",\"content\":\"$3\"}"; }

# reason output: the deny reason in the gate's output.
reason() {
    printf '%s' "$1" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])'
}

assertRefused() { assertContains "$1" '"permissionDecision": "deny"'; }
assertAllowed() { assertEquals '' "$1"; }

# --- Which edits touch a tag

test_editing_a_tagged_line_is_refused() {
    assertRefused "$(edit s1 "$repo/app.py" 'MAX_UPLOAD_MB = 8')"
}

test_editing_an_untagged_line_is_allowed() {
    assertAllowed "$(edit s1 "$repo/app.py" 'TIMEOUT = 5')"
}

test_editing_the_line_under_a_tag_on_its_own_line_is_refused() {
    assertRefused "$(edit s1 "$repo/app.py" 'def validate(value):')"
}

test_editing_inside_a_block_under_a_tag_is_refused() {
    assertRefused "$(edit s1 "$repo/app.py" '    return len(value) > 8')"
}

test_editing_inside_a_block_whose_first_line_is_tagged_is_refused() {
    printf '%s\n' 'location /build/ {  # COUPLED:password-rules: same-as' '    expires 1y;' '}' 'other 1;' >"$repo/b.conf"
    assertRefused "$(edit s1 "$repo/b.conf" '    expires 1y;')"
}

test_a_tag_on_a_block_does_not_reach_the_line_after_it() {
    printf '%s\n' 'location /build/ {  # COUPLED:password-rules: same-as' '    expires 1y;' '}' 'other 1;' >"$repo/b.conf"
    assertAllowed "$(edit s1 "$repo/b.conf" 'other 1;')"
}

test_the_tag_is_found_above_a_comment_block_above_the_edit() {
    printf '%s\n' '# COUPLED:password-rules: same-as' '# More words.' 'x = 1' >"$repo/b.py"
    assertRefused "$(edit s1 "$repo/b.py" 'x = 1')"
}

test_a_tag_above_an_untagged_code_line_does_not_reach_the_edit() {
    printf '%s\n' '# COUPLED:password-rules: same-as' 'def f():' '' 'y = 2' >"$repo/b.py"
    assertAllowed "$(edit s1 "$repo/b.py" 'y = 2')"
}

test_only_the_first_occurrence_counts_without_replace_all() {
    printf '%s\n' 'a = 1' 'a = 1  # COUPLED:password-rules: same-as' >"$repo/b.py"
    assertAllowed "$(edit s1 "$repo/b.py" 'a = 1')"
}

test_every_occurrence_counts_with_replace_all() {
    printf '%s\n' 'a = 1' 'a = 1  # COUPLED:password-rules: same-as' >"$repo/b.py"
    out=$(hook s1 Edit "{\"file_path\":\"$repo/b.py\",\"old_string\":\"a = 1\",\"new_string\":\"x\",\"replace_all\":true}")
    assertRefused "$out"
}

test_a_multi_edit_with_one_tagged_edit_is_refused() {
    out=$(hook s1 MultiEdit "{\"file_path\":\"$repo/app.py\",\"edits\":[{\"old_string\":\"TIMEOUT = 5\",\"new_string\":\"x\"},{\"old_string\":\"MAX_UPLOAD_MB = 8\",\"new_string\":\"y\"}]}")
    assertRefused "$out"
}

test_writing_over_a_tagged_line_is_refused() {
    printf '%s\n' 'MAX_UPLOAD_MB = 8  # COUPLED:upload-size-limit: <= client_max_body_size' 'TIMEOUT = 5' >"$repo/b.py"
    assertRefused "$(write s1 "$repo/b.py" 'MAX_UPLOAD_MB = 9  # COUPLED:upload-size-limit: <= client_max_body_size\nTIMEOUT = 5\n')"
}

test_writing_a_file_that_changes_only_untagged_lines_is_allowed() {
    printf '%s\n' 'MAX_UPLOAD_MB = 8  # COUPLED:upload-size-limit: <= client_max_body_size' '' 'TIMEOUT = 5' >"$repo/b.py"
    assertAllowed "$(write s1 "$repo/b.py" 'MAX_UPLOAD_MB = 8  # COUPLED:upload-size-limit: <= client_max_body_size\n\nTIMEOUT = 6\n')"
}

test_writing_a_new_file_is_allowed() {
    assertAllowed "$(write s1 "$repo/new.py" 'X = 1  # COUPLED:upload-size-limit: =\n')"
}

test_a_mention_of_the_format_is_not_a_tag() {
    b='`'
    printf '%s\n' "Search for ${b}COUPLED:<key>:${b} first." >"$repo/b.md"
    assertAllowed "$(edit s1 "$repo/b.md" 'first')"
}

test_files_in_the_coupled_tags_repository_are_allowed() {
    assertAllowed "$(edit s1 "$root/README.md" 'COUPLED:vat-calculation: same-as')"
}

# --- What the refusal says

test_the_refusal_names_the_key_and_lists_every_site() {
    out=$(reason "$(edit s1 "$repo/app.py" 'MAX_UPLOAD_MB = 8')")
    assertContains "$out" 'COUPLED:upload-size-limit:'
    assertContains "$out" 'app.py:2:'
    assertContains "$out" 'nginx.conf:1:client_max_body_size 10m;'
}

test_the_refusal_says_to_search_when_the_file_is_outside_git() {
    mkdir "$sandbox/plain"
    printf '%s\n' 'X = 1  # COUPLED:upload-size-limit: =' >"$sandbox/plain/a.py"
    out=$(reason "$(edit s1 "$sandbox/plain/a.py" 'X = 1')")
    b='`'
    assertContains "$out" "Search for ${b}COUPLED:upload-size-limit:${b}"
}

# --- Once per key per session

test_retrying_in_the_same_session_is_allowed() {
    edit s1 "$repo/app.py" 'MAX_UPLOAD_MB = 8' >/dev/null
    assertAllowed "$(edit s1 "$repo/nginx.conf" 'client_max_body_size 10m;')"
}

test_another_session_is_refused_again() {
    edit s1 "$repo/app.py" 'MAX_UPLOAD_MB = 8' >/dev/null
    assertRefused "$(edit s2 "$repo/app.py" 'MAX_UPLOAD_MB = 8')"
}

test_a_new_key_in_the_same_session_is_refused_naming_only_it() {
    edit s1 "$repo/app.py" 'MAX_UPLOAD_MB = 8' >/dev/null
    out=$(edit s1 "$repo/app.py" '    return len(value) > 8')
    assertRefused "$out"
    assertNotContains "$(reason "$out")" 'upload-size-limit'
}

# --- Failing open

test_input_that_is_not_json_is_allowed() {
    assertAllowed "$(printf 'not json' | python3 -I "$gate")"
}

test_other_tools_are_allowed() {
    assertAllowed "$(hook s1 Bash '{"command":"ls"}')"
}

# shellcheck disable=SC1090
. "${SHUNIT2:-$(command -v shunit2)}"
