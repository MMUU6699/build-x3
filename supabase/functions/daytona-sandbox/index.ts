import { AuthError, getRequiredSecret, requireUser } from "./_shared/supabase.ts";
import { handlePreflight, isOriginAllowed, jsonResponse } from "./_shared/http.ts";

const OWNER_LABEL = "build-x-user";
const PURPOSE_LABEL = "build-x-purpose";

class InputError extends Error {}
class NotFoundError extends Error {}
class DaytonaError extends Error {
  constructor(readonly status: number) {
    super(`Daytona request failed with status ${status}`);
  }
}

function daytonaConfig(): { apiUrl: string; apiKey: string; target?: string } {
  return {
    apiUrl: (Deno.env.get("DAYTONA_API_URL")?.trim() || "https://app.daytona.io/api").replace(/\/$/, ""),
    apiKey: getRequiredSecret("DAYTONA_API_KEY"),
    target: Deno.env.get("DAYTONA_TARGET")?.trim() || undefined,
  };
}

async function daytonaRequest(
  path: string,
  init: RequestInit = {},
  allowedStatuses: number[] = [],
): Promise<{ response: Response; body: Record<string, unknown> | null }> {
  const config = daytonaConfig();
  const response = await fetch(`${config.apiUrl}${path}`, {
    ...init,
    headers: {
      "Authorization": `Bearer ${config.apiKey}`,
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers,
    },
    signal: AbortSignal.timeout(65000),
  });
  if (!response.ok && !allowedStatuses.includes(response.status)) {
    throw new DaytonaError(response.status);
  }
  const text = await response.text();
  let body: Record<string, unknown> | null = null;
  if (text) {
    try { body = JSON.parse(text) as Record<string, unknown>; } catch { body = null; }
  }
  return { response, body };
}

function parseBody(value: unknown): { action: "create" | "get" | "delete"; sandboxId?: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError("Request body must be a JSON object");
  }
  const body = value as Record<string, unknown>;
  if (body.action !== "create" && body.action !== "get" && body.action !== "delete") {
    throw new InputError("action must be create, get, or delete");
  }
  if (body.action !== "create") {
    if (typeof body.sandbox_id !== "string" || !body.sandbox_id.trim()) {
      throw new InputError("sandbox_id is required");
    }
    return { action: body.action, sandboxId: body.sandbox_id.trim() };
  }
  return { action: "create" };
}

function ownedBy(sandbox: Record<string, unknown>, userId: string): boolean {
  const labels = sandbox.labels;
  return !!labels && typeof labels === "object" &&
    (labels as Record<string, unknown>)[OWNER_LABEL] === userId;
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (!isOriginAllowed(req)) return jsonResponse(req, { error: "Origin is not allowed" }, 403);
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405);

  try {
    const { user } = await requireUser(req);
    const input = parseBody(await req.json());
    const config = daytonaConfig();

    if (input.action === "create") {
      const { body: sandbox } = await daytonaRequest("/sandbox", {
        method: "POST",
        body: JSON.stringify({
          language: "typescript",
          ...(config.target ? { target: config.target } : {}),
          labels: {
            [OWNER_LABEL]: user.id,
            [PURPOSE_LABEL]: "integration-test",
          },
          autoStopInterval: 5,
          autoArchiveInterval: 60,
          autoDeleteInterval: 120,
        }),
      });
      const sandboxId = typeof sandbox?.id === "string" ? sandbox.id : null;
      if (!sandboxId) throw new DaytonaError(502);
      return jsonResponse(req, {
        sandbox_id: sandboxId,
        state: sandbox?.state ?? null,
        action: "created",
      }, 201);
    }

    const path = `/sandbox/${encodeURIComponent(input.sandboxId!)}`;
    const { body: sandbox } = await daytonaRequest(path, { method: "GET" }, [404]);
    if (!sandbox) throw new NotFoundError();
    if (!ownedBy(sandbox, user.id)) throw new NotFoundError();

    if (input.action === "get") {
      return jsonResponse(req, {
        sandbox_id: typeof sandbox.id === "string" ? sandbox.id : input.sandboxId,
        state: sandbox.state ?? null,
        action: "fetched",
      });
    }

    await daytonaRequest(path, { method: "DELETE" });
    let deleted = false;
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const check = await daytonaRequest(path, { method: "GET" }, [404, 410]);
      if (check.response.status === 404 || check.response.status === 410) {
        deleted = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
    if (!deleted) throw new DaytonaError(504);
    return jsonResponse(req, { sandbox_id: input.sandboxId, action: "deleted" });
  } catch (error) {
    if (error instanceof AuthError) return jsonResponse(req, { error: "Unauthorized" }, 401);
    if (error instanceof InputError) return jsonResponse(req, { error: error.message }, 400);
    if (error instanceof NotFoundError) return jsonResponse(req, { error: "Sandbox not found" }, 404);
    if (error instanceof DaytonaError) {
      console.error("Daytona request failed", { status: error.status });
      return jsonResponse(req, { error: "Sandbox operation failed", upstream_status: error.status }, 502);
    }
    console.error("daytona-sandbox failed", {
      type: error instanceof Error ? error.name : "UnknownError",
    });
    return jsonResponse(req, { error: "Sandbox operation failed" }, 502);
  }
});
