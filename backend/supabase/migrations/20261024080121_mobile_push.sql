SET local check_function_bodies = off;

CREATE TABLE "clepso_private"."mobile_device_control" (
  "user_id"    uuid                     NOT NULL,
  "device_id"  uuid                     NOT NULL,
  "enabled"    boolean                  NOT NULL,
  "generation" uuid                     NOT NULL,
  "changed_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "mobile_device_control_pkey" PRIMARY KEY (user_id, device_id)
);

ALTER TABLE "clepso_private"."mobile_device_control"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "clepso_private"."mobile_devices" (
  "user_id"       uuid                     NOT NULL,
  "device_id"     uuid                     NOT NULL,
  "token"         text                     NOT NULL,
  "environment"   text                     NOT NULL,
  "registered_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "mobile_devices_environment_check" CHECK ((environment = ANY (ARRAY['development'::text, 'production'::text]))),
  CONSTRAINT "mobile_devices_pkey" PRIMARY KEY (user_id, device_id),
  CONSTRAINT "mobile_devices_token_check" CHECK ((((length(token) >= 2) AND (length(token) <= 1024)) AND ((length(token) % 2) = 0) AND (token ~ '^[0-9a-f]+$'::text)))
);

ALTER TABLE "clepso_private"."mobile_devices"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."mobile_relay_control"
  ADD COLUMN "last_signal_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION clepso_private.register_mobile_device (
  p_device      uuid,
  p_generation  uuid,
  p_token       text,
  p_environment text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare owner_id uuid:=auth.uid(); control clepso_private.mobile_device_control;
begin
  if owner_id is null then raise insufficient_privilege using message='Sign-in required'; end if;
  select * into control from clepso_private.mobile_device_control where user_id=owner_id and device_id=p_device for update;
  if not found or not control.enabled or p_generation is null or control.generation<>p_generation then
    raise insufficient_privilege using message='Device lease is inactive';
  end if;
  if p_token is null or length(p_token) not between 2 and 1024 or length(p_token)%2<>0 or p_token !~ '^[0-9a-f]+$'
     or p_environment is null or p_environment not in ('development','production') then
    raise invalid_parameter_value using message='Invalid device registration';
  end if;
  insert into clepso_private.mobile_devices(user_id,device_id,token,environment,registered_at)
    values(owner_id,p_device,p_token,p_environment,now()) on conflict(user_id,device_id)
    do update set token=excluded.token,environment=excluded.environment,registered_at=excluded.registered_at;
end $function$;

