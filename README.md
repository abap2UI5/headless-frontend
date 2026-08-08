# abap2UI5 - test

**Test abap2UI5 apps in ABAP. No browser, no UI5, no HTTP.**

An abap2UI5 app is a class. Its whole conversation with the outside world is one
JSON request in, one JSON response out — the frontend sends the model delta and
an event id, the backend sends back a view, a model and some messages. That is
the entire contract.

This repo takes that contract seriously and plays the other side of it in ABAP.
`z2ui5_cl_frontend_simulator` builds the same request struct the UI5 frontend
builds, hands it to `z2ui5_cl_core_handler`, and parses the response — all in
the same session, in the same call stack, in a plain ABAP Unit test.

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
`main( )` dispatch, the real `check_on_event( )` chain, the real model
serialisation, the real draft handling. Only the browser is missing — and the
browser was never the part with your bugs in it.

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
recorded sessions. Each one needs the same two things the simulator already
needs — a protocol layer that owns the roundtrip, and a view layer that turns
the response XML into something renderable.

The simulator is the first consumer of that seam and the one that proves it
works. See [ROADMAP.md](ROADMAP.md) for how it gets there.

## API

| Method | Purpose |
| --- | --- |
| `start( app )` | Start an app — mirrors the browser's first POST with `?app_start=<class>` |
| `set_value( name value )` | Queue a value into the model delta of the next roundtrip |
| `click( event t_arg )` | Fire an event, send the pending delta, parse the response |
| `get_view( )` | Current view XML (last non-empty `S_VIEW/XML`) |
| `get_value( name )` | Read a value from the last server model |
| `get_message( )` | Text of the last message toast / message box |
| `get_id( )` | Current draft id |
| `get_response_json( )` | Raw response JSON of the last roundtrip |

`set_value( )` and `click( )` return the instance, so a whole session fits in one
statement:

```abap
DATA(msg) = z2ui5_cl_frontend_simulator=>start( `Z2UI5_CL_FRONTEND_SIM_EXAMPLE`
    )->set_value( name  = `MV_NAME`
                  value = `World`
    )->click( `GREET`
    )->get_message( ).
```

Each `start( )` / `click( )` is exactly one roundtrip. Sticky apps keep their
handler between roundtrips, draft-based apps chain their state through the
persisted id — the same distinction `z2ui5_cl_http_handler=>_http_post` makes,
so what you test is what runs in production.

## Contents

| Object | Description |
| --- | --- |
| `z2ui5_cl_frontend_simulator` | The simulator |
| `z2ui5_cl_frontend_sim_example` | Minimal app — one input, one text, two buttons — that exists to be driven by it |

The simulator's own unit tests live in
`z2ui5_cl_frontend_simulator.clas.testclasses.abap` and drive the example app
through a full session. They double as the usage documentation.

## Installation

Install with [abapGit](https://abapgit.org). Requires
[abap2UI5](https://github.com/abap2UI5/abap2UI5) in the same system. Runs on
ABAP Standard, ABAP Cloud and — via the downport in CI — 7.02.

## Current scope

The simulator parses `S_VIEW/XML`, `S_MSG_TOAST`, `S_MSG_BOX` and `MODEL` out of
the response. Not covered yet: popups (`S_POPUP`, `S_POPOVER`), nested views
(`S_VIEW_NEST`), follow-up actions, table deltas (`__delta`) and frontend
`CONFIG`. [ROADMAP.md](ROADMAP.md) has the plan and the order.

Known limitation worth stating up front: `click( )` does not yet check that the
event exists in the current view, so a test can drive a flow a real user could
not. Closing that gap is roadmap stage 3.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every change must leave `abaplint` at
zero issues.

## License

MIT — see [LICENSE](LICENSE).
