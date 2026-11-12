import { test } from "node:test";
import assert from "node:assert/strict";
import { apnsSigner, mobileSignal } from "./handler.ts";

const owner = "11111111-1111-1111-1111-111111111111";
const device = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const token = "a".repeat(64);
const config = { projectURL: "https://example.supabase.co", anonKey: "synthetic-anon", serviceKey: "synthetic-server" };
const providerSign = async () => "synthetic-provider-token";
const request = (body = "{}") => new Request("https://function.example/?user_id=ignored", {
  method: "POST", headers: { Authorization: "Bearer synthetic-user" }, body,
});
test("missing/invalid auth cannot reach token claims or Apple", async () => {
  const calls: string[] = [];
  const handler = mobileSignal(config, async input => { calls.push(String(input)); return Response.json({}, { status: 401 }); }, providerSign);
  assert.equal((await handler(new Request("https://function.example", { method: "POST" }))).status, 401);
  assert.equal(calls.length, 0);
  assert.equal((await handler(request())).status, 401);
  assert.deepEqual(calls, [config.projectURL + "/auth/v1/user"]);
});
test("caller cannot choose owner/destination or send an excessive body", async () => {
  let calls = 0;
  const handler = mobileSignal(config, async () => { calls++; throw new Error("should not fetch"); }, providerSign);
  for (const body of ['{"user_id":"other"}', '{"token":"chosen"}', '{"check":false}', "null", "[]", "x".repeat(129)]) {
    assert.equal((await handler(request(body))).status, 400);
  }
  assert.equal(calls, 0);
});
test("configured check verifies user and signs before returning, without a device claim", async () => {
  let calls = 0;
  const handler = mobileSignal(config, async () => { calls++; return Response.json({ id: owner }); }, providerSign);
  const response = await handler(request('{"check":true,"environment":"development"}'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { configured: true });
  assert.equal(calls, 1);
});
test("missing APNs configuration does not consume the device claim", async () => {
  const calls: string[] = [];
  const handler = mobileSignal(config, async input => { calls.push(String(input)); return Response.json({ id: owner }); });
  assert.equal((await handler(request())).status, 503);
  assert.equal(calls.length, 1);
});
test("only verified owner is claimed; Apple receives an empty background signal", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  const handler = mobileSignal(config, async (input, init) => {
    const url = String(input); calls.push({ url, init });
    if (url.endsWith("/auth/v1/user")) return Response.json({ id: owner, email: "private@example.test" });
    if (url.endsWith("/claim_mobile_signal")) {
      assert.deepEqual(JSON.parse(String(init?.body)), { p_user: owner });
      assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer synthetic-server");
      return Response.json([{ device_id: device, token, environment: "development" }]);
    }
    assert.equal(url, "https://api.sandbox.push.apple.com/3/device/" + token);
    const headers = new Headers(init?.headers);
    assert.equal(headers.get("apns-topic"), "com.elvisobi.clepso.mobile");
    assert.equal(headers.get("apns-push-type"), "background");
    assert.equal(headers.get("apns-priority"), "5");
    assert.equal(headers.get("apns-expiration"), "0");
    assert.equal(headers.get("Authorization"), "bearer synthetic-provider-token");
    assert.deepEqual(JSON.parse(String(init?.body)), { aps: { "content-available": 1 } });
    assert.equal(init?.redirect, "error");
    return new Response(null, { status: 200 });
  }, providerSign);
  const response = await handler(request());
  assert.equal(response.status, 202);
  assert.deepEqual(await response.json(), { accepted: 1, failed: 0 });
  assert.equal(calls.length, 3);
});
test("empty cooldown claim sends no Apple request", async () => {
  let calls = 0;
  const handler = mobileSignal(config, async input => {
    calls++;
    return Response.json(String(input).endsWith("/auth/v1/user") ? { id: owner } : []);
  }, providerSign);
  assert.deepEqual(await (await handler(request())).json(), { accepted: 0, failed: 0 });
  assert.equal(calls, 2);
});
test("invalid destinations and overlarge claims never reach Apple", async () => {
  for (const devices of [
    [{ device_id: device, token: "https://invalid.example/", environment: "production" }],
    [{ device_id: device, token, environment: "https://invalid.example" }],
    Array(9).fill({ device_id: device, token, environment: "production" }),
  ]) {
    let calls = 0;
    const handler = mobileSignal(config, async input => {
      calls++; assert.ok(String(input).startsWith(config.projectURL));
      return Response.json(String(input).endsWith("/auth/v1/user") ? { id: owner } : devices);
    }, providerSign);
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls, 2);
  }
});
test("expired token cleanup matches owner, device, token and environment", async () => {
  let cleaned = false;
  const handler = mobileSignal(config, async (input, init) => {
    const url = String(input);
    if (url.endsWith("/auth/v1/user")) return Response.json({ id: owner });
    if (url.endsWith("/claim_mobile_signal")) return Response.json([{ device_id: device, token, environment: "production" }]);
    if (url.includes("api.push.apple.com")) return Response.json({ reason: "Unregistered" }, { status: 410 });
    assert.ok(url.endsWith("/remove_invalid_mobile_device"));
    assert.deepEqual(JSON.parse(String(init?.body)), { p_user: owner, p_device: device, p_token: token, p_environment: "production" });
    cleaned = true;
    return new Response(null, { status: 204 });
  }, providerSign);
  assert.deepEqual(await (await handler(request())).json(), { accepted: 0, failed: 1 });
  assert.equal(cleaned, true);
});
test("errors expose no token, response body or private destination", async () => {
  const handler = mobileSignal(config, async () => { throw new Error("synthetic-user private@example.test " + token); }, providerSign);
  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.equal(await response.text(), '{"error":"unavailable"}');
});
test("provider JWT is ES256, verified, cached and reminted after twenty minutes or a clock rewind", async () => {
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keys.privateKey));
  const encoded = Buffer.from(der).toString("base64");
  const pem = "-----BEGIN PRIVATE KEY-----\n" + encoded + "\n-----END PRIVATE KEY-----"; // secret-scan: allow (PEM boundaries only; key generated in memory)
  let clock = 1_792_665_600_000;
  const sign = apnsSigner({ ...config, keyID: "ABCDEFGHIJ", teamID: "KLMNOPQRST", privateKey: pem }, () => clock);
  const first = await sign(), parts = first.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(parts[0], "base64url").toString()), { alg: "ES256", kid: "ABCDEFGHIJ" });
  assert.deepEqual(JSON.parse(Buffer.from(parts[1], "base64url").toString()), { iss: "KLMNOPQRST", iat: clock / 1000 });
  assert.equal(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, keys.publicKey,
    Buffer.from(parts[2], "base64url"), new TextEncoder().encode(parts[0] + "." + parts[1])), true);
  clock += 1_199_000; assert.equal(await sign(), first);
  clock += 1_000; assert.notEqual(await sign(), first);
  clock -= 3_600_000; assert.notEqual(await sign(), first);
});
