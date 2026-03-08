import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_BUCKET = Deno.env.get("SUPABASE_BUCKET") ?? "flutter-web";
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

  if (trimmedPath === "") {
    return INDEX_DOCUMENT;
  }

  return trimmedPath.endsWith("/") ? `${trimmedPath}${INDEX_DOCUMENT}` : trimmedPath;
}

function withStandardHeaders(filePath: string): Headers {
  return new Headers({
    "Content-Type": getContentType(filePath),
    "Cache-Control": getCacheControl(filePath),
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  });
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

Deno.serve(async (request: Request): Promise<Response> => {
  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !SUPABASE_BUCKET) {
      console.error(
        "Missing required environment variables: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_BUCKET",
      );
      return new Response("Internal Server Error", { status: 500 });
    }

    if (request.method === "OPTIONS") {
      return new Response("ok", {
        status: 200,
        headers: withStandardHeaders(INDEX_DOCUMENT),
      });
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: withStandardHeaders(INDEX_DOCUMENT),
      });
    }

    const objectPath = resolveObjectPath(request.url);
    const { data, error } = await supabase.storage
      .from(SUPABASE_BUCKET)
      .download(objectPath);

    if (error || !data) {
      return new Response("Not Found", {
        status: 404,
        headers: withStandardHeaders("not-found.txt"),
      });
    }

    return new Response(request.method === "HEAD" ? null : data, {
      status: 200,
      headers: withStandardHeaders(objectPath),
    });
  } catch (error) {
    console.error("static-proxy error", error);
    return new Response("Internal Server Error", {
      status: 500,
      headers: withStandardHeaders("error.txt"),
    });
  }
});
