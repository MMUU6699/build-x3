import { AuthError, getRequiredSecret, requireUser } from "../_shared/supabase.ts";
import {
  corsHeaders,
  handlePreflight,
  isOriginAllowed,
  jsonResponse,
} from "../_shared/http.ts";

const NVIDIA_API_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const DEFAULT_MODEL = "nvidia/nemotron-3-ultra-550b-a55b";
const ALLOWED_MODELS = new Set([DEFAULT_MODEL]);
const ABSOLUTE_MAX_TOKENS = 32768;
const MAX_MESSAGES = 100;
const MAX_TOTAL_MESSAGE_CHARS = 200000;
const FORBIDDEN_SECRET_FIELDS = new Set([
  "api_key",
  "apiKey",
  "nvidia_api_key",
  "nvidiaApiKey",
  "authorization",
  "secret",
]);

type ChatMessage = { role: "system" | "user" | "assistant"; content: string };

class InputError extends Error {}

function numberInRange(
  value: unknown,
  name: string,
  min: number,
  max: number,
  fallback: number,
): number {
  if (value == null) return fallback;
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) {
    throw new InputError(`${name} must be between ${min} and ${max}`);
  }
  return value;
}

function parseMessages(value: unknown): ChatMessage[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_MESSAGES) {
    throw new InputError(`messages must contain between 1 and ${MAX_MESSAGES} items`);
  }

  let totalChars = 0;
  const messages = value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new InputError("Each message must be an object");
    }
    const record = item as Record<string, unknown>;
    if (!new Set(["system", "user", "assistant"]).has(String(record.role))) {
      throw new InputError("Unsupported message role");
    }
    if (typeof record.content !== "string" || record.content.length === 0) {
      throw new InputError("Message content must be a non-empty string");
    }
    totalChars += record.content.length;
    return {
      role: record.role as ChatMessage["role"],
      content: record.content,
    };
  });

  if (totalChars > MAX_TOTAL_MESSAGE_CHARS) {
    throw new InputError(`Total message content exceeds ${MAX_TOTAL_MESSAGE_CHARS} characters`);
  }
  return messages;
}

function parseBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError("Request body must be a JSON object");
  }
  const body = value as Record<string, unknown>;
  for (const key of FORBIDDEN_SECRET_FIELDS) {
    if (key in body) throw new InputError("Client-provided provider credentials are not accepted");
  }
  return body;
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (!isOriginAllowed(req)) return jsonResponse(req, { error: "Origin is not allowed" }, 403);
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405);

  try {
    await requireUser(req);
    const body = parseBody(await req.json());
    const model = typeof body.model === "string" ? body.model : DEFAULT_MODEL;
    if (!ALLOWED_MODELS.has(model)) throw new InputError("Unsupported model");

    const configuredCap = Number(Deno.env.get("NVIDIA_MAX_TOKENS") ?? "16384");
    const maxTokenCap = Number.isInteger(configuredCap) && configuredCap > 0
      ? Math.min(configuredCap, ABSOLUTE_MAX_TOKENS)
      : 16384;
    const maxTokens = numberInRange(body.max_tokens, "max_tokens", 1, maxTokenCap, maxTokenCap);
    if (body.stream != null && typeof body.stream !== "boolean") {
      throw new InputError("stream must be a boolean");
    }
    const stream = body.stream ?? true;
    const reasoningEffort = body.reasoning_effort ?? "high";
    if (!new Set(["none", "medium", "high"]).has(String(reasoningEffort))) {
      throw new InputError("reasoning_effort must be none, medium, or high");
    }

    const payload = {
      model,
      messages: parseMessages(body.messages),
      temperature: numberInRange(body.temperature, "temperature", 0, 1, 1),
      top_p: numberInRange(body.top_p, "top_p", 0, 1, 0.95),
      max_tokens: maxTokens,
      stream,
      reasoning_effort: reasoningEffort,
      chat_template_kwargs: { enable_thinking: reasoningEffort !== "none" },
    };

    const response = await fetch(NVIDIA_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${getRequiredSecret("NVIDIA_API_KEY")}`,
        "Accept": stream ? "text/event-stream" : "application/json",
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(120000),
    });

    if (!response.ok) {
      console.error("NVIDIA request failed", { status: response.status });
      return jsonResponse(req, { error: "Upstream model request failed" }, response.status);
    }

    return new Response(response.body, {
      status: response.status,
      headers: {
        ...corsHeaders(req),
        "Content-Type": stream ? "text/event-stream" : "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        ...(stream ? { "X-Accel-Buffering": "no" } : {}),
      },
    });
  } catch (error) {
    if (error instanceof AuthError) return jsonResponse(req, { error: "Unauthorized" }, 401);
    if (error instanceof InputError || error instanceof SyntaxError) {
      return jsonResponse(req, { error: error.message }, 400);
    }
    console.error("nvidia-chat failed", {
      type: error instanceof Error ? error.name : "UnknownError",
    });
    return jsonResponse(req, { error: "Internal server error" }, 500);
  }
});
