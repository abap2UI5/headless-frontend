# Contributing

## Setup

```sh
npm ci
npm run lint          # abaplint, ABAP Standard
```

Install into a system with [abapGit](https://abapgit.org);
[abap2UI5](https://github.com/abap2UI5/abap2UI5) must be present.

## Gates

Three abaplint configurations run on every pull request, and all three must be
green:

| Workflow | Config | Checks |
| --- | --- | --- |
| `ABAP_STANDARD` | `abaplint.jsonc` | v750 syntax plus the full style ruleset |
| `ABAP_CLOUD` | `.github/abaplint/abap_cloud.jsonc` | ABAP Cloud language version |
| `ABAP_702` | `.github/abaplint/abap_702.jsonc` | downports the source, then lints it as v702 |

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
drive real apps. Keep `RISK LEVEL` honest: a test that reaches
`z2ui5_cl_core_srv_draft` writes to `z2ui5_t_01` and commits, which is not
`HARMLESS`. See [ROADMAP.md](ROADMAP.md) stage 0.1.
