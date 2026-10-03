# abap2UI5 - test

**Test abap2UI5 apps in ABAP. No browser, no UI5, no HTTP.**

An abap2UI5 app is a class. Its whole conversation with the outside world is one
JSON request in, one JSON response out — the frontend sends the model delta and
an event id, the backend sends back view-lifecycle actions, a model and
follow-up actions. That is the entire contract.

This repo takes that contract seriously and plays the other side of it in ABAP.
`z2ui5_cl_frontend_simulator` builds the same request the UI5 frontend builds,
hands it to `z2ui5_cl_ui5_handler`, and replays the response the way the
frontend does — all in the same session, in the same call stack, in a plain
ABAP Unit test.

```abap
DATA(sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE` ).

sim->set_value( name = `MV_NAME` value = `World` ).
sim->click( `GREET` ).

cl_abap_unit_assert=>assert_equals( exp = `Hello World!`
                                    act = sim->get_message( ) ).
```

That is a full user session: typed a name, pressed a button, read the result
back. It runs in milliseconds, needs no server, no browser driver and no
network, and it fails with an ABAP stack trace pointing at your app.

## Why

**Testing abap2UI5 apps is currently all-or-nothing.** You either unit-test the
pieces around the app — which skips the part where the app actually talks to the
framework — or you drive a real browser with Playwright/Selenium, which is slow,
flaky, needs a deployed system, and breaks whenever the layout moves. There is
nothing in between.

The simulator is the in-between. It exercises the real framework: the real
`main( )` dispatch, the real event handling, the real model serialisation, the
real draft handling. Only the browser is missing — and the browser was never the
part with your bugs in it.

**Apps are addressed by the names their author already wrote.** `MV_NAME` is the
bound attribute (`client->_bind( mv_name )`), `GREET` is the event id
(`client->_event( 'GREET' )`). No CSS selectors, no control ids, no XPath. A
test does not break when someone swaps a `VBox` for a `Grid`, because a user
pressing "Greet" does not care either. The rendered XML is still there via
`get_view( )` when you do want to assert on it.

## The bigger idea

If the frontend contract can be served from ABAP, the browser is not the only
possible frontend — it is just the first one.

A headless module that speaks this protocol is the seam where other frontends
attach: SAP GUI, a console renderer, a REST facade, a batch driver that replays
recorded sessions — or an AI agent. The
[agent addon](https://github.com/abap2UI5-addons/agent) exposes abap2UI5 apps
over an ABAP-native MCP endpoint and uses this simulator as its engine: every
MCP call is one HTTP request, so it starts an app, `resume( )`s the session in
the next request, and builds its screen snapshot from `get_layers( )`,
`get_messages( )`, `get_actions( )` and `get_events( )`.

See [ROADMAP.md](ROADMAP.md) for where it goes from here.

## API

### Driving the app

| Method | Purpose |
| --- | --- |
| `start( app )` | Start an app — mirrors the browser's first POST with `?app_start=<class>` |
| `resume( id state refresh )` | Continue a draft-based session from its draft id in a new instance — see below |
| `set_value( name value layer )` | Queue a text value (what an input sends) into the delta of the next roundtrip |
| `set_json( path json layer )` | Queue a raw JSON value at a model path — `true`, `42`, `["A","C"]`, `{"F":1}` — see [Typed edits](#typed-edits) |
| `set_bool( name value layer )` | Queue a boolean (CheckBox, Switch), sent as JSON `true` / `false` |
| `set_cell( table row column value layer )` | Queue one table cell as a row delta (`TABLE.__delta.row.COLUMN`), `row` 1-based |
| `set_row( table row json layer )` | Queue several cells of one row from a JSON object (`{"QTY":3,"NAME":"Pen"}`), one row delta |
| `select_row( table row column selected layer )` | Select / deselect a row — a boolean in the column its items bind `selected` to |
| `close_layer( layer )` | Close a layer in the browser only (`_event_client( cs_event-popup_close )`) — no roundtrip |
| `click( event t_arg layer )` | Fire an event, send the pending edits of the firing layer's model, replay the response |
| `set_check_events( val )` | Opt in: `click( )` raises for an event that is not wired in the firing layer |

`layer` is optional everywhere: an edit goes into, and an event is fired from,
the topmost open layer unless another one is named.

The setters, `close_layer( )`, `click( )` and `set_check_events( )` return the
instance, so a whole session fits in one statement:

```abap
DATA(msg) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`
    )->set_value( name  = `MV_NAME`
                  value = `World`
    )->click( `GREET`
    )->get_message( ).
```

### Typed edits

The browser does not send text only: a CheckBox writes a boolean into its
model, a MultiComboBox an array of keys, a StepInput a number.
`set_json( path json )` queues exactly such a value; `set_value( )`,
`set_bool( )`, `set_cell( )`, `set_row( )` and `select_row( )` are shorthands
for it, so every edit takes the same way:

