import { assertEquals } from "jsr:@std/assert";
import { handleHealth } from "./index.ts";

Deno.test("health returns ok json", async () => {
  const res = await handleHealth();
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "ok");
});
