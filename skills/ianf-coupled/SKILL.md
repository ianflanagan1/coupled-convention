---
name: ianf-coupled
description: "Add COUPLED markers (e.g. `# COUPLED:upload-limit: proxy`) and their group in coupled-registry.toml, linking values or code that must change together but can't share a single source of truth. When editing anything marked COUPLED:, change every site in its group together."
argument-hint: <this> with <that> [as <key>]
allowed-tools: Bash(coupled *)
disable-model-invocation: false
model: inherit
---
<!-- COUPLED:IGNORE-FILE -->

# COUPLED groups

Some things must change together but cannot share a single source of truth: a runtime version pinned in several files, size or timeout limits that must stay ordered across a proxy and an app, a URL registered in an external console, a block of code deliberately duplicated. Each place, a *site*, carries a marker, and the repository's registry describes the group: how its sites relate. Whoever changes one site finds the rest, and the group's table, by searching for `COUPLED:<key>:`.

## Markers

```
<comment> COUPLED:<key>: <label>
```

- `<key>` names the group, the invariant it protects; `<label>` names this site within it, for the registry's relations (`proxy`, `app`, `docker`). Both are lowercase letters and digits, in words joined by single hyphens.
- The space between `COUPLED:<key>:` and the label is part of the form: a search for `COUPLED:<key>:` finds every site and the group's table.
- Labels are unique within a group.
- Prose goes before `COUPLED:`, or after the label and a `.`: `# COUPLED:upload-limit: proxy. Larger bodies get a 413.` Never straight after the label without the `.`.
- A site in two groups gets two markers; they can share a comment: `# COUPLED:a: x. COUPLED:b: y`.
- A marker describes the code before its comment on its line, or for a marker on a comment line, the first line of code after it, past other comment lines but not a blank line.
- `COUPLED:<key>:END`, in a comment on the line after a block's last, closes the nearest marker of its key above it, so it describes every line down to the END. Only in groups using structural ops. Blocks of different keys can nest but not overlap.
- `COUPLED:IGNORE-FILE`, on a line of its own, says a file's `COUPLED:` text is all examples, as in this skill: the lint and the hooks skip the file. Don't add it to a file holding real sites.
- If the repository's settings set `tag-relations` or `tag-pointer`, each label is followed by a message: the site's relations, then what to search for and where the group is described. `coupled --fix` writes it from the registry; don't write or edit it by hand.

## The registry

`coupled-registry.toml` at the repository's root, unless `.config/coupled.toml` names another file as `registry-file`. Each group is a table named as its markers are searched for:

```toml
version = 1

["COUPLED:upload-limit:"]
relations = ["proxy >= app", "proxy = ./limits.json#/upload_mb"]
```

- `relations`: each `<ref> <op> <ref> [<arith> <number>]`, read as: the first ref's value, by op, the second's after the formula. Write each relation once; there are no mirrors.
  - A ref is a site, by its label, or a file that can't hold a marker (below).
  - Or a bare op alone, `["="]`, `["same-as"]` or `["same-shape"]`, when every site and file in the group is the same.
- `<op>` is one of two kinds, and a group uses only one; split it into two keys if it needs both.
  - Value ops `=`, `!=`, `<`, `<=`, `>`, `>=` compare single values, and the lint checks them (see Values).
  - Structural ops relate code or structure, which the lint doesn't compare: `same-as` (duplicated code), `same-shape` (types and schemas with the same fields), `subset-of` and `superset-of` (lists).
- `<arith> <number>`: `+`, `-`, `*` or `/` and a number, applied to the second ref's value. Use it for a margin (`proxy >= app + 5`) or a change of units (`app > load-balancer * 1000`, ms against s).
- `files`: files in a group whose relation is a bare op, since no relation names them.
- `select`: a regex for a site, by its label, picking its value out of its line when the lint can't, with the value in its one capture group: `select = { url = ':(\d+)$' }`.
- `why`: why the sites must change together, in a sentence, which the lint and the hooks show to whoever changes a site: `why = "nginx rejects a larger body before the app sees it"`. Give every group one unless its key says it.
- Below the groups, `coupled --update <key>` writes the reviewed section. Never edit it.

