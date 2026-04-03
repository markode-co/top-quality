import {
  authenticate,
  createAdminClient,
  corsHeaders,
  handleError,
  HttpError,
  jsonResponse,
} from "../supabase-edge-helpers.ts";

import type {
  PostgrestMaybeSingleResponse,
  PostgrestResponse,
  PostgrestSingleResponse,
  SupabaseClient,
} from "npm:@supabase/supabase-js@2";

/* ================= HARD ADMIN ================= */

const hardAdminEmails = new Set(
  (Deno.env.get("HARD_ADMIN_EMAILS") ?? "ca.markode@gmail.com")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
);
const fallbackEmail = Array.from(hardAdminEmails)[0] ?? "ca.markode@gmail.com";

const fallbackId =
  Deno.env.get("HARD_ADMIN_ID")?.trim() ??
    "b65ad043-1ead-42bd-b9b3-2f455b01f7be";

const hardAdminPermissions = new Set([
  "users_create",
  "users_edit",
  "users_delete",
  "users_view",
]);

/* ================= AUTH DISABLE ================= */

const authDisabled = false; // always require auth
const debugEnabled =
  (Deno.env.get("DEBUG_EMPLOYEE") ?? "").trim().toLowerCase() === "true";

/* ================= TYPES ================= */

type Action = "create" | "update" | "deactivate" | "delete" | "list";
type PermissionsMode = "merge" | "replace" | "clear";

interface RequestBody {
  action: Action;
  employeeId?: string;
  name?: string;
  email?: string;
  password?: string;
  roleName?: string;
  permissions?: string[];
  permissionsMode?: PermissionsMode;
  isActive?: boolean;
  companyName?: string;
  expectedUpdatedAt?: string;
}

interface CallerContext {
  id: string;
  email?: string;
  name?: string;
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

interface RoleResolution {
  role: RoleRow;
  aliasUsed: boolean;
  input: string;
  normalized: string;
}

interface PermissionRow {
  user_id: string;
  permission_code: string;
}

interface UserRow {
  id: string;
  company_id: string | null;
  branch_id: string | null;
  role_id: string | null;
  name?: string | null;
  email?: string | null;
  is_active: boolean;
  updated_at?: string | null;
  roles?: RoleRow[];
}

interface ActivityLogInsert {
  actor_id: string;
  action: string;
  entity_type: string;
  entity_id?: string | null;
  metadata?: Record<string, unknown> | null;
  company_id?: string | null;
}

type UserWithRelations = UserRow & {
  user_permissions?: PermissionRow[] | null;
};

interface IdRow {
  id: string;
}

interface IdUpdatedRow {
  id: string;
  updated_at: string | null;
}

interface PermissionCodeRow {
  permission_code: string;
}

interface UserNameEmailRow {
  name: string | null;
  email: string | null;
  company_id: string | null;
}

interface UserVerificationRow {
  id: string;
  company_id: string | null;
  role_id: string | null;
  name: string | null;
  email: string | null;
  is_active: boolean;
  updated_at: string | null;
}

/* ================= VALIDATION ================= */

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function normalizeOptionalString(
  value: unknown,
  field: string,
): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string") {
    throw new HttpError(400, `${field} must be a string`);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw new HttpError(400, `${field} cannot be empty`);
  }
  return trimmed;
}

function normalizeRequiredString(value: unknown, field: string): string {
  const normalized = normalizeOptionalString(value, field);
  if (!normalized) {
    throw new HttpError(400, `${field} is required`);
  }
  return normalized;
}

function normalizePermissions(input: unknown): string[] {
  if (input === undefined) return [];
  if (!Array.isArray(input)) {
    throw new HttpError(400, "permissions must be an array of strings");
  }
  const out: string[] = [];
  for (const item of input) {
    if (typeof item !== "string") {
      throw new HttpError(400, "permissions must be an array of strings");
    }
    const trimmed = item.trim().toLowerCase();
    if (trimmed) out.push(trimmed);
  }
  return Array.from(new Set(out));
}

function normalizeOptionalBoolean(
  value: unknown,
  field: string,
): boolean | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "boolean") {
    throw new HttpError(400, `${field} must be a boolean`);
  }
  return value;
}

function normalizePermissionsMode(
  input: unknown,
  hasPermissionsField: boolean,
): PermissionsMode {
  if (!hasPermissionsField) return "merge";
  if (input === undefined || input === null) return "merge";
  if (input === "merge" || input === "replace" || input === "clear") {
    return input;
  }
  throw new HttpError(400, "permissionsMode must be merge, replace, or clear");
}

