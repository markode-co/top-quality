# Supabase ERP Architecture Review

## Critical Findings

1. The current schema is not multi-tenant. `public.users`, `public.products`, `public.inventory`, `public.orders`, `public.notifications`, and `public.activity_logs` were all global records with no `company_id` or `branch_id` boundary in `supabase/migrations/0001_initial_schema.sql`.
2. `public.inventory` is structurally single-branch because `product_id` is the primary key. That blocks true branch-level stock balances and transfer flows. This remains a phase-two refactor even after the hardening migration.
3. The app depends on public views such as `v_users_with_permissions` and `v_products`, but those views were created without `security_invoker`, which is risky in Supabase/PostgREST when RLS is the main isolation layer.
4. `supabase/migrations/0002_activity_logs_user_rls.sql` narrowed `activity_logs` access to `user_id = auth.uid()`, while Flutter still fetches the latest 40 logs for the dashboard and activity page from `lib/data/datasources/remote/supabase_backend_data_source.dart`. That mismatch causes role-based audit visibility to regress.
5. Dashboard and employee reports are assembled client-side by loading full order, product, and activity datasets into memory. That will not scale once orders and logs become large.

## Delivered Migration

`supabase/migrations/0003_multi_tenant_hardening.sql` adds:

- `companies` and `branches`
- tenant columns on the current operational tables
- tenant backfill for existing data
- tenant default triggers for new inserts
- `security_invoker` views: `profiles`, `user_roles`, `audit_logs`, `v_users_with_permissions`, `v_products`, `v_order_summaries`
- indexed access paths for orders, inventory, notifications, logs, and permission joins
- permission helpers rewritten to query base tables directly
- RLS scoped by company and branch
- `write_activity_log()` and `notify_roles()` updated to write tenant-aware rows

## Recommended Supabase Query Shapes

Use views for list pages and summaries:

```sql
select *
from public.v_order_summaries
where company_id = public.current_company_id()
order by order_date desc
limit 50;
```

```sql
select *
from public.v_products
where company_id = public.current_company_id()
order by name;
```

Prefer narrow nested reads only for detail pages:

```sql
select
  id,
  customer_name,
  customer_phone,
  order_date,
  order_notes,
  status,
  total_cost,
  total_revenue,
  profit,
  created_by,
  created_by_name,
  order_items (
    id,
    product_id,
    product_name,
    quantity,
    purchase_price,
    sale_price,
    profit
  ),
  order_status_history (
    id,
    status,
    changed_by,
    changed_by_name,
    changed_at,
    note
  )
from public.orders
where id = :order_id;
```

For audit pages:

```sql
select *
from public.audit_logs
order by created_at desc
limit 100;
```

## Flutter Data Access Patterns

1. Use summary views for list screens and keep nested relational selects for one-record detail screens only.
2. Replace client-side dashboard/report aggregation with server-side views or RPCs. The current dashboard builder reads every order and every product before calculating totals.
3. Wrap `.rpc()` and `.from(...).select()` calls in a shared error mapper that turns missing function/view/column errors into migration hints.
4. Add pagination to orders, notifications, and activity logs. Avoid unbounded `select()` for ERP tables.
5. Keep realtime listeners on small summary tables or list views. Do not rebuild dashboard KPIs from full-table fetches on every change event.

## Supabase Error Prevention

- `404 RPC function`: keep migrations applied in order and expose only functions in `public`.
- `404 view`: create views in `public` and keep names stable for Flutter.
- `missing column`: avoid `select(*)` in Flutter for critical DTOs; request explicit columns.
- RLS/view mismatch: use `security_invoker` on views that back REST reads.
- permission drift: keep permission checks in SQL functions, not duplicated across Flutter widgets.

## Next Phase

The remaining structural gap is branch-scoped inventory. To support true multi-branch stock and transfers, `inventory` should move from `product_id` as the primary key to a branch-scoped key such as `(branch_id, product_id)` or a surrogate `id` plus a unique `(branch_id, product_id)` constraint, followed by updates to the inventory RPCs and Flutter DTOs.
