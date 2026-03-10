import { createClient, type SupabaseClient, type User } from "jsr:@supabase/supabase-js@2";
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "HttpError";
  }
}

export function getRequiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim() ?? "";
  if (!value) {
    throw new HttpError(500, `Missing required environment variable: ${name}`);
  }
  return value;
}

export function createAdminClient(): SupabaseClient {
  return createClient(
    getRequiredEnv("SUPABASE_URL"),
    getRequiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

export async function authenticate(
  req: Request,
  supabase: SupabaseClient,
): Promise<{ user: User }> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    throw new HttpError(401, "Missing or invalid Authorization header.");
  }

  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) {
    throw new HttpError(401, "Missing or invalid Authorization header.");
  }

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) {
    throw new HttpError(401, "Invalid JWT.");
  }

  return { user: data.user };
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

export function handleError(error: unknown, debug = true): Response {
  const status = error instanceof HttpError ? error.status : 500;
  const message = error instanceof Error
    ? (debug ? error.message : "Internal Server Error")
    : "Internal Server Error";

  console.error("[EDGE FUNCTION ERROR]", error);

  return jsonResponse(
    {
      status: "error",
      message,
    },
    status,
  );
}