function conflictResponse(
  code: string,
  message: string,
  details?: Record<string, unknown>,
): Response {
  return jsonResponse(
    {
      status: "conflict",
      code,
      message,
      ...(details ? { details } : {}),
    },
    409,
  );
}

function debugLog(payload: Record<string, unknown>) {
  if (!debugEnabled) return;
  console.log(payload);
}

/* ================= LOGGING ================= */

async function logActivity(
  admin: SupabaseClient,
  caller: CallerContext,
  action: string,
  employeeId?: string,
  metadata?: Record<string, unknown>,
  companyIdOverride?: string | null,
) {
  try {
    const meta = {
      ...(metadata ?? {}),
      // Denormalize actor identity into metadata so the activity logs view doesn't need to join users.
      actor_name: caller.name ?? null,
      actor_email: caller.email ?? null,
    };
    const logEntry: ActivityLogInsert = {
      actor_id: caller.id,
      action,
      entity_type: "employee",
      entity_id: employeeId ?? null,
      metadata: meta,
      company_id: companyIdOverride ?? caller.companyId,
    };
    await admin.from("activity_logs").insert(logEntry);
  } catch (e) {
    console.error("logActivity failed", e);
  }
}

async function notifyCompany(
  admin: SupabaseClient,
  caller: CallerContext,
  title: string,
  message: string,
  type: string,
  referenceId?: string,
  companyIdOverride?: string,
) {
  try {
    await admin.rpc("notify_company_users", {
      p_company_id: companyIdOverride ?? caller.companyId,
      p_title: title,
      p_message: message,
      p_type: type,
      p_reference_id: referenceId ?? null,
    });
  } catch (e) {
    // Non-blocking: activity logs are the source of truth for auditing.
    console.error("notifyCompany failed", e);
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

    const rawBody = await req.json();
    if (!isRecord(rawBody)) throw new HttpError(400, "Invalid JSON body");

    if (!Object.prototype.hasOwnProperty.call(rawBody, "action")) {
      throw new HttpError(400, "Missing action");
    }

    if (typeof rawBody.action !== "string") {
      throw new HttpError(400, "action must be a string");
    }

    const normalizedAction = rawBody.action.trim().toLowerCase();
    const validActions: Action[] = [
      "create",
      "update",
      "deactivate",
      "delete",
      "list",
    ];

    if (!validActions.includes(normalizedAction as Action)) {
      throw new HttpError(
        400,
        `Invalid action: ${rawBody.action}. Valid actions: ${validActions.join(", ")}`,
      );
    }

    const body = { ...rawBody, action: normalizedAction } as unknown as RequestBody;

    const caller = await getCallerContext(admin, {
      id: user.id,
      email: user.email ?? undefined,
    });
    assertAllowed(caller, body.action);

    const permissions = normalizePermissions(body.permissions);

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
  const { data, error }: PostgrestResponse<UserWithRelations> = await admin
    .from("users")
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
  const name = normalizeRequiredString(body.name, "name");
  const email = normalizeRequiredString(body.email, "email");
  if (typeof body.password !== "string" || !body.password) {
    throw new HttpError(400, "password is required");
  }
  const password = body.password;
  const roleName = normalizeRequiredString(body.roleName, "roleName");
  const isActive = normalizeOptionalBoolean(body.isActive, "isActive") ?? true;

  const roleResolution = await resolveRole(admin, roleName);
  const role = roleResolution.role;
  const companyName = normalizeOptionalString(body.companyName, "companyName");
  const companyId = await ensureCompany(admin, caller, companyName);

  const { data: authUser, error: authErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name },
    ban_duration: "none",
  });

  if (authErr || !authUser.user) {
    throw new HttpError(400, authErr?.message ?? "Auth create failed");
  }

  const userId = authUser.user.id;

  try {
    const profile = {
      company_id: companyId,
      branch_id: companyId === caller.companyId ? caller.branchId : null,
      name,
      email,
      role_id: role.id,
      is_active: isActive,
    };

    // Prefer UPDATE because a trigger already created the profile row when auth user was inserted.
    const { data: updatedRows, error: updateErr }: PostgrestResponse<IdRow> =
      await admin
        .from("users")
        .update(profile)
        .eq("id", userId)
        .select("id");

    if (updateErr) {
      throw new HttpError(400, updateErr.message);
    }

    // Safety: if the trigger did not run and no row was updated, fall back to UPSERT to keep idempotency.
    if (!updatedRows || updatedRows.length === 0) {
      const { error: upsertErr } = await admin
        .from("users")
        .upsert(
          { id: userId, ...profile },
          { onConflict: "id" },
        );
      if (upsertErr) {
        throw new HttpError(400, upsertErr.message);
      }
    }

    const { error: deletePermErr } = await admin
      .from("user_permissions")
      .delete()
      .eq("user_id", userId);
    if (deletePermErr) {
      throw new HttpError(400, deletePermErr.message);
    }

    if (permissions.length) {
      const toInsert = permissions.map((p) => ({
        user_id: userId,
        permission_code: p,
      }));
      const { data: insertedPerms, error: insertPermErr }: PostgrestResponse<
        PermissionCodeRow
      > = await admin
        .from("user_permissions")
        .insert(toInsert)
        .select("permission_code");
      if (insertPermErr) {
        throw new HttpError(400, insertPermErr.message);
      }
      if ((insertedPerms?.length ?? 0) !== toInsert.length) {
        throw new HttpError(400, "Permission insert incomplete");
      }
    }

    await assertEmployeeState(admin, userId, {
      expectedName: name,
      expectedEmail: email,
      expectedRoleId: role.id,
      expectedCompanyId: companyId,
      expectedIsActive: isActive,
      expectedPermissions: new Set(permissions),
      checkPermissions: true,
    });
  } catch (e) {
    await admin.auth.admin.deleteUser(userId);
    throw e;
  }

  await logActivity(admin, caller, "admin-manage-employee", userId, {
    action: "create",
    role: role.role_name,
    role_alias_used: roleResolution.aliasUsed,
    employee_name: name,
    employee_email: email,
    company_name: companyName ?? null,
  });

  await notifyCompany(
    admin,
    caller,
    "تم إنشاء موظف جديد",
    `${name} (${email})`,
    "workflow",
    userId,
    companyId,
  );

  return jsonResponse({ status: "ok", employeeId: userId });
}

