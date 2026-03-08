import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "@supabase/supabase-js";

type DenoEnv = {
  get(key: string): string | undefined;
};

const denoEnv = (
  globalThis as typeof globalThis & {
    Deno?: { env: DenoEnv };
  }
).Deno?.env;

const SUPABASE_URL = denoEnv?.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  denoEnv?.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_BUCKET = denoEnv?.get("SUPABASE_BUCKET") ?? "";
const INDEX_DOCUMENT = "index.html";
const FUNCTION_PREFIXES = [
  "/functions/v1/static-proxy",
  "/static-proxy",
];

function getContentType(filePath: string): string {
  const lowerPath = filePath.toLowerCase();

  if (lowerPath.endsWith(".html")) return "text/html; charset=UTF-8";
  if (lowerPath.endsWith(".js")) return "application/javascript";
  if (lowerPath.endsWith(".json")) return "application/json";
  if (lowerPath.endsWith(".wasm")) return "application/wasm";
  if (lowerPath.endsWith(".png")) return "image/png";
  if (lowerPath.endsWith(".ttf")) return "font/ttf";
  if (lowerPath.endsWith(".otf")) return "font/otf";
  if (lowerPath.endsWith(".frag")) return "text/plain; charset=UTF-8";

  return "application/octet-stream";
}

function getCacheControl(filePath: string): string {
  return filePath === INDEX_DOCUMENT
    ? "public, max-age=0, must-revalidate"
    : "public, max-age=31536000, immutable";
}

function stripFunctionPrefix(pathname: string): string {
  for (const prefix of FUNCTION_PREFIXES) {
    if (pathname === prefix) {
      return "/";
    }

    if (pathname.startsWith(`${prefix}/`)) {
      return pathname.slice(prefix.length) || "/";
    }
  }

  return pathname;
}

function resolveObjectPath(requestUrl: string): string {
  const url = new URL(requestUrl);
  const pathname = stripFunctionPrefix(decodeURIComponent(url.pathname));
  const trimmedPath = pathname.replace(/^\/+/, "");

  return trimmedPath === "" ? INDEX_DOCUMENT : trimmedPath;
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

serve(async (request: Request): Promise<Response> => {
  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !SUPABASE_BUCKET) {
      console.error(
        "Missing required environment variables: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_BUCKET",
      );
      return new Response("Internal Server Error", { status: 500 });
    }

    const objectPath = resolveObjectPath(request.url);
    const { data, error } = await supabase.storage
      .from(SUPABASE_BUCKET)
      .download(objectPath);

    if (error || !data) {
      return new Response("Not Found", { status: 404 });
    }

    return new Response(data, {
      status: 200,
      headers: {
        "Content-Type": getContentType(objectPath),
        "Cache-Control": getCacheControl(objectPath),
      },
    });
  } catch (error) {
    console.error("static-proxy error", error);
    return new Response("Internal Server Error", { status: 500 });
  }
});
