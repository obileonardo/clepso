import { mobileSignal } from "./handler.ts";

// Keep separate HTTP/2 pools per environment; topic-specific APNs keys must not share an unrelated connection.
const apple = {
  development: Deno.createHttpClient({ http1: false, http2: true }),
  production: Deno.createHttpClient({ http1: false, http2: true }),
};
const handler = mobileSignal({
  projectURL: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  teamID: Deno.env.get("APNS_TEAM_ID"),
  sandbox: { keyID: Deno.env.get("APNS_SANDBOX_KEY_ID"), privateKey: Deno.env.get("APNS_SANDBOX_KEY_P8") },
  production: { keyID: Deno.env.get("APNS_PRODUCTION_KEY_ID"), privateKey: Deno.env.get("APNS_PRODUCTION_KEY_P8") },
}, (input, init) => {
  const host = new URL(input instanceof Request ? input.url : input).hostname;
  if (host === "api.sandbox.push.apple.com") return fetch(input, { ...init, client: apple.development });
  if (host === "api.push.apple.com") return fetch(input, { ...init, client: apple.production });
  return fetch(input, init);
});
Deno.serve(handler);
