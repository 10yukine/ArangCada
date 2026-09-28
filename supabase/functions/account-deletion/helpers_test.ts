import assert from "node:assert/strict";
import { test } from "node:test";
import { escapeHtml, hashToken, newToken, validToken } from "./helpers.ts";

test("deletion links use unpredictable tokens and store only hashes", async () => {
  const first = newToken();
  const second = newToken();
  assert.ok(validToken(first));
  assert.notEqual(first, second);
  assert.equal(validToken(first.slice(1)), false);
  assert.equal(validToken("<script>"), false);
  assert.notEqual(await hashToken(first), first);
  assert.equal((await hashToken(first)).length, 64);
  assert.equal(escapeHtml('a<b&"c'), 'a&lt;b&amp;&quot;c');
});
