import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildInterviewPrompt,
  buildSynthesizePrompt,
  detectGaps,
  emptyBrief,
  parseInterviewJSON,
  parseSectionsJSON,
} from "./brief.ts";

Deno.test("emptyBrief has all six keys blank", () => {
  const b = emptyBrief();
  assertEquals(Object.keys(b).sort(), [
    "activation", "business_model", "current_focus", "icp", "one_liner", "signal_glossary",
  ]);
  assertEquals(b.one_liner, "");
});

Deno.test("parseSectionsJSON extracts JSON and fills missing keys", () => {
  const out = parseSectionsJSON('noise {"one_liner":"A CRM","icp":"founders"} tail');
  assertEquals(out.one_liner, "A CRM");
  assertEquals(out.icp, "founders");
  assertEquals(out.activation, ""); // missing → blank
});

Deno.test("detectGaps flags blank/too-short sections", () => {
  const b = emptyBrief();
  b.one_liner = "A real one-liner that is long enough to count.";
  const gaps = detectGaps(b);
  assertEquals(gaps.includes("one_liner"), false);
  assertEquals(gaps.includes("icp"), true);
});

Deno.test("parseInterviewJSON reads question/options and done", () => {
  assertEquals(parseInterviewJSON('{"done":true}'), { done: true });
  const q = parseInterviewJSON('{"question":"Who?","options":["A","B"]}');
  assertEquals(q.question, "Who?");
  assertEquals(q.options, ["A", "B"]);
});

Deno.test("buildSynthesizePrompt includes signals and document and edit instruction", () => {
  const p = buildSynthesizePrompt({
    signals: "서비스명: Acme",
    document: "we sell widgets",
    current: emptyBrief(),
    userPrompt: "make icp B2B",
  });
  assertEquals(p.includes("서비스명: Acme"), true);
  assertEquals(p.includes("we sell widgets"), true);
  assertEquals(p.includes("make icp B2B"), true);
  assertEquals(p.includes("[현재 브리프]"), true);
});

Deno.test("buildInterviewPrompt limits to target sections when given", () => {
  const p = buildInterviewPrompt({ signals: "s", transcript: [], targetSections: ["icp"] });
  assertEquals(p.includes("- icp:"), true);
  assertEquals(p.includes("- business_model:"), false);
});
