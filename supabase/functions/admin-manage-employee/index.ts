import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Action = "create" | "update" | "deactivate" | "delete";

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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const clientKey =
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      Deno.env.get("SUPABASE_ANON_KEY") ??
      "";
    const authHeader = req.headers.get("Authorization");

    if (!supabaseUrl || !serviceRoleKey || !clientKey || !authHeader) {
      throw new Error("Missing Supabase environment configuration.");
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const userClient = createClient(supabaseUrl, clientKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user: caller },
      error: callerError,
    } = await userClient.auth.getUser();

    if (callerError || !caller) {
      throw new Error("Unauthorized request.");
    }

    const body = (await req.json()) as RequestBody;
    const callerContext = await getCallerContext(adminClient, caller.id);
    assertActionAllowed(callerContext, body.action);
    const permissions = Array.from(
      new Set((body.permissions ?? []).map((item) => item.trim()).filter(Boolean)),
    );

    switch (body.action) {
      case "create": {
        if (!body.name || !body.email || !body.password || !body.roleName) {
          throw new Error("Missing required fields for employee creation.");
        }

        const role = await findRoleByName(adminClient, body.roleName);

        if (!role) {
          throw new Error("Invalid role selected.");
        }

        const { data: created, error: createError } = await adminClient.auth.admin
          .createUser({
            email: body.email,
            password: body.password,
            email_confirm: true,
            user_metadata: { name: body.name },
          });

        if (createError || !created.user) {
          throw new Error(createError?.message ?? "Failed to create auth user.");
        }

        const employeeId = created.user.id;

        const { error: userInsertError } = await adminClient.from("users").insert({
          id: employeeId,
          company_id: callerContext.companyId,
          branch_id: callerContext.branchId,
          name: body.name,
          email: body.email,
          role_id: role.id,
          is_active: body.isActive ?? true,
        });

        if (userInsertError) {
          await adminClient.auth.admin.deleteUser(employeeId);
          throw new Error(userInsertError.message);
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
            throw new Error(permissionInsertError.message);
          }
        }

        await adminClient.rpc("write_activity_log", {
          p_actor_id: caller.id,
          p_action: "employee_created",
          p_entity_type: "user",
          p_entity_id: employeeId,
          p_metadata: {
            email: body.email,
            role_name: body.roleName,
          },
        });

        return jsonResponse({ success: true, employeeId });
      }

      case "update": {
        if (!body.employeeId || !body.name || !body.email || !body.roleName) {
          throw new Error("Missing required fields for employee update.");
        }

        await assertManagedUserInTenant(adminClient, callerContext, body.employeeId);

        const role = await findRoleByName(adminClient, body.roleName);

        if (!role) {
          throw new Error("Invalid role selected.");
        }

        const userUpdatePayload: Record<string, unknown> = {
          email: body.email,
          user_metadata: { name: body.name },
        };

        if (body.password && body.password.trim().length > 0) {
          userUpdatePayload.password = body.password;
        }

        const { error: authUpdateError } = await adminClient.auth.admin.updateUserById(
          body.employeeId,
          userUpdatePayload,
        );

        if (authUpdateError) {
          throw new Error(authUpdateError.message);
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
          throw new Error(profileUpdateError.message);
        }

        const { error: permissionDeleteError } = await adminClient
          .from("user_permissions")
          .delete()
          .eq("user_id", body.employeeId);

        if (permissionDeleteError) {
          throw new Error(permissionDeleteError.message);
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
            throw new Error(permissionInsertError.message);
          }
        }

        await adminClient.rpc("write_activity_log", {
          p_actor_id: caller.id,
          p_action: "employee_updated",
          p_entity_type: "user",
          p_entity_id: body.employeeId,
          p_metadata: {
            email: body.email,
            role_name: body.roleName,
          },
        });

        return jsonResponse({ success: true, employeeId: body.employeeId });
      }

      case "deactivate": {
        if (!body.employeeId || body.isActive === undefined) {
          throw new Error("Missing employee activation payload.");
        }

        await assertManagedUserInTenant(adminClient, callerContext, body.employeeId);

        const { error } = await adminClient
          .from("users")
          .update({ is_active: body.isActive })
          .eq("id", body.employeeId);

        if (error) {
          throw new Error(error.message);
        }

        await adminClient.rpc("write_activity_log", {
          p_actor_id: caller.id,
          p_action: body.isActive ? "employee_activated" : "employee_deactivated",
          p_entity_type: "user",
          p_entity_id: body.employeeId,
          p_metadata: {},
        });

        return jsonResponse({ success: true, employeeId: body.employeeId });
      }

      case "delete": {
        if (!body.employeeId) {
          throw new Error("Missing employee identifier.");
        }

        await assertManagedUserInTenant(adminClient, callerContext, body.employeeId);

        await adminClient.rpc("write_activity_log", {
          p_actor_id: caller.id,
          p_action: "employee_deleted",
          p_entity_type: "user",
          p_entity_id: body.employeeId,
          p_metadata: {},
        });

        const { error: dbDeleteError } = await adminClient
          .from("users")
          .delete()
          .eq("id", body.employeeId);

        if (dbDeleteError) {
          throw new Error(dbDeleteError.message);
        }

        const { error: authDeleteError } = await adminClient.auth.admin.deleteUser(
          body.employeeId,
        );

        if (authDeleteError) {
          throw new Error(authDeleteError.message);
        }

        return jsonResponse({ success: true, employeeId: body.employeeId });
      }

      default:
        throw new Error("Unsupported employee action.");
    }
  } catch (error) {
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : "Unknown error" },
      400,
    );
  }
});

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