## Files that can't hold a marker

A file without comments (JSON, `.nvmrc`) and a site in another repository are refs in the relations:

- `./<path>` is a file in this repository, `//<git-host>/<owner>/<name>/<path>` one in another: `//github.com/ianflanagan1/code-rulebook/schema/coverage.schema.json`.
- `#<pointer>` after the path is a JSON Pointer to the value: `./package.json#/engines/node`. A one-line file such as `.nvmrc` is its own value.
- `?` after the path marks a file that's only sometimes there, such as an untracked `.env`: `./.env?`.
- A group can be files alone, with no marker: `relations = ["./.nvmrc = ./.tool-versions"]`.
- For a site in another repository, mark it there too, and describe that side in that repository's registry with a `//` ref to this one. The two registries are the whole record of the coupling; don't describe it in a doc as well.

## Values

In a group using value ops, the lint reads each site's value from the line its marker describes. It takes, in order:

1. the one quoted or backticked literal on the line
2. an image's version (`FROM node:24.22.1-alpine`)
3. the right-hand side of an assignment (`HTTP_PORT=8080`, `key: value`)
4. a directive's value (`client_max_body_size 10m;`)

When a line has several candidates or none, add a `select` regex for its label. If the sites don't hold single values (lists, blocks, shapes), use a structural op instead.

Values compare like this:
- Versions match on the parts both give, so `24`, `24.22` and `24.22.1` are all `=`.
- Numbers compare numerically, ignoring a unit suffix (`10m`, `65s`): scale between units with a formula.
- Anything else compares as text, by `=` and `!=` only.

Write each value in its own file's notation (`10m` in nginx, `10M` in php.ini, `8` for `MAX_UPLOAD_MB`), never converted for the lint's sake. The reviewed section records each site's unit, so a unit changed at one site fails until the group is reviewed.

## Placement

Use the file's own comment syntax. Put the marker in a trailing comment on the line it describes. Where the line can't take one, or a trailing comment would change the value (Dockerfiles, many `.env` parsers, Makefile variables), or the site is a block, put it in the comment directly above, with no blank line before the code. For a whole function, put it in the docblock and close it with an END after the function. In Markdown, write it as plain visible text.

## Choosing the key and labels

Name the key for the invariant the group protects, not the technology or file it lives in: `request-timeout-chain`, not `nginx-timeouts`; `python-version`, not `versions`. Test it both ways:
- If an unrelated setting could plausibly carry the key, it is too vague.
- If a site that belongs would look out of place carrying it, it is too narrow.

Name each group's labels on their own, not from another group's: the same file can be `docker` in one group and `app` in another. First choose the group's axis, the one way its sites differ that explains the relations, so every label is the same kind of noun and each relation reads as the invariant:
- Components along a request path (`proxy >= app`).
- Two sides of a contract (`client`/`server`, `writer`/`reader`).
- The tools one pinned value is read by (`docker`, `ci`, `nvmrc`).
- Environments (`dev`, `prod`).
- Sites in one language or file: what each does with the value (`limit`/`error-message`, `check`/`docs`).

For components, use the project's own names first. Name a site for the Compose service (or Kubernetes deployment) that holds its file, through a bind mount, `env_file`, `configs`, `build.dockerfile` or its build context, when one service holds it, or every service that holds it is plainly one component (`app`, `worker` and `scheduler` built from one PHP image). Keep the name as the project writes it, a product name or an abbreviation included (`nginx`, `db`). For a site no service holds, or one the services leave unclear, fall back to the component's role (`cdn`, `load-balancer`, `proxy`, `app`, `database`), not the product filling it.

