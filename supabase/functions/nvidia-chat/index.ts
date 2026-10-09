import { AuthError, getRequiredSecret, requireUser } from "./_shared/supabase.ts";
import {
  corsHeaders,
  handlePreflight,
  isOriginAllowed,
  jsonResponse,
} from "./_shared/http.ts";

const NVIDIA_API_URL = "https://integrate.api.nvidia.com/v1/chat/completions";

const MODEL_NEMOTRON = "nvidia/nemotron-3-ultra-550b-a55b";
const MODEL_GLM = "z-ai/glm-5.3";
const MODEL_GLM_FLASH = "z-ai/glm-5.3-flash";
const MODEL_VISION = "meta/llama-3.2-11b-vision-instruct";
const ALLOWED_MODELS = new Set([MODEL_NEMOTRON, MODEL_GLM, MODEL_GLM_FLASH, MODEL_VISION]);

// Both selected NVIDIA model pages advertise up to 1M context. max_tokens is
// the completion allowance; reasoning_effort remains a separate API field.
const MODEL_CONTEXT_TOKEN_LIMIT = 1_000_000;
const MAX_MESSAGES = 10000;
const MAX_TOTAL_MESSAGE_CHARS = 4_000_000;
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
    if (typeof record.content === "string") {
      if (record.content.length === 0) {
        throw new InputError("Message content must be non-empty");
      }
      totalChars += record.content.length;
    } else if (Array.isArray(record.content)) {
      if (record.content.length === 0) {
        throw new InputError("Message content array cannot be empty");
      }
      for (const part of record.content) {
        if (!part || typeof part !== "object") {
          throw new InputError("Content part must be an object");
        }
        const p = part as Record<string, unknown>;
        if (p.type === "text" && typeof p.text === "string") {
          totalChars += p.text.length;
        } else if (p.type === "image_url" && p.image_url && typeof p.image_url === "object") {
          // Valid multimodal image_url part
        } else {
          throw new InputError("Unsupported content part type");
        }
      }
    } else {
      throw new InputError("Message content must be a non-empty string or array of parts");
    }
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

