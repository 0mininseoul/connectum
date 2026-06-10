import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { claudeEnv } from "../_shared/claude_env.ts";
import { CLAUDE_CODE_IDENTITY, claudeHeaders } from "../_shared/claude_chat.ts";
import { runTool, TOOL_DEFS } from "./tools.ts";

const MAX_ROUNDS = 8;

// deno-lint-ignore no-explicit-any
function sse(controller: ReadableStreamDefaultController, event: string, data: any) {
  controller.enqueue(new TextEncoder().encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
}

function systemPrompt(serviceContext: string, brief: string): unknown[] {
  const blocks: unknown[] = [
    { type: "text", text: CLAUDE_CODE_IDENTITY },
    {
      type: "text",
      text: "You are Connectum's embedded CRM analyst. Answer questions about the user's customers " +
        "using ONLY the provided tools, which are scoped to the currently selected service. " +
        "Prefer concrete numbers and cite user emails when relevant. Reply in the user's language (Korean or English).\n\n" +
        "Selected service context (overview):\n" + serviceContext,
      cache_control: { type: "ephemeral" },
    },
  ];
  if (brief) {
    blocks.push({
      type: "text",
      text: "Service brief (what this service is — use it to interpret the data and prioritize):\n" + brief,
      cache_control: { type: "ephemeral" },
    });
  }
  return blocks;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  let body: { service_id?: string; messages?: unknown[] };
  try {
    body = await req.json();
  } catch {
    return new Response("bad json", { status: 400, headers: corsHeaders });
  }
  const serviceId = body.service_id;
  const userMessages = (body.messages ?? []) as unknown[];
  if (!serviceId) return new Response("missing service_id", { status: 400, headers: corsHeaders });

  const stream = new ReadableStream({
    async start(controller) {
      try {
        const overview = await runTool(db, serviceId, "get_service_overview", {});
        const { data: briefRow } = await db.from("service_brief")
          .select("sections,status").eq("service_id", serviceId).maybeSingle();
        const briefText = briefRow?.status === "ready"
          ? Object.entries(briefRow.sections as Record<string, string>)
            .filter(([, v]) => (v ?? "").trim()).map(([k, v]) => `[${k}] ${v}`).join("\n")
          : "";
        const system = systemPrompt(overview, briefText);
        // deno-lint-ignore no-explicit-any
        const messages: any[] = [...userMessages];
        const headers = await claudeHeaders();

        for (let round = 0; round < MAX_ROUNDS; round++) {
          const res = await fetch(claudeEnv.apiUrl(), {
            method: "POST",
            headers,
            body: JSON.stringify({
              model: claudeEnv.model(),
              max_tokens: 4096,
              system,
              tools: TOOL_DEFS,
              messages,
            }),
          });
          if (res.status === 401 || res.status === 403) {
            sse(controller, "error", { code: "ai_reauth_required", message: await res.text() });
            break;
          }
          if (!res.ok) {
            sse(controller, "error", { code: "claude_error", message: `${res.status}: ${await res.text()}` });
            break;
          }
          const msg = await res.json();
          messages.push({ role: "assistant", content: msg.content });

          if (msg.stop_reason === "tool_use") {
            // deno-lint-ignore no-explicit-any
            const results: any[] = [];
            for (const block of msg.content) {
              if (block.type === "tool_use") {
                sse(controller, "status", { tool: block.name });
                const out = await runTool(db, serviceId, block.name, block.input ?? {});
                results.push({ type: "tool_result", tool_use_id: block.id, content: out });
              }
            }
            messages.push({ role: "user", content: results });
            continue;
          }

          for (const block of msg.content) {
            if (block.type === "text") sse(controller, "text", { text: block.text });
          }
          sse(controller, "done", { usage: msg.usage ?? null });
          break;
        }
      } catch (e) {
        sse(controller, "error", { code: "exception", message: String(e) });
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: { ...corsHeaders, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
  });
}

if (import.meta.main) Deno.serve(handle);
