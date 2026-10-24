type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
export type SignalConfig = {
  projectURL: string; anonKey: string; serviceKey: string;
  teamID?: string;
  sandbox?: { keyID?: string; privateKey?: string };
  production?: { keyID?: string; privateKey?: string };
};
type SigningConfig = { keyID?: string; teamID?: string; privateKey?: string };
type Environment = "development" | "production";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const topic = "com.elvisobi.clepso.mobile";
function reply(status: number, value: object): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
}
async function read(response: Response | Request, limit: number): Promise<string> {
  const reader = response.body?.getReader();
  if (!reader) return "";
  let size = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new Error("size"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder().decode(bytes);
}
function base64url(bytes: Uint8Array): string {
  let text = "";
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
function json64(value: object): string { return base64url(new TextEncoder().encode(JSON.stringify(value))); }

/** JWT stays in server memory, reused for twenty minutes. No private key, device token or caller token is logged. */
export function apnsSigner(config: SigningConfig, now: () => number = Date.now): () => Promise<string> {
  let key: CryptoKey | undefined;
  let cached: { value: string; issued: number } | undefined;
  return async () => {
    if (!/^[A-Z0-9]{10}$/.test(config.keyID ?? "") || !/^[A-Z0-9]{10}$/.test(config.teamID ?? "") || !config.privateKey) throw new Error("configuration");
    const issued = Math.floor(now() / 1000);
    if (cached && issued >= cached.issued && issued - cached.issued < 1200) return cached.value;
    if (!key) {
      const text = config.privateKey.replaceAll("\\n", "\n").split("\n").map(line => line.trim()).filter(line => line && !line.startsWith("-----")).join("");
      const der = Uint8Array.from(atob(text), char => char.charCodeAt(0));
      key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
    }
    const input = json64({ alg: "ES256", kid: config.keyID }) + "." + json64({ iss: config.teamID, iat: issued });
    const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
    const value = input + "." + base64url(new Uint8Array(signature));
    cached = { value, issued };
    return value;
  };
}

/** Platform JWT verification stays enabled. Auth.getUser independently establishes the owner before service RPCs. */
export function mobileSignal(config: SignalConfig, fetcher: Fetcher = fetch,
  signer?: (environment: Environment) => Promise<string>): (request: Request) => Promise<Response> {
  const development = apnsSigner({ ...config.sandbox, teamID: config.teamID });
  const production = apnsSigner({ ...config.production, teamID: config.teamID });
  const sign = signer ?? (environment => environment === "development" ? development() : production());
  return async request => {
    if (request.method !== "POST") return reply(405, { error: "post_required" });
    const authorization = request.headers.get("Authorization") ?? "";
    if (!/^Bearer \S+$/i.test(authorization) || authorization.length > 8192) return reply(401, { error: "sign_in_required" });
    let check = false;
    let checkEnvironment: Environment | undefined;
    try {
      const text = await read(request, 128);
      const input = text.trim() ? JSON.parse(text) : {};
      if (input === null || Array.isArray(input) || typeof input !== "object" ||
          Object.keys(input).some(key => !["check", "environment"].includes(key)) || ("check" in input && input.check !== true) ||
          ("environment" in input && (input.check !== true || !["development", "production"].includes(input.environment)))) return reply(400, { error: "invalid_request" });
      check = input.check === true;
      if (check) {
        if (!["development", "production"].includes(input.environment)) return reply(400, { error: "invalid_request" });
        checkEnvironment = input.environment;
      }
    } catch { return reply(400, { error: "invalid_request" }); }
    if (!config.projectURL || !config.anonKey || !config.serviceKey) return reply(503, { error: "unavailable" });
    const base = config.projectURL.replace(/\/$/, "");
    try {
      const verified = await fetcher(base + "/auth/v1/user", {
        headers: { apikey: config.anonKey, Authorization: authorization },
        redirect: "error", signal: AbortSignal.timeout(5000),
      });
      if (!verified.ok) return reply(401, { error: "sign_in_required" });
      const user = JSON.parse(await read(verified, 128 * 1024));
      if (!uuid.test(user.id ?? "") || user.is_anonymous === true) return reply(401, { error: "sign_in_required" });
      if (check && checkEnvironment) {
        try { await sign(checkEnvironment); return reply(200, { configured: true }); }
        catch { return reply(503, { error: "push_not_configured" }); }
      }
      const providerTokens: Partial<Record<Environment, string>> = {};
      for (const environment of ["development", "production"] as const) {
        try { providerTokens[environment] = await sign(environment); } catch { /* Separate environment keys are optional until configured. */ }
      }
      if (Object.keys(providerTokens).length === 0) return reply(503, { error: "push_not_configured" });
      const headers = { apikey: config.serviceKey, Authorization: "Bearer " + config.serviceKey, "Content-Type": "application/json" };
      const rpc = await fetcher(base + "/rest/v1/rpc/claim_mobile_signal", {
        method: "POST", headers, body: JSON.stringify({ p_user: user.id }),
        redirect: "error", signal: AbortSignal.timeout(5000),
      });
      if (!rpc.ok) return reply(503, { error: "unavailable" });
      const devices = JSON.parse(await read(rpc, 32 * 1024));
      if (!Array.isArray(devices) || devices.length > 8 || !devices.every(device =>
        uuid.test(device.device_id ?? "") && typeof device.token === "string" &&
        /^[0-9a-f]+$/.test(device.token) && device.token.length >= 2 && device.token.length <= 1024 && device.token.length % 2 === 0 &&
        ["development", "production"].includes(device.environment))) return reply(503, { error: "unavailable" });
      const results = await Promise.all(devices.map(async device => {
        try {
          const providerToken = providerTokens[device.environment as Environment];
          if (!providerToken) return false;
          const host = device.environment === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
          const response = await fetcher("https://" + host + "/3/device/" + device.token, {
            method: "POST",
            headers: { Authorization: "bearer " + providerToken, "Content-Type": "application/json", "apns-topic": topic, "apns-push-type": "background",
              "apns-priority": "5", "apns-expiration": "0", "apns-collapse-id": "clepso-mobile-refresh" },
            body: JSON.stringify({ aps: { "content-available": 1 } }), redirect: "error", signal: AbortSignal.timeout(5000),
          });
          if (response.ok) return true;
          const reason = JSON.parse((await read(response, 2048)) || "{}").reason;
          if (response.status === 410 || (response.status === 400 && reason === "BadDeviceToken")) {
            await fetcher(base + "/rest/v1/rpc/remove_invalid_mobile_device", {
              method: "POST", headers, body: JSON.stringify({ p_user: user.id, p_device: device.device_id, p_token: device.token, p_environment: device.environment }),
              redirect: "error", signal: AbortSignal.timeout(5000),
            });
          }
        } catch { /* Delivery is best effort; never echo a provider response or token. */ }
        return false;
      }));
      return reply(202, { accepted: results.filter(Boolean).length, failed: results.filter(value => !value).length });
    } catch { return reply(503, { error: "unavailable" }); }
  };
}