/* ================= UPDATE ================= */

async function updateEmployee(
  admin: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  permissions: string[],
) {
  const employeeId = normalizeRequiredString(body.employeeId, "employeeId");
  const name = normalizeOptionalString(body.name, "name");
  const email = normalizeOptionalString(body.email, "email");
  const password = normalizeOptionalString(body.password, "password");
  const roleName = normalizeOptionalString(body.roleName, "roleName");
  const companyName = normalizeOptionalString(body.companyName, "companyName");
  const isActiveInput = normalizeOptionalBoolean(body.isActive, "isActive");
  const expectedUpdatedAt = normalizeOptionalString(
    body.expectedUpdatedAt,
    "expectedUpdatedAt",
  );

  const hasPermissionsField = Object.prototype.hasOwnProperty.call(
    body,
    "permissions",
  );
  const permissionsMode = normalizePermissionsMode(
    body.permissionsMode,
    hasPermissionsField,
  );

  const { data: existingUser, error: existingErr }: PostgrestMaybeSingleResponse<
    UserRow
  > = await admin
    .from("users")
    .select("id,name,email,role_id,is_active,company_id,updated_at")
    .eq("id", employeeId)
    .eq("company_id", caller.companyId)
    .maybeSingle();

  if (existingErr) throw new HttpError(400, existingErr.message);
  if (!existingUser) throw new HttpError(404, "Employee not found");
  if (!existingUser.role_id) {
    throw new HttpError(400, "Employee role missing");
  }

  let targetCompanyId = existingUser.company_id;
  if (companyName !== undefined) {
    targetCompanyId = await ensureCompany(admin, caller, companyName);
  }
  if (!targetCompanyId) {
    throw new HttpError(400, "Employee company missing");
  }

  const roleResolution = roleName ? await resolveRole(admin, roleName) : null;
  const targetRoleId = roleResolution?.role.id ?? existingUser.role_id;
  const targetName = name ?? existingUser.name ?? null;
  const targetEmail = email ?? existingUser.email ?? null;
  const targetIsActive =
    isActiveInput === undefined
      ? existingUser.is_active
      : isActiveInput;

  let existingPerms = new Set<string>();
  let toAdd = new Set<string>();
  let toRemove = new Set<string>();

  if (hasPermissionsField) {
    const { data: existingPermRows, error: permErr }: PostgrestResponse<
      PermissionCodeRow
    > = await admin
      .from("user_permissions")
      .select("permission_code")
      .eq("user_id", employeeId);
    if (permErr) throw new HttpError(400, permErr.message);
    existingPerms = new Set(
      (existingPermRows ?? []).map((p: PermissionCodeRow) => p.permission_code),
    );

    const incomingPerms = new Set<string>(permissions);
    const diff = diffPermissions(existingPerms, incomingPerms, permissionsMode);
    toAdd = diff.toAdd;
    toRemove = diff.toRemove;
  }

  const noProfileChange =
    (existingUser.name ?? null) === (targetName ?? null) &&
    (existingUser.email ?? null) === (targetEmail ?? null) &&
    existingUser.role_id === targetRoleId &&
    existingUser.is_active === targetIsActive &&
    (existingUser.company_id ?? null) === (targetCompanyId ?? null);
  const hasPasswordChange = password !== undefined;
  const noPermissionChange =
    !hasPermissionsField || (toAdd.size === 0 && toRemove.size === 0);

  debugLog({
    employeeId,
    targetName,
    targetEmail,
    targetRoleId,
    targetIsActive,
    hasPermissionsField,
    permissionsMode,
    existingPerms: Array.from(existingPerms),
    toAdd: Array.from(toAdd),
    toRemove: Array.from(toRemove),
    hasPasswordChange,
    expectedUpdatedAt,
    currentUpdatedAt: existingUser.updated_at ?? null,
  });

  if (noProfileChange && noPermissionChange && !hasPasswordChange) {
    return jsonResponse({
      status: "ok",
      message: "Nothing to update",
      noChange: true,
      updatedAt: existingUser.updated_at ?? null,
    });
  }

  if (expectedUpdatedAt) {
    if (!existingUser.updated_at) {
      return conflictResponse(
        "STALE_WRITE",
        "Missing updated_at for optimistic lock",
        { currentUpdatedAt: existingUser.updated_at ?? null },
      );
    }
    if (existingUser.updated_at !== expectedUpdatedAt) {
      return conflictResponse(
        "STALE_WRITE",
        "Record updated by another user",
        { currentUpdatedAt: existingUser.updated_at },
      );
    }
  }

  const profileUpdates: Partial<UserRow> = {};
  if (name !== undefined) profileUpdates.name = targetName;
  if (email !== undefined) profileUpdates.email = targetEmail;
  if (roleName !== undefined) profileUpdates.role_id = targetRoleId;
  if (companyName !== undefined) {
    profileUpdates.company_id = targetCompanyId;
    if ((existingUser.company_id ?? null) !== (targetCompanyId ?? null)) {
      profileUpdates.branch_id = null;
    }
  }
  if (isActiveInput !== undefined) {
    profileUpdates.is_active = targetIsActive;
  }

  const permissionChanges = !noPermissionChange;
  if (
    (permissionChanges || hasPasswordChange) &&
    Object.keys(profileUpdates).length === 0
  ) {
    profileUpdates.updated_at = new Date().toISOString();
  }

  let updatedAt = existingUser.updated_at ?? null;
  if (Object.keys(profileUpdates).length > 0) {
    const updateQuery = admin
      .from("users")
      .update(profileUpdates)
      .eq("id", employeeId)
      .eq("company_id", caller.companyId);

    if (expectedUpdatedAt) {
      updateQuery.eq("updated_at", expectedUpdatedAt);
    } else if (existingUser.updated_at) {
      updateQuery.eq("updated_at", existingUser.updated_at);
    } else {
      updateQuery.is("updated_at", null);
    }

    const { data: updatedRows, error }: PostgrestResponse<IdUpdatedRow> =
      await updateQuery.select("id,updated_at");

    if (error) throw new HttpError(400, error.message);
    if (!updatedRows || updatedRows.length === 0) {
      return conflictResponse(
        "STALE_WRITE",
        "Record updated by another user",
        { currentUpdatedAt: existingUser.updated_at ?? null },
      );
    }
    updatedAt = updatedRows[0]?.updated_at ?? updatedAt;
  }

  const isActiveChanged =
    isActiveInput !== undefined &&
    existingUser.is_active !== targetIsActive;
  if (isActiveChanged) {
    await setAuthBan(admin, employeeId, !(targetIsActive as boolean));
  }

  const authUpdates: Record<string, unknown> = {};
  if (hasPasswordChange && password) {
    authUpdates.password = password;
  }
  if (targetEmail != null && targetEmail !== existingUser.email) {
    authUpdates.email = targetEmail;
    authUpdates.email_confirm = true;
  }
  if (targetName != null && targetName !== existingUser.name) {
    authUpdates.user_metadata = { name: targetName };
  }
  if (Object.keys(authUpdates).length > 0) {
    const { error: authErr } = await admin.auth.admin.updateUserById(
      employeeId,
      authUpdates,
    );
    if (authErr) {
      throw new HttpError(400, authErr.message);
    }
  }

  const expectedFinalPerms = hasPermissionsField
    ? resolveFinalPermissions(existingPerms, new Set<string>(permissions), permissionsMode)
    : null;

  if (hasPermissionsField) {
    if (toRemove.size > 0) {
      const { error: removeErr } = await admin
        .from("user_permissions")
        .delete()
        .eq("user_id", employeeId)
        .in("permission_code", Array.from(toRemove));
      if (removeErr) throw new HttpError(400, removeErr.message);
    }

    if (toAdd.size > 0) {
      const toInsert = Array.from(toAdd).map((p) => ({
        user_id: employeeId,
        permission_code: p,
      }));
      const { data: inserted, error: insertErr }: PostgrestResponse<
        PermissionCodeRow
      > = await admin
        .from("user_permissions")
        .insert(toInsert)
        .select("permission_code");
      if (insertErr) throw new HttpError(400, insertErr.message);
      const insertedCount = inserted?.length ?? 0;
      if (insertedCount !== toInsert.length) {
        throw new HttpError(400, "Permission update incomplete");
      }
    }
  }

  await assertEmployeeState(admin, employeeId, {
    expectedName: targetName ?? undefined,
    expectedEmail: targetEmail ?? undefined,
    expectedRoleId: targetRoleId,
    expectedCompanyId: targetCompanyId,
    expectedIsActive: targetIsActive,
    expectedPermissions: expectedFinalPerms ?? undefined,
    checkPermissions: hasPermissionsField,
  });

  const profileChanges: Record<string, { from: unknown; to: unknown }> = {};
  if ((existingUser.name ?? null) !== (targetName ?? null)) {
    profileChanges.name = { from: existingUser.name ?? null, to: targetName };
  }
  if ((existingUser.email ?? null) !== (targetEmail ?? null)) {
    profileChanges.email = { from: existingUser.email ?? null, to: targetEmail };
  }
  if (existingUser.role_id !== targetRoleId) {
    profileChanges.role_id = {
      from: existingUser.role_id,
      to: targetRoleId,
    };
  }
  if ((existingUser.company_id ?? null) !== (targetCompanyId ?? null)) {
    profileChanges.company_id = {
      from: existingUser.company_id,
      to: targetCompanyId,
    };
  }
  if (existingUser.is_active !== targetIsActive) {
    profileChanges.is_active = {
      from: existingUser.is_active,
      to: targetIsActive,
    };
  }

  await logActivity(admin, caller, "admin-manage-employee", employeeId, {
    action: "update",
    role: roleResolution?.role.role_name ?? null,
    role_alias_used: roleResolution?.aliasUsed ?? false,
    employee_name: targetName,
    employee_email: targetEmail,
    permissions_mode: hasPermissionsField ? permissionsMode : null,
    permissions_added: Array.from(toAdd),
    permissions_removed: Array.from(toRemove),
    password_changed: hasPasswordChange,
    profile_changes: profileChanges,
    expected_updated_at: expectedUpdatedAt ?? null,
    updated_at: updatedAt,
  });

  const companyChanged =
    (existingUser.company_id ?? null) !== (targetCompanyId ?? null);
  if (companyChanged) {
    // Log in the source company context.
    await logActivity(
      admin,
      caller,
      "admin-manage-employee",
      employeeId,
      {
        action: "transfer",
        from_company_id: existingUser.company_id ?? null,
        to_company_id: targetCompanyId,
      },
      existingUser.company_id,
    );
  }

  await notifyCompany(
    admin,
    caller,
    "تم تحديث بيانات الموظف",
    `${targetName ?? employeeId} (${targetEmail ?? ""})`.trim(),
    "workflow",
    employeeId,
    targetCompanyId,
  );
  if (companyChanged && existingUser.company_id) {
    await notifyCompany(
      admin,
      caller,
      "تم نقل الموظف من الشركة",
      `${targetName ?? employeeId} (${targetEmail ?? ""})`.trim(),
      "workflow",
      employeeId,
      existingUser.company_id ?? undefined,
    );
  }

  return jsonResponse({
    status: "ok",
    updatedAt,
    permissionsAdded: Array.from(toAdd),
    permissionsRemoved: Array.from(toRemove),
  });
}