async function getCallerContext(
  adminClient: ReturnType<typeof createClient>,
  callerId: string,
): Promise<CallerContext> {
  const { data: userRow, error: userError } = await adminClient
    .from("users")
    .select("id, company_id, branch_id, role_id, is_active")
    .eq("id", callerId)
    .single();

  if (userError || !userRow) {
    throw new Error("Caller profile was not found in public.users.");
  }

  const { data: roleRow, error: roleError } = await adminClient
    .from("roles")
    .select("*")
    .eq("id", userRow.role_id)
    .single();

  if (roleError || !roleRow) {
    throw new Error("Caller role is invalid.");
  }

  const [rolePermissionsResult, directPermissionsResult, permissionsResult] = await Promise.all([
    adminClient
      .from("role_permissions")
      .select("*")
      .eq("role_id", userRow.role_id),
    adminClient
      .from("user_permissions")
      .select("*")
      .eq("user_id", callerId),
    adminClient
      .from("permissions")
      .select("*"),
  ]);

  if (rolePermissionsResult.error) {
    throw new Error(rolePermissionsResult.error.message);
  }

  if (directPermissionsResult.error) {
    throw new Error(directPermissionsResult.error.message);
  }

  if (permissionsResult.error) {
    throw new Error(permissionsResult.error.message);
  }

  const permissionCodeById = new Map<string, string>();
  for (const item of permissionsResult.data ?? []) {
    const permissionId = resolvePermissionId(item);
    const permissionCode = resolvePermissionCode(item, permissionCodeById);
    if (permissionId && permissionCode) {
      permissionCodeById.set(permissionId, permissionCode);
    }
  }

  const permissions = new Set<string>([
    ...(rolePermissionsResult.data ?? [])
      .map((item) => resolvePermissionCode(item, permissionCodeById))
      .filter((item): item is string => typeof item === "string" && item.length > 0),
    ...(directPermissionsResult.data ?? [])
      .map((item) => resolvePermissionCode(item, permissionCodeById))
      .filter((item): item is string => typeof item === "string" && item.length > 0),
  ]);

  if (!userRow.company_id) {
    throw new Error("Caller company is missing.");
  }

  if (!userRow.is_active) {
    throw new Error("Only active users can manage employees.");
  }

  return {
    id: callerId,
    companyId: userRow.company_id,
    branchId: userRow.branch_id,
    roleId: userRow.role_id,
    roleName: resolveRoleName(roleRow),
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
  };

  const missing = requiredPermissions[action].filter(
    (permission) => !caller.permissions.has(permission),
  );

  if (missing.length > 0) {
    throw new Error(
      `Missing employee management permissions: ${missing.join(", ")}`,
    );
  }
}

async function assertManagedUserInTenant(
  adminClient: ReturnType<typeof createClient>,
  caller: CallerContext,
  employeeId: string,
) {
  const { data: targetUser, error } = await adminClient
    .from("users")
    .select("id, company_id")
    .eq("id", employeeId)
    .single();

  if (error || !targetUser) {
    throw new Error("Employee profile was not found.");
  }

  if (targetUser.company_id !== caller.companyId) {
    throw new Error("Cross-company employee management is not allowed.");
  }
}

async function findRoleByName(
  adminClient: ReturnType<typeof createClient>,
  roleName: string,
) {
  const { data, error } = await adminClient.from("roles").select("*");

  if (error) {
    throw new Error(error.message);
  }

  return data.find((item) => resolveRoleName(item) === roleName) ?? null;
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

function resolvePermissionId(row: Record<string, unknown>) {
  for (const key of ["id", "permission_id"]) {
    const value = row[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
  }

  return null;
}

function resolvePermissionCode(
  row: Record<string, unknown>,
  permissionCodeById: Map<string, string>,
) {
  for (const key of ["permission_code", "code", "name"]) {
    const value = row[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
  }

  const permissionId = resolvePermissionId(row);
  if (!permissionId) {
    return null;
  }

  return permissionCodeById.get(permissionId) ?? null;
}
