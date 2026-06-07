import { assertEquals } from "jsr:@std/assert";
import { amplitudeHost, exportProbeUrl, basicAuth } from "./amplitude.ts";
import { exportUrl } from "./amplitude.ts";

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

Deno.test("exportUrl builds a window with YYYYMMDDTHH stamps", () => {
  const url = exportUrl("us", new Date("2026-06-07T12:00:00Z"), new Date("2026-06-07T15:00:00Z"));
  assertEquals(url, "https://amplitude.com/api/2/export?start=20260607T12&end=20260607T15");
});