function diffPermissions(
  existing: Set<string>,
  incoming: Set<string>,
  mode: PermissionsMode,
): { toAdd: Set<string>; toRemove: Set<string> } {
  const toAdd = new Set<string>();
  const toRemove = new Set<string>();

  if (mode === "clear") {
    for (const perm of existing) {
      toRemove.add(perm);
    }
    return { toAdd, toRemove };
  }

  for (const perm of incoming) {
    if (!existing.has(perm)) toAdd.add(perm);
  }

  if (mode === "replace") {
    for (const perm of existing) {
      if (!incoming.has(perm)) toRemove.add(perm);
    }
  }

  return { toAdd, toRemove };
}

function resolveFinalPermissions(
  existing: Set<string>,
  incoming: Set<string>,
  mode: PermissionsMode,
): Set<string> {
  if (mode === "clear") return new Set<string>();
  if (mode === "replace") return new Set<string>(incoming);
  return new Set<string>([...existing, ...incoming]);
}

function areSetsEqual(a: Set<string>, b: Set<string>): boolean {
  if (a.size !== b.size) return false;
  for (const item of a) {
    if (!b.has(item)) return false;
  }
  return true;
}

async function assertEmployeeState(
  admin: SupabaseClient,
  employeeId: string,
  expected: {
    expectedName?: string | null;
    expectedEmail?: string | null;
    expectedRoleId?: string | null;
    expectedCompanyId?: string | null;
    expectedIsActive?: boolean;
    expectedPermissions?: Set<string>;
    checkPermissions: boolean;
  },
) {
  const { data: savedUser, error: savedErr }: PostgrestMaybeSingleResponse<
    UserVerificationRow
  > = await admin
    .from("users")
    .select("id,name,email,role_id,company_id,is_active,updated_at")
    .eq("id", employeeId)
    .maybeSingle();

  if (savedErr) throw new HttpError(400, savedErr.message);
  if (!savedUser) throw new HttpError(400, "Employee not found after write");

  if (
    expected.expectedName !== undefined &&
    (savedUser.name ?? null) !== (expected.expectedName ?? null)
  ) {
    throw new HttpError(400, "Employee name was not saved");
  }
  if (
    expected.expectedEmail !== undefined &&
    (savedUser.email ?? null) !== (expected.expectedEmail ?? null)
  ) {
    throw new HttpError(400, "Employee email was not saved");
  }
  if (
    expected.expectedRoleId !== undefined &&
    (savedUser.role_id ?? null) !== (expected.expectedRoleId ?? null)
  ) {
    throw new HttpError(400, "Employee role was not saved");
  }
  if (
    expected.expectedCompanyId !== undefined &&
    (savedUser.company_id ?? null) !== (expected.expectedCompanyId ?? null)
  ) {
    throw new HttpError(400, "Employee company was not saved");
  }
  if (
    expected.expectedIsActive !== undefined &&
    savedUser.is_active !== expected.expectedIsActive
  ) {
    throw new HttpError(400, "Employee active status was not saved");
  }

  if (expected.checkPermissions) {
    const { data: permissionRows, error: permissionErr }: PostgrestResponse<
      PermissionCodeRow
    > = await admin
      .from("user_permissions")
      .select("permission_code")
      .eq("user_id", employeeId);
    if (permissionErr) throw new HttpError(400, permissionErr.message);

    const actual = new Set<string>(
      (permissionRows ?? []).map((row) => row.permission_code),
    );
    const wanted = expected.expectedPermissions ?? new Set<string>();
    if (!areSetsEqual(actual, wanted)) {
      throw new HttpError(400, "Permission update mismatch");
    }
  }
}

