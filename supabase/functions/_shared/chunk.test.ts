import { assertEquals } from "jsr:@std/assert";
import { planWindows } from "./chunk.ts";

Deno.test("planWindows splits a range into N-hour windows", () => {
  const wins = planWindows(new Date("2026-06-01T00:00:00Z"), new Date("2026-06-01T06:00:00Z"), 2);
  assertEquals(wins.length, 3);
  assertEquals(wins[0].start.toISOString(), "2026-06-01T00:00:00.000Z");
  assertEquals(wins[2].end.toISOString(), "2026-06-01T06:00:00.000Z");
});

Deno.test("planWindows clamps a partial final window to end", () => {
  const wins = planWindows(new Date("2026-06-01T00:00:00Z"), new Date("2026-06-01T05:00:00Z"), 2);
  assertEquals(wins.length, 3);
  assertEquals(wins[2].end.toISOString(), "2026-06-01T05:00:00.000Z");
});
