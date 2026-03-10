import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createAdminClient, authenticate, corsHeaders, handleError, HttpError, jsonResponse } from "../supabase-edge-helpers.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

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
  companyId: string;
  branchId: string | null;
  roleId: string;
  roleName: string;
  isActive: boolean;
  permissions: Set<string>;
}

console.info("Edge Function admin-manage-employee started");

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const debug = Deno.env.get("DEBUG") === "true";

  try {
    const adminClient = createAdminClient();
    const { user } = await authenticate(req, adminClient);

    const body = (await req.json()) as RequestBody;
    const callerContext = await getCallerContext(adminClient, user.id);
    assertActionAllowed(callerContext, body.action);

    const permissions = Array.from(
      new Set((body.permissions ?? []).map((item) => item.trim()).filter(Boolean)),
    );

    try {
      switch (body.action) {
        case "create":
          return await handleCreate(adminClient, callerContext, body, permissions);
        case "update":
          return await handleUpdate(adminClient, callerContext, body, permissions);
        case "deactivate":
          return await handleDeactivate(adminClient, callerContext, body);
        case "delete":
          return await handleDelete(adminClient, callerContext, body);
        case "list":
          return await handleList(adminClient, callerContext);
        default:
          throw new HttpError(400, "Unsupported employee action.");
      }
    } catch (actionError) {
      await writeAuditLog(adminClient, callerContext.id, `employee_${body.action}_failed`, body.employeeId ?? null, {
        error: actionError instanceof Error ? actionError.message : "Unknown error",
      });
      throw actionError;
    }
  } catch (error) {
    return handleError(error, debug);
  }
});

async function handleCreate(
  adminClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  permissions: string[],
) {
  if (!body.name || !body.email || !body.password || !body.roleName) {
    throw new HttpError(400, "Missing required fields for employee creation.");
  }

  const role = await findRoleByName(adminClient, body.roleName);
  if (!role) {
    throw new HttpError(400, "Invalid role selected.");
  }

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email: body.email,
    password: body.password,
    email_confirm: true,
    user_metadata: { name: body.name },
  });

  if (createError || !created.user) {
    throw new HttpError(400, createError?.message ?? "Failed to create auth user.");
  }

  const employeeId = created.user.id;
  const { error: userInsertError } = await adminClient.from("users").insert({
    id: employeeId,
    company_id: caller.companyId,
    branch_id: caller.branchId,
    name: body.name,
    email: body.email,
    role_id: role.id,
    is_active: body.isActive ?? true,
  });

  if (userInsertError) {
    await adminClient.auth.admin.deleteUser(employeeId);
    throw new HttpError(400, userInsertError.message);
  }

  if (permissions.length > 0) {
    const { error: permissionInsertError } = await adminClient
      .from("user_permissions")
      .insert(
        permissions.map((code) => ({
          user_id: employeeId,
          permission_code: code,
        })),
      );

    if (permissionInsertError) {
      throw new HttpError(400, permissionInsertError.message);
    }
  }

  await writeAuditLog(adminClient, caller.id, "employee_created", employeeId, {
    email: body.email,
    role_name: body.roleName,
  });

  return jsonResponse({ status: "ok", employeeId });
}

async function handleList(adminClient: SupabaseClient, caller: CallerContext) {
  const { data, error } = await adminClient
    .from("users")
    .select(
      "id, name, email, is_active, branch_id, company_id, role:roles(role_name), user_permissions(permission_code)",
    )
    .eq("company_id", caller.companyId)
    .order("name", { ascending: true });

  if (error) {
    throw new HttpError(400, error.message);
  }

  const employees =
    data?.map((row) => ({
      id: row.id,
      name: row.name,
      email: row.email,
      isActive: row.is_active ?? false,
      branchId: row.branch_id ?? null,
      roleName: resolveRoleName(
        Array.isArray(row.role) && row.role.length > 0 ? row.role[0] : row.role ?? {},
      ),
      permissions:
        Array.isArray(row.user_permissions) && row.user_permissions.length > 0
          ? row.user_permissions
              .map((item: Record<string, unknown>) => item?.permission_code)
              .filter((code): code is string => typeof code === "string" && code.length > 0)
          : [],
    })) ?? [];

  return jsonResponse({ status: "ok", employees });
}

