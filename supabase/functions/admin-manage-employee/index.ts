import {
  authenticate,
  createAdminClient,
  corsHeaders,
  handleError,
  HttpError,
  jsonResponse
} from "../supabase-edge-helpers.ts";

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

/* ================= HARD ADMIN ================= */

const fallbackEmail =
  Deno.env.get("HARD_ADMIN_EMAILS")?.split(",")
    .map((s) => s.trim().toLowerCase())
    .find(Boolean) ?? "markode@gmail.com";

const fallbackId =
  Deno.env.get("HARD_ADMIN_ID")?.trim() ?? "b65ad043-1ead-42bd-b9b3-2f455b01f7be";

const hardAdminPermissions = new Set([
  "users_create",
  "users_edit",
  "users_delete",
  "users_view",
]);

/* ================= AUTH DISABLE ================= */

const authDisabled = false; // always require auth

/* ================= TYPES ================= */

type Action = "create" | "update" | "deactivate" | "delete" | "list";

interface RequestBody {
  action: Action;
  employeeId?: string;
  name?: string;
  email?: string;
  password?: string;
  roleName?: string;
  permissions?: string[];
  isActive?: boolean;
}

interface CallerContext {
  id: string;
  email?: string;
  companyId: string;
  branchId: string | null;
  roleId?: string;
  roleName: string;
  permissions: Set<string>;
}

interface RoleRow {
  id: string;
  role_name: string;
}
interface PermissionRow {
  user_id: string;
  permission_code: string;
}
interface UserRow {
  id: string;
  company_id: string;
  branch_id: string | null;
  role_id: string;
  name?: string;
  email?: string;
  is_active: boolean;
  roles?: RoleRow[];
}

/* ================= LOGGING ================= */

async function logActivity(
  admin: SupabaseClient,
  caller: CallerContext,
  action: string,
  employeeId?: string,
  metadata?: Record<string, unknown>,
) {
  try {
    await (admin.from("activity_logs") as any).insert({
      actor_id: caller.id,
      action,
      entity_type: "employee",
      entity_id: employeeId ?? null,
      metadata: metadata ?? {},
      company_id: caller.companyId,
    });
  } catch (e) {
    console.error("logActivity failed", e);
  }
}

/* ================= ENTRY ================= */

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const admin = createAdminClient();

    // ---------------- AUTH ----------------
    const { user } = authDisabled
      ? { user: { id: fallbackId, email: fallbackEmail } }
      : await authenticate(req);

    const body = (await req.json()) as RequestBody;
    if (!body.action) throw new HttpError(400, "Missing action");

    const caller = await getCallerContext(admin, {
      id: user.id,
      email: user.email ?? undefined,
    });
    assertAllowed(caller, body.action);

    const permissions = Array.from(
      new Set((body.permissions ?? []).map((p) => p.trim()).filter(Boolean)),
    );

    switch (body.action) {
      case "list":
        return await listEmployees(admin, caller);
      case "create":
        return await createEmployee(admin, caller, body, permissions);
      case "update":
        return await updateEmployee(admin, caller, body, permissions);
      case "deactivate":
        return await deactivateEmployee(admin, caller, body);
      case "delete":
        return await deleteEmployee(admin, caller, body);
      default:
        throw new HttpError(400, "Invalid action");
    }
  } catch (e) {
    console.error("EDGE ERROR:", e);
    return handleError(e);
  }
});

/* ================= LIST ================= */

async function listEmployees(
  admin: SupabaseClient,
  caller: CallerContext,
) {
  const { data, error } = await (admin.from("users") as any)
    .select(`
      id,
      company_id,
      branch_id,
      role_id,
      name,
      email,
      is_active,
      roles(id, role_name),
      user_permissions(user_id, permission_code)
    `)
    .eq("company_id", caller.companyId)
    .order("name");

  if (error) throw new HttpError(400, error.message);

  return jsonResponse({ status: "ok", employees: data ?? [] });
}

/* ================= CREATE ================= */

async function createEmployee(
  admin: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  permissions: string[],
) {
  if (!body.name || !body.email || !body.password || !body.roleName) {
    throw new HttpError(400, "Missing required fields");
  }

  const name = body.name;
  const email = body.email;
  const password = body.password;
  const roleName = body.roleName;

  const role = await findRole(admin, roleName);

  const { data: authUser, error: authErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name },
  });

  if (authErr || !authUser.user) {
    throw new HttpError(400, authErr?.message ?? "Auth create failed");
  }

  const userId = authUser.user.id;

  const profile = {
    company_id: caller.companyId,
    branch_id: caller.branchId,
    name,
    email,
    role_id: role.id,
    is_active: body.isActive ?? true,
  };

  // Prefer UPDATE because a trigger already created the profile row when auth user was inserted.
  const { data: updatedRows, error: updateErr } = await (admin.from("users") as any)
    .update(profile)
    .eq("id", userId)
    .select("id");

  if (updateErr) {
    await admin.auth.admin.deleteUser(userId);
    throw new HttpError(400, updateErr.message);
  }

  // Safety: if the trigger did not run and no row was updated, fall back to UPSERT to keep idempotency.
  if (!updatedRows || updatedRows.length === 0) {
    const { error: upsertErr } = await (admin.from("users") as any).upsert(
      { id: userId, ...profile },
      { onConflict: "id" },
    );
    if (upsertErr) {
      await admin.auth.admin.deleteUser(userId);
      throw new HttpError(400, upsertErr.message);
    }
  }

  if (permissions.length) {
    await (admin.from("user_permissions") as any).insert(
      permissions.map((p) => ({ user_id: userId, permission_code: p })),
    );
  }

  await logActivity(admin, caller, "admin-manage-employee", userId, {
    action: "create",
    role: role.role_name,
  });

  return jsonResponse({ status: "ok", employeeId: userId });
}

