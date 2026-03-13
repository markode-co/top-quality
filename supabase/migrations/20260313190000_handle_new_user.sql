-- Ensure pgcrypto for gen_random_uuid
create extension if not exists "pgcrypto";
-- Ensure public.users.id has a default (safety for manual inserts; trigger passes explicit id)
alter table public.users
  alter column id set default gen_random_uuid();
-- Trigger to create a profile row whenever a new auth user is created
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.users (id, email, name)
  values (new.id, new.email, '')
  on conflict (id) do nothing;

  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();
