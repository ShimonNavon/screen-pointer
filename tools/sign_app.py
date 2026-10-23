#!/usr/bin/env python3
"""Sign local builds with a persistent, app-specific certificate in an isolated keychain.

No trust-store changes, no permission grants, no shared developer account required.
Private material lives outside the repository with mode 0700/0600.
"""
import argparse,hashlib,json,os,secrets,shutil,subprocess,tempfile
from pathlib import Path

STATE=Path.home()/'Library/Application Support/Screen Pointer/Signing'
KEYCHAIN=STATE/'screen-pointer.keychain-db'

def run(argv,**kwargs):
    result=subprocess.run(list(map(str,argv)),capture_output=True,text=True,**kwargs)
    if result.returncode:
        # Never include argv: it can contain temporary keychain passwords.
        raise RuntimeError(f'{Path(str(argv[0])).name} failed: {result.stderr.strip()}')
    return result.stdout

def initialize():
    STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
    if (STATE/'identity.json').exists():return
    if KEYCHAIN.exists():raise RuntimeError('Signing setup is incomplete; inspect the private signing directory before retrying.')
    openssl=shutil.which('openssl')
    if not openssl:raise RuntimeError('OpenSSL is required to create the local signing identity.')
    password=secrets.token_urlsafe(40)
    password_file=STATE/'keychain-password'
    password_file.write_text(password);password_file.chmod(0o600)
    # Creating a keychain can add it to the search list. Restore the existing list afterward.
    import shlex
    search=shlex.split(run(['security','list-keychains','-d','user']))
    try:
        run(['security','create-keychain','-p',password,KEYCHAIN])
        run(['security','set-keychain-settings','-lut','600',KEYCHAIN])
        run(['security','unlock-keychain','-p',password,KEYCHAIN])
        with tempfile.TemporaryDirectory(dir=STATE) as temp:
            folder=Path(temp);config=folder/'openssl.cnf';key=folder/'key.pem';cert=folder/'cert.pem';p12=folder/'identity.p12'
            config.write_text('''[req]
prompt=no
distinguished_name=dn
x509_extensions=signing
[dn]
CN=Screen Pointer Local Development
O=Screen Pointer Local Development
[signing]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
''')
            env=os.environ.copy();env['SCREEN_POINTER_SIGNING_PASSWORD']=password
            run([openssl,'req','-new','-x509','-newkey','rsa:3072','-nodes','-days','3650','-config',config,'-keyout',key,'-out',cert])
            key.chmod(0o600)
            run([openssl,'pkcs12','-export','-legacy','-inkey',key,'-in',cert,'-out',p12,'-passout','env:SCREEN_POINTER_SIGNING_PASSWORD'],env=env)
            run(['security','import',p12,'-k',KEYCHAIN,'-P',password,'-T','/usr/bin/codesign'])
            run(['security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,KEYCHAIN])
            der=STATE/'certificate.der'
            run([openssl,'x509','-in',cert,'-outform','DER','-out',der])
            fingerprint=hashlib.sha1(der.read_bytes()).hexdigest().upper()
            (STATE/'identity.json').write_text(json.dumps({'sha1':fingerprint,'label':'Screen Pointer Local Development'},indent=2)+'\n')
            (STATE/'identity.json').chmod(0o600)
    finally:
        run(['security','list-keychains','-d','user','-s',*search])

def sign(app):
    initialize()
    identity=json.loads((STATE/'identity.json').read_text())['sha1']
    password=(STATE/'keychain-password').read_text()
    run(['security','unlock-keychain','-p',password,KEYCHAIN])
    requirement=f'designated => identifier "com.navonsimon.screen-pointer" and certificate leaf = H"{identity}"'
    import shlex
    search=shlex.split(run(['security','list-keychains','-d','user']))
    run(['security','list-keychains','-d','user','-s',*search,KEYCHAIN])
    try:
        run(['codesign','--force','--sign',identity,'--keychain',KEYCHAIN,'--timestamp=none','--requirements','='+requirement,app])
        run(['codesign','--verify','--strict','--verbose=2',app])
    finally:
        run(['security','lock-keychain',KEYCHAIN])
        run(['security','list-keychains','-d','user','-s',*search])
    print('Signed and verified with the persistent Screen Pointer local certificate.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('app',type=Path);args=parser.parse_args()
    sign(args.app)