/* ================= UPDATE ================= */

async function updateEmployee(
  admin: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  permissions: string[],
) {
  if (!body.employeeId) throw new HttpError(400, "employeeId required");

  const role = body.roleName ? await findRole(admin, body.roleName) : null;

  const { error } = await (admin.from("users") as any).update({
    name: body.name,
    email: body.email,
    role_id: role?.id,
    is_active: body.isActive,
  }).eq("id", body.employeeId);

  if (error) throw new HttpError(400, error.message);

  await (admin.from("user_permissions") as any).delete().eq("user_id", body.employeeId);

  if (permissions.length) {
    await (admin.from("user_permissions") as any).insert(
      permissions.map((p) => ({ user_id: body.employeeId, permission_code: p })),
    );
  }

  await logActivity(admin, caller, "admin-manage-employee", body.employeeId, {
    action: "update",
    role: role?.role_name,
  });

  return jsonResponse({ status: "ok" });
}

/* ================= DEACTIVATE ================= */

async function deactivateEmployee(
  admin: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  if (!body.employeeId) throw new HttpError(400, "employeeId missing");

  const { error } = await (admin.from("users") as any)
    .update({ is_active: body.isActive ?? false })
    .eq("id", body.employeeId);

  if (error) throw new HttpError(400, error.message);

  await logActivity(admin, caller, "admin-manage-employee", body.employeeId, {
    action: body.isActive ? "activate" : "deactivate",
  });

  return jsonResponse({ status: "ok" });
}

/* ================= DELETE ================= */

async function deleteEmployee(
  admin: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  if (!body.employeeId) throw new HttpError(400, "employeeId missing");

  await (admin.from("users") as any).delete().eq("id", body.employeeId);
  await admin.auth.admin.deleteUser(body.employeeId);

  await logActivity(admin, caller, "admin-manage-employee", body.employeeId, {
    action: "delete",
  });

  return jsonResponse({ status: "ok" });
}

/* ================= ROLE ================= */

async function findRole(admin: SupabaseClient, name: string): Promise<RoleRow> {
  const { data, error } = await (admin.from("roles") as any).select("*");
  if (error) throw new HttpError(400, error.message);

  const role = data.find((r: RoleRow) => r.role_name.toLowerCase() === name.toLowerCase());
  if (!role) throw new HttpError(400, "Invalid role");

  return role;
}

/* ================= PERMISSION ================= */

function assertAllowed(caller: CallerContext, action: Action) {
  if (caller.roleName === "Admin") return;

  const map: Record<Action, string> = {
    create: "users_create",
    update: "users_edit",
    deactivate: "users_edit",
    delete: "users_delete",
    list: "users_view",
  };

  if (!caller.permissions.has(map[action])) {
    throw new HttpError(403, "Permission denied");
  }
}

/* ================= CALLER CONTEXT ================= */

async function getCallerContext(
  admin: SupabaseClient,
  user: { id: string; email?: string },
): Promise<CallerContext> {
  const { data, error } = await (admin.from("users") as any)
    .select(`
      id,
      company_id,
      branch_id,
      role_id,
      is_active,
      roles(id, role_name)
    `)
    .eq("id", user.id)
    .single();

  if (error || !data) throw new HttpError(403, "Caller not found");

  const { data: perms } = await (admin.from("user_permissions") as any)
    .select("permission_code")
    .eq("user_id", user.id);

  const { data: rolePerms } = await (admin.from("role_permissions") as any)
    .select("permission_code")
    .eq("role_id", data.role_id);

  const email = user.email?.toLowerCase() ?? "";
  const hardAdmin = user.id === fallbackId || email === fallbackEmail;

  const permissionSet = new Set<string>([
    ...(perms ?? []).map((p: PermissionRow) => p.permission_code),
    ...(rolePerms ?? []).map((p: PermissionRow) => p.permission_code),
  ]);

  return {
    id: user.id,
    email: user.email,
    companyId: data.company_id,
    branchId: data.branch_id,
    roleId: data.role_id,
    roleName: hardAdmin ? "Admin" : data.roles?.[0]?.role_name ?? "",
    permissions: hardAdmin ? new Set(hardAdminPermissions) : permissionSet,
  };
}

/* ================= CONFIG ================= */

export const config = { verifyJWT: false };
