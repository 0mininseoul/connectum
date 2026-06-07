import { assertEquals } from "jsr:@std/assert";
import { decodeSaKey } from "./gcp_token.ts";

Deno.test("decodeSaKey parses a base64 service-account json", () => {
  const fake = { client_email: "x@y.iam.gserviceaccount.com", private_key: "PEM" };
  const b64 = btoa(JSON.stringify(fake));
  const sa = decodeSaKey(b64);
  assertEquals(sa.client_email, "x@y.iam.gserviceaccount.com");
  assertEquals(sa.private_key, "PEM");
});
