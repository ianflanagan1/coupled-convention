#!/bin/sh
# Behaviour of skills/ianf-coupled-tags/scripts/coupled-tags-lint.sh. Run with `devbox run -- task test`.
#
# Each test writes its files into a fresh directory that isn't a git work tree, so the script
# falls back to grep.

root=$(cd "$(dirname "$0")/.." && pwd)
lint=$root/skills/ianf-coupled-tags/scripts/coupled-tags-lint.sh

setUp() {
    sandbox=$(mktemp -d "${SHUNIT_TMPDIR:-${TMPDIR:-/tmp}}/test.XXXXXX")
}

tearDown() {
    rm -rf "$sandbox"
}

# file name line...: write the lines to name in the sandbox.
file() {
    name=$1
    shift
    mkdir -p "$(dirname "$sandbox/$name")"
    printf '%s\n' "$@" >"$sandbox/$name"
}

# run_lint: lint the sandbox, leaving its stderr in $errors and its exit status in $status.
run_lint() {
    errors=$(sh "$lint" "$sandbox" 2>&1 >/dev/null)
    status=$?
}

assertClean() {
    run_lint
    assertEquals "unexpected problems: $errors" 0 "$status"
}

# assertProblem text: the lint fails and reports text.
assertProblem() {
    run_lint
    assertEquals 1 "$status"
    assertContains "$errors" "$1"
}

# --- Keys

test_a_key_with_two_sites_is_clean() {
    file a.py 'X = 1  # COUPLED:x-limit: ='
    file b.conf 'x 1;  # COUPLED:x-limit: ='
    assertClean
}

test_a_key_with_one_site_is_an_orphan() {
    file a.py 'X = 1  # COUPLED:x-limit: ='
    assertProblem 'a.py:1 Orphan key'
}

test_a_single_site_whose_note_names_a_site_the_search_cannot_reach_is_not_an_orphan() {
    file a.py 'X = 1  # COUPLED:x-limit: = (also other-repo: src/x.py)'
    assertClean
}

test_a_single_site_whose_note_only_explains_is_still_an_orphan() {
    file a.py 'X = 1  # COUPLED:x-limit: = (seconds)'
    assertProblem 'a.py:1 Orphan key'
}

test_a_key_with_an_uppercase_letter_is_malformed() {
    file a.py 'X = 1  # COUPLED:X-limit: =' 'Y = 1  # COUPLED:X-limit: ='
    assertProblem 'a.py:1 Malformed tag'
}

test_a_key_ended_by_a_full_stop_is_malformed() {
    file a.py 'X = 1  # COUPLED:x-limit. =' 'Y = 1  # COUPLED:x-limit. ='
    assertProblem 'a.py:1 Malformed tag'
}

test_prose_and_search_patterns_that_mention_tags_are_not_tags() {
    b='`' q="'"
    file a.md "Search for ${b}COUPLED:<key>:${b}, or run ${b}grep COUPLED:${b} or ${b}grep ${q}COUPLED:x-limit:${q}${b}."
    assertClean
}

# --- Ops

test_every_allowed_op_is_clean() {
    for op in '=' '!=' '<' '<=' '>' '>=' 'same-as'; do
        file a.py "X = 1  # COUPLED:x-limit: $op Y"
        file b.py "Y = 1  # COUPLED:x-limit: $op X"
        assertClean
    done
}

test_a_tag_without_a_relation_names_the_ops() {
    file a.py 'X = 1  # COUPLED:x-limit:' 'Y = 1  # COUPLED:x-limit: ='
    assertProblem 'a.py:1 Start the relation with one of = != < <= > >= same-as'
}

test_a_relation_starting_with_another_word_names_the_ops() {
    file a.py 'X = 1  # COUPLED:x-limit: equals Y' 'Y = 1  # COUPLED:x-limit: = X'
    assertProblem 'a.py:1 Start the relation with one of = != < <= > >= same-as'
}

