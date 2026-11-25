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
- A regex between slashes may follow the label, picking the site's value out of its line, or each of its members out of its block, when the lint can't (see Values, and Sets and text): `# COUPLED:dev-port: url /:(\d+)$/`. Write a `/` in it as `\/`; prose after it follows a `.`, as after a label. In a block comment, keep the comment's closer out of it, even across its slashes: write `\s*/` in `/* */` as `\s{0,}/`.
- A site in two groups gets two markers; they can share a comment: `# COUPLED:a: x. COUPLED:b: y`.
- A marker describes the code before its comment on its line, or for a marker on a comment line, the first line of code after it, past other comment lines but not a blank line.
- `COUPLED:<key>:END`, in a comment on the line after a block's last, closes the nearest marker of its key above it, so it describes every line down to the END. Not in groups using value ops, where a marker describes one line. Blocks of different keys can nest but not overlap.
- `COUPLED:IGNORE-FILE`, on a line of its own, says a file's `COUPLED:` text is all examples, as in this skill: the lint and the hooks skip the file. Don't add it to a file holding real sites.
- If the repository's settings set `markers-show-relations` or `markers-point-to-registry`, each label is followed by a message: the site's relations, then what to search for and where the group is described. `coupled --fix` writes it from the registry; don't write or edit it by hand.

## The registry

`coupled-registry.toml` at the repository's root, unless `.config/coupled.toml` names another file as `registry-file`. Each group is a table named as its markers are searched for:

```toml
version = 1

["COUPLED:upload-limit:"]
relations = ["proxy >= app", "proxy = limits"]
has-no-marker = { limits = "./limits.json#/upload_mb" }
```

A group's table gives its fields in the order below, which the lint checks.

- `relations`: each `<label> <op> <label> [<arith> <number>]`, read as: the first site's value, by op, the second's after the formula. Every relation names two sites by their labels, and every site is named in at least one. Write each relation once; there are no mirrors. For a group whose sites are all the same, relate each to one of them: `["ci = docker", "nvmrc = docker"]`.
- `<op>` is one of four kinds, by what it reads each site as, and a group uses only one kind; split it into two keys if it needs two.
  - Value ops `=`, `!=`, `<`, `<=`, `>`, `>=` compare single values, and the lint checks them (see Values).
  - Set ops `same-set`, `subset-of` and `superset-of` compare the names each site holds, such as an enum's members, a table's columns or a list, and the lint checks them (see Sets and text).
  - The text op `same-text` compares the sites' text, such as a block copied between two files, and the lint checks it (see Sets and text).
  - Judged ops relate code or prose that only a reader can compare, so the lint records each block and reports a change to one: `same-as` (code that must behave the same, such as one calculation in two languages), `same-shape` (types and schemas with the same fields), `description-of` (prose that must stay true of code; `described-by` is the same relation written from the code).
  - Choose a kind the lint checks wherever the sites can be read that way, and a judged op only when they can't.
- `<arith> <number>`: `+`, `-`, `*` or `/` and a number, applied to the second site's value. Use it for a margin (`proxy >= app + 5`) or a change of units (`app > load-balancer * 1000`, ms against s).
- `has-no-marker`, `in-another-registry` and `has-no-file` give a label to each site that has no marker, by why (below).
- `why`: why the sites must change together, in a sentence, which the lint and the hooks show to whoever changes a site: `why = "nginx rejects a larger body before the app sees it"`. A group using judged ops must have one, since it's all that tells a reviewer what must hold. Give every other group one unless its key says it.
- Below the groups, `coupled --update <key>` writes the reviewed section. Never edit it.

## Sites without a marker

Mark every site you can. A site that can't carry a marker here gets its label in the group's table, in the field that says why, and relations name it by that label like any other:

