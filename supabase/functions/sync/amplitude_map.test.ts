import { assertEquals } from "jsr:@std/assert";
import { mapExportRow } from "./amplitude_map.ts";

Deno.test("mapExportRow keeps only matched users and normalizes fields", () => {
  const matched = new Map([["u1", "crm-1"]]);
  const row = {
    user_id: "u1", event_type: "login", event_time: "2026-06-01 03:04:05.000000",
    os_name: "Mac OS X", device_family: "Mac", platform: "Web",
    event_properties: { plan: "free" },
  };
  const mapped = mapExportRow(row, matched);
  assertEquals(mapped?.crm_user_id, "crm-1");
  assertEquals(mapped?.event_type, "login");
  assertEquals(mapped?.os, "Mac OS X");
  assertEquals(mapped?.props.plan, "free");
});

Deno.test("mapExportRow drops unmatched users", () => {
  const mapped = mapExportRow({ user_id: "ghost", event_type: "x", event_time: "2026-06-01 00:00:00" }, new Map());
  assertEquals(mapped, null);
});
