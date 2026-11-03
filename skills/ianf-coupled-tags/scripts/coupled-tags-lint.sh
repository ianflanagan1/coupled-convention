#!/bin/sh
# coupled-tags-lint: check COUPLED:<key>: tags in a repository.
#
# Reports:
#   - malformed tags (key not [a-z0-9-], or not terminated by ":" and a space)
#   - relations that don't start with an op: = != < <= > >= same-as
#   - a missing target: after != < <= > >=, and after = or same-as in a group that mixes ops
#   - a note that isn't one parenthesised piece at the end of the relation
#   - orphan keys (only one site, so the other end was removed or never tagged), unless a note
#     starts with "also", naming a site the search can't reach (a file without comments, or a
#     file in another repository)
#
# A tag's relation runs to the next tag or the end of the line, less any comment closer
# (*/, -->, #}, ", or |) after it.
#
# Usage: coupled-tags-lint.sh [-l] [-x path]... [dir]
#   -l       list every key and its sites
#   -x path  exclude a path prefix (relative to dir); repeatable
#   dir      directory to scan (default: .)
#
# Exit status: 0 clean, 1 problems found, 2 usage error.

set -o errexit -o nounset

usage() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed '/^#$/d; s/^# \{0,1\}//'
}

list=0
excludes=''
while getopts 'lx:h' opt; do
    case $opt in
        l) list=1 ;;
        x) excludes="$excludes
${OPTARG%/}" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || { usage >&2; exit 2; }

cd "${1:-.}"

# Tracked and untracked-but-not-ignored files in a git work tree; plain grep otherwise.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    search() { git grep --untracked -I --line-number --fixed-strings 'COUPLED:' -- . || true; }
else
    search() {
        grep --recursive -I --line-number --fixed-strings 'COUPLED:' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor . \
            | sed 's|^\./||' || true
    }
fi

search | EXCLUDES="$excludes" LIST="$list" awk '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function problem(site, message) { printf "%s %s\n", site, message | err; problems++ }
BEGIN {
    nex = split(ENVIRON["EXCLUDES"], ex, "\n")
    list = ENVIRON["LIST"] == "1"
    err = "cat 1>&2"
    ops = "= != < <= > >= same-as"
}
{
    i = index($0, ":");  path = substr($0, 1, i - 1);  rest = substr($0, i + 1)
    j = index(rest, ":"); line = substr(rest, 1, j - 1); text = substr(rest, j + 1)
    site = path ":" line

    for (k = 1; k <= nex; k++)
        if (ex[k] != "" && (path == ex[k] || index(path, ex[k] "/") == 1)) next

    while ((p = index(text, "COUPLED:")) > 0) {
        text = substr(text, p + 8)
        # Prose mentions such as `COUPLED:<key>:` or `COUPLED:` are not tags.
        if (text !~ /^[A-Za-z0-9_-]/) continue
        # A search pattern such as `COUPLED:<key>:` mentions a tag; it is not one.
        if (text ~ /^[a-z0-9-]+:[\047"`]/) continue
        if (!match(text, /^[a-z0-9-]+:( |$)/)) {
            problem(site, "Malformed tag. Must be `COUPLED:<key>: <relation>` with key [a-z0-9-]")
            continue
        }
        key = substr(text, 1, index(text, ":") - 1)
        if (!(key in count)) order[++nkeys] = key
        count[key]++
        sites[key] = sites[key] "\n    " site

        relation = substr(text, length(key) + 2)
        q = index(relation, "COUPLED:")
        if (q > 0) relation = substr(relation, 1, q - 1)
        relation = trim(relation)
        sub(/[ \t]*(\*\/|-->|#}|",?|[|])$/, "", relation)
        relation = trim(relation)

        if (!match(relation, /^(!=|<=|>=|=|<|>|same-as)( |$)/)) {
            problem(site, "Start the relation with one of " ops ", then a space")
            continue
        }
        op = trim(substr(relation, 1, RLENGTH))
        rest = trim(substr(relation, RLENGTH + 1))
        if (substr(rest, 1, 1) == "(") { target = ""; note = rest }
        else if ((n = index(rest, " (")) > 0) { target = substr(rest, 1, n - 1); note = substr(rest, n + 1) }
        else { target = rest; note = "" }

        if (note ~ /^\(also /) reaches[key] = 1
        if (note != "" && note !~ /\)$/)
            problem(site, "End the note with ), and put any text after it inside the note")
        if (!(key in firstop)) firstop[key] = op
        else if (firstop[key] != op) mixed[key] = 1
        if (target == "") {
            if (op == "=" || op == "same-as") bare[key] = bare[key] "\n" site "\t" op
            else problem(site, "Name the other value after " op "; only = and same-as can go without one")
        }
    }
}
END {
    for (k = 1; k <= nkeys; k++) {
        key = order[k]
        if (list) printf "%s (%d)%s\n", key, count[key], sites[key]
        if (count[key] < 2 && !(key in reaches)) problem(substr(sites[key], 6), "Orphan key with only one site")
        if (key in mixed) {
            nb = split(substr(bare[key], 2), b, "\n")
            for (m = 1; m <= nb; m++) {
                split(b[m], f, "\t")
                problem(f[1], "Name the other value after " f[2] ": its group mixes ops, so a bare op is ambiguous")
            }
        }
    }
    close(err)
    exit problems ? 1 : 0
}'