- `has-no-marker`: a file that holds no marker. In this repository, it's one that can't hold a marker, or not where its value is, such as JSON, `.nvmrc`, or a value inside a YAML block scalar or a heredoc: `has-no-marker = { nvmrc = "./.nvmrc", engines = "./package.json#/engines/node" }`.
  - `#<pointer>` after the path is a JSON Pointer to the value. Or pick the value out of its lines with a regex, writing the entry as a table with the regex beside the file: `dev = { file = "./web/package.json", regex = 'localhost:(\d+)' }`, where `^` and `$` match at each line. The regex is optional, so `{ file = "./.nvmrc" }` is the same as `"./.nvmrc"`. A one-line file such as `.nvmrc` is its own value.
  - `?` after the path marks a file that's only sometimes there, such as an untracked `.env`: `./.env?`.
  - Use it only for a file that really can't hold a marker where its value is: listing one is a claim a reviewer checks, and the lint reports a file here that holds a marker of the group.
  - In another repository that keeps no such group, such as a third party's published schema, it's `//<git-host>/<owner>/<name>/<path>[#<pointer>]`, with no `?`. Use it only when that repository's owners won't keep the group; otherwise use `in-another-registry`.
- `in-another-registry`: a site in another repository that keeps the group too, by the repository alone: `in-another-registry = { schema = "//github.com/ianflanagan1/code-rulebook" }`. Give the group the same key there, and describe that side in that repository's registry: mark the site, or give it the same label in that registry's `has-no-marker`, and name this repository's sites in its `in-another-registry`. Where its file is, is recorded only there. The two registries are the whole record of the coupling; don't describe it in a doc as well.
- `has-no-file`: a site in no file at all, with where it's set: `has-no-file = { google = "Google Cloud console > Credentials > Authorised redirect URIs" }`. See External systems.

A label is unique within its group, across markers and all three fields. A group can be files alone, with no marker: `relations = ["nvmrc = tools"]`, `has-no-marker = { nvmrc = "./.nvmrc", tools = "./.tool-versions" }`.

## Values

In a group using value ops, the lint reads each site's value from the line its marker describes. It takes, in order:

1. the one quoted or backticked literal on the line
2. an image's version (`FROM node:24.22.1-alpine`)
3. the right-hand side of an assignment (`HTTP_PORT=8080`, `key: value`)
4. a directive's value (`client_max_body_size 10m;`)

When a line has several candidates or none, add a regex after the marker's label, with the value in its one capture group: `COUPLED:dev-port: url /:(\d+)$/`. If the sites don't hold single values (lists, blocks, shapes), use a set, text or judged op instead.

Values compare like this:
- Versions match on the parts both give, so `24`, `24.22` and `24.22.1` are all `=`.
- Numbers compare numerically, ignoring a unit suffix (`10m`, `65s`): scale between units with a formula.
- Anything else compares as text, by `=` and `!=` only.

Write each value in its own file's notation (`10m` in nginx, `10M` in php.ini, `8` for `MAX_UPLOAD_MB`), never converted for the lint's sake. The reviewed section records each site's unit, so a unit changed at one site fails until the group is reviewed.

## Sets and text

In a group using set ops, the lint reads each site's members from its block, which an END closes, or from the one line its marker describes. It takes:

- the quoted literals on the block's lines (`"pending" | "stored"`, `PENDING = "pending"`)
- or, when the marker has a regex after its label, each match of it, with the member in its one capture group: `-- COUPLED:upload-columns: table /^([a-z_]+) /` for a table's columns

A file gives the items of the JSON list at its pointer, or the keys of the object there, or each match of its regex, or with neither, its lines. Members compare as text, in any order.

In a group using `same-text`, the lint compares the sites' blocks line by line. Indentation, blank lines and the markers of sites inside a block aren't part of its text. A file's text is all of it, or the JSON at its pointer.

When only part of what two sites share can be compared, mark them for two groups: a table's column names and a model's field names as `same-set`, and the two under `same-shape` for their types.

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
```sh
APP_URL=http://localhost:8080      # COUPLED:dev-port: url /:(\d+)$/
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
relations = ["nvmrc = docker", "engines = docker"]
has-no-marker = { nvmrc = "./.nvmrc", engines = "./package.json#/engines/node" }

["COUPLED:keepalive-timeout:"]
relations = ["app > load-balancer * 1000"]

["COUPLED:dev-port:"]
relations = ["url = port"]

["COUPLED:upload-status:"]
relations = ["web subset-of app"]

["COUPLED:setup-steps:"]
relations = ["ci same-text release"]

["COUPLED:password-rules:"]
relations = ["client same-as server", "help-page description-of server"]
why = "the form must refuse what the server would, and the help page says what both accept"

["COUPLED:coverage-listing-shape:"]
relations = ["writer same-shape schema"]
in-another-registry = { schema = "//github.com/ianflanagan1/code-rulebook" }
why = "the rulebook's schema validates the listing this writes"
```

