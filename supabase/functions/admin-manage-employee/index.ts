import {
  createAdminClient,
  authenticate,
  corsHeaders,
  handleError,
  HttpError,
  jsonResponse
} from "../supabase-edge-helpers.ts";

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
// Optional hard admin override so an emergency account can always manage employees.
// Configure via env: HARD_ADMIN_EMAILS="admin@example.com,other@example.com" and HARD_ADMIN_ID.
// Defaults keep the existing fallback used elsewhere in the app.
const fallbackEmail =
  Deno.env.get("HARD_ADMIN_EMAILS")?.split(",")
    .map((s) => s.trim().toLowerCase())
    .find(Boolean) ??
  "markode@gmail.com";

const fallbackId =
  Deno.env.get("HARD_ADMIN_ID")?.trim() ??
  "b65ad043-1ead-42bd-b9b3-2f455b01f7be";

const hardAdminPermissions = new Set([
  "users_create",
  "users_edit",
  "users_delete",
  "users_view",
]);

const authDisabledEnv = Deno.env.get("DISABLE_ADMIN_EMPLOYEE_AUTH")
// Treat presence (unless explicitly "false") as a temporary auth bypass.
const authDisabled =
  authDisabledEnv !== undefined && authDisabledEnv.toLowerCase() !== "false";


/* ---------------- TYPES ---------------- */

type Action = "create" | "update" | "deactivate" | "delete" | "list";

interface RequestBody {
  action: Action
  employeeId?: string
  name?: string
  email?: string
  password?: string
  roleName?: string
  permissions?: string[]
  isActive?: boolean
}

interface CallerContext {
  id: string
  email: string
  companyId: string
  branchId: string | null
  roleId: string
  roleName: string
  isActive: boolean
  permissions: Set<string>
}

interface RoleRow {
  role_name: string
}

interface PermissionRow {
  permission_code: string
}

interface UserRow {
  id: string
  name: string
  email: string
  is_active: boolean
  branch_id: string | null
  role?: RoleRow[]
  user_permissions?: PermissionRow[]
}

/* ---------------- ENTRY ---------------- */

console.info("admin-manage-employee started")

Deno.serve(async (req: Request) => {

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {

    const adminClient = createAdminClient()

    // Allow temporarily disabling auth via env for maintenance/seeding.
    if (authDisabled) {
      console.warn("DISABLE_ADMIN_EMPLOYEE_AUTH set; skipping authentication")
    }

    const { user } = authDisabled
      ? { user: { id: fallbackId, email: fallbackEmail } as { id: string; email?: string } }
      : await authenticate(req, adminClient)

    const body = await req.json() as RequestBody

    if (!body.action) {
      throw new HttpError(400, "Missing action")
    }

    const caller = await getCallerContext(adminClient, user)

    assertActionAllowed(caller, body.action)

    const permissions = Array.from(
      new Set(
        (body.permissions ?? [])
          .map((p: string) => p.trim())
          .filter(Boolean)
      )
    )

    switch (body.action) {

      case "create":
        return await handleCreate(adminClient, caller, body, permissions)

      case "update":
        return await handleUpdate(adminClient, body, permissions)

      case "deactivate":
        return await handleDeactivate(adminClient, body)

      case "delete":
        return await handleDelete(adminClient, body)

      case "list":
        return await handleList(adminClient, caller)

      default:
        throw new HttpError(400, "Invalid action")
    }

  } catch (error) {
    console.error("admin-manage-employee error", error)
    return handleError(error)
  }

})

/* ---------------- CREATE ---------------- */

async function handleCreate(
  adminClient: SupabaseClient,
  caller: CallerContext,
  body: RequestBody,
  permissions: string[]
) {

  if (!body.name || !body.email || !body.password || !body.roleName) {
    throw new HttpError(400, "Missing fields")
  }

  const role = await findRoleByName(adminClient, body.roleName)

  if (!role) {
    throw new HttpError(400, "Invalid role")
  }

  const { data: created, error: createError } =
    await adminClient.auth.admin.createUser({
      email: body.email,
      password: body.password,
      email_confirm: true,
      user_metadata: { name: body.name }
    })

  if (createError || !created.user) {
    throw new HttpError(400, createError?.message ?? "Auth create failed")
  }

  const employeeId = created.user.id

  const { error: insertError } =
    await adminClient.from("users").insert({
      id: employeeId,
      company_id: caller.companyId,
      branch_id: caller.branchId,
      name: body.name,
      email: body.email,
      role_id: role.id,
      is_active: body.isActive ?? true
    })

  if (insertError) {
    throw new HttpError(400, insertError.message)
  }

  if (permissions.length > 0) {

    const rows = permissions.map((p: string) => ({
      user_id: employeeId,
      permission_code: p
    }))

    const { error } =
      await adminClient.from("user_permissions").insert(rows)

    if (error) throw new HttpError(400, error.message)
  }

  return jsonResponse({
    status: "ok",
    employeeId
  })
}

/* ---------------- LIST ---------------- */

