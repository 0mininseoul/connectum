import { assertEquals } from "jsr:@std/assert";
import { parseProjects } from "./projects.ts";

Deno.test("parseProjects keeps id/name/region only", () => {
  const out = parseProjects([
    { id: "abc", name: "Proj A", region: "ap-northeast-2", organization_id: "o1" },
    { id: "def", name: "Proj B", region: "us-east-1", organization_id: "o1" },
  ]);
  assertEquals(out, [
    { ref: "abc", name: "Proj A", region: "ap-northeast-2" },
    { ref: "def", name: "Proj B", region: "us-east-1" },
  ]);
});
