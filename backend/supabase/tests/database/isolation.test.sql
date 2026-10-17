-- ROADMAP 2.0 step 1 proof: one user can never read or write another's rows; anonymous callers see nothing;
-- deleting an account removes every row it owned and nothing else.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.test', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.test', 'authenticated', 'authenticated');

select is((select count(*)::int from public.profiles), 2, 'a profile is created for each new account');

-- User A writes their own rows.
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
insert into public.daily_activity (day, messages, sessions, active) values ('2026-10-16', 120, 3, true);
insert into public.daily_model_tokens (day, model, tokens) values ('2026-10-16', 'claude-opus-5-5', 1000000);
insert into public.model_totals (model, output) values ('claude-opus-5-5', 18200000);
insert into public.daily_limits (day, five_hour_peak_pct, seven_day_end_pct) values ('2026-10-16', 83, 21);
insert into public.daily_agents (day, tasks, agents, by_type) values ('2026-10-16', 4, 10, '{"Explore": 6, "Plan": 4}');
insert into public.goals (kind, target) values ('fiveHourPeak', 80);
select is((select count(*)::int from public.daily_activity), 1, 'A sees their own day');
select is((select user_id from public.daily_activity), '11111111-1111-1111-1111-111111111111'::uuid, 'rows default to the signed-in user');

-- User B sees none of A's rows, and cannot write rows for A.
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.daily_activity), 0, 'B cannot read A''s activity');
select is((select count(*)::int from public.daily_model_tokens), 0, 'B cannot read A''s tokens');
select is((select count(*)::int from public.model_totals), 0, 'B cannot read A''s totals');
select is((select count(*)::int from public.goals), 0, 'B cannot read A''s goals');
select is((select count(*)::int from public.profiles), 1, 'B sees only their own profile');
select throws_ok($$ insert into public.daily_activity (user_id, day) values ('11111111-1111-1111-1111-111111111111', '2026-10-15') $$,
                 '42501', null, 'B cannot write a row for A');
update public.daily_activity set messages = 0;     -- touches nothing: no visible rows
delete from public.goals;                           -- likewise
select throws_ok($$ insert into public.daily_model_tokens (day, model, tokens) values ('2026-10-16', '/Users/someone', 1) $$,
                 '23514', null, 'a path is not a model name');

-- Anonymous callers: no access at all.
set local role anon;
select throws_ok($$ select count(*) from public.daily_activity $$, '42501', null, 'anonymous cannot read');
select throws_ok($$ select public.delete_account() $$, '42501', null, 'anonymous cannot delete an account');

-- A's rows survived B's attempts.
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select messages from public.daily_activity), 120, 'B''s update did not reach A''s row');
select is((select count(*)::int from public.goals), 1, 'B''s delete did not reach A''s goal');

-- A deletes their account: all of A's rows go, B's profile stays.
select public.delete_account();
reset role;
select is((select count(*)::int from public.daily_activity where user_id = '11111111-1111-1111-1111-111111111111'), 0, 'A''s rows are gone');
select is((select count(*)::int from public.profiles), 1, 'only B remains');

select * from finish();
rollback;