function resolveNvidiaApiKey(model: string): string {
  const nemotronKey = Deno.env.get("NVIDIA_NEMOTRON_API_KEY")?.trim();
  const glmKey = Deno.env.get("NVIDIA_GLM_API_KEY")?.trim();
  const generalKey = Deno.env.get("NVIDIA_API_KEY")?.trim();
  const isGlm = model.includes("glm");

  if (isGlm && glmKey) return glmKey;
  if (!isGlm && nemotronKey) return nemotronKey;
  return nemotronKey || glmKey || generalKey || "";
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (!isOriginAllowed(req)) return jsonResponse(req, { error: "Origin is not allowed" }, 403);
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405);

  try {
    await requireUser(req);
    const body = parseBody(await req.json());
    const model = typeof body.model === "string" ? body.model : MODEL_NEMOTRON;
    if (!ALLOWED_MODELS.has(model)) throw new InputError("Unsupported model");

    let parsedMsgs = parseMessages(body.messages);
    const hasImages = parsedMsgs.some((m) => {
      const c = m.content;
      return Array.isArray(c) && c.some((p) => p && typeof p === "object" && (p as Record<string, unknown>).type === "image_url");
    });

    const isGlm = !hasImages && model.includes("glm");
    const defaultMaxTokens = 16384;
    const defaultTemp = hasImages ? 0.2 : (isGlm ? 0.5 : 1.0);
    const defaultTopP = isGlm ? 1.0 : 0.95;
    const defaultStream = true;

    const maxTokens = numberInRange(
      body.max_tokens,
      "max_tokens",
      1,
      MODEL_CONTEXT_TOKEN_LIMIT,
      defaultMaxTokens,
    );

    if (body.stream != null && typeof body.stream !== "boolean") {
      throw new InputError("stream must be a boolean");
    }
    const stream = body.stream != null ? Boolean(body.stream) : defaultStream;
    const reasoningEffort = body.reasoning_effort ?? (isGlm ? "none" : "low");
    const allowedEfforts = isGlm
      ? new Set(["none", "low", "medium", "high", "max", "standard"])
      : new Set(["none", "low", "medium", "high", "standard"]);
    if (!allowedEfforts.has(String(reasoningEffort))) {
      throw new InputError(isGlm
        ? "reasoning_effort must be none, low, medium, high, max, or standard"
        : "reasoning_effort must be none, low, medium, high, or standard");
    }

    const hasSystem = parsedMsgs.some((m) => m.role === "system");
    if (!hasSystem) {
      parsedMsgs = [{
        role: "system",
        content: hasImages
          ? "You are Build X. You have full multimodal vision capabilities. Analyze the provided image and explain what is shown clearly, accurately, and concisely in natural Arabic. Do not repeat phrases. Be direct."
          : "You are Build X, an advanced AI assistant. You converse naturally, fluently, and directly with the user.\n" +
            "- When addressed in Arabic, respond in clear, natural, grammatically correct Arabic with proper RTL sentence structure.\n" +
            "- When addressed in English, respond in natural English.\n" +
            "- Always provide direct, helpful, and non-empty responses."
      }, ...parsedMsgs];
    }

    const effectiveModel = hasImages ? MODEL_VISION : model;

    const payload: Record<string, unknown> = {
      model: effectiveModel,
      messages: parsedMsgs,
      temperature: numberInRange(body.temperature, "temperature", 0, 1, defaultTemp),
      top_p: numberInRange(body.top_p, "top_p", 0, 1, defaultTopP),
      max_tokens: maxTokens,
      stream,
    };

    if (body.chat_template_kwargs && typeof body.chat_template_kwargs === "object") {
      payload.chat_template_kwargs = body.chat_template_kwargs;
    } else if (isGlm) {
      if (reasoningEffort !== "none") {
        payload.chat_template_kwargs = { enable_thinking: true };
      } else {
        payload.chat_template_kwargs = { clear_thinking: true };
      }
    } else if (!hasImages) {
      payload.chat_template_kwargs = {
        enable_thinking: reasoningEffort !== "none",
        force_nonempty_content: true,
        ...(reasoningEffort === "low" || reasoningEffort === "medium"
          ? { medium_effort: true }
          : {}),
      };
    }

    let activeModel = effectiveModel;
    let activeKey = resolveNvidiaApiKey(activeModel);
    let activePayload = { ...payload };
    let response: Response;

    try {
      response = await fetch(NVIDIA_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${activeKey}`,
          "Accept": stream ? "text/event-stream" : "application/json",
        },
        body: JSON.stringify(activePayload),
        signal: AbortSignal.timeout(120000),
      });

      if (!response.ok && activeModel.includes("glm") && (response.status >= 500 || response.status === 404)) {
        throw new Error(`GLM returned HTTP ${response.status}`);
      }
    } catch (err) {
      if (activeModel.includes("glm")) {
        console.warn("GLM unavailable or timed out; falling back to Nemotron", err);
        activeModel = MODEL_NEMOTRON;
        activeKey = resolveNvidiaApiKey(MODEL_NEMOTRON);
        activePayload.model = MODEL_NEMOTRON;
        activePayload.chat_template_kwargs = {
          enable_thinking: reasoningEffort !== "none",
          force_nonempty_content: true,
          ...(reasoningEffort === "low" || reasoningEffort === "medium"
            ? { medium_effort: true }
            : {}),
        };
        response = await fetch(NVIDIA_API_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${activeKey}`,
            "Accept": stream ? "text/event-stream" : "application/json",
          },
          body: JSON.stringify(activePayload),
          signal: AbortSignal.timeout(120000),
        });
      } else {
        throw err;
      }
    }

    if (!response.ok) {
      const upstreamBody = await response.text();
      const safeUpstreamBody = upstreamBody
        .replace(/bearer\s+\S+|nvapi-[\w-]+/gi, "[redacted]")
        .replace(/\s+/g, " ")
        .slice(0, 2000);
      console.error("NVIDIA upstream failed", { status: response.status, model, body: safeUpstreamBody });
      let upstreamDetail = upstreamBody;
      try {
        const parsed = JSON.parse(upstreamBody) as Record<string, unknown>;
        const error = parsed.error;
        upstreamDetail = error && typeof error === "object"
          ? String((error as Record<string, unknown>).message ?? (error as Record<string, unknown>).detail ?? JSON.stringify(error))
          : String(error ?? parsed.message ?? parsed.detail ?? upstreamBody);
      } catch {
        // NVIDIA may return plain text for proxy and routing errors.
      }
      upstreamDetail = upstreamDetail.replace(/bearer\s+\S+|nvapi-[\w-]+/gi, "[redacted]").slice(0, 500);
      let clientMsg = "Connection interrupted. Please try again.";
      if (response.status === 401 || response.status === 403) {
        clientMsg = "The AI service could not authenticate.";
      } else if (response.status === 404) {
        clientMsg = `NVIDIA returned HTTP 404: ${upstreamDetail}`;
      } else if (response.status === 429) {
        clientMsg = `Rate limit reached: ${upstreamDetail}`;
      } else {
        clientMsg = `NVIDIA request failed with HTTP ${response.status}: ${upstreamDetail}`;
      }
      return jsonResponse(req, { error: clientMsg }, response.status);
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
    if (error instanceof AuthError) {
      return jsonResponse(req, { error: "The AI service could not authenticate." }, 401);
    }
    if (error instanceof InputError || error instanceof SyntaxError) {
      return jsonResponse(req, { error: error.message }, 400);
    }
    console.error("nvidia-chat failed", {
      type: error instanceof Error ? error.name : "UnknownError",
    });
    if (error instanceof DOMException && error.name === "TimeoutError") {
      return jsonResponse(req, {
        error: "The AI response timed out. Please try again.",
      }, 504);
    }
    return jsonResponse(req, { error: "Connection interrupted. Please try again." }, 500);
  }
});
