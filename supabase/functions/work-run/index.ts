import { Buffer } from "node:buffer";
import { Daytona } from "npm:@daytona/sdk@0.217.0";
import { AuthError, createAdminClient, getRequiredSecret, requireUser } from "../_shared/supabase.ts";
import { handlePreflight, isOriginAllowed, jsonResponse } from "../_shared/http.ts";

const NVIDIA_API_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const DEFAULT_MODEL = "nvidia/nemotron-3-ultra-550b-a55b";
const ALLOWED_MODELS = new Set([DEFAULT_MODEL]);
const ALLOWED_REASONING_EFFORTS = new Set(["none", "medium", "high"]);
const MAX_PROMPT_CHARS = 20000;
const MAX_HTML_BYTES = 1000000;
const FORBIDDEN_SECRET_FIELDS = new Set([
  "api_key",
  "apiKey",
  "nvidia_api_key",
  "nvidiaApiKey",
  "daytona_api_key",
  "daytonaApiKey",
  "authorization",
  "secret",
]);

class InputError extends Error {}

function parseBody(value: unknown): {
  prompt: string;
  model: string;
  reasoningEffort: string;
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError("Request body must be a JSON object");
  }
  const body = value as Record<string, unknown>;
  for (const key of FORBIDDEN_SECRET_FIELDS) {
    if (key in body) throw new InputError("Client-provided provider credentials are not accepted");
  }

  const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
  if (!prompt || prompt.length > MAX_PROMPT_CHARS) {
    throw new InputError(`prompt must contain between 1 and ${MAX_PROMPT_CHARS} characters`);
  }
  const model = typeof body.model === "string" ? body.model : DEFAULT_MODEL;
  if (!ALLOWED_MODELS.has(model)) throw new InputError("Unsupported model");
  const reasoningEffort = typeof body.reasoning_effort === "string"
    ? body.reasoning_effort
    : "high";
  if (!ALLOWED_REASONING_EFFORTS.has(reasoningEffort)) {
    throw new InputError("reasoning_effort must be none, medium, or high");
  }
  return { prompt, model, reasoningEffort };
}

function extractHtml(output: string): string {
  const fenced = /```html\s*([\s\S]*?)```/i.exec(output)?.[1]?.trim();
  const htmlStart = output.search(/<!doctype html|<html/i);
  const candidate = fenced || (htmlStart >= 0 ? output.slice(htmlStart).trim() : "");
  if (!candidate || !/<(?:!doctype\s+html|html)[\s>]/i.test(candidate)) {
    throw new Error("Model did not produce a standalone HTML deliverable");
  }
  if (new TextEncoder().encode(candidate).byteLength > MAX_HTML_BYTES) {
    throw new Error("Generated deliverable exceeds the server size limit");
  }
  return candidate;
}

async function generateHtml(
  prompt: string,
  model: string,
  reasoningEffort: string,
): Promise<string> {
  const response = await fetch(NVIDIA_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${getRequiredSecret("NVIDIA_API_KEY")}`,
      "Accept": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          content:
            "You are a software delivery agent. Produce one complete, standalone index.html file with embedded CSS and JavaScript. Return only one ```html fenced code block. Do not include secrets, remote credentials, or prose outside the code block.",
        },
        { role: "user", content: prompt },
      ],
      temperature: 0.7,
      top_p: 0.95,
      max_tokens: 8192,
      stream: false,
      reasoning_effort: reasoningEffort,
      chat_template_kwargs: {
        enable_thinking: reasoningEffort !== "none",
        force_nonempty_content: true,
      },
    }),
    signal: AbortSignal.timeout(120000),
  });
  if (!response.ok) {
    console.error("NVIDIA work generation failed", { status: response.status });
    throw new Error("Model generation failed");
  }

  const data = await response.json() as Record<string, unknown>;
  const choices = data.choices;
  if (!Array.isArray(choices) || choices.length === 0) throw new Error("Model returned no choices");
  const message = (choices[0] as Record<string, unknown>).message;
  const content = message && typeof message === "object"
    ? (message as Record<string, unknown>).content
    : null;
  if (typeof content !== "string" || !content.trim()) throw new Error("Model returned no content");
  return extractHtml(content);
}