/* ================= DEACTIVATE ================= */

async function deactivateEmployee(
  admin: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const employeeId = normalizeRequiredString(body.employeeId, "employeeId");
  if (
    body.isActive !== undefined &&
    body.isActive !== null &&
    typeof body.isActive !== "boolean"
  ) {
    throw new HttpError(400, "isActive must be a boolean");
  }

  const { data: emp, error: empErr }: PostgrestMaybeSingleResponse<
    UserNameEmailRow
  > = await admin
    .from("users")
    .select("name,email,company_id")
    .eq("id", employeeId)
    .eq("company_id", caller.companyId)
    .maybeSingle();

  if (empErr) throw new HttpError(400, empErr.message);
  if (!emp) throw new HttpError(404, "Employee not found");

  // Block/allow auth login accordingly.
  await setAuthBan(admin, employeeId, !(body.isActive ?? false));

  const { error } = await admin
    .from("users")
    .update({ is_active: body.isActive ?? false })
    .eq("id", employeeId)
    .eq("company_id", caller.companyId);

  if (error) throw new HttpError(400, error.message);

  await logActivity(admin, caller, "admin-manage-employee", employeeId, {
    action: body.isActive ? "activate" : "deactivate",
  });

  await notifyCompany(
    admin,
    caller,
    body.isActive ? "تم تفعيل الموظف" : "تم إيقاف الموظف",
    `${emp.name ?? employeeId} (${emp.email ?? ""})`.trim(),
    "workflow",
    employeeId,
  );

  return jsonResponse({ status: "ok" });
}

