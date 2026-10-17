-- Pulse accounts (ROADMAP 2.0, DECISIONS C9, docs/ACCOUNTS_AND_SYNC.md).
-- Daily counts only: no prompts, replies, paths, project names or raw session/agent ids exist anywhere here.
-- Every table is keyed by the signed-in user and readable and writable only by that user (row-level security).
-- Deleting the account (delete_account) removes the auth user, and every row cascades with it.

create table public.profiles (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 40),
  plan_label   text check (char_length(plan_label) <= 60),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Per day: what Claude Code's statistics file reports (messages and sessions), and whether the user was active.
create table public.daily_activity (
  user_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day      date not null,
  messages integer not null default 0 check (messages >= 0),
  sessions integer not null default 0 check (sessions >= 0),
  active   boolean not null default false,
  primary key (user_id, day)
);

-- Per day and model: tokens as the statistics file counts them (all kinds together; it keeps no per-day split).
create table public.daily_model_tokens (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day     date not null,
  model   text not null check (model ~ '^[a-z0-9][a-z0-9.\-]{0,63}$'),
  tokens  bigint not null check (tokens >= 0),
  primary key (user_id, day, model)
);

-- Per model, all time, by kind: what levels are computed from (output) and the Arena shows.
create table public.model_totals (
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  model       text not null check (model ~ '^[a-z0-9][a-z0-9.\-]{0,63}$'),
  input       bigint not null default 0 check (input >= 0),
  output      bigint not null default 0 check (output >= 0),
  cache_read  bigint not null default 0 check (cache_read >= 0),
  cache_write bigint not null default 0 check (cache_write >= 0),
  updated_at  timestamptz not null default now(),
  primary key (user_id, model)
);

-- Per day: the limits as Pulse saw them on the Mac.
create table public.daily_limits (
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day                date not null,
  five_hour_peak_pct numeric(5, 2) check (five_hour_peak_pct between 0 and 100),
  seven_day_end_pct  numeric(5, 2) check (seven_day_end_pct between 0 and 100),
  primary key (user_id, day)
);

-- Per day: agents per task (increment 1.9), counts and built-in types only.
create table public.daily_agents (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day     date not null,
  tasks   integer not null default 0 check (tasks >= 0),
  agents  integer not null default 0 check (agents >= 0),
  by_type jsonb not null default '{}'::jsonb check (jsonb_typeof(by_type) = 'object'),
  primary key (user_id, day)
);

create table public.goals (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind       text not null check (kind in ('activeDays', 'fiveHourPeak', 'weeklyFinish')),
  target     integer check (target between 1 and 100),          -- null: turned off
  updated_at timestamptz not null default now(),
  primary key (user_id, kind)
);

create table public.goal_days (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day     date not null,
  kind    text not null check (kind in ('activeDays', 'fiveHourPeak', 'weeklyFinish')),
  value   numeric(7, 2),
  met     boolean,
  primary key (user_id, day, kind)
);

-- Row-level security: each table, the signed-in user's own rows only.
do $$
declare t text;
begin
  foreach t in array array['profiles', 'daily_activity', 'daily_model_tokens', 'model_totals', 'daily_limits', 'daily_agents', 'goals', 'goal_days']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
                   t || '_own_rows', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- A profile for every new account.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- "Delete account": removes the caller's auth user; every row above goes with it (on delete cascade).
create function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
