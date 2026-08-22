# Contributing

## Development

No build step and no npm dependencies. Three checks run on every pull request
and on pushes to `master` ([.github/workflows/checks.yml](.github/workflows/checks.yml)),
all runnable locally:

```bash
node Model.test.js
node Release.test.js
```

`Model.js` holds the pure logic (formatting, validation, history parsing and
capping) and `Model.test.js` is a plain `assert` self-check — no framework.
`Release.js` holds the version-bump logic used by the release workflow, with
`Release.test.js` as its self-check in the same shape. The last check parses
`manifest.json`, which catches a typo that would otherwise make the plugin
silently undiscoverable.

The QML is not linted or covered by tests. `qmllint` was tried and removed:
Quickshell is AUR-only and `qs.*` is omarchy-shell's own module namespace, so
neither resolves on a stock runner, and every type in the QML files comes from
one of them — the run produced 317 warnings, none of them real. See
[improvements.md](improvements.md) for the measurement and the upgrade path.

## Dev setup

Clone the repo directly into the plugin directory (see [README.md](README.md#install)
for the full install flow), then edit in place:

```bash
git clone https://github.com/nejcm/omarchy-pomodoro.git ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy-shell shell rescanPlugins
```

`omarchy plugin validate` rejects a symlinked plugin folder, so a working copy
has to live at that path — there is no separate "link a local checkout" mode.
Re-run `omarchy-shell shell rescanPlugins` after editing `Service.qml`,
`BarWidget.qml` or `Panel.qml` to pick up changes; `Model.js` and `Release.js` changes are covered
by the test commands above instead of a manual reload.

## Releases

`version` in `manifest.json` is bumped automatically on every push to `master`
([.github/workflows/release.yml](.github/workflows/release.yml)) — **do not edit
it by hand.** The workflow reads the conventional-commit subjects since the last
`vX.Y.Z` tag, takes the highest bump level, writes the new version, commits it as
`chore(release): vX.Y.Z`, tags it, and publishes a GitHub Release with
auto-generated notes.

| Commit | Bump |
|---|---|
| `type!:` in the subject, or `BREAKING CHANGE:` in the body | major |
| `feat:` | minor |
| `fix:`, `perf:`, `revert:`, `chore:`, `refactor:` | patch |
| anything else (`docs:`, `ci:`, `style:`, `test:`, `build:`) | no release |

A push containing only `docs`/`ci` commits ships nothing: the job runs, reports
that there is no release-worthy commit, and succeeds. Release commits are skipped
by the workflow's own guard, so it cannot loop.