async function handleList(
  adminClient: SupabaseClient,
  caller: CallerContext
) {

  const { data, error } = await adminClient
    .from("users")
    .select(`
      id,
      name,
      email,
      is_active,
      branch_id,
      role:roles(role_name),
      user_permissions(permission_code)
    `)
    .eq("company_id", caller.companyId)
    .order("name")

  if (error) throw new HttpError(400, error.message)

  const employees = (data ?? []).map((row: UserRow) => ({

    id: row.id,
    name: row.name,
    email: row.email,
    isActive: row.is_active,
    branchId: row.branch_id,

    roleName:
      Array.isArray(row.role)
        ? row.role[0]?.role_name ?? ""
        : "",

    permissions:
      (row.user_permissions ?? [])
        .map((p: PermissionRow) => p.permission_code)

  }))

  return jsonResponse({
    status: "ok",
    employees
  })
}

/* ---------------- UPDATE ---------------- */

async function handleUpdate(
  adminClient: SupabaseClient,
  body: RequestBody,
  permissions: string[]
) {

  if (!body.employeeId) {
    throw new HttpError(400, "employeeId required")
  }

  const role = body.roleName
    ? await findRoleByName(adminClient, body.roleName)
    : null

  const { error } = await adminClient
    .from("users")
    .update({
      name: body.name,
      email: body.email,
      role_id: role?.id,
      is_active: body.isActive ?? true
    })
    .eq("id", body.employeeId)

  if (error) throw new HttpError(400, error.message)

  await adminClient
    .from("user_permissions")
    .delete()
    .eq("user_id", body.employeeId)

  if (permissions.length > 0) {

    const rows = permissions.map((p: string) => ({
      user_id: body.employeeId,
      permission_code: p
    }))

    await adminClient
      .from("user_permissions")
      .insert(rows)
  }

  return jsonResponse({ status: "ok" })
}

/* ---------------- ACTIVATE ---------------- */

async function handleDeactivate(
  adminClient: SupabaseClient,
  body: RequestBody
) {

  if (!body.employeeId) {
    throw new HttpError(400, "employeeId missing")
  }

  const { error } = await adminClient
    .from("users")
    .update({ is_active: body.isActive ?? false })
    .eq("id", body.employeeId)

  if (error) throw new HttpError(400, error.message)

  return jsonResponse({ status: "ok" })
}

/* ---------------- DELETE ---------------- */

async function handleDelete(
  adminClient: SupabaseClient,
  body: RequestBody
) {

  if (!body.employeeId) {
    throw new HttpError(400, "employeeId missing")
  }

  await adminClient.from("users").delete().eq("id", body.employeeId)

  await adminClient.auth.admin.deleteUser(body.employeeId)

  return jsonResponse({ status: "ok" })
}

/* ---------------- ROLE ---------------- */

async function findRoleByName(
  adminClient: SupabaseClient,
  roleName: string
) {

  const { data, error } =
    await adminClient.from("roles").select("*")

  if (error) throw new HttpError(400, error.message)

  const normalized = roleName.toLowerCase()

  return data.find(
    (r: { role_name: string }) =>
      r.role_name?.toLowerCase() === normalized
  ) ?? null
}

/* ---------------- PERMISSIONS ---------------- */

function assertActionAllowed(
  caller: CallerContext,
  action: Action
) {

  if (caller.roleName === "Admin") return

  const permissions: Record<Action, string> = {
    create: "users_create",
    update: "users_edit",
    deactivate: "users_edit",
    delete: "users_delete",
    list: "users_view"
  }

  const needed = permissions[action]

  if (!caller.permissions.has(needed)) {
    throw new HttpError(403, "Missing permission: " + needed)
  }
}

/* ---------------- CALLER ---------------- */

async function getCallerContext(
  adminClient: SupabaseClient,
  caller: { id: string; email?: string }
): Promise<CallerContext> {

  const { data, error } = await adminClient
    .from("users")
    .select(`
      id,
      company_id,
      branch_id,
      role_id,
      is_active,
      roles(role_name)
    `)
    .eq("id", caller.id)
    .single()

  if (error || !data) {
    throw new HttpError(403, "Caller not found")
  }

  const { data: permissions } = await adminClient
    .from("user_permissions")
    .select("permission_code")
    .eq("user_id", caller.id)

  const email = caller.email?.toLowerCase() ?? ""
  const hardAdmin =
    caller.id === fallbackId ||
    (email && email === fallbackEmail)

  const roleName = hardAdmin
    ? "Admin"
    : Array.isArray(data.roles)
      ? data.roles[0]?.role_name ?? ""
      : ""

  const permissionSet = new Set(
    (permissions ?? []).map(
      (p: PermissionRow) => p.permission_code
    )
  )

  return {

    id: caller.id,
    email: caller.email ?? "",

    companyId: data.company_id,
    branchId: data.branch_id,
    roleId: data.role_id,

    roleName,

    isActive: data.is_active,

    permissions: hardAdmin
      ? new Set(hardAdminPermissions)
      : permissionSet

  }
}

// Disable platform JWT verification (we handle auth manually)
export const config = {
  verifyJWT: false
}
