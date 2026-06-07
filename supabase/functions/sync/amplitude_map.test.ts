import { assertEquals } from "jsr:@std/assert";
import { mapExportRow, extractProfiles } from "./amplitude_map.ts";

Deno.test("mapExportRow keeps matched users, carries event_uuid, normalizes fields", () => {
  const matched = new Map([["u1", "crm-1"]]);
  const row = {
    uuid: "ev-1", user_id: "u1", event_type: "login", event_time: "2026-06-01 03:04:05.000000",
    os_name: "Chrome", device_family: "Mac", platform: "Web", event_properties: { plan: "free" },
  };
  const m = mapExportRow(row, matched);
  assertEquals(m?.event_uuid, "ev-1");
  assertEquals(m?.crm_user_id, "crm-1");
  assertEquals(m?.event_type, "login");
  assertEquals(m?.event_time, "2026-06-01T03:04:05.000000Z");
  assertEquals(m?.os, "Chrome");
  assertEquals(m?.props.plan, "free");
});

Deno.test("mapExportRow drops unmatched / anonymous users", () => {
  assertEquals(mapExportRow({ uuid: "x", user_id: "ghost", event_type: "e", event_time: "2026-06-01 00:00:00" }, new Map()), null);
  assertEquals(mapExportRow({ uuid: "y", event_type: "e", event_time: "2026-06-01 00:00:00" }, new Map([["u1", "c1"]])), null);
});

Deno.test("extractProfiles keeps the latest event's device/geo per matched user", () => {
  const matched = new Map([["u1", "crm-1"]]);
  const rows = [
    { user_id: "u1", event_time: "2026-06-01 01:00:00", os_name: "Chrome", device_family: "Mac", device_type: "Mac", country: "KR", region: "Seoul", city: "Seoul", platform: "Web" },
    { user_id: "u1", event_time: "2026-06-02 09:00:00", os_name: "Safari", device_family: "iPhone", device_type: "iPhone", country: "KR", region: "Busan", city: "Busan", platform: "Web" },
    { user_id: "ghost", event_time: "2026-06-03 00:00:00", os_name: "X" },
  ];
  const profiles = extractProfiles(rows, matched);
  assertEquals(profiles.size, 1);
  const p = profiles.get("crm-1")!;
  assertEquals(p.os, "Safari");
  assertEquals(p.region, "Busan");
  assertEquals(p.last_event_time, "2026-06-02T09:00:00Z");
});