```abap
sim->set_bool( `MV_ACTIVE`
    )->set_json( path = `MT_KEY`
                 json = `["A","C"]`
    )->set_value( name  = `MS_ORDER/NAME`
                  value = `Max`
    )->select_row( table  = `MT_ROW`
                   row    = 2
                   column = `SELKZ`
    )->click( `SAVE` ).
```

- **An edit goes into the model of its layer** — the own copy of an open popup
  or popover, else the MAIN model the nested views share — and travels with
  the next event of that layer. An event of another layer leaves it pending;
  closing its layer drops it. This is the frontend's rule
  (`View1 _pickModelForRoundtrip`).
- **The delta is the frontend's** (`Lib.buildDeltaFromPaths`), built from the
  layer's model with every edit applied: a table cell (`/TAB/1/COL`, nested
  `/TAB/1/SUB/0/COL`) goes out as a row delta `TAB.__delta.1.COL`, every other
  path — a scalar, a structure field, an array element, a cell of a table
  inside a structure — as the whole top-level attribute. A whole value queued
  next to a delta of the same attribute wins, a later edit of a path replaces
  the earlier one.
- **Model paths count rows from 0**, as the frontend records them
  (`/MS_ORDER/T_POS/1/QTY` is the second position). `set_cell( )`,
  `set_row( )` and `select_row( )` take ABAP's 1-based row.
- **What went out stays in the layer's model**, as in the browser — the
  backend leaves an unchanged model out of its response, so `get_value( )`
  reads the sent value back afterwards. A pending edit is not visible there.
- `get_request_json( )` shows the request as it went out, the delta included.

### Reading the screen

| Method | Purpose |
| --- | --- |
| `get_view( layer )` | View XML of the topmost open layer (popover, else popup, else the main view) — or of the given one |
| `get_popup( )` / `get_popover( )` | XML of the open popup / popover, empty when closed |
| `get_layer( )` | Name of the topmost open layer: `POPOVER`, `POPUP` or `MAIN` |
| `get_layers( )` | Every open layer — `MAIN`, `NEST`, `NEST2`, `POPUP`, `POPOVER` — with view XML, JSON model, owning app and anchor control |
| `get_model( layer )` | JSON model of the topmost (or given) layer |
| `get_value( name layer )` | A value from the model of the topmost (or given) layer, falling back to the last model the server sent |
| `get_events( layer )` | Events wired in the active (or given) layer |
| `check_event_exists( event layer )` | Whether an event is wired in the active (or given) layer |
| `get_message( )` | Text of the last toast / message box of the last roundtrip |
| `get_messages( only_last )` | All messages of the session: source (`toast` / `box`), type (`success` / `info` / `warning` / `error`), raw MessageBox method, text, title, details, roundtrip |
| `get_actions( )` | Follow-up actions of the last response (`SET_FOCUS`, `CONTROL_BY_ID`, ...) with their arguments |
| `get_nav( )` | Browser-history intent of the last response (app-state hash, push state, routing mode, nav-back) — read-only |
| `get_app( )` | App class that answered the last roundtrip — after `nav_app_call( )` the called one |
| `get_id( )` | Current draft id |
| `is_sticky( )` | Whether the app runs in a held stateful session (no draft, cannot be resumed) |
| `get_state( )` | What the browser knows and the draft does not, as JSON — for `resume( )` |
| `get_roundtrip( )` | Number of roundtrips of this instance |
| `get_response_json( )` | Raw response JSON of the last roundtrip |
| `get_request_json( )` | Raw request JSON of the last roundtrip, with the model delta as it went out |

### Layers

The frontend has five view slots, and the simulator keeps them the same way:

- **`MAIN`** — the page. A new main view is a new screen: it takes the nested
  views, the popup and the popover down with it.
- **`NEST`, `NEST2`** — nested views inserted into a control of the main view
  (`anchor_id`). They own no model; `get_layers( )` reports the main model
  they inherit.
- **`POPUP`, `POPOVER`** — standalone, on top of the page, each with its own
  copy of the model. A popover remembers the control it opens by
  (`anchor_id`). Both die when the response names another app.

A response's model is pushed into every open layer that belongs to the app that
answered — exactly the frontend's rule, so a popup of a called app does not see
the caller's model.

A layer the browser closes on its own — `_event_client( cs_event-popup_close )`
— is closed with `close_layer( )`: no roundtrip, the backend is not told, the
layer and the unsent edits of its model are gone, and `get_state( )` no longer
carries it.

### Event validation

`check_event_exists( )` and `get_events( )` read the event wires
(`.eB(['NAME',...])`) out of the active layer: an open popover, else an open
popup — dialogs are modal — else the main view with its nested views. With
`set_check_events( )` on, `click( )` refuses an event the user could not reach
and names the ones they could. A `click( )` that names the `MAIN` layer while a
popup is open is refused as well — a dialog is modal. It is a check on the
view XML, not on a control tree: visibility and enablement are not evaluated,
and events raised by timers or keyboard shortcuts are not wired in a view.