CREATE OR REPLACE FUNCTION clepso_private.set_mobile_device (
  p_device  uuid,
  p_enabled boolean
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare owner_id uuid:=auth.uid(); lease uuid:=gen_random_uuid();
begin
  if owner_id is null then raise insufficient_privilege using message='Sign-in required'; end if;
  if p_device is null or p_enabled is null then raise invalid_parameter_value using message='Explicit device consent required'; end if;
  -- One short per-owner lock bounds concurrent registrations as well as ordinary sequential calls.
  perform 1 from auth.users where id=owner_id for update;
  if not found then raise insufficient_privilege using message='Account is unavailable'; end if;
  delete from clepso_private.mobile_device_control c where c.user_id=owner_id and c.device_id<>p_device
    and c.changed_at < now()-interval '30 days' and not exists (
      select 1 from clepso_private.mobile_devices d where d.user_id=c.user_id and d.device_id=c.device_id
        and d.registered_at > now()-interval '30 days');
  if not exists(select 1 from clepso_private.mobile_device_control where user_id=owner_id and device_id=p_device)
     and (select count(*) from clepso_private.mobile_device_control where user_id=owner_id)>=8 then
    raise check_violation using message='Device registration limit reached';
  end if;
  insert into clepso_private.mobile_device_control(user_id,device_id,enabled,generation,changed_at)
    values(owner_id,p_device,p_enabled,lease,now()) on conflict(user_id,device_id)
    do update set enabled=excluded.enabled,generation=excluded.generation,changed_at=excluded.changed_at;
  delete from clepso_private.mobile_devices where user_id=owner_id and device_id=p_device;
  return lease;
end $function$;

CREATE OR REPLACE FUNCTION public.claim_mobile_signal (
  p_user uuid
)
  RETURNS TABLE (
    device_id   uuid,
    token       text,
    environment text
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with claimed as (
    update public.mobile_relay_control c set last_signal_at=now()
    where c.user_id=p_user and c.enabled and (c.last_signal_at is null or c.last_signal_at<=now()-interval '20 minutes')
      and exists(select 1 from public.mobile_relay r where r.user_id=c.user_id and r.expires_at>now())
      and exists(select 1 from clepso_private.mobile_devices d
        join clepso_private.mobile_device_control dc on dc.user_id=d.user_id and dc.device_id=d.device_id
        where d.user_id=c.user_id and dc.enabled and d.registered_at>now()-interval '30 days')
    returning c.user_id
  )
  select d.device_id,d.token,d.environment from claimed c
    join clepso_private.mobile_devices d on d.user_id=c.user_id
    join clepso_private.mobile_device_control dc on dc.user_id=d.user_id and dc.device_id=d.device_id
    where dc.enabled and d.registered_at>now()-interval '30 days' order by d.device_id limit 8
$function$;

REVOKE ALL ON FUNCTION "public"."claim_mobile_signal"(uuid) FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.register_mobile_device (
  p_device      uuid,
  p_generation  uuid,
  p_token       text,
  p_environment text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select clepso_private.register_mobile_device(p_device,p_generation,p_token,p_environment) $function$;

REVOKE ALL ON FUNCTION "public"."register_mobile_device"(uuid, uuid, text, text) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.remove_invalid_mobile_device (
  p_user        uuid,
  p_device      uuid,
  p_token       text,
  p_environment text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  delete from clepso_private.mobile_devices where user_id=p_user and device_id=p_device and token=p_token and environment=p_environment
$function$;

REVOKE ALL ON FUNCTION "public"."remove_invalid_mobile_device"(uuid, uuid, text, text) FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.set_mobile_device (
  p_device  uuid,
  p_enabled boolean
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select clepso_private.set_mobile_device(p_device,p_enabled) $function$;

REVOKE ALL ON FUNCTION "public"."set_mobile_device"(uuid, boolean) FROM PUBLIC, "anon";

ALTER TABLE "clepso_private"."mobile_device_control"
  ADD CONSTRAINT "mobile_device_control_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "clepso_private"."mobile_devices"
  ADD CONSTRAINT "mobile_devices_user_id_device_id_fkey" FOREIGN KEY (user_id, device_id) REFERENCES clepso_private.mobile_device_control(user_id, device_id) ON DELETE CASCADE;

CREATE INDEX mobile_device_registration_expiry ON clepso_private.mobile_devices USING btree (registered_at);

REVOKE ALL ON FUNCTION "clepso_private"."register_mobile_device"(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "clepso_private"."register_mobile_device"(uuid, uuid, text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "clepso_private"."set_mobile_device"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "clepso_private"."set_mobile_device"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."claim_mobile_signal"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."claim_mobile_signal"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."claim_mobile_signal"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."register_mobile_device"(uuid, uuid, text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."register_mobile_device"(uuid, uuid, text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_mobile_device"(uuid, uuid, text, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_mobile_device"(uuid, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "public"."remove_invalid_mobile_device"(uuid, uuid, text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."remove_invalid_mobile_device"(uuid, uuid, text, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."remove_invalid_mobile_device"(uuid, uuid, text, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."set_mobile_device"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_mobile_device"(uuid, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_mobile_device"(uuid, boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_mobile_device"(uuid, boolean) TO "service_role";

REVOKE ALL ON SCHEMA "clepso_private" FROM "service_role";

GRANT USAGE ON SCHEMA "clepso_private" TO "service_role";

GRANT SELECT ON TABLE "clepso_private"."mobile_device_control" TO "service_role";

GRANT DELETE, SELECT ON TABLE "clepso_private"."mobile_devices" TO "service_role";


-- Cron job data is not included in a schema diff.
select cron.schedule('clepso-expire-mobile-devices','17 3 * * *','delete from clepso_private.mobile_devices where registered_at <= now() - interval ''30 days''');
