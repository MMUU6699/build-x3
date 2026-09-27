const DEFAULT_ALLOWED_HEADERS =
  "authorization, x-client-info, apikey, content-type";

function configuredOrigins(): Set<string> {
  return new Set(
    (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
}

export function isOriginAllowed(req: Request): boolean {
  const origin = req.headers.get("Origin");
  if (!origin) return true;
  const allowed = configuredOrigins();
  return allowed.has("*") || allowed.has(origin);
}

export function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get("Origin");
  const allowed = configuredOrigins();
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": DEFAULT_ALLOWED_HEADERS,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };

  if (origin && (allowed.has("*") || allowed.has(origin))) {
    headers["Access-Control-Allow-Origin"] = allowed.has("*") ? "*" : origin;
  }
  return headers;
}

export function jsonResponse(
  req: Request,
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export function handlePreflight(req: Request): Response | null {
  if (req.method !== "OPTIONS") return null;
  if (!isOriginAllowed(req)) {
    return jsonResponse(req, { error: "Origin is not allowed" }, 403);
  }
  return new Response(null, { status: 204, headers: corsHeaders(req) });
}
