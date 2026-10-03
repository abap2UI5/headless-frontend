# Contributing

## Setup

```sh
npm ci
npm run lint          # abaplint, ABAP Standard
npm run unit          # the ABAP Unit tests on abap2UI5's transpiled runtime
```

Install into a system with [abapGit](https://abapgit.org);
[abap2UI5](https://github.com/abap2UI5/abap2UI5) must be present.

## Gates

Three abaplint configurations and the unit tests run on every push and pull
request, and all four must be green:

| Workflow | Config | Checks |
| --- | --- | --- |
| `ABAP_STANDARD` | `abaplint.jsonc` | v750 syntax plus the full style ruleset |
| `ABAP_CLOUD` | `.github/abaplint/abap_cloud.jsonc` | ABAP Cloud language version |
| `ABAP_702` | `.github/abaplint/abap_702.jsonc` | downports the source, then lints it as v702 |
| `ABAP_UNIT` | `.github/scripts/unit.mjs` | the ABAP Unit tests on abap2UI5 `main`, transpiled (`npm run unit`) |

`ABAP_702` runs `npm run downport` first, which rewrites the sources in place.
That transformation belongs to CI only — **never commit downported source**. The
repo is written in modern ABAP; 7.02 support is produced, not maintained by
hand.

Run `npm run lint` before every commit and leave it at zero issues.

## Conventions

Same house style as [abap2UI5](https://github.com/abap2UI5/abap2UI5):

- Backticks for string literals, string templates (`|...{ }...|`) for
  concatenation.
- Prefix tables `t_` and structures `s_`; local types `ty_s_` / `ty_t_`;
  instance attributes `mv_` / `mo_` / `mt_` / `ms_`.
- `DATA` declarations inline where the version allows it.
- Keywords upper case, everything else lower case.
- Classes are named `z2ui5_cl_*`, interfaces `z2ui5_if_*`.

**ABAP Doc (`"!`) is parsed as HTML.** A raw `<...>` is read as an HTML tag, so
never put a literal UI5 element or any other `<tag>` in a `"!` comment — write it
plain or escape it as `&lt;tag&gt;`. abaplint flags it as both an unsupported and
an unclosed tag.

## Tests

Unit tests live in the class's `.clas.testclasses.abap` and use the simulator to
drive real apps. Keep `RISK LEVEL` honest: a test that reaches the shipped draft
store writes to `z2ui5_t_01` and commits — and every app start runs the draft
cleanup, sticky or not — which is not `HARMLESS`.

- `ltcl_frontend_simulator` is `HARMLESS` because its `setup` installs the
  in-memory store `ltd_draft_store` through `z2ui5_cl_ui5_srv_draft=>set_instance`
  and its `teardown` restores the default. New tests that do not need the real
  database go here.
- `ltcl_frontend_simulator_db` is `DANGEROUS` and runs against `z2ui5_t_01`.
  Pass every simulator to `track( )` after each roundtrip so `teardown` deletes
  the drafts it created.

### Running them without a system

The tests run on the transpiled runtime abap2UI5 uses for its own suite (SQLite
behind the database statements, so `ltcl_frontend_simulator_db` runs too):

```sh
npm run unit                                          # every Z2UI5_CL_FRONTEND_SIM* test
UNIT_FILTER=ltcl_frontend_simulator_db npm run unit   # only those whose "OBJECT: class->method" contains it
```

`.github/scripts/unit.mjs` is the whole recipe, and the `ABAP_UNIT` workflow
runs the same script (with the checkout made by `actions/checkout`): a checkout of abap2UI5 `main` in `.unit/abap2UI5`
(git-ignored; cloned on the first run, refreshed on every later one), `npm ci`
there, this repository's `src/` copied in as the package `src/zz_headless_frontend`,
`npm run downport && npm run auto_transpile`, then the generated tests of
`Z2UI5_CL_FRONTEND_SIM*` - each one printed, exit code 1 on any failure or when
none ran. The first run takes a few minutes (install, downport, transpile of
the whole framework).

Never commit `.unit/`. A green transpiled run is not a substitute for running
the tests on a system (see abap2UI5's `abap-check` skill for what the
transpiler cannot see).
