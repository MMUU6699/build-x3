import { Daytona } from "npm:@daytona/sdk@0.217.0";
import { AuthError, createAdminClient, getRequiredSecret, requireUser } from "../_shared/supabase.ts";
import { handlePreflight, isOriginAllowed, jsonResponse } from "../_shared/http.ts";

class InputError extends Error {}
class NotFoundError extends Error {}

type ControlRequest = {
  runId: string;
  action: "mouse_click" | "mouse_move" | "key" | "insert_text" | "scroll";
  x?: number;
  y?: number;
  key?: string;
  code?: string;
  text?: string;
  direction?: "up" | "down";
};

function parseRequest(value: unknown): ControlRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError("Request body must be a JSON object");
  }
  const body = value as Record<string, unknown>;
  const runId = typeof body.run_id === "string" ? body.run_id.trim() : "";
  if (!/^[0-9a-f-]{36}$/i.test(runId)) throw new InputError("run_id is invalid");
  const action = body.action;
  if (!['mouse_click', 'mouse_move', 'key', 'insert_text', 'scroll'].includes(String(action))) {
    throw new InputError("Unsupported browser control action");
  }
  const result: ControlRequest = { runId, action: action as ControlRequest["action"] };
  if (action === "mouse_click" || action === "mouse_move") {
    const x = Number(body.x);
    const y = Number(body.y);
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x > 10000 || y > 10000) {
      throw new InputError("Browser coordinates are invalid");
    }
    result.x = x;
    result.y = y;
  }
  if (action === "key") {
    const key = typeof body.key === "string" ? body.key.trim() : "";
    if (!key || key.length > 80) throw new InputError("key is required");
    result.key = key;
    result.code = typeof body.code === "string" ? body.code.slice(0, 80) : key;
  }
  if (action === "insert_text") {
    const text = typeof body.text === "string" ? body.text : "";
    if (!text || text.length > 4000) throw new InputError("text is required and must be short");
    result.text = text;
  }
  if (action === "scroll") result.direction = body.direction === "up" ? "up" : "down";
  return result;
}

function daytona(): Daytona {
  const apiUrl = (Deno.env.get("DAYTONA_API_URL")?.trim() || "https://app.daytona.io/api").replace(/\/$/, "");
  const target = Deno.env.get("DAYTONA_TARGET")?.trim();
  return new Daytona({
    apiKey: getRequiredSecret("DAYTONA_API_KEY"),
    apiUrl,
    ...(target ? { target } : {}),
  });
}

async function executeCdp(sandbox: any, request: Record<string, unknown>): Promise<Record<string, unknown>> {
  const encoded = btoa(unescape(encodeURIComponent(JSON.stringify(request))));
  const command = `printf '%s' '${encoded}' | base64 -d | python3 .buildx_cdp.py`;
  const response = await sandbox.process.executeCommand(command, "workspace", undefined, 45);
  const line = String(response.result ?? "").split(/\r?\n/).filter(Boolean).at(-1) ?? "{}";
  if (response.exitCode !== 0) throw new Error(line || "CDP control failed");
  const parsed = JSON.parse(line) as Record<string, unknown>;
  if (typeof parsed.error === "string") throw new Error(parsed.error);
  return parsed;
}

async function appendControlEvent(
  admin: ReturnType<typeof createAdminClient>,
  userId: string,
  runId: string,
  payload: Record<string, unknown>,
) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const { data: last } = await admin
      .from("work_events")
      .select("sequence")
      .eq("run_id", runId)
      .order("sequence", { ascending: false })
      .limit(1)
      .maybeSingle();
    const sequence = Number(last?.sequence ?? 0) + 1;
    const { error } = await admin.from("work_events").insert({
      run_id: runId,
      user_id: userId,
      sequence,
      event_type: "computer",
      payload,
    });
    if (!error) return;
  }
  throw new Error("Failed to persist browser control event");
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (!isOriginAllowed(req)) return jsonResponse(req, { error: "Origin is not allowed" }, 403);
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405);

  try {
    const { user } = await requireUser(req);
    const control = parseRequest(await req.json());
    const admin = createAdminClient();
    const { data: run } = await admin
      .from("work_runs")
      .select("id,sandbox_id,status")
      .eq("id", control.runId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!run?.sandbox_id || !["running", "waiting"].includes(String(run.status))) {
      throw new NotFoundError();
    }

    const sandbox = await daytona().get(String(run.sandbox_id));
    const result = await executeCdp(sandbox, {
      action: control.action,
      ...(control.x != null ? { x: control.x } : {}),
      ...(control.y != null ? { y: control.y } : {}),
      ...(control.key ? { key: control.key, code: control.code } : {}),
      ...(control.text != null ? { text: control.text } : {}),
      ...(control.direction ? { direction: control.direction } : {}),
    });
    const screenshot = await executeCdp(sandbox, { action: "screenshot" });
    const payload = {
      action: `User ${control.action.replace("mouse_", "")}`,
      screenshot_base64: String(screenshot.screenshot_base64 ?? ""),
      url: String(result.url ?? ""),
      title: String(result.title ?? "Web Page"),
      control_action: control.action,
    };
    await appendControlEvent(admin, user.id, control.runId, payload);
    return jsonResponse(req, { run_id: control.runId, ...payload }, 200);
  } catch (error) {
    if (error instanceof AuthError) return jsonResponse(req, { error: "Unauthorized" }, 401);
    if (error instanceof InputError) return jsonResponse(req, { error: error.message }, 400);
    if (error instanceof NotFoundError) return jsonResponse(req, { error: "Active Work browser not found" }, 404);
    console.error("work-control failed", { type: error instanceof Error ? error.name : "UnknownError" });
    return jsonResponse(req, { error: "Browser control failed" }, 502);
  }
});