Write the labels you choose in whole words (`database`, not `db`), keeping an acronym that is the usual name (`cdn`, `ci`). When one component holds several sites, keep its name and add what each holds: `app-body`, `app-file`. Never name a label for its language (unless that's the only difference), its file, or by number. A site that joins later takes a label of the same kind.

When you rename a component the labels name, such as a Compose service, offer to relabel its sites. A stale label still works, so this is for readers, not the lint.

If the user supplied a key (`as <key>`), use it. Otherwise propose one or two and wait for the user to choose before marking anything.

## Examples

```nginx
client_max_body_size 10m;          # COUPLED:upload-limit: proxy
```
```python
MAX_UPLOAD_MB = 8                  # COUPLED:upload-limit: app
```
```dockerfile
# Slim keeps the image small. COUPLED:node-version: docker
FROM node:24.22.1-slim
```
```js
// COUPLED:password-rules: client
function validatePassword(value) {
  ...
}
// COUPLED:password-rules:END
```
```toml
["COUPLED:upload-limit:"]
relations = ["proxy >= app"]

["COUPLED:node-version:"]
relations = ["="]
files = ["./.nvmrc", "./package.json#/engines/node"]

["COUPLED:keepalive-timeout:"]
relations = ["app > load-balancer * 1000"]

["COUPLED:dev-port:"]
relations = ["url = port"]
select = { url = ':(\d+)$' }

["COUPLED:password-rules:"]
relations = ["client same-as server"]

["COUPLED:coverage-listing-shape:"]
relations = ["writer same-shape //github.com/ianflanagan1/code-rulebook/schema/coverage.schema.json"]
```

## External systems

An external system keeps its settings in no repository at all: a cloud console, DNS, a provider's dashboard. Nothing can be marked at its end, so the repo needs a written record of it. Keep the **current** configuration of each external system in `docs/external/<service>.md`: what is set, where, and for which environment. Mark each value in that doc like any other site, with the value in backticks on the marker's line (`` Idle timeout: `60` s. COUPLED:keepalive-timeout: load-balancer ``), so the lint can read it. Create or update it whenever an external coupling is added or changed. Leave visible TODOs for values you cannot see.

Another repository is never an external system, even one that isn't checked out here: its end is code that can carry a marker, so mark it and link the two with `//` refs. Don't write a `docs/external/` page for it.

## The reviewed section

The registry's reviewed section records each group as it was last reviewed: a fingerprint of its table, each site's marker, each value's unit, and a fingerprint of each block or file a structural op relates. The lint fails when a group differs from it, and names the group's other sites. `coupled --update <key>` records the group of each key it names as it is now, so run it only for a group whose every site is changed together and holds, never just to clear the failure. Commit the registry with the change.

## Adding a group (`/ianf-coupled $ARGUMENTS`)

1. Settle the key (see above).
2. Find every site, not only the ones named. Search for the literal value and related names across dev and prod configs, build files, app code and docs, and in any other repository the user names.
3. Reuse an existing group if this one already has one (search for `COUPLED:`).
4. Mark each site with the key and a label. For a site in another repository, mark it there if it's checked out, otherwise tell the user which file in which repository needs the marker.
5. Add the group's table to the registry, creating it with `version = 1` if there's none: its relations, each written once, its files and selectors, and why its sites must change together.
6. Check that the relations hold now: the lint checks value ops, and you judge structural ones. Never silently change a value to make one hold.
7. For sites in an external system, create or update `docs/external/<service>.md`.
8. Run `coupled --fix --update <key>` from the repo root, which writes the message after each label if the settings ask for it, and records the group in the registry's reviewed section; then fix what it reports, other than relations that don't hold now. If the command isn't found, tell the user it's installed from https://github.com/ianflanagan1/coupled, and check the markers and the table by reading them against this file.
9. Reply `✅ Marked COUPLED:<key>:.`, then each site as `path:line`, then each relation that doesn't hold now.

## Changing a marked value or block

1. Search for `COUPLED:<key>:` and read every site, down to its `COUPLED:<key>:END` if it has one, the group's table in the registry, and every file the table names. For a `//<git-host>/<owner>/<name>/<path>` ref, search that repository for the key too, or read the file on its git host if it isn't checked out.
2. Change them all together, so every relation still holds. Change the table's relations only if what must hold has changed.
3. For a site in another repository, change it there if it's checked out; otherwise tell the user what to change in which repository. For sites in an external system, tell the user what to change there, and update the external doc.
4. Run `coupled` and fix what it reports. When it reports that the group differs from what was reviewed, check that every site it names is changed and the group holds, then rerun with `--update <key>`.
