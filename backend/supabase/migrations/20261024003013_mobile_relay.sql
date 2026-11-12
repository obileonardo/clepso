SET local check_function_bodies = off;

CREATE SCHEMA "clepso_private";

CREATE TABLE "public"."mobile_relay_control" (
  "user_id"    uuid                     NOT NULL,
  "enabled"    boolean                  NOT NULL DEFAULT false,
  "generation" uuid                     NOT NULL,
  "changed_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "mobile_relay_control_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."mobile_relay_control"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."mobile_relay_control" FROM "anon";

CREATE TABLE "public"."mobile_relay" (
  "user_id"     uuid                     NOT NULL,
  "snapshot"    jsonb                    NOT NULL,
  "received_at" timestamp with time zone NOT NULL,
  "expires_at"  timestamp with time zone NOT NULL,
  CONSTRAINT "mobile_relay_check" CHECK (((expires_at > received_at) AND (expires_at <= (received_at + '01:00:00'::interval)))),
  CONSTRAINT "mobile_relay_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."mobile_relay"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."mobile_relay" FROM "anon";

CREATE OR REPLACE FUNCTION clepso_private.publish_mobile_relay (
  p_snapshot   jsonb,
  p_generation uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare owner_id uuid := auth.uid(); control public.mobile_relay_control; generated timestamptz;
begin
  if owner_id is null then raise insufficient_privilege using message = 'Sign-in required'; end if;
  select * into control from public.mobile_relay_control where user_id=owner_id for update;
  if not found or not control.enabled or p_generation is null or control.generation <> p_generation then
    raise insufficient_privilege using message = 'Sharing lease is inactive';
  end if;
  if not clepso_private.valid_mobile_snapshot(p_snapshot) then raise invalid_parameter_value using message = 'Invalid aggregate snapshot'; end if;
  generated := (p_snapshot->>'generatedAt')::timestamptz;
  if generated < now() - interval '15 minutes' or generated > now() + interval '1 minute' then
    raise invalid_parameter_value using message = 'Snapshot is outside the accepted time window';
  end if;
  insert into public.mobile_relay(user_id,snapshot,received_at,expires_at) values (owner_id,p_snapshot,now(),now()+interval '15 minutes')
    on conflict(user_id) do update set snapshot=excluded.snapshot,received_at=excluded.received_at,expires_at=excluded.expires_at
    where (public.mobile_relay.snapshot->>'generatedAt')::timestamptz < generated;
end $function$;

CREATE OR REPLACE FUNCTION clepso_private.set_mobile_relay (
  p_enabled boolean
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare owner_id uuid := auth.uid(); lease uuid := gen_random_uuid();
begin
  if owner_id is null then raise insufficient_privilege using message = 'Sign-in required'; end if;
  if p_enabled is null then raise invalid_parameter_value using message = 'Explicit consent required'; end if;
  insert into public.mobile_relay_control(user_id,enabled,generation,changed_at) values (owner_id,p_enabled,lease,now())
    on conflict(user_id) do update set enabled=excluded.enabled,generation=excluded.generation,changed_at=excluded.changed_at;
  delete from public.mobile_relay where user_id=owner_id;
  return lease;
end $function$;

CREATE OR REPLACE FUNCTION clepso_private.valid_mobile_snapshot (
  p jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare r jsonb; k text; d timestamptz;
begin
  if jsonb_typeof(p) is distinct from 'object' or octet_length(p::text) > 131072 then return false; end if;
  if not (p ?& array['schemaVersion','generatedAt','demo','limits']) or
     (p - array['schemaVersion','generatedAt','demo','limits']) <> '{}'::jsonb or
     p->'schemaVersion' is distinct from '1'::jsonb or p->'demo' is distinct from 'false'::jsonb or
     jsonb_typeof(p->'limits') is distinct from 'array' then return false; end if;
  if jsonb_array_length(p->'limits') > 64 then return false; end if;
  if jsonb_typeof(p->'generatedAt') is distinct from 'string' or
     (p->>'generatedAt') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$' then return false; end if;
  d := (p->>'generatedAt')::timestamptz;
  for r in select value from jsonb_array_elements(p->'limits') loop
    if jsonb_typeof(r) is distinct from 'object' or
       not (r ?& array['provider','window','source','state']) or
       (r - array['provider','window','source','state','usedPercent','observedAt','resetsAt']) <> '{}'::jsonb then return false; end if;
    if (r->>'provider') not in ('claude-code','codex','claude-chat','chatgpt','gemini','grok','cursor','copilot','windsurf') or
       (r->>'window') not in ('fiveHour','weekly','daily') or
       (r->>'source') not in ('automatic','manual') or
       (r->>'state') not in ('reported','missing','disconnected','invalid','resetExpected') or
       jsonb_typeof(r->'provider') is distinct from 'string' or jsonb_typeof(r->'window') is distinct from 'string' or
       jsonb_typeof(r->'source') is distinct from 'string' or jsonb_typeof(r->'state') is distinct from 'string' then return false; end if;
    if r ? 'usedPercent' then
      if jsonb_typeof(r->'usedPercent') is distinct from 'number' then return false; end if;
      if (r->>'usedPercent')::numeric not between 0 and 1000000 then return false; end if;
    end if;
    foreach k in array array['observedAt','resetsAt'] loop
      if r ? k then
        if jsonb_typeof(r->k) is distinct from 'string' or
           (r->>k) !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$' then return false; end if;
        d := (r->>k)::timestamptz;
      end if;
    end loop;
  end loop;
  return true;
exception when others then return false;
end $function$;

CREATE OR REPLACE FUNCTION public.publish_mobile_relay (
  p_snapshot   jsonb,
  p_generation uuid
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select clepso_private.publish_mobile_relay(p_snapshot,p_generation) $function$;

REVOKE ALL ON FUNCTION "public"."publish_mobile_relay"(jsonb, uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.set_mobile_relay (
  p_enabled boolean
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select clepso_private.set_mobile_relay(p_enabled) $function$;

REVOKE ALL ON FUNCTION "public"."set_mobile_relay"(boolean) FROM PUBLIC, "anon";

ALTER TABLE "public"."mobile_relay"
  ADD CONSTRAINT "mobile_relay_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."mobile_relay_control"
  ADD CONSTRAINT "mobile_relay_control_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX mobile_relay_expiry ON public.mobile_relay USING btree (expires_at);

CREATE POLICY "mobile_owner_read" ON "public"."mobile_relay"
  FOR SELECT
  TO "authenticated"
  USING (((( SELECT auth.uid() AS uid) = user_id) AND (expires_at > now())));

CREATE POLICY "mobile_control_owner_read" ON "public"."mobile_relay_control"
  FOR SELECT
  TO "authenticated"
  USING ((( SELECT auth.uid() AS uid) = user_id));

REVOKE ALL ON FUNCTION "clepso_private"."publish_mobile_relay"(jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "clepso_private"."publish_mobile_relay"(jsonb, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "clepso_private"."set_mobile_relay"(boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "clepso_private"."set_mobile_relay"(boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "clepso_private"."valid_mobile_snapshot"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."publish_mobile_relay"(jsonb, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."publish_mobile_relay"(jsonb, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."publish_mobile_relay"(jsonb, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."publish_mobile_relay"(jsonb, uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."set_mobile_relay"(boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_mobile_relay"(boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_mobile_relay"(boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_mobile_relay"(boolean) TO "service_role";

GRANT USAGE ON SCHEMA "clepso_private" TO "authenticated";

REVOKE ALL ON TABLE "public"."mobile_relay" FROM "authenticated";

GRANT SELECT ON TABLE "public"."mobile_relay" TO "authenticated";

REVOKE ALL ON TABLE "public"."mobile_relay" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."mobile_relay" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."mobile_relay" TO "service_role";

REVOKE ALL ON TABLE "public"."mobile_relay_control" FROM "authenticated";

GRANT SELECT ON TABLE "public"."mobile_relay_control" TO "authenticated";

REVOKE ALL ON TABLE "public"."mobile_relay_control" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."mobile_relay_control" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."mobile_relay_control" TO "service_role";

ALTER TABLE "public"."mobile_relay"
  ADD CONSTRAINT "mobile_relay_snapshot_check" CHECK (clepso_private.valid_mobile_snapshot(snapshot));


-- Explicit least privilege, independent of project default grants.
REVOKE ALL ON TABLE public.mobile_relay, public.mobile_relay_control FROM PUBLIC, anon;
REVOKE ALL ON SCHEMA clepso_private FROM PUBLIC, anon;

-- Expiry is enforced by RLS immediately; this job removes expired payloads every five minutes.
-- No device tokens or per-user payloads occur in the scheduled command.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('clepso-expire-mobile-relay','*/5 * * * *',
  'delete from public.mobile_relay where expires_at <= now()');
