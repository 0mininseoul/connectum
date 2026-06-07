import { assertEquals } from "jsr:@std/assert";
import { mgmtUrl, mgmtHeaders } from "./mgmt.ts";

Deno.test("mgmtUrl joins the base with a path", () => {
  assertEquals(mgmtUrl("/v1/projects"), "https://api.supabase.com/v1/projects");
  assertEquals(mgmtUrl("v1/projects"), "https://api.supabase.com/v1/projects");
});

Deno.test("mgmtHeaders sets bearer auth + json", () => {
  const h = mgmtHeaders("tok123");
  assertEquals(h["Authorization"], "Bearer tok123");
  assertEquals(h["Content-Type"], "application/json");
});