async function handleUpdate(
  adminClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  permissions: string[],
) {
  if (!body.employeeId || !body.name || !body.email || !body.roleName) {
    throw new HttpError(400, "Missing required fields for employee update.");
  }

  await assertManagedUserInTenant(adminClient, caller, body.employeeId);

  const role = await findRoleByName(adminClient, body.roleName);
  if (!role) {
    throw new HttpError(400, "Invalid role selected.");
  }

  const updatePayload: Record<string, unknown> = {
    email: body.email,
    user_metadata: { name: body.name },
  };
  if (body.password?.trim()) {
    updatePayload.password = body.password;
  }

  const { error: authUpdateError } = await adminClient.auth.admin.updateUserById(
    body.employeeId,
    updatePayload,
  );
  if (authUpdateError) {
    throw new HttpError(400, authUpdateError.message);
  }

  const { error: profileUpdateError } = await adminClient
    .from("users")
    .update({
      name: body.name,
      email: body.email,
      role_id: role.id,
      is_active: body.isActive ?? true,
    })
    .eq("id", body.employeeId);
  if (profileUpdateError) {
    throw new HttpError(400, profileUpdateError.message);
  }

  const { error: permissionDeleteError } = await adminClient
    .from("user_permissions")
    .delete()
    .eq("user_id", body.employeeId);
  if (permissionDeleteError) {
    throw new HttpError(400, permissionDeleteError.message);
  }

  if (permissions.length > 0) {
    const { error: permissionInsertError } = await adminClient
      .from("user_permissions")
      .insert(
        permissions.map((code) => ({
          user_id: body.employeeId,
          permission_code: code,
        })),
      );

    if (permissionInsertError) {
      throw new HttpError(400, permissionInsertError.message);
    }
  }

  await writeAuditLog(adminClient, caller.id, "employee_updated", body.employeeId, {
    email: body.email,
    role_name: body.roleName,
  });

  return jsonResponse({ status: "ok", employeeId: body.employeeId });
}

async function handleDeactivate(
  adminClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  if (!body.employeeId || body.isActive === undefined) {
    throw new HttpError(400, "Missing employee activation payload.");
  }

  await assertManagedUserInTenant(adminClient, caller, body.employeeId);

  const { error } = await adminClient
    .from("users")
    .update({ is_active: body.isActive })
    .eq("id", body.employeeId);
  if (error) {
    throw new HttpError(400, error.message);
  }

  await writeAuditLog(
    adminClient,
    caller.id,
    body.isActive ? "employee_activated" : "employee_deactivated",
    body.employeeId,
    {},
  );

  return jsonResponse({ status: "ok", employeeId: body.employeeId });
}

async function handleDelete(
  adminClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  if (!body.employeeId) {
    throw new HttpError(400, "Missing employee identifier.");
  }

  await assertManagedUserInTenant(adminClient, caller, body.employeeId);

  await writeAuditLog(adminClient, caller.id, "employee_deleted", body.employeeId, {});

  const { error: dbDeleteError } = await adminClient
    .from("users")
    .delete()
    .eq("id", body.employeeId);
  if (dbDeleteError) {
    throw new HttpError(400, dbDeleteError.message);
  }

  const { error: authDeleteError } = await adminClient.auth.admin.deleteUser(body.employeeId);
  if (authDeleteError) {
    throw new HttpError(400, authDeleteError.message);
  }

  return jsonResponse({ status: "ok", employeeId: body.employeeId });
}

