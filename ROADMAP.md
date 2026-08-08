# Roadmap

Where the headless frontend simulator goes next, in the order it should get
there. Every stage is independently shippable; nothing later depends on
anything later than itself.

Line references point at [abap2UI5](https://github.com/abap2UI5/abap2UI5) as of
2026-08-08.

---

## Stage 0 — Correctness

Small, but blocking: these are defects in what already exists, and they get
harder to fix once other people run this code.

### 0.1 The unit tests commit to the database

`z2ui5_cl_core_handler` calls `db_save( )` whenever the app is not sticky
(`core_handler.clas.abap:639`), and `z2ui5_cl_core_srv_draft->create( )` ends in
`MODIFY z2ui5_t_01` + `COMMIT WORK AND WAIT`. The test class declares
`RISK LEVEL HARMLESS`, which by definition means no database updates.

The fix is not simply raising the risk level, because the draft roundtrip is
exactly what you want covered for real apps. Split it:

- Give the example app `check_sticky = abap_true`. The handler is then held
  between roundtrips and no draft is written, so the existing tests are honestly
  `HARMLESS`.
- Add a second test class at `RISK LEVEL DANGEROUS` that covers the draft path
  on purpose, with a teardown that deletes the rows it created.

While doing this, cover the rollback bracket too: in non-sticky mode the
framework wraps the app's `main( )` in `db_rollback( )` on both sides
(`core_handler.clas.abap:651` and `:667`). That is observable behaviour and
nothing tests it today.

Watch out for one asymmetry: `prepare_app_stack` (`core_action.clas.abap:215`)
calls `db_save( )` unconditionally, so app-to-app navigation persists a draft
even for sticky apps.

### 0.2 Message handling loses data

`parse_response( )` keeps a single `mv_message` and picks the toast *or* the
box. If a roundtrip produces both, the box is silently dropped. There is also no
severity and no history — the field is cleared on every roundtrip.

Replace it with a message table carrying type and severity, kept across the
session, and keep `get_message( )` as the convenience accessor for the last one.

---

## Stage 1 — Protocol coverage

The response wire format is documented in `app/webapp/core/Server.js:148`. The
simulator reads four fields of it. This is the functional gap.

### 1.1 Popups — `S_POPUP`, `S_POPOVER`

The single biggest unlock. Without it not one dialog flow is testable, and
dialogs are everywhere in real abap2UI5 apps. Needs `get_popup( )` and a
`get_view( )` that returns the topmost active view rather than always the main
one.

Note that popups own their own model (`core_action.clas.abap:202-210` — MAIN,
popup and popover are the three slots with a model), so the model slice has to
follow the active view, not be assumed global.

### 1.2 Nested views — `S_VIEW_NEST`, `S_VIEW_NEST2`

Inserted into the MAIN control tree and inheriting its model, so simpler than
popups: parse and expose, no separate model handling.

### 1.3 Follow-up actions and browser state

`S_FOLLOW_UP_ACTION/CUSTOM_JS`, `SET_NAV_BACK`, `SET_PUSH_STATE`,
`SET_APP_STATE_ACTIVE`. Exposing them read-only is enough to let a test assert
"focus was set" or "navigation went back" — behaviour that is currently
invisible.

---

## Stage 2 — The request side

### 2.1 Table deltas

The wire format carries `TAB.__delta.{row}.{col}` (`Server.js:135`);
`set_value( )` can only write scalars. Everything with an editable table — which
is most real apps — is untestable until this exists. Needs `set_cell( )` and
`set_row( )` producing the delta structure.

### 2.2 Injectable frontend `CONFIG`

`S_UI5`, `S_DEVICE`, `S_FOCUS`, `S_SCROLL` and `ComponentData` are not sent at
all today, so an app that branches on device or theme sees initial values.
Making them injectable fixes that — and is the lever for stage 4, where a
non-browser frontend declares what it actually is.

---

## Stage 3 — Fidelity

This is what turns a protocol driver into a browser simulator.

Today `click( 'GREET' )` fires the event regardless of whether that button is
rendered, visible or enabled. A green test can therefore describe a flow no user
could perform — which is the one failure mode a test suite must not have.

- **3.1** Parse the view XML into a lightweight control tree once, while parsing
  the response.
- **3.2** Make `click( )` verify the event id occurs in the active view and
  `set_value( )` verify the path is bound there; raise otherwise. Keep an
  explicit opt-out for tests that deliberately exercise the protocol.
- **3.3** Build assertions on the tree: `get_control( )`, `check_visible( )`,
  `check_enabled( )`.

The control tree from 3.1 is also the prerequisite for stage 4, which is why
stage 3 comes before it rather than after.

---

## Stage 4 — Other frontends

Only worth starting once stages 1–3 are in. Then split the simulator along the
seam it already implies:

- `z2ui5_cl_frontend_session` — protocol only: roundtrip, draft id, sticky
  handling, app stack. Essentially what exists today.
- `z2ui5_cl_frontend_view` — response XML to control tree with binding paths.
  Falls out of 3.1.
- `z2ui5_if_frontend` — the contract an alternative frontend implements.

The simulator becomes a thin facade over the two. A SAP GUI renderer, a console
renderer or a REST facade is then a second consumer of the same base rather than
a fork of the simulator — which is where this ends up if the split does not
happen first.

---

## Stage 5 — Convenience

Once the foundation is right:

- **Record and replay.** Dump a session to JSON, replay it as a regression test.
  Lets people write tests without writing ABAP.
- **Assertion helpers** that return the instance, so assertions chain like the
  rest of the API.

---

## Order

Stage 0.1 first, because it is a real defect and cheap to fix now. Then 1.1,
because popups are the wall you hit on the first realistic app. Everything after
that is genuinely optional until someone needs it.
