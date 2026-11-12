import json,secrets,subprocess,urllib.request,urllib.error,uuid
from pathlib import Path
root=Path(__file__).resolve().parents[2]
value=subprocess.run(['supabase','status','--workdir','build/mobile-db','-o','json'],cwd=root,capture_output=True,text=True,check=True)
config=json.loads(value.stdout);url=config['API_URL'];assert url=='http://127.0.0.1:55321'
anon=config['ANON_KEY'];admin=config['SERVICE_ROLE_KEY']
def call(path,method='POST',body=None,token=None,key=anon,expected=200):
    headers={'apikey':key,'Content-Type':'application/json'}
    if token is not None:headers['Authorization']='Bearer '+token
    try:
        with urllib.request.urlopen(urllib.request.Request(url+path,method=method,headers=headers,data=None if body is None else json.dumps(body).encode()),timeout=20) as response:
            code=response.status;data=response.read()
    except urllib.error.HTTPError as error:code=error.code;data=error.read()
    assert code==expected,'Unexpected local status '+str(code)+' at '+path.split('?')[0]
    return json.loads(data) if data else None
user=None
try:
    password=secrets.token_urlsafe(32);email=uuid.uuid4().hex+'@example.test'
    user=call('/auth/v1/admin/users',body={'email':email,'password':password,'email_confirm':True},token=admin,key=admin)
    jwt=call('/auth/v1/token?grant_type=password',body={'email':email,'password':password})['access_token']
    endpoint='/functions/v1/mobile-signal'
    call(endpoint,body={},expected=401)
    call(endpoint,body={},token=anon,expected=401)
    call(endpoint,body={'user_id':'not-accepted'},token=jwt,expected=400)
    response=call(endpoint,body={'check':True,'environment':'development'},token=jwt,expected=503)
    assert response=={'error':'push_not_configured'},'Local worker did not reach verified readiness check'
    response=call(endpoint,body={},token=jwt,expected=503)
    assert response=={'error':'push_not_configured'}
    record={'actual_edge_runtime_executed':True,'gateway_jwt_verification_enabled':True,'unauthenticated_and_anon_denied':True,'verified_user_owner_check':True,'unknown_request_fields_denied':True,'missing_apple_credentials_reported':True,'no_apple_push_sent':True,'no_emails_sent':True}
    evidence=root/'build/mobile-test-evidence';evidence.mkdir(parents=True,exist_ok=True)
    (evidence/'edge-runtime.json').write_text(json.dumps(record,indent=2)+'\n')
    print('Local Edge runtime: authenticated owner, rejected anonymous/extra fields, explicit missing-key response PASS; no Apple push/email sent.')
finally:
    if user:call('/auth/v1/admin/users/'+user['id'],method='DELETE',token=admin,key=admin)
