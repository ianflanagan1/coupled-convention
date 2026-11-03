---
name: ianf-coupled-tags
description: "Add COUPLED:<key>: comments linking values or code that must change together but can't share a single source of truth. Before editing anything tagged COUPLED:, update every site."
argument-hint: <this> with <that> [as <key>]
allowed-tools: Bash(sh *scripts/coupled-tags-lint.sh*)
disable-model-invocation: false
model: inherit
---

# COUPLED tags

Some things must change together but cannot share a single source of truth: a runtime version pinned in several files, size or timeout limits that must stay ordered across a proxy and an app, a URL registered in an external console, a block of code deliberately duplicated. Every site gets a tag, so whoever changes one finds the others by searching for `COUPLED:<key>:`.

## Format

```
<comment> COUPLED:<key>: <op> [<target>] [(<note>)]
```

- `<key>`: lowercase `[a-z0-9-]`, ended by `:`. One key per group.
- `<op>`: one of `=`, `!=`, `<`, `<=`, `>`, `>=`, `same-as` (for duplicated code). Written from this site's point of view.
- `<target>`: the other value, by its own name at its site (`MAX_UPLOAD_MB`, `client_max_body_size`, `PasswordValidator::validate()`). Never its file or location: the search for the key shows where every site is.
  - Leave out the target when every site in the group is `=`, or every site is `same-as`: each is then the same as all the others.
  - Write a target with any other op, or when the group mixes ops.
- `(<note>)`: optional free text the op and target can't express: units (`m vs MB`), a formula, a reason (`deliberate`). A note starting `also` lists sites the search can't reach (below).
- The tag is the last thing in its comment. Put an existing comment before it. A site in two groups gets two tags; they can share one comment.

## Placement

Use the file's own comment syntax. Put the tag in a trailing comment on the line it describes. Where the line can't take one, or a trailing comment would change the value (Dockerfiles, many `.env` parsers, Makefile variables), or the site is a multi-line block, put it on the comment line directly above. For a whole function, put it in the docblock. In Markdown, write it as plain visible text.

## Sites the search can't reach

A file that can't take a comment (JSON, `.nvmrc`) gets no tag, and a search of one repository doesn't reach a site in another. List them in an `also` note on every tagged site in the group: `(also .nvmrc)`, `(also repo-tools: src/repo_list/agents.py)`. A group whose other sites are all listed this way can have a single tagged site in this repository.

## Choosing the key

Name the invariant the group protects, not the technology or file it lives in: `request-timeout-chain`, not `nginx-timeouts`; `python-version`, not `versions`. Test it both ways:
- If an unrelated setting could plausibly carry the key, it is too vague.
- If a site that belongs would look out of place carrying it, it is too narrow.

If the user supplied a key (`as <key>`), use it. Otherwise propose one or two and wait for the user to choose before tagging anything.

## Examples

```dockerfile
# COUPLED:node-version: = (also .nvmrc)
FROM node:22-slim
```
```yaml
node-version: "22"                 # COUPLED:node-version: = (also .nvmrc)
```
```nginx
client_max_body_size 10m;          # COUPLED:upload-size-limit: >= MAX_UPLOAD_MB (m vs MB)
```
```python
MAX_UPLOAD_MB = 8                  # COUPLED:upload-size-limit: <= client_max_body_size (MB vs m)
```
```js
server.keepAliveTimeout = 65_000;  // COUPLED:keepalive-timeout: > idle timeout (ms vs s)
```
```js
// COUPLED:password-rules: same-as
function validatePassword(value) { ... }
```

## External systems

The search can't reach the far end of an external coupling, so the repo needs a record of it. Keep the **current** configuration of each external system in `docs/external/<service>.md`: what is set, where, and for which environment. Tag each value in that doc like any other site. Create or update it whenever an external coupling is added or changed. Leave visible TODOs for values you cannot see.

## Adding a coupling (`/ianf-coupled-tags $ARGUMENTS`)

1. Settle the key (see above).
2. Find every site, not only the ones named. Search for the literal value and related names across dev and prod configs, build files, app code and docs.
3. Reuse an existing key if this group already has one (search for `COUPLED:`).
4. Tag each site.
5. Check that the relations hold now. Never silently change a value to make one hold.
6. For external sites, create or update `docs/external/<service>.md`.
7. Run `sh <directory containing this file>/scripts/coupled-tags-lint.sh` from the repo root and fix what it reports.
8. Reply `✅ Tagged COUPLED:<key>:.`, then each site as `path:line`, then each relation that doesn't hold now.

## Changing a tagged value or block

1. Search for `COUPLED:<key>:` and read every site, and every site listed in an `also` note.
2. Change them all together, so every relation still holds.
3. For external sites, tell the user what to change outside the repo, and update the external doc.