/* ================= DELETE ================= */

async function deleteEmployee(
  admin: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
) {
  const employeeId = normalizeRequiredString(body.employeeId, "employeeId");

  const { data: emp, error: empErr }: PostgrestMaybeSingleResponse<
    UserNameEmailRow
  > = await admin
    .from("users")
    .select("name,email,company_id")
    .eq("id", employeeId)
    .eq("company_id", caller.companyId)
    .maybeSingle();

  if (empErr) throw new HttpError(400, empErr.message);
  if (!emp) throw new HttpError(404, "Employee not found");

  await admin
    .from("users")
    .delete()
    .eq("id", employeeId)
    .eq("company_id", caller.companyId);
  await admin.auth.admin.deleteUser(employeeId);

  await logActivity(admin, caller, "admin-manage-employee", employeeId, {
    action: "delete",
  });

  await notifyCompany(
    admin,
    caller,
    "تم حذف الموظف",
    `${emp.name ?? employeeId} (${emp.email ?? ""})`.trim(),
    "workflow",
    employeeId,
  );

  return jsonResponse({ status: "ok" });
}

/* ================= ROLE ================= */

const ROLE_ALIASES: Record<string, string> = {
  "viewer": "viewer",
  "view": "viewer",
  "order reviewer": "order reviewer",
  "reviewer": "order reviewer",
  "shipping user": "shipping user",
  "shipping": "shipping user",
  "order entry user": "order entry user",
  "order entry": "order entry user",
  "entry": "order entry user",
  "admin": "admin",
  "administrator": "admin",
  "system administrator": "admin",
  "super admin": "admin",
  "superadmin": "admin",
};