test_an_op_run_into_its_target_names_the_ops() {
    file a.py 'X = 1  # COUPLED:x-limit: =Y' 'Y = 1  # COUPLED:x-limit: = X'
    assertProblem 'a.py:1 Start the relation with one of'
}

# --- Targets

test_an_ordering_op_without_a_target_needs_one() {
    file a.py 'X = 1  # COUPLED:x-limit: <=' 'Y = 1  # COUPLED:x-limit: >= X'
    assertProblem 'a.py:1 Name the other value after <='
}

test_an_ordering_op_with_only_a_note_needs_a_target() {
    file a.py 'X = 1  # COUPLED:x-limit: < (seconds)' 'Y = 1  # COUPLED:x-limit: > X'
    assertProblem 'a.py:1 Name the other value after <'
}

test_bare_equals_is_clean_when_every_site_is_equals() {
    file a.py 'X = 1  # COUPLED:x-version: = (also .nvmrc)'
    file b.yml 'x: 1  # COUPLED:x-version: ='
    file c.conf 'x 1;  # COUPLED:x-version: = X'
    assertClean
}

test_bare_same_as_is_clean_when_every_site_is_same_as() {
    file a.js '// COUPLED:x-rules: same-as' 'function a() {}'
    file b.js '// COUPLED:x-rules: same-as' 'function b() {}'
    assertClean
}

test_bare_equals_in_a_group_that_mixes_ops_needs_a_target() {
    file a.py 'X = 1  # COUPLED:x-limit: ='
    file b.py 'Y = 1  # COUPLED:x-limit: >= X'
    assertProblem 'a.py:1 Name the other value after ='
}

test_a_target_may_contain_parentheses_without_a_space_before_them() {
    file a.js '// COUPLED:x-rules: same-as Validator::validate()' 'function a() {}'
    file b.php '// COUPLED:x-rules: same-as a()' 'function validate() {}'
    assertClean
}

# --- Notes

test_a_note_that_is_not_closed_must_be() {
    file a.py 'X = 1  # COUPLED:x-limit: = (seconds' 'Y = 1  # COUPLED:x-limit: ='
    assertProblem 'a.py:1 End the note with )'
}

test_text_after_a_note_must_go_inside_it() {
    file a.py 'X = 1  # COUPLED:x-limit: = (seconds) and more' 'Y = 1  # COUPLED:x-limit: ='
    assertProblem 'a.py:1 End the note with )'
}

# --- Where the tag sits

test_comment_closers_after_a_tag_are_not_part_of_its_relation() {
    file a.js '/* COUPLED:x-limit: = */'
    file b.md '<!-- COUPLED:x-limit: = (seconds) -->'
    file c.json "  \"\$comment\": \"COUPLED:x-limit: = (also d.json)\","
    file e.md '| X | COUPLED:x-limit: = |'
    assertClean
}

test_two_tags_can_share_a_comment() {
    file a.py 'X = 1  # COUPLED:x-limit: = COUPLED:y-limit: < Z'
    file b.py 'Y = 1  # COUPLED:x-limit: = COUPLED:y-limit: > X'
    assertClean
}

# --- Exit status

test_a_clean_directory_with_no_tags_exits_zero() {
    file a.py 'X = 1'
    assertClean
}

test_help_prints_the_usage_and_each_option() {
    out=$(sh "$lint" -h)
    assertEquals 0 $?
    assertContains "$out" 'Usage: coupled-tags-lint.sh [-l] [-x path]... [dir]'
    assertContains "$out" '-x path  exclude a path prefix'
    assertContains "$out" 'dir      directory to scan'
    assertNotContains "$out" 'Exit status'
}

test_an_unknown_option_is_a_usage_error() {
    sh "$lint" -q "$sandbox" >/dev/null 2>&1
    assertEquals 2 $?
}

# shellcheck disable=SC1090
. "${SHUNIT2:-$(command -v shunit2)}"
