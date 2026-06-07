import { assertEquals } from "jsr:@std/assert";
import { amplitudeHost, exportProbeUrl, basicAuth } from "./amplitude.ts";

Deno.test("amplitudeHost picks EU vs US", () => {
  assertEquals(amplitudeHost("eu"), "analytics.eu.amplitude.com");
  assertEquals(amplitudeHost("us"), "amplitude.com");
  assertEquals(amplitudeHost(undefined), "amplitude.com");
});

Deno.test("exportProbeUrl builds a 1-hour window with YYYYMMDDTHH stamps", () => {
  const url = exportProbeUrl("us", new Date("2026-06-01T05:30:00Z"));
  // Amplitude requires the literal 'T' between date and hour.
  assertEquals(url, "https://amplitude.com/api/2/export?start=20260601T04&end=20260601T05");
});

Deno.test("basicAuth base64-encodes key:secret", () => {
  assertEquals(basicAuth("k", "s"), "Basic " + btoa("k:s"));
});
