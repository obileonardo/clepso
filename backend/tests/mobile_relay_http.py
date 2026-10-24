import datetime,json,secrets,subprocess,urllib.request,urllib.error,uuid
from pathlib import Path
root=Path(__file__).resolve().parents[2]
status=subprocess.run(['supabase','status','--workdir','build/mobile-db','-o','json'],cwd=root,capture_output=True,text=True,check=True)
settings=json.loads(status.stdout)
url=settings['API_URL']; assert url=='http://127.0.0.1:55321'
anon=settings['ANON_KEY']; admin=settings['SERVICE_ROLE_KEY']
def request(path,method='GET',body=None,token=None,key=anon,expected=200):
    data=None if body is None else json.dumps(body).encode()
    headers={'apikey':key,'Authorization':'Bearer '+(token or key),'Content-Type':'application/json'}
    try:
        with urllib.request.urlopen(urllib.request.Request(url+path,data=data,headers=headers,method=method),timeout=15) as response:
            code=response.status; result=response.read()
    except urllib.error.HTTPError as error: code=error.code;result=error.read()
    assert code==expected, 'Unexpected HTTP status '+str(code)+' for '+path.split('?')[0]
    return json.loads(result) if result else None
users=[]
try:
    tokens=[]
    for _ in range(2):
        email=uuid.uuid4().hex+'@example.test';password=secrets.token_urlsafe(32)
        user=request('/auth/v1/admin/users','POST',{'email':email,'password':password,'email_confirm':True},admin,admin)
        users.append(user['id'])
        tokens.append(request('/auth/v1/token?grant_type=password','POST',{'email':email,'password':password})['access_token'])
    now=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z')
    snapshot={'schemaVersion':1,'generatedAt':now,'demo':False,'limits':[{'provider':'codex','window':'fiveHour','source':'automatic','state':'reported','usedPercent':80,'observedAt':now}]}
    lease=request('/rest/v1/rpc/set_mobile_relay','POST',{'p_enabled':True},tokens[0])
    request('/rest/v1/rpc/publish_mobile_relay','POST',{'p_snapshot':snapshot,'p_generation':lease},tokens[0],expected=204)
    own=request('/rest/v1/mobile_relay?select=snapshot,received_at,expires_at',token=tokens[0]); assert len(own)==1 and own[0]['snapshot']==snapshot
    assert request('/rest/v1/mobile_relay?select=snapshot',token=tokens[1])==[]
    request('/rest/v1/rpc/publish_mobile_relay','POST',{'p_snapshot':snapshot,'p_generation':lease},tokens[1],expected=403)
    request('/rest/v1/mobile_relay',expected=401)
    request('/rest/v1/rpc/publish_mobile_relay','POST',{'p_snapshot':dict(snapshot,prompt='rejected synthetic content'),'p_generation':lease},tokens[0],expected=400)
    request('/rest/v1/rpc/set_mobile_relay','POST',{'p_enabled':False},tokens[0])
    assert request('/rest/v1/mobile_relay?select=snapshot',token=tokens[0])==[]
    request('/rest/v1/rpc/publish_mobile_relay','POST',{'p_snapshot':snapshot,'p_generation':lease},tokens[0],expected=403)
    evidence=root/'build/mobile-test-evidence';evidence.mkdir(parents=True,exist_ok=True)
    (evidence/'local-api.json').write_text(json.dumps({'synthetic_local_users_only':True,'no_emails_sent':True,'owner_read':True,'cross_account_read_isolated':True,'cross_account_publish_denied':True,'anonymous_denied':True,'unknown_fields_rejected':True,'revocation_clears_snapshot':True,'revoked_generation_rejected':True},indent=2)+'\n')
    print('Local Auth → RPC → REST: ownership, validation and revocation PASS; no email sent.')
finally:
    for user in users: request('/auth/v1/admin/users/'+user,'DELETE',token=admin,key=admin)
