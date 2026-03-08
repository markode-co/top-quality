const fs = require("fs");
const path = require("path");

const defaultEnvFile = path.resolve(process.cwd(), "supabase.functions.local.env");

async function main() {
  const envFile = process.argv[2]
    ? path.resolve(process.cwd(), process.argv[2])
    : defaultEnvFile;
  const env = loadEnvFile(envFile);

  const supabaseUrl = env.SUPABASE_URL;
  const serviceRoleKey = env.SUPABASE_SERVICE_ROLE_KEY;
  const anonKey = env.SUPABASE_PUBLISHABLE_KEY || env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    throw new Error(
      `Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or SUPABASE_PUBLISHABLE_KEY in ${envFile}.`,
    );
  }

  const restBaseUrl = `${supabaseUrl}/rest/v1`;
  const functionBaseUrl = `${supabaseUrl}/functions/v1`;
  const failures = [];

  const relationChecks = [
    ["users", "id,name,email,role_id,is_active,company_id,branch_id"],
    ["roles", "*"],
    ["permissions", "*"],
    ["role_permissions", "*"],
    ["user_permissions", "*"],
    ["products", "id,name,sku,category,purchase_price,sale_price,is_active,company_id"],
    ["inventory", "product_id,stock,min_stock,company_id,branch_id"],
    ["orders", "id,customer_name,status,company_id,branch_id"],
    ["order_items", "id,order_id,product_id,quantity,purchase_price,sale_price"],
    ["order_status_history", "id,order_id,status,changed_by,changed_at"],
    ["notifications", "id,user_id,title,message,read,company_id"],
    ["activity_logs", "id,actor_id,actor_name,action,entity_type,metadata,company_id"],
    ["v_users_with_permissions", "id,name,email,role_id,role_name,is_active,permissions,company_id,branch_id"],
    ["v_products", "id,name,sku,category,purchase_price,sale_price,stock,min_stock,company_id,branch_id"],
  ];

  console.log(`Checking Supabase runtime using ${path.basename(envFile)}...`);

  for (const [relation, select] of relationChecks) {
    const url = `${restBaseUrl}/${relation}?select=${encodeURIComponent(select)}&limit=1`;
    const result = await request(url, {
      method: "GET",
      headers: restHeaders(serviceRoleKey),
    });
    recordResult(`REST ${relation}`, result, failures);
  }

  const rpcChecks = [
    ["record_user_login", {}],
    [
      "create_order",
      {
        p_customer_name: "Runtime Check",
        p_customer_phone: "0000000000",
        p_order_notes: "smoke-test",
        p_items: [],
      },
    ],
    [
      "update_order",
      {
        p_order_id: "00000000-0000-0000-0000-000000000000",
        p_customer_name: "Runtime Check",
        p_customer_phone: "0000000000",
        p_order_notes: "smoke-test",
        p_items: [],
      },
    ],
    ["delete_order", { p_order_id: "00000000-0000-0000-0000-000000000000" }],
    [
      "transition_order",
      {
        p_order_id: "00000000-0000-0000-0000-000000000000",
        p_next_status: "checked",
        p_note: "smoke-test",
      },
    ],
    [
      "override_order_status",
      {
        p_order_id: "00000000-0000-0000-0000-000000000000",
        p_next_status: "checked",
        p_note: "smoke-test",
      },
    ],
    [
      "upsert_product",
      {
        p_product_id: null,
        p_name: "Runtime Check",
        p_sku: "RUNTIME-CHECK",
        p_category: "Diagnostics",
        p_purchase_price: 1,
        p_sale_price: 2,
        p_stock: 0,
        p_min_stock: 0,
      },
    ],
    [
      "adjust_inventory",
      {
        p_product_id: "00000000-0000-0000-0000-000000000000",
        p_quantity_delta: 1,
        p_reason: "smoke-test",
      },
    ],
    ["mark_notification_read", { p_notification_id: "00000000-0000-0000-0000-000000000000" }],
    [
      "write_activity_log",
      {
        p_actor_id: "00000000-0000-0000-0000-000000000000",
        p_action: "smoke_test",
        p_entity_type: "diagnostics",
        p_entity_id: "runtime-check",
        p_metadata: {},
      },
    ],
  ];

  for (const [rpcName, payload] of rpcChecks) {
    const url = `${restBaseUrl}/rpc/${rpcName}`;
    const result = await request(url, {
      method: "POST",
      headers: {
        ...restHeaders(serviceRoleKey),
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    recordRpcResult(`RPC ${rpcName}`, result, failures);
  }

  const edgeResult = await request(`${functionBaseUrl}/admin-manage-employee`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ action: "create" }),
  });
  recordFunctionResult("Edge admin-manage-employee", edgeResult, failures);

  if (failures.length > 0) {
    console.error("");
    console.error("Runtime check failed:");
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log("");
  console.log("Runtime check passed.");
}

function loadEnvFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  const env = {};

  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex <= 0) {
      continue;
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    const value = trimmed.slice(separatorIndex + 1).trim();
    env[key] = value;
  }

  return env;
}

function restHeaders(apiKey) {
  return {
    apikey: apiKey,
    Authorization: `Bearer ${apiKey}`,
  };
}

async function request(url, options) {
  try {
    const response = await fetch(url, options);
    const text = await response.text();
    let json = null;

    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = null;
    }

    return {
      ok: response.ok,
      status: response.status,
      text,
      json,
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      text: error instanceof Error ? error.message : String(error),
      json: null,
    };
  }
}

function recordResult(label, result, failures) {
  if (result.ok) {
    console.log(`[ok] ${label}`);
    return;
  }

  failures.push(`${label}: ${summarize(result)}`);
  console.log(`[fail] ${label}`);
}

function recordRpcResult(label, result, failures) {
  if (result.status !== 404 && !looksLikeMissingFunction(result)) {
    console.log(`[ok] ${label}`);
    return;
  }

  failures.push(`${label}: ${summarize(result)}`);
  console.log(`[fail] ${label}`);
}

function recordFunctionResult(label, result, failures) {
  if (result.status !== 404 && !looksLikeMissingFunctionRoute(result)) {
    console.log(`[ok] ${label}`);
    return;
  }

  failures.push(`${label}: ${summarize(result)}`);
  console.log(`[fail] ${label}`);
}

function looksLikeMissingFunction(result) {
  const message = `${result.text}`.toLowerCase();
  return (
    message.includes("function") &&
    (message.includes("does not exist") || message.includes("could not find"))
  );
}

function looksLikeMissingFunctionRoute(result) {
  const message = `${result.text}`.toLowerCase();
  return result.status === 404 || message.includes("function not found");
}

function summarize(result) {
  const source = result.text || JSON.stringify(result.json) || "Unknown error";
  return `HTTP ${result.status}: ${source.slice(0, 240)}`;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
