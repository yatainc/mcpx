#!/usr/bin/env python3
"""Actual-binary project discovery, launch-context and OAuth isolation checks."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading


PEER = r'''
import json, os, sys
calls = 0
for line in sys.stdin:
    q = json.loads(line)
    if 'id' not in q:
        continue
    method = q['method']
    if method == 'server/discover' and os.getenv('MCPX_TEST_LEGACY'):
        print(json.dumps({'jsonrpc':'2.0', 'id':q['id'], 'error':{'code':-32601,'message':'legacy'}}), flush=True)
        continue
    if method == 'initialize':
        r = {'protocolVersion':'2025-11-25', 'capabilities':{'tools':{}}}
    elif method == 'server/discover':
        r = {'resultType':'complete', 'supportedVersions':['2026-07-28'], 'capabilities':{'tools':{}, 'resources':{}, 'extensions':{'io.modelcontextprotocol/skills':{}}}}
    elif method == 'skills/list':
        r = {'resultType':'complete', 'skills':[], 'ttlMs':0, 'cacheScope':'private'}
    elif method == 'tools/call':
        calls += 1
        text = json.dumps({'cwd':os.getcwd(), 'relay':os.getenv('FOLDKIT_DEVTOOLS_RELAY_DIRECTORY'), 'stale':os.getenv('MCPX_TEST_DAEMON_ONLY'), 'override':os.getenv('OVERRIDE'), 'executable':os.getenv('MCPX_TEST_EXECUTABLE'), 'pid':os.getpid(), 'calls':calls, 'daemonFlag':os.getenv('MCPX_INTERNAL_DAEMON'), 'gitDir':os.getenv('GIT_DIR')})
        r = {'resultType':'complete', 'content':[{'type':'text','text':text}], 'ttlMs':0, 'cacheScope':'private'}
    else:
        r = {'resultType':'complete', 'tools':[{'name':'probe','inputSchema':{'type':'object'}}], 'ttlMs':0, 'cacheScope':'private'}
    print(json.dumps({'jsonrpc':'2.0', 'id':q['id'], 'result':r}), flush=True)
'''


def identity(path, name):
    raw = json.dumps([str(path), name], ensure_ascii=False, separators=(',', ':')).encode()
    return 'config:sha256:' + hashlib.sha256(raw).hexdigest()


def main():
    binary = str(Path(sys.argv[1]).resolve())
    git = shutil.which('git')
    assert git, 'Git is required for these fixtures'
    with tempfile.TemporaryDirectory(prefix='mcpx-project-e2e-') as td:
        root = Path(td).resolve()
        config = root / 'config' / 'mcpx'
        config.mkdir(parents=True)
        env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        env.update(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(config.parent))
        for key in ['MCPX_INTERNAL_DAEMON', 'MCPX_KEEPALIVE', 'MCPX_DISABLE_KEEPALIVE', 'MCPX_NO_KEEPALIVE']:
            env.pop(key, None)

        def run(*args, cwd=root, environment=env, ok=True):
            p = subprocess.run([binary, *args], cwd=cwd, env=environment,
                               text=True, capture_output=True, timeout=20)
            assert p.returncode == (0 if ok else 2), (args, p.returncode, p.stdout, p.stderr)
            assert not p.stderr, p.stderr
            return p.stdout.strip()

        def git_run(*args, cwd=root):
            subprocess.run([git, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', *args],
                           cwd=cwd, env=env, check=True, capture_output=True, timeout=20)

        def write_config(directory, servers, filename='.mcp.json'):
            path = directory / filename
            path.write_text(json.dumps({'mcpServers': servers}))
            return path

        user = {'foldkit-devtools': {'url': 'https://never-contact.example.invalid',
                'auth': {'type': 'oauth'}, 'disabledTools': ['probe']},
                'user-only': {'command': '/must/not/spawn'}}
        write_config(config, user, 'mcp.jsonc')
        (root / '.mcp.json').write_text('invalid but outside Git')
        assert 'user-only' in run('info')
        projects = [root / 'project a\nend ', root / 'project-b']
        sample = {'command': 'node', 'args': ['./node_modules/@foldkit/devtools-mcp/dist/server.js']}
        for project in projects:
            project.mkdir()
            git_run('init', '-q', str(project))
            peer = project / sample['args'][0]
            peer.parent.mkdir(parents=True)
            peer.write_text(PEER)
            write_config(project, {'foldkit-devtools': sample, 'project-only': {'command': '/must/not/spawn'}})
            (project / 'nested').mkdir()
            (project / 'nested' / '.mcp.json').write_text('must not shadow root')
        a, b = projects
        for label in ['A', 'B']:
            directory = root / ('bin-' + label)
            directory.mkdir()
            node = directory / 'node'
            node.write_text(f'#!{sys.executable}\nimport os,sys\nos.environ["MCPX_TEST_EXECUTABLE"]={label!r}\nos.execv(sys.executable, [sys.executable, *sys.argv[1:]])\n')
            node.chmod(0o755)
        env_a = dict(env, PATH=str(root / 'bin-A') + os.pathsep + env['PATH'],
                     FOLDKIT_DEVTOOLS_RELAY_DIRECTORY='relay-A', MCPX_TEST_DAEMON_ONLY='stale-secret')
        env_b = dict(env, PATH=str(root / 'bin-B') + os.pathsep + env['PATH'],
                     FOLDKIT_DEVTOOLS_RELAY_DIRECTORY='relay-B')
        env_b.pop('MCPX_TEST_DAEMON_ONLY', None)
        selected = run('info', cwd=a / 'nested')
        assert set(selected.splitlines()) == {'Servers:', '  foldkit-devtools', '  project-only', '  user-only'}, selected
        assert 'foldkit-devtools' in run('search', 'foldkit', cwd=a / 'nested')
        poisoned_git = dict(env_a, GIT_DIR=str(b / '.git'), GIT_WORK_TREE=str(b),
                            GIT_CEILING_DIRECTORIES=str(a / 'nested'))
        probe = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=a / 'nested', environment=poisoned_git))
        assert probe['cwd'] == str(a) and probe['relay'] == 'relay-A'
        assert probe['executable'] == 'A' and probe['calls'] == 1
        assert probe['gitDir'] == str(b / '.git'), 'Git cleanup must affect only the discovery child'
        # The original command-only shape works without user auth/filter inheritance.
        no_git = dict(env, PATH=str(root / 'bin-A'))
        assert set(run('info', cwd=a, environment=no_git).splitlines()) == {'Servers:', '  foldkit-devtools', '  user-only'}

        git_run('commit', '--allow-empty', '-qm', 'fixture', cwd=b)
        worktree = root / 'worktree'
        git_run('worktree', 'add', '--detach', str(worktree), 'HEAD', cwd=b)
        write_config(worktree, {'worktree-only': {'command': '/must/not/spawn'}})
        assert 'worktree-only' in run('info', cwd=worktree)
        git_run('-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(b), 'sub', cwd=a)
        submodule = a / 'sub'
        write_config(submodule, {'sub-only': {'command': '/must/not/spawn'}})
        assert 'sub-only' in run('info', cwd=submodule)
        bare = root / 'bare'
        git_run('init', '--bare', '-q', str(bare))
        assert 'user-only' in run('info', cwd=bare)
        broken = root / 'broken'
        broken.mkdir()
        (broken / '.git').write_text('gitdir: /does/not/exist\n')
        assert 'Git root' in run('info', cwd=broken, ok=False)
        fake_bin = root / 'fake-git-bin'
        fake_bin.mkdir()
        fake_git = fake_bin / 'git'
        fake_git.write_text('#!/bin/sh\nexec /bin/sleep 10\n')
        fake_git.chmod(0o755)
        assert 'Git root discovery timed out' in run('info', cwd=a,
            environment=dict(env, PATH=str(fake_bin)), ok=False)
        print('PASS: automatic roots, nested paths, Git overrides, worktree, submodule, non-Git, unavailable Git, broken Git')

        # Filesystem symlink/.. semantics must not be replaced by lexical cleanup.
        physical = root / 'physical'
        (physical / 'deep').mkdir(parents=True)
        for directory, marker in [(a, 'wrong-lexical-target'), (physical, 'physical-target')]:
            (directory / 'bin').mkdir()
            executable = directory / 'bin' / 'peer'
            executable.write_text(f'#!{sys.executable}\nimport os\nos.environ["MCPX_TEST_EXECUTABLE"]={marker!r}\n' + PEER)
            executable.chmod(0o755)
        (a / 'link').symlink_to(physical / 'deep', target_is_directory=True)
        for command in ['peer', 'link/../bin/peer', str(a / 'link/../bin/peer')]:
            write_config(a, {'foldkit-devtools': {'command': command, 'env': {'PATH': 'link/../bin'}}})
            result = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=a))
            assert result['executable'] == 'physical-target'
        for cwd in ['link/..', 'missing/..']:
            write_config(a, {'foldkit-devtools': {'command': str(physical / 'bin/peer'), 'cwd': cwd}})
            if cwd.startswith('missing'):
                run('call', 'foldkit-devtools', 'probe', cwd=a, ok=False)
            else:
                assert json.loads(run('call', 'foldkit-devtools', 'probe', cwd=a))['cwd'] == str(physical)
        print('PASS: executable/PATH/cwd preserve filesystem symlink parents; missing components cannot be erased')

        try:
            write_config(config, dict(user, **{'user-probe': {
                'command': sys.executable, 'args': [str(a / sample['args'][0])], 'lifecycle': 'keep-alive',
            }}), 'mcp.jsonc')
            user_first = json.loads(run('call', 'user-probe', 'probe', cwd=root, environment=env_a))
            user_next = json.loads(run('call', 'user-probe', 'probe', cwd=b / 'nested', environment=env_b))
            assert user_first['cwd'] == str(root) and user_next['cwd'] == str(b / 'nested')
            assert user_first['pid'] != user_next['pid'] and user_next['stale'] is None
            warm = dict(sample, lifecycle='keep-alive')
            write_config(a, {'foldkit-devtools': warm})
            first = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=a, environment=env_a))
            second = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=a / 'nested', environment=env_b))
            again = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=a, environment=env_b))
            assert first['pid'] != second['pid'] == again['pid']
            assert second['cwd'] == str(a) and second['relay'] == 'relay-B'
            assert second['executable'] == 'B' and second['stale'] is None and second['daemonFlag'] is None
            assert again['calls'] == 2
            write_config(b, {'foldkit-devtools': warm})
            other = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=b, environment=env_b))
            assert other['pid'] != second['pid'] and other['cwd'] == str(b)
            last = other
            for value, mode in [('A', 'stateful'), ('B', 'stateful'), ('B', 'stateless'), ('B', 'auto')]:
                overrides = {'OVERRIDE': value}
                if mode == 'auto':
                    overrides['MCPX_TEST_LEGACY'] = '1'
                write_config(b, {'foldkit-devtools': dict(warm, env=overrides, protocol={'mode': mode})})
                current = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=b, environment=env_b))
                assert current['pid'] != last['pid'] and current['override'] == value
                assert current['stale'] is None and current['daemonFlag'] is None
                last = current
            # Explicit PATH must select the executable, not only reach its environment.
            write_config(b, {'foldkit-devtools': dict(warm, env={'PATH': env_b['PATH']})})
            explicit_path = json.loads(run('call', 'foldkit-devtools', 'probe', cwd=b, environment=env_a))
            assert explicit_path['executable'] == 'B'
            working_link = root / 'working-link'
            working_link.symlink_to(a, target_is_directory=True)
            write_config(b, {'cwd-probe': {'command': sys.executable,
                'args': [str(a / sample['args'][0])], 'cwd': str(working_link), 'lifecycle': 'keep-alive'}})
            first_cwd = json.loads(run('call', 'cwd-probe', 'probe', cwd=b, environment=env_b))
            working_link.unlink()
            working_link.symlink_to(b, target_is_directory=True)
            next_cwd = json.loads(run('call', 'cwd-probe', 'probe', cwd=b, environment=env_b))
            assert first_cwd['cwd'] == str(a) and next_cwd['cwd'] == str(b)
            assert first_cwd['pid'] != next_cwd['pid']
            print('PASS: daemon uses invoking cwd/env/executable, excludes stale env, scopes reuse and includes env values/protocol')
        finally:
            run('daemon', 'stop')

        for project in projects:
            path = write_config(project, {'foldkit-devtools': sample})
            listing = json.loads(run('skills', 'foldkit-devtools', '--json', cwd=project, environment=env_a))
            assert listing['origin'] == identity(path, 'foldkit-devtools')
        print('PASS: same-name Skills origins retain the selected project source')

        requests = []
        class Handler(BaseHTTPRequestHandler):
            def reply(self, obj):
                data = json.dumps(obj).encode()
                self.send_response(200)
                self.send_header('content-type', 'application/json')
                self.send_header('content-length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                self.reply({'authorization_endpoint': url + '/authorize', 'token_endpoint': url + '/token'})

            def do_POST(self):
                requests.append((self.path, self.headers.get('Authorization'), self.headers.get_all('Authorization', [])))
                if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
                    parts = []
                    while True:
                        size = int(self.rfile.readline().split(b';')[0], 16)
                        if not size:
                            assert self.rfile.readline() == b'\r\n'
                            break
                        parts.append(self.rfile.read(size))
                        assert self.rfile.read(2) == b'\r\n'
                    body = b''.join(parts)
                else:
                    body = self.rfile.read(int(self.headers['Content-Length']))
                if self.path == '/token':
                    self.reply({'access_token': 'synthetic-token', 'token_type': 'Bearer'})
                else:
                    q = json.loads(body)
                    result = ({'resultType': 'complete', 'supportedVersions': ['2026-07-28'], 'capabilities': {'tools': {}}}
                              if q['method'] == 'server/discover' else
                              {'resultType': 'complete', 'tools': [], 'ttlMs': 0, 'cacheScope': 'private'})
                    self.reply({'jsonrpc': '2.0', 'id': q['id'], 'result': result})

            def log_message(self, *_):
                pass

        http = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{http.server_port}'
        auth = {'url': url + '/mcp', 'auth': {'type': 'oauth', 'clientId': 'fixture', 'metadataUrl': url + '/metadata'}}
        try:
            for project in projects:
                write_config(project, {'same': auth})
            write_config(config, dict(user, same=auth), 'mcp.jsonc')
            states = [json.loads(run('auth', 'same', '--no-browser', '--json', cwd=p))['state'] for p in projects]
            credentials = json.loads((config / 'credentials.json').read_text())
            assert len(credentials['pendingOAuth']) == 2
            before = len(requests)
            assert 'pending OAuth flow not found' in run('auth', 'same', '--code', 'fixture', '--state', states[0], cwd=b, ok=False)
            assert len(requests) == before
            run('auth', 'same', '--code', 'fixture', '--state', states[0], cwd=a)
            run('info', 'same', cwd=a)
            assert requests[-1][1] == 'Bearer synthetic-token'
            before = len(requests)
            assert 'mcpx auth same' in run('info', 'same', cwd=b, ok=False)
            assert 'mcpx auth same' in run('info', 'same', cwd=root, ok=False)
            assert len(requests) == before
            for header in ['AUTHORIZATION', 'aUtHoRiZaTiOn']:
                write_config(b, {'same': dict(auth, headers={header: 'Bearer explicit-fixture'})})
                run('info', 'same', cwd=b)
                assert requests[-1][1] == 'Bearer explicit-fixture'
            write_config(b, {'same': auth})
            run('auth', 'same', '--code', 'fixture', '--state', states[1], cwd=b)
            run('info', 'same', cwd=b)
            assert len(json.loads((config / 'credentials.json').read_text())['entries']) == 2
            write_config(b, {'same': dict(auth, headers={'aUtHoRiZaTiOn': 'Bearer explicit-fixture'})})
            run('info', 'same', cwd=b)
            assert requests[-1][2] == ['Bearer explicit-fixture'], 'cached bearer must not add a second Authorization header'
            write_config(b, {'same': auth})
            pending = json.loads(run('auth', 'same', '--no-browser', '--json', cwd=a))['state']
            write_config(a, {'same': dict(auth, url=url + '/changed')})
            before = len(requests)
            assert 'mcpx auth same' in run('info', 'same', cwd=a, ok=False)
            assert 'endpoint changed' in run('auth', 'same', '--code', 'fixture', '--state', pending, cwd=a, ok=False)
            assert len(requests) == before
            print('PASS: OAuth start/completion/lookup isolate source and endpoint; no cross-scope token or code exchange')

            invalid = a / 'mcp.jsonc'
            invalid.write_text('invalid preferred config')
            for args in [('info',), ('search', 'same'), ('info', 'same')]:
                assert str(invalid) in run(*args, cwd=a, ok=False)
            invalid.write_text(json.dumps({'mcpServers': {'bad': {'transport': 'sse', 'url': url}}}))
            assert 'unsupported transport: sse' in run('search', 'bad', cwd=a, ok=False)
            for args in [('--help',), ('--version',), ('daemon', 'status'), ('info', url + '/mcp')]:
                run(*args, cwd=a)
            invalid.unlink()
            invalid.symlink_to(root / 'missing-config')
            assert str(invalid) in run('search', 'same', cwd=a, ok=False)
            invalid.unlink()
            invalid.mkdir()
            assert str(invalid) in run('info', cwd=a, ok=False)
            invalid.rmdir()
            if os.geteuid() != 0:
                invalid.write_text('{"mcpServers":{}}')
                invalid.chmod(0)
                try:
                    assert str(invalid) in run('info', cwd=a, ok=False)
                finally:
                    invalid.chmod(0o600)
            print('PASS: selected-file failures are not hidden; direct URLs/help/version/daemon control bypass config')
        finally:
            http.shutdown()
            http.server_close()
            thread.join()


if __name__ == '__main__':
    main()