## External systems

An external system keeps its settings in no repository at all: a cloud console, DNS, a provider's dashboard. Nothing can be marked at its end, so it joins a group in one of two ways.

Prefer a doc. Keep the **current** configuration of each external system in `docs/external/<service>.md`: what is set, where, and for which environment. Mark each value in that doc like any other site, with the value in backticks on the marker's line (`` Idle timeout: `60` s. COUPLED:keepalive-timeout: load-balancer ``), so the lint can read it and compare it with the rest of the group. Create or update it whenever an external coupling is added or changed. Leave visible TODOs for values you cannot see.

When the user doesn't want a doc, or you can't see the value to record it, name the site in the group's `has-no-file` instead, with where it's set, and relate it by its label like any other site:

```toml
["COUPLED:oauth-redirect:"]
relations = ["app = google"]
has-no-file = { google = "Google Cloud console > APIs & Services > Credentials > the web client > Authorised redirect URIs" }
why = "Google refuses to send a user back to a URI the client doesn't list"
```

The lint can't compare the value of a site with no file, and lists it as not checked; the table still tells whoever changes another site what to change and where. To move one to a doc later, mark it there and drop it from `has-no-file`.

Another repository is never an external system, even one that isn't checked out here: its end is code that its own registry can describe, so give the group to both and link them with `in-another-registry` entries. Don't write a `docs/external/` page for it.

## The reviewed section

The registry's reviewed section records each group as it was last reviewed: a fingerprint of its table, each site's marker, each value's unit, each marker's regex, and a fingerprint of each block or file a judged op relates. Values, sets and text aren't recorded, since the lint compares them on every run. The lint fails when a group differs from it, and names the group's other sites. `coupled --update <key>` records the group of each key it names as it is now, so run it only for a group whose every site is changed together and holds, never just to clear the failure. Commit the registry with the change.

## Adding a group (`/ianf-coupled $ARGUMENTS`)

1. Settle the key (see above).
2. Find every site, not only the ones named. Search for the literal value and related names across dev and prod configs, build files, app code and docs, and in any other repository the user names.
3. Reuse an existing group if this one already has one (search for `COUPLED:`).
4. Mark each site with the key and a label. For a site in another repository, mark it there if it's checked out, otherwise tell the user which file in which repository needs the marker.
5. Add the group's table to the registry, creating it with `version = 1` if there's none: its relations, each written once, a label for each site without a marker, and why its sites must change together.
6. Check that the relations hold now: the lint checks value, set and text ops, and you judge the rest. Never silently change a value to make one hold.
7. For sites in an external system, create or update `docs/external/<service>.md`, or name them in `has-no-file` (see External systems).
8. Run `coupled --fix --update <key>` from the repo root, which writes the message after each label if the settings ask for it, and records the group in the registry's reviewed section; then fix what it reports, other than relations that don't hold now. If the command isn't found, tell the user it's installed from https://github.com/ianflanagan1/coupled, and check the markers and the table by reading them against this file.
9. Reply `✅ Marked COUPLED:<key>:.`, then each site as `path:line`, then each relation that doesn't hold now.

## Changing a marked value or block

1. Search for `COUPLED:<key>:` and read every site, down to its `COUPLED:<key>:END` if it has one, the group's table in the registry, and every file the table names. For an `in-another-registry` site, search that repository for `COUPLED:<key>: <label>` to find its marker or its entry in that repository's registry, and read the file it names, on its git host if it isn't checked out. Read a `//` file in `has-no-marker` the same way.
2. Change them all together, so every relation still holds. Change the table's relations only if what must hold has changed.
3. For a site in another repository, change it there if it's checked out; otherwise tell the user what to change in which repository. For sites in an external system, tell the user what to change there, and where, as its doc or `has-no-file` says, and update its doc if it has one.
4. Run `coupled` and fix what it reports. When it reports that the group differs from what was reviewed, check that every site it names is changed and the group holds, then rerun with `--update <key>`.
