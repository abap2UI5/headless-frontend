# AGENTS.md — abap2UI5 headless frontend

Single source of truth for agents working on **headless-frontend**: an ABAP
implementation of the browser side of the abap2UI5 wire protocol.
`z2ui5_cl_frontend_sim` builds the request the UI5 frontend builds, hands it
to `z2ui5_cl_ui5_handler` and replays the response - so an abap2UI5 app can
be driven from ABAP Unit, without a browser. `CLAUDE.md` next to this file is
a pointer at it, nothing more. Human-facing docs: [README](README.md),
[CONTRIBUTING](CONTRIBUTING.md), [ROADMAP](ROADMAP.md).

**Language:** English for all code, comments, docs, commit messages, PRs.

## Layout

| Path | What |
|---|---|
| `src/z2ui5_cl_frontend_sim.clas.abap` | the simulator: request building, response parsing (VIEWS / NAV / ACTIONS), layers, model |
| `src/z2ui5_cl_frontend_sim.clas.testclasses.abap` | its tests, with an in-memory draft store double |
| `src/z2ui5_cl_frontend_{example,form,layers}.clas.abap` | example apps the tests drive |
| `abaplint.jsonc`, `.github/abaplint/abap_{cloud,702}.jsonc` | the three lint configurations |
| `.github/scripts/unit.mjs` | ABAP Unit on the transpiled abap2UI5 of `@abap2ui5/node-runtime` |
| `.github/scripts/rename.mjs` | the namespace rename check, shared with the addons - change it everywhere or nowhere |
| `.github/scripts/downport-fixes.mjs` | the text rewrites of `npm run auto_downport` (`syfixes`, `strip_trailing_ws`, `abaplintpathfix`) - node, not `sed -i`, so they run on BSD/macOS sed too |

## The contract it follows

- It speaks the **wire protocol of abap2UI5** (`c_protocol`, currently 3) as
  specified in [abap2UI5/protocol](https://github.com/abap2UI5/protocol).
  A new protocol revision in abap2UI5 means a change here; a response with
  another protocol number is refused with `PROTOCOL_MISMATCH`.
- Its public methods (`start`, `resume`, `click`, `set_value`, `get_view`,
  `get_layers`, `get_actions`, `get_nav`, ...) are API for
  [abap2UI5-addons/abap-agent-runtime](https://github.com/abap2UI5-addons/abap-agent-runtime),
  which pins this repository in its `.github/deps.json`. Change them only
  additively; run that repository's `npm run check` and `npm run unit` against
  your change before pushing.
- Test doubles implement framework interfaces (`z2ui5_if_ui5_draft_store`):
  a new method there is a compile error here.

## Commands

```sh
npm ci
npm run check   # lint (standard), lint:cloud, rename
npm run unit    # ABAP Unit on @abap2ui5/node-runtime
```

The unit tests run against the PUBLISHED runtime of abap2UI5
(`@abap2ui5/node-runtime` in package.json). Until a release is on npm, a
change that follows abap2UI5 main can only be unit-tested against a locally
packed runtime; say so in the PR.

## Rules

- `npm run check` stays at zero issues before every commit.
- Never commit downported source (`ABAP_702` rewrites it in CI only).
- abap2UI5 is linted as `/src/0[0-2]/**/*.*`: its `src/03` (ICF handler on
  `IF_HTTP_EXTENSION`, BSP) is the installation package, nothing here uses it.
- House style of abap2UI5 (see CONTRIBUTING).