async function getCallerContext(
  adminClient: SupabaseClient,
  callerId: string,
): Promise<CallerContext> {
  const { data: userRow, error: userError } = await adminClient
    .from("users")
    .select("id, company_id, branch_id, role_id, is_active")
    .eq("id", callerId)
    .single();
  if (userError || !userRow) {
    throw new HttpError(403, "Caller profile was not found in public.users.");
  }

  if (!userRow.is_active) {
    throw new HttpError(403, "Only active users can manage employees.");
  }
  if (!userRow.company_id) {
    throw new HttpError(403, "Caller company is missing.");
  }

  const { data: roleRow, error: roleError } = await adminClient
    .from("roles")
    .select("*")
    .eq("id", userRow.role_id)
    .single();
  if (roleError || !roleRow) {
    throw new HttpError(403, "Caller role is invalid.");
  }

  const [rolePermissionsRes, directPermissionsRes] = await Promise.all([
    adminClient.from("role_permissions").select("permission_code").eq("role_id", userRow.role_id),
    adminClient.from("user_permissions").select("permission_code").eq("user_id", callerId),
  ]);

  if (rolePermissionsRes.error) {
    throw new HttpError(400, rolePermissionsRes.error.message);
  }
  if (directPermissionsRes.error) {
    throw new HttpError(400, directPermissionsRes.error.message);
  }

  const permissions = new Set<string>([
    ...(rolePermissionsRes.data ?? [])
      .map((item) => item.permission_code)
      .filter((item): item is string => typeof item === "string" && item.length > 0),
    ...(directPermissionsRes.data ?? [])
      .map((item) => item.permission_code)
      .filter((item): item is string => typeof item === "string" && item.length > 0),
  ]);

  return {
    id: callerId,
    companyId: userRow.company_id,
    branchId: userRow.branch_id,
    roleId: roleRow.id,
    roleName: roleRow.role_name,
    isActive: userRow.is_active,
    permissions,
  };
}

function assertActionAllowed(caller: CallerContext, action: Action) {
  if (caller.roleName === "Admin") {
    return;
  }

  const requiredPermissions: Record<Action, string[]> = {
    create: ["users_create", "users_assign_permissions"],
    update: ["users_edit", "users_assign_permissions"],
    deactivate: ["users_edit"],
    delete: ["users_delete"],
    list: ["users_view"],
  };

  const missing = requiredPermissions[action].filter((permission) => !caller.permissions.has(permission));
  if (missing.length > 0) {
    throw new HttpError(403, `Missing employee management permissions: ${missing.join(", ")}`);
  }
}

async function assertManagedUserInTenant(
  adminClient: SupabaseClient,
  caller: CallerContext,
  employeeId: string,
) {
  const { data: targetUser, error } = await adminClient
    .from("users")
    .select("id, company_id")
    .eq("id", employeeId)
    .single();

  if (error || !targetUser) {
    throw new HttpError(404, "Employee profile was not found.");
  }

  if (targetUser.company_id !== caller.companyId) {
    throw new HttpError(403, "Cross-company employee management is not allowed.");
  }
}

async function findRoleByName(adminClient: SupabaseClient, roleName: string) {
  const { data, error } = await adminClient.from("roles").select("*");
  if (error) {
    throw new HttpError(400, error.message);
  }

  const normalized = roleName.trim().toLowerCase();
  const acceptedNames = new Set<string>([normalized, ...resolveRoleAliases(normalized)]);
  return data.find((item) => acceptedNames.has(resolveRoleName(item).trim().toLowerCase())) ?? null;
}

function resolveRoleName(row: Record<string, unknown>) {
  for (const key of ["role_name", "name", "title", "label"]) {
    const value = row[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
  }
  return "";
}

function resolveRoleAliases(roleName: string) {
  switch (roleName) {
    case "order entry user":
      return ["employee", "order entry", "viewer"];
    case "order reviewer":
      return ["manager", "reviewer"];
    case "shipping user":
      return ["shipping"];
    case "admin":
      return ["system administrator", "administrator"];
    default:
      return [];
  }
}

async function writeAuditLog(
  adminClient: SupabaseClient,
  actorId: string,
  action: string,
  entityId: string | null,
  metadata: Record<string, unknown>,
) {
  const { error } = await adminClient.rpc("write_activity_log", {
    p_actor_id: actorId,
    p_action: action,
    p_entity_type: "user",
    p_entity_id: entityId,
    p_metadata: metadata,
  });

  if (error) {
    throw new HttpError(400, error.message);
  }
}
