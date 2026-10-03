# Roadmap

Where the headless frontend simulator goes next, in the order it should get
there. Every stage is independently shippable; nothing later depends on
anything later than itself.

Code references point at [abap2UI5](https://github.com/abap2UI5/abap2UI5) as of
2026-10-03 (wire protocol 2, `S_FRONT.S_ACTION`). Status markers: **done**,
**partly done**, **open**.

---

## Stage 0 — Correctness — **done**

### 0.1 The unit tests commit to the database — **done**

`z2ui5_cl_ui5_handler` saves a draft whenever the app is not sticky
(`main_end_save`), the draft service ends in `INSERT z2ui5_t_01` +
`COMMIT WORK AND WAIT`, and every app start runs the draft `cleanup( )` — a
`DELETE` plus `COMMIT WORK`, sticky or not. The test class declared
`RISK LEVEL HARMLESS`.

The plan was to make the example app sticky; the start-up cleanup makes that
insufficient. What shipped instead:

- The `HARMLESS` class installs an in-memory draft store through the core's
  store seam (`z2ui5_cl_ui5_srv_draft=>set_instance`). The full draft
  roundtrip — serialize, persist, restore — runs without a database write.
- `ltcl_frontend_simulator_db` (`RISK LEVEL DANGEROUS`) covers the real store
  on purpose and deletes every draft it created in `teardown`.
- The rollback bracket is covered: in the draft path an uncommitted row of the
  caller is gone after `click( )` (`db_rollback( )` before `main( )`), in a
  sticky session it survives.

Still true and untested: `prepare_app_stack` (`z2ui5_cl_ui5_action`) calls
`db_save( )` unconditionally, so app-to-app navigation persists a draft even
for sticky apps.

### 0.2 Message handling loses data — **done**

`get_messages( )` returns every toast and message box of the session with
source, type (`success` / `info` / `warning` / `error`), the raw MessageBox
method, title, details and roundtrip number. `get_message( )` stays the
convenience accessor for the last message of the last roundtrip.

---

## Stage 1 — Protocol coverage — **done**

The response is documented in `app/webapp/core/Server.js`: the view lifecycle
travels as `VIEW_SLOTS` system actions, history as one `ROUTER/sync` action,
everything an app queued as follow-up actions, and the model once per
response.

### 1.1 Popups — `POPUP`, `POPOVER` — **done**

`get_popup( )`, `get_popover( )`, `get_layer( )`, and a `get_view( )` that
returns the topmost open layer. Each standalone layer keeps its own model,
pushed only from responses of the app that owns it — the frontend's rule
(`actions/Slots updateModelIfRequired`). A new main view and an app switch take
both down, as on the frontend.

### 1.2 Nested views — `NEST`, `NEST2` — **done**

Parsed with their anchor control, reported with the main model they inherit,
destroyed with the main view.

### 1.3 Follow-up actions and browser state — **done**

`get_actions( )` lists the follow-up actions of the last response with their
arguments; `get_nav( )` exposes the `ROUTER/sync` options (app-state hash, push
state, hash replace, routing mode, nav-app-call bookkeeping) and whether the
main display played as a way back. Read-only — nothing is navigated.

---

## Stage 2 — The request side — **partly done**

### 2.1 Table deltas — **done**

`set_cell( table row column value )` sends the frontend's row delta
(`TAB.__delta.{row}.{col}`, `Lib.buildDeltaFromPaths`), `set_row( )` several
cells of one row, `select_row( )` the boolean a selectable table writes into
its rows. Nested tables get one `__delta` level per table.

### 2.1b Typed edits — **done**

Asked for by the [agent addon](https://github.com/abap2UI5-addons/agent),
which had to refuse booleans as anything but `X` / space, MultiComboBox
arrays and edits inside a structure that also holds a table.
`set_json( path json )` queues a raw JSON value at a model path (`set_bool( )`
is the boolean shorthand), and every setter shares its path logic: an edit
goes into the model of the layer it is made in, and `click( )` sends the delta
`Lib.buildDeltaFromPaths` builds from that model with the edits applied — a
row delta for a table cell, the whole top-level attribute for everything else.
Edits of another layer's model wait for an event of their own layer (an
optional `layer` on every setter and on `click( )`), and what went out stays
in the layer's model, as in the browser. `get_request_json( )` shows the
request as it went out.

### 2.2 Injectable frontend `CONFIG` — **open**

`S_UI5`, `S_DEVICE`, `S_FOCUS`, `S_SCROLL` and `ComponentData` are not sent at
all today, so an app that branches on device or theme sees initial values.
Making them injectable fixes that — and is the lever for stage 4, where a
non-browser frontend declares what it actually is.

---

## Stage 3 — Fidelity — **partly done**

This is what turns a protocol driver into a browser simulator.

`click( 'GREET' )` fires the event regardless of whether that button is
rendered, visible or enabled — unless the test opts in.

- **3.1** Parse the view XML into a lightweight control tree once, while parsing
  the response. — **open**
- **3.2** Make `click( )` verify the event id occurs in the active view and
  `set_value( )` verify the path is bound there. — **partly done**:
  `check_event_exists( )`, `get_events( )` and the opt-in
  `set_check_events( )` read the event wires of the active layer (topmost
  popover / popup, else main plus nested views) out of the XML. It is opt-in
  rather than opt-out to keep existing tests green. `set_value( )` is not
  checked yet, and visibility / enablement need 3.1.
- **3.3** Build assertions on the tree: `get_control( )`, `check_visible( )`,
  `check_enabled( )`. — **open**

The control tree from 3.1 is also the prerequisite for stage 4, which is why
stage 3 comes before it rather than after.

---

## Stage 3b — Sessions across requests — **done**

Added for the [agent addon](https://github.com/abap2UI5-addons/agent), which
drives apps over MCP: every tool call is a separate HTTP request.

- `resume( id state refresh )` continues a draft-based session in a new
  instance. The backend needs nothing but the draft id; the view XML of each
  layer comes from `get_state( )` of the previous request, or is re-requested
  with a route-restore roundtrip (`refresh`). Sticky apps keep no draft and
  cannot be resumed — `resume( )` raises, `is_sticky( )` tells beforehand.
- `get_app( )`, `get_layers( )` (XML and model per layer), `get_messages( )`,
  `get_actions( )` and `get_events( )` are what the agent's screen snapshot is
  built from.
- `close_layer( layer )` closes a layer the way a frontend event does
  (`_event_client( cs_event-popup_close )`): no roundtrip, the layer and the
  unsent edits of its model are gone, `get_state( )` reflects it. The agent
  used to edit the private state JSON for its `@CLOSE_POPUP`.

---

## Stage 4 — Other frontends — **open**

Only worth starting once stages 1–3 are in. Then split the simulator along the
seam it already implies:

- `z2ui5_cl_frontend_session` — protocol only: roundtrip, draft id, sticky
  handling, resume, app stack. Essentially what exists today.
- `z2ui5_cl_frontend_view` — response XML to control tree with binding paths.
  Falls out of 3.1.
- `z2ui5_if_frontend` — the contract an alternative frontend implements.

The simulator becomes a thin facade over the two. A SAP GUI renderer, a console
renderer or a REST facade is then a second consumer of the same base rather than
a fork of the simulator — which is where this ends up if the split does not
happen first. The agent addon is the first such consumer.

---

## Stage 5 — Convenience — **open**

Once the foundation is right:

- **Record and replay.** Dump a session to JSON, replay it as a regression test.
  Lets people write tests without writing ABAP. `get_state( )` is the start of
  the format.
- **Assertion helpers** that return the instance, so assertions chain like the
  rest of the API.

---

## Order

Next: 2.2 (frontend `CONFIG`), then 3.1 — the control tree is what closes 3.2
(bound-path check, visibility, enablement) and opens stage 4.
