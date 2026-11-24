const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const modelPath = path.join(__dirname, "..", "MenuModel.js");
const src = fs.readFileSync(modelPath, "utf8").replace(/^\.pragma\s+library\s*$/m, "");

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(src, sandbox, { filename: "MenuModel.js" });

// 1. JSONC line-comment + trailing comma stripping
const stripped = sandbox.stripJsonc(`{
  // line comment
  "a": 1,
  "b": "http://example.com//keep",
}`);
const parsed = JSON.parse(stripped);
assert.strictEqual(parsed.a, 1);
assert.strictEqual(parsed.b, "http://example.com//keep");

// 2. Menu source merging and override order
const merged = sandbox.mergeMenuSources(
  [
    { id: "appearance", parent: "root", kind: "menu", label: "Appearance", aliases: ["style"] },
    { id: "appearance.theme", parent: "appearance", kind: "action", label: "Theme", action: "echo theme" },
  ],
  [
    { id: "appearance.theme", label: "Theme Custom" },
  ]
);
assert.strictEqual(merged.items["appearance.theme"].label, "Theme Custom");
assert.strictEqual(merged.items["appearance.theme"].action, "echo theme");
assert.ok(merged.itemOrder.includes("appearance"));
assert.strictEqual(sandbox.resolveRoute(merged.items, merged.itemOrder, "style"), "appearance");

// 3. Guard script generation
const script = sandbox.guardScript({
  foo: { id: "foo", when: "true", checked: "false" },
});
assert.ok(typeof script === "string" && script.includes("foo"));

console.log("MenuModel.js unit tests passed.");