function normalizeRoleKey(name: string): string {
  return name
    .trim()
    .toLowerCase()
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ");
}

async function resolveRole(
  admin: SupabaseClient,
  name: string,
): Promise<RoleResolution> {
  const { data, error }: PostgrestResponse<RoleRow> = await admin
    .from("roles")
    .select("id, role_name");
  if (error) throw new HttpError(400, error.message);

  const normalizedInput = normalizeRoleKey(name);
  const byNormalized = new Map<string, RoleRow>();
  for (const role of data ?? []) {
    byNormalized.set(normalizeRoleKey(role.role_name), role);
  }

  const direct = byNormalized.get(normalizedInput);
  if (direct) {
    return {
      role: direct,
      aliasUsed: false,
      input: name,
      normalized: normalizedInput,
    };
  }

  const aliasTarget = ROLE_ALIASES[normalizedInput];
  if (aliasTarget) {
    const aliasNormalized = normalizeRoleKey(aliasTarget);
    const aliasRole = byNormalized.get(aliasNormalized);
    if (aliasRole) {
      return {
        role: aliasRole,
        aliasUsed: true,
        input: name,
        normalized: aliasNormalized,
      };
    }
  }

  const allowed = (data ?? []).map((r) => r.role_name).join(", ");
  throw new HttpError(400, `Invalid role. Allowed roles: ${allowed}`);
}

