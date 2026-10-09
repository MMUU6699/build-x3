import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2.117.1";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required server configuration: ${name}`);
  return value;
}

function bearerToken(req: Request): string {
  const authorization = req.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+([^\s]+)$/i.exec(authorization.trim());
  if (!match) throw new AuthError("Missing or malformed bearer token");
  return match[1];
}

export class AuthError extends Error {}

export async function requireUser(
  req: Request,
): Promise<{ user: User; client: SupabaseClient }> {
  const token = bearerToken(req);
  const client = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    },
  );

  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new AuthError("Invalid or expired bearer token");
  return { user: data.user, client };
}

export function createAdminClient(): SupabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    },
  );
}

export function getRequiredSecret(name: string): string {
  return requiredEnv(name);
}
