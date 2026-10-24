import json, subprocess, uuid
from pathlib import Path
container='supabase_db_clepso_mobile_test'
base=['docker','exec',container,'psql','-U','postgres','-d','postgres','-Atq','-v','ON_ERROR_STOP=1','-c']
owner=str(uuid.uuid4())
def sql(value): return subprocess.run(base+[value],check=True,capture_output=True,text=True).stdout.strip()
claims=json.dumps({'sub':owner,'role':'authenticated'})
context="set role authenticated; set request.jwt.claims='"+claims+"';"
snapshot="jsonb_build_object('schemaVersion',1,'demo',false,'generatedAt',to_char(now() at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'),'limits','[]'::jsonb)"
try:
    sql("insert into auth.users(id,email,aud,role) values ('"+owner+"','race@example.test','authenticated','authenticated')")
    lease=sql(context+' select public.set_mobile_relay(true);').splitlines()[-1]
    writer=subprocess.Popen(base+["begin; "+context+" select public.publish_mobile_relay("+snapshot+",'"+lease+"'); select 'LOCKED'; select pg_sleep(2); commit;"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    while True:
        line=writer.stdout.readline()
        if line.strip()=='LOCKED': break
        if not line: raise RuntimeError('Writer did not acquire its lease lock')
    # This call blocks behind the older publication, then rotates its generation and deletes the row.
    sql(context+' select public.set_mobile_relay(false);')
    _,err=writer.communicate(timeout=10)
    assert writer.returncode==0,err
    assert sql("select count(*) from public.mobile_relay where user_id='"+owner+"'")=='0'
    replay=subprocess.run(base+[context+" select public.publish_mobile_relay("+snapshot+",'"+lease+"');"],capture_output=True,text=True)
    assert replay.returncode!=0 and 'Sharing lease is inactive' in replay.stderr
    root=Path(__file__).resolve().parents[2]
    evidence=root/'build/mobile-test-evidence';evidence.mkdir(exist_ok=True,parents=True)
    (evidence/'relay-concurrency.json').write_text(json.dumps({'older_publication_locked':True,'disable_serialized_after_writer':True,'revocation_left_no_snapshot':True,'old_generation_replay_rejected':True},indent=2)+'\n')
    print('Two PostgreSQL connections: revocation wins suspended publication; old generation replay rejected.')
finally:
    sql("delete from auth.users where id='"+owner+"'")
