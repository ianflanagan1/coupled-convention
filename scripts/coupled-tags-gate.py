"""PreToolUse hook: before Claude first edits a COUPLED-tagged line in a session, show it the group.

Reads the hook event as JSON on stdin. If an Edit, MultiEdit or Write call changes lines that carry
a COUPLED:<key>: tag, lines under a comment block holding one, or lines inside a block (found by
indentation) whose first line or comment block holds one, and this session hasn't been shown
that key yet, it prints a "deny" decision whose reason lists every site of each such key. Claude
reads them, changes the group together and retries; later calls touching those keys pass. Anything
else, and any input it can't parse, passes silently (exit 0, no output), so a broken hook never
blocks work.

It doesn't see edits made through Bash, or blocks that aren't indented, such as a function body
written flush with its signature.

Per-session state is a marker file per key in $TMPDIR/claude-coupled-tags/<session>/.

Runs on the Python 3.13 in this repository's devbox.
"""

import difflib
import json
import os
import re
import subprocess
import sys
import tempfile

_REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

_TAG = re.compile(r"COUPLED:([a-z0-9-]+):(?=\s|$)")

# A line that is only a comment, in the syntaxes tagged files use.
_COMMENT_LINE = re.compile(r"^\s*(#|//|/\*|\*|;|<!--|--|\{#)")

_MAX_SITES = 40
_MAX_SITE_LENGTH = 200


def _line_ranges_of(content, old, every):
    """The [first, last] line indexes of old in content: its first occurrence, or every one."""
    ranges = []
    start = content.find(old) if old else -1
    while start != -1:
        first = content.count("\n", 0, start)
        ranges.append((first, first + old.count("\n")))
        if not every:
            break
        start = content.find(old, start + len(old))
    return ranges


def _changed_line_ranges(before, after):
    """The [first, last] line indexes in before that writing after would change or insert at."""
    old_lines = before.splitlines()
    matcher = difflib.SequenceMatcher(None, old_lines, after.splitlines(), autojunk=False)
    return [
        (i1, max(i1, i2 - 1))
        for tag, i1, i2, _, _ in matcher.get_opcodes()
        if tag != "equal" and i1 < max(len(old_lines), 1)
    ]


def _touched_ranges(tool, tool_input, content):
    if tool == "Edit":
        return _line_ranges_of(
            content, str(tool_input.get("old_string", "")), bool(tool_input.get("replace_all"))
        )
    if tool == "MultiEdit":
        ranges = []
        for edit in tool_input.get("edits") or []:
            ranges += _line_ranges_of(
                content, str(edit.get("old_string", "")), bool(edit.get("replace_all"))
            )
        return ranges
    if tool == "Write":
        return _changed_line_ranges(content, str(tool_input.get("content", "")))
    return []


def _indent(line):
    return len(line) - len(line.lstrip())


def _comment_block_start(lines, index):
    """The first line of the comment block directly above lines[index], or index if none."""
    while index > 0 and _COMMENT_LINE.match(lines[index - 1]):
        index -= 1
    return index


def _tagged_lines(lines, first, last):
    """The lines whose tags cover lines[first..last]: those lines, each line enclosing them by
    indentation, and the comment block directly above each."""
    covering = list(range(_comment_block_start(lines, first), last + 1))
    if first >= len(lines):
        return covering
    indent = _indent(lines[first])
    for index in range(first - 1, -1, -1):
        if indent == 0:
            break
        line = lines[index]
        if line.strip() and not _COMMENT_LINE.match(line) and _indent(line) < indent:
            indent = _indent(line)
            covering += range(_comment_block_start(lines, index), index + 1)
    return covering


def touched_keys(tool, tool_input, content):
    """The keys of the tags covering the lines the call changes."""
    lines = content.splitlines()
    keys = []
    for first, last in _touched_ranges(tool, tool_input, content):
        for index in _tagged_lines(lines, first, last):
            if index < len(lines):
                for key in _TAG.findall(lines[index]):
                    if key not in keys:
                        keys.append(key)
    return keys


def _sites(path, key):
    """The 'path:line:text' sites of key in path's git work tree, or None outside one."""
    directory = os.path.dirname(os.path.abspath(path))
    try:
        top = subprocess.run(
            ["git", "-C", directory, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        found = subprocess.run(
            ["git", "-C", top, "grep", "--untracked", "-I", "--line-number", "--fixed-strings",
             "COUPLED:" + key + ":", "--", "."],
            capture_output=True, text=True,
        ).stdout.splitlines()
    except (OSError, subprocess.CalledProcessError):
        return None
    sites = [site.strip()[:_MAX_SITE_LENGTH] for site in found[:_MAX_SITES]]
    if len(found) > _MAX_SITES:
        sites.append("... and " + str(len(found) - _MAX_SITES) + " more")
    return top, sites


def reason(groups):
    """The deny reason for groups, a list of (key, sites) where sites is (top, lines) or None."""
    parts = [
        "This edit touches COUPLED tags. Before changing a tagged value or block, read every "
        "site in its group and every site listed in an `also` note, which may be in another "
        "repository, and change them together so every "
        "relation still holds (see /ianf-coupled-tags). Then retry this call."
    ]
    for key, sites in groups:
        if sites is None:
            parts.append("Search for `COUPLED:" + key + ":` to find its sites.")
        else:
            top, lines = sites
            parts.append("COUPLED:" + key + ": sites in " + top + ":\n" + "\n".join(lines))
    return "\n\n".join(parts)


def _unseen(session, keys):
    """The keys this session hasn't been shown, marking them shown."""
    state = os.path.join(
        tempfile.gettempdir(), "claude-coupled-tags",
        re.sub(r"[^A-Za-z0-9_-]", "_", session) or "unknown",
    )
    os.makedirs(state, exist_ok=True)
    unseen = []
    for key in keys:
        try:
            with open(os.path.join(state, key), "x"):
                unseen.append(key)
        except FileExistsError:
            pass
    return unseen


def main():
    try:
        event = json.load(sys.stdin)
        tool_input = event.get("tool_input") or {}
        path = os.path.abspath(str(tool_input.get("file_path", "")))
        if path == _REPO or path.startswith(_REPO + os.sep):
            return
        with open(path, encoding="utf-8") as f:
            content = f.read()
        keys = touched_keys(str(event.get("tool_name", "")), tool_input, content)
        unseen = _unseen(str(event.get("session_id", "")), keys) if keys else []
        if not unseen:
            return
        groups = [(key, _sites(path, key)) for key in unseen]
    except Exception:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason(groups),
    }}))


if __name__ == "__main__":
    main()
