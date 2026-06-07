function b64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlStr(s: string): string { return b64url(new TextEncoder().encode(s)); }
function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}
// Web Crypto wants a concrete ArrayBuffer (Deno's strict lib types reject Uint8Array<ArrayBufferLike>).
function toBuf(u: Uint8Array): ArrayBuffer {
  return u.slice().buffer as ArrayBuffer;
}

export interface SaKey { client_email: string; private_key: string; }

export function decodeSaKey(b64: string): SaKey {
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
}

// Mint a short-lived GCP access token from a service-account key (JWT bearer flow).
export async function getAccessToken(saB64: string): Promise<string> {
  const sa = decodeSaKey(saB64);
  const now = Math.floor(Date.now() / 1000);
  const header = b64urlStr(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64urlStr(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/cloud-platform",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey("pkcs8", toBuf(pemToDer(sa.private_key)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, toBuf(new TextEncoder().encode(signingInput))));
  const jwt = `${signingInput}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const tok = await res.json();
  if (!tok.access_token) throw new Error("token exchange failed: " + JSON.stringify(tok));
  return tok.access_token as string;
}
