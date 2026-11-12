#!/usr/bin/env python3
"""Exercise an already packaged host using private disposable workspaces."""
import argparse,base64,json,os,select,struct,subprocess,tempfile,uuid
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('app',type=Path);args=parser.parse_args()
app=args.app.resolve();configuration=json.loads((app/'Contents/Resources/BridgeConfiguration.json').read_text())
host=app/'Contents/Helpers/GalmuriBridgeHost';origin='chrome-extension://'+configuration['extensionID']+'/'
def send(process,command,**extra):
    request={'version':1,'requestID':str(uuid.uuid4()),'command':command,**extra}
    if command=='hello':request['apiProtocol']=2
    data=json.dumps(request).encode();process.stdin.write(struct.pack('=I',len(data))+data);process.stdin.flush();return request
def receive(process):
    if not select.select([process.stdout],[],[],5)[0]: raise AssertionError('Host reply timed out')
    header=process.stdout.read(4);assert len(header)==4,process.stderr.read().decode()
    count=struct.unpack('=I',header)[0];assert 0<count<=65536
    return json.loads(process.stdout.read(count))
with tempfile.TemporaryDirectory(prefix='galmuri-host-proof-', dir=Path(__file__).resolve().parent.parent/'build') as temporary:
    workspace=Path(temporary).resolve();workspace.chmod(0o700)
    (workspace/'.galmuri-bridge-proof').write_text('Galmuri pairing-only proof v1\n')
    process=subprocess.Popen([str(host),origin,'--proof-workspace',str(workspace)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    request=send(process,'hello',installationID=str(uuid.uuid4()),name='Synthetic profile')
    reply=receive(process);assert reply['requestID']==request['requestID'] and reply['status']=='pending' and reply['bookmarkAccess'] is True
    pending=workspace/'BridgeProof'/(reply['sessionID']+'.request.json')
    approval=pending.with_name(reply['sessionID']+'.approval.json')
    with open(approval,'xb') as output:os.chmod(approval,0o600);output.write(pending.read_bytes())
    send(process,'status');assert receive(process)['status']=='approved'
    send(process,'acknowledge');assert receive(process)['status']=='verified'
    send(process,'poll');assert receive(process)['writable'] is False
    assert pending.with_name(reply['sessionID']+'.verified.json').exists()
    process.stdin.close();assert process.wait(timeout=5)==0
    assert list((workspace/'BridgeProof').iterdir())==[]
    for case in ['wrong-origin','wrong-version','unknown-command','duplicate-request','oversized','truncated','ack-before-approval','write-flag-without-marker','old-api-client']:
        process=subprocess.Popen([str(host),origin if case!='wrong-origin' else 'chrome-extension://'+'a'*32+'/', '--proof-workspace',str(workspace)]+(['--api-test-writes'] if case=='write-flag-without-marker' else []),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if case in ['oversized','truncated']: process.stdin.write(struct.pack('=I',65537) if case=='oversized' else b'\x01')
        elif case=='old-api-client':
            data=json.dumps({'version':1,'apiProtocol':1,'requestID':str(uuid.uuid4()),'command':'hello','installationID':str(uuid.uuid4()),'name':'QA'}).encode();process.stdin.write(struct.pack('=I',len(data))+data)
        elif case=='wrong-version':
            data=json.dumps({'version':2,'requestID':str(uuid.uuid4()),'command':'hello'}).encode();process.stdin.write(struct.pack('=I',len(data))+data)
        elif case=='duplicate-request':
            data=json.dumps({'version':1,'apiProtocol':2,'requestID':str(uuid.uuid4()),'command':'hello','installationID':str(uuid.uuid4()),'name':'QA'}).encode()
            process.stdin.write(struct.pack('=I',len(data))+data);process.stdin.flush();receive(process)
            process.stdin.write(struct.pack('=I',len(data))+data)
        else: send(process,'acknowledge' if case=='ack-before-approval' else 'writeBookmarks')
        process.stdin.close();assert process.wait(timeout=5)!=0,case
        assert list((workspace/'BridgeProof').iterdir())==[],case
    for case in ['large-record','orphan-part','duplicate-part','changed-command','foreign-result']:
        process=subprocess.Popen([str(host),origin,'--proof-workspace',str(workspace)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        installation=str(uuid.uuid4());send(process,'hello',installationID=installation,name='Chunk QA');reply=receive(process)
        assert reply['apiProtocol']==2
        pending=workspace/'BridgeProof'/(reply['sessionID']+'.request.json')
        approval=pending.with_name(reply['sessionID']+'.approval.json')
        with open(approval,'xb') as output:os.chmod(approval,0o600);output.write(pending.read_bytes())
        send(process,'status');receive(process);send(process,'acknowledge');receive(process)
        api=workspace/'BridgeAPI';api.mkdir(mode=0o700,exist_ok=True)
        job=str(uuid.uuid4());outbox=api/(reply['sessionID'].upper()+'.outbox.json')
        body={'id':job,'sessionID':reply['sessionID'],'installationID':installation,'command':'snapshot','scope':'','expected':'','desired':[],'recoveryIDs':[]}
        with open(outbox,'x') as output:os.chmod(outbox,0o600);json.dump(body,output)
        send(process,'poll');assert receive(process)['job']['id']==job
        record={'jobID':job if case!='foreign-result' else str(uuid.uuid4()),'state':'succeeded','mapping':{str(uuid.uuid4()):'opaque-'+str(i) for i in range(1200)}}
        data=json.dumps(record).encode();chunks=[data[i:i+32000] for i in range(0,len(data),32000)];assert len(chunks)>1
        transfer=str(uuid.uuid4())
        if case=='orphan-part':
            send(process,'result',transfer=transfer,part=1,total=len(chunks),payload=base64.b64encode(chunks[1]).decode())
        else:
            for index,chunk in enumerate(chunks):
                send(process,'progress' if case=='changed-command' and index else 'result',transfer=transfer,part=0 if case=='duplicate-part' else index,total=len(chunks),payload=base64.b64encode(chunk).decode())
                if (case in ['duplicate-part','changed-command'] and index==1) or (case=='foreign-result' and index==len(chunks)-1):break
                receive(process)
                if case in ['duplicate-part','changed-command'] and index==0:continue
        process.stdin.close();assert process.wait(timeout=5)==(0 if case=='large-record' else 1),case
        result=api/(job.upper()+'.result.json')
        if case=='large-record':
            saved=json.loads(result.read_text());assert saved['jobID'].lower()==job and saved['mapping']==record['mapping'] and saved['state']=='succeeded'
        else:assert not result.exists(),case
        assert list((workspace/'BridgeProof').iterdir())==[] and not outbox.exists(),case
print(json.dumps({'variant':configuration['variant'],'framedHandshakeApprovalAcknowledgement':True,'rejections':13,'chunkedResultLargerThan32KB':True,'disconnectCleanup':True,'bookmarkAccess':True,'apiProtocol':2}))
