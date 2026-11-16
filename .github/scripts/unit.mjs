#!/usr/bin/env node
/*
 * unit - runs the ABAP Unit tests of this repository without an SAP system,
 * on abap2UI5's transpiled Node runtime (SQLite behind the database
 * statements, so RISK LEVEL DANGEROUS classes run too).
 *
 * The framework is not built here. abap2UI5 downports and transpiles itself
 * and publishes the result as the npm package @abap2ui5/node-runtime; this
 * script takes that package (a devDependency, pinned exactly) and has it add
 * this repository's classes - "Your own unit tests" in the package's README,
 * `abap2ui5-transpile src <out> --unit-tests` as a function:
 *
 *   1. transpile( ) of the package's setup/transpile.mjs with
 *      `unitTests: true` - open-abap-core and express-icf-shim at the commits
 *      the package records (once, under
 *      node_modules/.cache/abap2ui5-node-runtime), src/ and the package's
 *      downport/ - the framework's ABAP, from the release commit - in one
 *      transpile into UNIT_DIR/output, with the transpiler the package names
 *      (@abaplint/transpiler-cli, a devDependency at exactly that version -
 *      another one is refused) and its ABAP Unit runner. The package ships no
 *      test classes of the framework, so the generated runner holds this
 *      repository's and nothing else. About 15 seconds
 *   2. the generated tests - all risk levels - each one reported, exit code
 *      1 on any failure or when no test ran at all. The transpiler's own
 *      runner (UNIT_DIR/output/index.mjs) stops at the first failure and
 *      knows no filter, so its list of tests is run by the runner below
 *
 *   npm ci
 *   npm run unit
 *   UNIT_FILTER=ltcl_frontend_simulator_db npm run unit
 *
 * Environment:
 *   UNIT_DIR     the work folder (default .unit, git-ignored), below the
 *                repository - the transpiler reads every folder relative to it.
 *                Its output/ is emptied before every transpile
 *   UNIT_FILTER  run only the tests whose "OBJECT: class->method" contains it
 *
 * The framework under test is the release in package.json, not abap2UI5's
 * main: bump @abap2ui5/node-runtime (and @abaplint/transpiler-cli to the
 * `abap2ui5.transpiler` its package.json names) to test against a newer one.
 * src/ is transpiled as it is written, not downported first - the 702
 * rendering is what ABAP_702 lints.
 *
 * Never commit the work folder. A green transpiled run is not a substitute
 * for a run on a system (abap2UI5's abap-check skill lists what the
 * transpiler cannot see).
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const WORK = path.resolve(ROOT, process.env.UNIT_DIR || ".unit");

const CONFIG = {
  // the test classes of this repository
  prefix: "Z2UI5_CL_FRONTEND",
  // abap2UI5, transpiled, and the tool that adds classes to it
  runtime: "@abap2ui5/node-runtime",
  // this repository's ABAP, relative to ROOT
  abap: "src",
};

function fail(message) {
  console.error(`::error::unit: ${message}`);
  process.exit(1);
}

// 1. the package, and one transpile of the framework and this repository
// with the unit tests switched on - the package checks the transpiler's
// version, fetches the two libraries and writes the config
const require = createRequire(path.join(ROOT, "package.json"));
let manifest;
try {
  manifest = require(`${CONFIG.runtime}/package.json`);
} catch {
  fail(`${CONFIG.runtime} is not installed - run \`npm ci\` first`);
}
const built = manifest.abap2ui5 || {};
const { transpile } = await import(`${CONFIG.runtime}/setup/transpile.mjs`);
console.log(`${CONFIG.runtime} ${manifest.version} (abap2UI5 @ ${built.commit}, transpiler ${built.transpiler})`);

const output = path.join(WORK, "output");
console.log(`\n== transpile: ${CONFIG.abap}/ with ${CONFIG.runtime}/downport`);
try {
  transpile({ cwd: ROOT, abap: CONFIG.abap, output, unitTests: true, log: (line) => console.log(line) });
} catch (e) {
  fail(`the transpile failed - ${e.message}`);
}

// 2. the generated tests of this repository's classes
const indexFile = path.join(output, "index.mjs");
if (!fs.existsSync(indexFile)) fail(`the transpile wrote no ${path.relative(ROOT, indexFile)} - ${CONFIG.runtime} ${manifest.version} does not know unitTests, 1.149.0 is the first that does`);
const index = fs.readFileSync(indexFile, "utf8");
const cut = index.indexOf("async function run");
if (cut < 0) fail(`${path.relative(ROOT, indexFile)} has no 'async function run' - the transpiler's runner changed`);

const runner = `
const PREFIX = ${JSON.stringify(CONFIG.prefix)};
const FILTER = ${JSON.stringify(process.env.UNIT_FILTER || "")};

function describe(e) {
  const str = (v) => { try { return v && v.get ? String(v.get()) : ""; } catch { return ""; } };
  const parts = [e?.constructor?.name || String(e)];
  if (e?.msg && str(e.msg)) parts.push(str(e.msg));
  if (e?.expected && str(e.expected)) parts.push("expected: " + str(e.expected).slice(0, 2000));
  if (e?.actual && str(e.actual)) parts.push("actual: " + str(e.actual).slice(0, 2000));
  if (parts.length === 1 && e?.message) parts.push(e.message);
  return parts.join("\\n    ");
}

async function run() {
  const tally = { passed: 0, failed: 0, skipped: 0 };
  const risks = {};
  for (const st of getData()) {
    if (!st.objectName.startsWith(PREFIX)) continue;
    const methods = st.methods.filter((m) => !FILTER || (st.objectName + ": " + st.localClass + "->" + m.name).includes(FILTER));
    if (methods.length === 0) continue;
    const imported = await import(st.filename);
    const localClass = imported[st.localClass];
    try {
      if (localClass.class_setup) await localClass.class_setup();
    } catch (e) {
      for (const m of methods) console.log("FAIL " + st.objectName + ": " + st.localClass + "->" + m.name + " (class_setup)");
      console.log("    " + describe(e));
      tally.failed += methods.length;
      continue;
    }
    for (const m of methods) {
      const name = st.objectName + ": " + st.localClass + "->" + m.name;
      if (m.skip) {
        console.log("SKIP " + name + " (transpile config)");
        tally.skipped++;
        continue;
      }
      let error;
      let test;
      try {
        test = await (new localClass()).constructor_();
        if (test.setup) await test.setup();
        if (test.FRIENDS_ACCESS_INSTANCE.setup) await test.FRIENDS_ACCESS_INSTANCE.setup();
        if (test.FRIENDS_ACCESS_INSTANCE.SUPER && test.FRIENDS_ACCESS_INSTANCE.SUPER.setup) await test.FRIENDS_ACCESS_INSTANCE.SUPER.setup();
        await test.FRIENDS_ACCESS_INSTANCE[m.name]();
      } catch (e) {
        error = e;
      }
      try {
        if (test && test.teardown) await test.teardown();
        if (test && test.FRIENDS_ACCESS_INSTANCE.teardown) await test.FRIENDS_ACCESS_INSTANCE.teardown();
        if (test && test.FRIENDS_ACCESS_INSTANCE.SUPER && test.FRIENDS_ACCESS_INSTANCE.SUPER.teardown) await test.FRIENDS_ACCESS_INSTANCE.SUPER.teardown();
      } catch (e) {
        error = error || e;
      }
      if (error) {
        console.log("FAIL " + name + " [" + st.riskLevel + "]");
        console.log("    " + describe(error));
        if (process.env.UNIT_STACK) console.log(error?.stack);
        tally.failed++;
      } else {
        console.log("PASS " + name + " [" + st.riskLevel + "]");
        tally.passed++;
        risks[st.riskLevel] = (risks[st.riskLevel] || 0) + 1;
      }
    }
    try {
      if (localClass.class_teardown) await localClass.class_teardown();
    } catch (e) {
      console.log("FAIL " + st.objectName + ": " + st.localClass + " (class_teardown)");
      console.log("    " + describe(e));
      tally.failed++;
    }
  }
  const byRisk = Object.entries(risks).map(([k, v]) => k + " " + v).join(", ");
  console.log("\\n" + PREFIX + "*: " + tally.passed + " passed, " + tally.failed + " failed, " + tally.skipped + " skipped" + (byRisk ? " (passed by risk level: " + byRisk + ")" : ""));
  if (tally.passed + tally.failed === 0) {
    console.log("::error::no test of " + PREFIX + "* ran" + (FILTER ? " for UNIT_FILTER=" + FILTER : ""));
    return 1;
  }
  return tally.failed ? 1 : 0;
}

run().then((code) => process.exit(code)).catch((err) => {
  console.log(err);
  process.exit(1);
});
`;

const file = path.join(output, "unit-addon.mjs");
fs.writeFileSync(file, index.slice(0, cut) + runner);
console.log(`\n== ABAP Unit: ${CONFIG.prefix}*${process.env.UNIT_FILTER ? ` matching "${process.env.UNIT_FILTER}"` : ""}`);
const r = spawnSync(process.execPath, [file], { cwd: output, stdio: "inherit" });
process.exit(r.status ?? 1);