function safeFailure(error: unknown): string {
  if (error instanceof DOMException && error.name === "TimeoutError") return "Operation timed out";
  if (error instanceof Error) {
    const allowed = new Set([
      "Model generation failed",
      "Model returned no choices",
      "Model returned no content",
      "Model did not produce a standalone HTML deliverable",
      "Generated deliverable exceeds the server size limit",
    ]);
    if (allowed.has(error.message)) return error.message;
  }
  return "Work execution failed";
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (!isOriginAllowed(req)) return jsonResponse(req, { error: "Origin is not allowed" }, 403);
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405);

  let runId: string | null = null;
  let sandbox: any = null;
  let daytona: Daytona | null = null;
  let admin: ReturnType<typeof createAdminClient> | null = null;
  let userId: string | null = null;
  let sequence = 0;

  const appendEvent = async (eventType: string, payload: Record<string, unknown> = {}) => {
    if (!admin || !runId || !userId) return;
    sequence += 1;
    const { error } = await admin.from("work_events").insert({
      run_id: runId,
      user_id: userId,
      sequence,
      event_type: eventType,
      payload,
    });
    if (error) throw new Error("Failed to persist work event");
  };

  try {
    const { user } = await requireUser(req);
    userId = user.id;
    const { prompt, model, reasoningEffort } = parseBody(await req.json());
    admin = createAdminClient();
    runId = crypto.randomUUID();

    const { error: insertError } = await admin.from("work_runs").insert({
      id: runId,
      user_id: userId,
      prompt,
      model,
      reasoning_effort: reasoningEffort,
      status: "queued",
    });
    if (insertError) throw new Error("Failed to persist work run");
    await appendEvent("queued", { model, reasoning_effort: reasoningEffort });

    const daytonaApiKey = getRequiredSecret("DAYTONA_API_KEY");
    const daytonaApiUrl = Deno.env.get("DAYTONA_API_URL")?.trim();
    const daytonaTarget = Deno.env.get("DAYTONA_TARGET")?.trim();
    daytona = new Daytona({
      apiKey: daytonaApiKey,
      ...(daytonaApiUrl ? { apiUrl: daytonaApiUrl } : {}),
      ...(daytonaTarget ? { target: daytonaTarget } : {}),
    });

    const { error: runningError } = await admin.from("work_runs").update({
      status: "running",
      started_at: new Date().toISOString(),
    }).eq("id", runId);
    if (runningError) throw new Error("Failed to persist running work state");
    await appendEvent("planning", { message: "Preparing isolated execution environment" });

    sandbox = await daytona.create({
      language: "typescript",
      labels: { "build-x-run": runId },
      autoStopInterval: 5,
      autoArchiveInterval: 60,
      autoDeleteInterval: 120,
    }, { timeout: 60 });
    const { error: sandboxUpdateError } = await admin.from("work_runs")
      .update({ sandbox_id: sandbox.id })
      .eq("id", runId);
    if (sandboxUpdateError) throw new Error("Failed to persist sandbox state");
    await appendEvent("sandbox_created", { sandbox_id: sandbox.id });

    await appendEvent("generating", { model, reasoning_effort: reasoningEffort });
    const html = await generateHtml(prompt, model, reasoningEffort);

    await sandbox.process.executeCommand("mkdir -p workspace", undefined, undefined, 30);
    await sandbox.fs.uploadFile(Buffer.from(html, "utf8"), "workspace/index.html", 60);
    const verification = await sandbox.process.executeCommand(
      "test -s workspace/index.html && wc -c < workspace/index.html",
      undefined,
      undefined,
      30,
    );
    if (verification.exitCode !== 0) throw new Error("Sandbox verification failed");
    await appendEvent("verified", {
      entrypoint: "index.html",
      bytes: Buffer.byteLength(html, "utf8"),
    });

    const result = {
      title: prompt.length <= 80 ? prompt : `${prompt.slice(0, 77)}...`,
      type: "web_app",
      entrypoint: "index.html",
      files: ["index.html"],
      previewHtml: html,
    };
    const { error: updateError } = await admin.from("work_runs").update({
      status: "completed",
      result,
      completed_at: new Date().toISOString(),
    }).eq("id", runId);
    if (updateError) throw new Error("Failed to persist completed work run");
    await appendEvent("completed", {
      entrypoint: "index.html",
      files: ["index.html"],
    });

    return jsonResponse(req, { run_id: runId, status: "completed", result }, 200);
  } catch (error) {
    if (error instanceof AuthError) return jsonResponse(req, { error: "Unauthorized" }, 401);
    if (error instanceof InputError || error instanceof SyntaxError) {
      return jsonResponse(req, { error: error.message }, 400);
    }

    const failure = safeFailure(error);
    console.error("work-run failed", {
      run_id: runId,
      type: error instanceof Error ? error.name : "UnknownError",
    });
    if (admin && runId) {
      try {
        await appendEvent("failed", { message: failure });
        await admin.from("work_runs").update({
          status: "failed",
          error: failure,
          completed_at: new Date().toISOString(),
        }).eq("id", runId);
      } catch {
        console.error("Failed to persist terminal work-run state", { run_id: runId });
      }
    }
    return jsonResponse(req, { error: failure, run_id: runId }, 502);
  } finally {
    if (daytona && sandbox) {
      try {
        await daytona.delete(sandbox, 30, false);
      } catch {
        console.error("Failed to delete Daytona sandbox", { run_id: runId });
      }
    }
  }
});
