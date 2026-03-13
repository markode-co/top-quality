import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2";

/* ------------------------------------------------ */
/* CORS */
/* ------------------------------------------------ */

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-auth, x-sb-jwt, x-jwt",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/* ------------------------------------------------ */
/* HTTP ERROR */
/* ------------------------------------------------ */

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = "HttpError";
  }
}

/* ------------------------------------------------ */
/* ENV */
/* ------------------------------------------------ */

export function getRequiredEnv(name: string): string {
  const value =
    Deno.env.get(name)?.trim() ??
    Deno.env.get(`FUNCTION_${name}`)?.trim() ??
    "";

  if (!value) {
    throw new HttpError(
      500,
      `Missing required environment variable: ${name}`,
    );
  }

  return value;
}

/* ------------------------------------------------ */
/* ADMIN CLIENT */
/* ------------------------------------------------ */

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

// Auth client for validating user tokens (uses anon/publishable key; no admin privileges).
export function createAuthClient(): SupabaseClient {
  return createClient(
    getRequiredEnv("SUPABASE_URL"),
    getRequiredEnv("SUPABASE_PUBLISHABLE_KEY") ||
      getRequiredEnv("SUPABASE_ANON_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

/* ------------------------------------------------ */
/* AUTHENTICATION */
/* ------------------------------------------------ */

function extractToken(req: Request): string | null {
  const authHeader =
    req.headers.get("Authorization") ??
    req.headers.get("authorization");

  if (authHeader?.startsWith("Bearer ")) {
    return authHeader.slice("Bearer ".length).trim();
  }

  // Supabase Edge may forward user JWT in custom headers when verify_jwt=false
  const headerToken =
    req.headers.get("x-supabase-auth") ??
    req.headers.get("x-sb-jwt") ??
    req.headers.get("x-jwt");
  if (headerToken) return headerToken.trim();

  // Fallback: try to read from cookies (web clients may rely on sb-access-token cookie)
  const cookie = req.headers.get("Cookie") ?? req.headers.get("cookie");
  if (cookie) {
    for (const part of cookie.split(";")) {
      const [k, v] = part.trim().split("=");
      if (!v) continue;
      if (k === "sb-access-token" || k === "access_token") return decodeURIComponent(v);
      if (k === "supabase-auth-token") {
        try {
          const arr = JSON.parse(decodeURIComponent(v));
          if (Array.isArray(arr) && arr[0]?.access_token) return arr[0].access_token;
        } catch {
          /* ignore */
        }
      }
    }
  }

  return null;
}

export async function authenticate(
  req: Request,
  supabase?: SupabaseClient,
): Promise<{ user: User }> {
  const token = extractToken(req);

  if (!token) {
    throw new HttpError(401, "Missing Authorization header");
  }

  // Prefer provided client; otherwise fall back to a lightweight auth client
  const authClient = supabase ?? createAuthClient();

  const {
    data: { user },
    error,
  } = await authClient.auth.getUser(token);

  if (error || !user) {
    throw new HttpError(401, "Invalid token");
  }

  return { user };
}

/* ------------------------------------------------ */
/* JSON RESPONSE */
/* ------------------------------------------------ */

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

/* ------------------------------------------------ */
/* ERROR HANDLER */
/* ------------------------------------------------ */

export function handleError(error: unknown, debug = true): Response {
  const status = error instanceof HttpError ? error.status : 500;

  const message =
    error instanceof Error
      ? debug
        ? error.message
        : "Internal Server Error"
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