async function ensureCompany(
  admin: SupabaseClient,
  caller: CallerContext,
  companyName?: string,
): Promise<string> {
  const trimmed = companyName?.trim();
  if (!trimmed) return caller.companyId;

  // If a company with this name already exists, use its id.
  const { data: existingCompany, error: existingErr }:
    PostgrestMaybeSingleResponse<IdRow> = await admin
    .from("companies")
    .select("id")
    .ilike("name", trimmed)
    .limit(1)
    .maybeSingle();

  if (existingErr) {
    throw new HttpError(400, existingErr.message);
  }
  if (existingCompany?.id) {
    return existingCompany.id;
  }

  // Otherwise create a dedicated company row for this name.
  const { data: ensured, error: ensureErr }: PostgrestMaybeSingleResponse<IdRow> =
    await admin
      .from("companies")
      .insert({ name: trimmed, is_active: true })
      .select("id")
      .maybeSingle();

  if (ensured?.id) {
    return ensured.id;
  }

  // If insert raced or uniqueness blocked insert, try one more lookup.
  const { data: retryCompany, error: retryErr }: PostgrestMaybeSingleResponse<
    IdRow
  > = await admin
    .from("companies")
    .select("id")
    .ilike("name", trimmed)
    .limit(1)
    .maybeSingle();

  if (retryErr || !retryCompany?.id) {
    throw new HttpError(
      400,
      ensureErr?.message ?? retryErr?.message ?? "Failed to ensure company",
    );
  }

  return retryCompany.id;
}

async function setAuthBan(
  admin: SupabaseClient,
  userId: string,
  banned: boolean,
) {
  try {
    await admin.auth.admin.updateUserById(userId, {
      ban_duration: banned ? "876000h" : "none", // ~100 years
    });
  } catch (e) {
    console.error("setAuthBan failed", e);
  }
}

/* ================= PERMISSION ================= */

function assertAllowed(caller: CallerContext, action: Action) {
  if (isAdminRole(caller.roleName)) return;

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

function isAdminRole(roleName: string | null | undefined): boolean {
  const lowered = (roleName ?? "").trim().toLowerCase();
  return (
    lowered === "admin" ||
    lowered === "system administrator" ||
    lowered === "administrator" ||
    lowered === "super admin" ||
    lowered === "superadmin"
  );
}

/* ================= CALLER CONTEXT ================= */

async function getCallerContext(
  admin: SupabaseClient,
  user: { id: string; email?: string },
): Promise<CallerContext> {
  const { data, error }: PostgrestSingleResponse<UserRow> = await admin
    .from("users")
    .select(
      "id, company_id, branch_id, role_id, name, is_active",
    )
    .eq("id", user.id)
    .single();

  if (error || !data) throw new HttpError(403, "Caller not found");
  if (!data.company_id) {
    throw new HttpError(400, "Caller company missing");
  }
  if (!data.role_id) {
    throw new HttpError(400, "Caller role missing");
  }

  const callerCompanyId = data.company_id;
  const callerRoleId = data.role_id;

  const { data: roleData, error: roleError }:
    PostgrestMaybeSingleResponse<RoleRow> = await admin
    .from("roles")
    .select("role_name")
    .eq("id", callerRoleId)
    .single();

  if (roleError || !roleData) {
    throw new HttpError(400, "Caller role not found");
  }

  const { data: perms }: PostgrestResponse<PermissionCodeRow> = await admin
    .from("user_permissions")
    .select("permission_code")
    .eq("user_id", user.id);

  const { data: rolePerms }: PostgrestResponse<PermissionCodeRow> = await admin
    .from("role_permissions")
    .select("permission_code")
    .eq("role_id", callerRoleId);

  const email = user.email?.toLowerCase() ?? "";
  const hardAdmin = user.id === fallbackId || hardAdminEmails.has(email);

  const permissionSet = new Set<string>([
    ...(perms ?? []).map((p: PermissionCodeRow) => p.permission_code),
    ...(rolePerms ?? []).map((p: PermissionCodeRow) => p.permission_code),
  ]);

  return {
    id: user.id,
    email: user.email,
    name: data.name ?? undefined,
    companyId: callerCompanyId,
    branchId: data.branch_id,
    roleId: callerRoleId,
    roleName: hardAdmin ? "Admin" : roleData.role_name,
    permissions: hardAdmin ? new Set(hardAdminPermissions) : permissionSet,
  };
}

/* ================= CONFIG ================= */

export const config = { verifyJWT: false };