### Resuming a session

Every `start( )` / `click( )` is one roundtrip, and the draft id is the whole
backend state of a draft-based app — which is what lets a session continue in
another request, another work process:

```abap
" request 1
DATA(sim) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_LAYERS` ).
sim->click( `POPUP_OPEN` ).
DATA(id)    = sim->get_id( ).
DATA(state) = sim->get_state( ).

" request 2
sim = z2ui5_cl_frontend_simulator=>resume( id = id state = state ).
sim->set_value( name = `MV_POPUP_TEXT` value = `Bea` )->click( `POPUP_CONFIRM` ).
```

What `resume( )` does and does not do:

- **It sends what the browser sends.** No roundtrip happens on `resume( )`; the
  next `click( )` posts the draft id, the pending delta and the event, and the
  backend restores the app from the draft. Nothing else is needed on the
  backend side.
- **The view comes from `state`.** The backend does not keep view XML — the
  browser does. Pass the `get_state( )` string of the previous request and the
  layers (XML and model per layer) are back. A state that belongs to another
  draft id is refused.
- **Without `state`** the instance knows the app class and the model from the
  draft, but no view and no layer: `get_value( )` works, `get_view( )` is
  empty, and `set_check_events( )` would refuse every event.
- **`refresh = abap_true` re-requests the view** with the request a browser
  reload sends for a routed app (`#/app/<class>/<draft>`): the app runs
  `check_on_navigated( )` and, written the canonical way, displays its main
  view again. A popup is back only if the app re-opens it there. The restore
  mints a new draft id.
- **Sticky apps cannot be resumed.** A stateful session
  (`client->set_session_stateful( )`) keeps the app in the handler, not in a
  draft — the id it reports has no draft behind it, and `resume( )` raises.
  Within one instance a sticky app works normally (`is_sticky( )` tells).
- **The draft must still exist and belong to the current user** — the draft
  service binds drafts to their creator and expires them after a few hours.

Each `start( )` / `click( )` is exactly one roundtrip. Sticky apps keep their
handler between roundtrips, draft-based apps chain their state through the
persisted id — the same distinction `z2ui5_cl_ui5_http_handler=>_http_post`
makes, so what you test is what runs in production.

## Contents

| Object | Description |
| --- | --- |
| `z2ui5_cl_frontend_simulator` | The simulator |
| `z2ui5_cl_frontend_sim_example` | Minimal app — one input, one text, two buttons — that exists to be driven by it |
| `z2ui5_cl_frontend_sim_layers` | Example app with every layer: popup, popover, nested view, an editable table, follow-up actions, a message box, app-state hash, `nav_app_call( )` and the switch to a sticky session |
| `z2ui5_cl_frontend_sim_form` | Example app for typed edits: a CheckBox, a MultiComboBox, a structure that holds a table, a selectable table with a nested table in its rows |

The simulator's own unit tests live in
`z2ui5_cl_frontend_simulator.clas.testclasses.abap` and drive both example
apps and the form app. They double as the usage documentation:

- `ltcl_frontend_simulator` (`RISK LEVEL HARMLESS`) installs an in-memory draft
  store through the core's store seam (`z2ui5_cl_ui5_srv_draft=>set_instance`),
  so even the draft path writes nothing to the database.
- `ltcl_frontend_simulator_db` (`RISK LEVEL DANGEROUS`) runs against the real
  store — `Z2UI5_T_01` and its commits — including the rollback bracket the
  framework puts around `main( )` in the draft path, and deletes every draft it
  created in `teardown`.

## Installation

Install with [abapGit](https://abapgit.org). Requires
[abap2UI5](https://github.com/abap2UI5/abap2UI5) in the same system, at a
version that speaks wire protocol 2 (`S_FRONT.S_ACTION`) — a response that
names another protocol is refused with `PROTOCOL_MISMATCH`. Runs on ABAP
Standard, ABAP Cloud and — via the downport in CI — 7.02.

The simulator works on the core's engine (`z2ui5_cl_ui5_handler` and the draft
service), which is not part of abap2UI5's released API in `src/02` — a core
change there can require a change here.

## Current scope

Covered: the main view, nested views, popup and popover with their models,
messages with severity, follow-up actions, the browser-history intent, typed
edits (booleans, arrays, numbers, structures with tables) with the frontend's
delta per layer model, table row deltas including nested tables, row
selection, closing a layer in the browser, sticky and draft sessions,
app-to-app navigation, resuming a session across requests, and an opt-in check
that an event is wired in the active layer.

Not covered yet: an injectable frontend `CONFIG` (device, UI5 version, focus,
scroll), a control tree with visibility and enablement, and
`set_value( )` validation against the bound paths. [ROADMAP.md](ROADMAP.md)
has the plan and the order.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every change must leave `abaplint` at
zero issues.

## License

MIT — see [LICENSE](LICENSE).
