"""Explicit real WinINet integration checks; temporarily changes current-user LAN proxy.
Always restores the captured initial settings. No Internet requests are made.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import hashlib
import json
import os
from pathlib import Path
import queue
import socket
import subprocess
import tempfile
import threading
from verify_host import config, free_port

class Value(c.Union):
    _fields_ = [('number', w.DWORD), ('text', c.c_void_p), ('time', w.FILETIME)]
class Option(c.Structure):
    _fields_ = [('option', w.DWORD), ('value', Value)]
class List(c.Structure):
    _fields_ = [('size', w.DWORD), ('connection', c.c_void_p), ('count', w.DWORD),
                ('error', w.DWORD), ('options', c.POINTER(Option))]
inet = c.WinDLL('wininet', use_last_error=True)
kernel = c.WinDLL('kernel32', use_last_error=True)
inet.InternetQueryOptionW.argtypes = [c.c_void_p, w.DWORD, c.c_void_p, c.POINTER(w.DWORD)]
inet.InternetSetOptionW.argtypes = [c.c_void_p, w.DWORD, c.c_void_p, w.DWORD]
kernel.GlobalFree.argtypes = [c.c_void_p]
kernel.GlobalFree.restype = c.c_void_p

def read():
    opts = (Option * 4)()
    for o, n in zip(opts, [10, 2, 3, 4]): o.option = n
    data = List(c.sizeof(List), None, 4, 0, opts)
    size = w.DWORD(c.sizeof(data))
    assert inet.InternetQueryOptionW(None, 75, c.byref(data), c.byref(size)), 'WinINet read failed'
    strings = []
    for opt in opts[1:]:
        ptr = opt.value.text
        strings.append(c.wstring_at(ptr) if ptr else '')
        if ptr: kernel.GlobalFree(ptr)
    return dict(zip(['flags', 'proxy', 'bypass', 'pac'], [opts[0].value.number, *strings]))

def write(value):
    opts = (Option * 4)()
    for o, n in zip(opts, [1, 2, 3, 4]): o.option = n
    opts[0].value.number = value['flags']
    bufs = [c.create_unicode_buffer(value[k]) for k in ['proxy', 'bypass', 'pac']]
    for opt, buf in zip(opts[1:], bufs): opt.value.text = c.cast(buf, c.c_void_p).value
    data = List(c.sizeof(List), None, 4, 0, opts)
    assert inet.InternetSetOptionW(None, 75, c.byref(data), c.sizeof(data)), 'WinINet write failed'
    assert inet.InternetSetOptionW(None, 39, None, 0), 'WinINet notify failed'
    assert inet.InternetSetOptionW(None, 37, None, 0), 'WinINet refresh failed'
    assert read() == value, 'WinINet readback differs'

class Host:
    def __init__(self, exe, root):
        self.proc = subprocess.Popen([str(exe)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, encoding='utf-8', env={**os.environ, 'FLVP_APP_SUPPORT_DIR': str(root)})
        self.q = queue.Queue()
        threading.Thread(target=lambda: [self.q.put(line) for line in self.proc.stdout], daemon=True).start()
        self.state = {'generation': 0, 'appliedRevision': 0}
    def call(self, op, port=None, revision=0, stale=False):
        args = {}
        if port is not None:
            text = json.dumps(config(port), separators=(',', ':'))
            args = {'config': text, 'configHash': hashlib.sha256(text.encode()).hexdigest(), 'revision': revision}
        self.proc.stdin.write(json.dumps({'requestId': 'test', 'operation': op, 'arguments': args,
            'expectedGeneration': 999 if stale else self.state['generation'],
            'expectedAppliedRevision': self.state['appliedRevision']}) + '\n')
        self.proc.stdin.flush()
        result = json.loads(self.q.get(timeout=25))
        state = result.get('result') if result['ok'] else result.get('status')
        if state and 'state' in state: self.state = state
        return result
    def close(self):
        if self.proc.poll() is None:
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
    def kill(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait(timeout=10)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', type=Path, default=Path('native/core-host/target/debug/flvp-core-host.exe'))
    args = parser.parse_args()
    exe = args.host.resolve()
    original = read()
    hosts = []
    with tempfile.TemporaryDirectory(prefix='flvp-wininet-') as folder:
        root = Path(folder)
        # Private recovery artifact; values may include a user's PAC URL. Never print it.
        (root / 'original.json').write_text(json.dumps(original), encoding='utf-8')
        try:
            host = Host(exe, root); hosts.append(host)
            assert host.call('capabilities')['result']['systemProxy']
            second = Host(exe, root); hosts.append(second)
            assert not second.call('capabilities')['result']['systemProxy']
            assert not second.call('disableSystemProxy')['ok']
            second.close()
            assert not host.call('enableSystemProxy')['ok']
            print('PASS single owner and stopped-listener guard')
            synthetic = dict(flags=13, proxy='http=127.0.0.1:9', bypass='*.invalid;<local>', pac='http://127.0.0.1:9/test.pac')
            write(synthetic)
            port = free_port()
            assert host.call('start', port, 1)['ok']
            assert not host.call('enableSystemProxy', stale=True)['ok']
            assert host.call('enableSystemProxy')['ok']
            assert read()['flags'] == 3 and read()['proxy'] == f'127.0.0.1:{port}'
            assert host.call('disableSystemProxy')['ok']
            assert read() == synthetic
            print('PASS real PAC/WPAD/manual settings restore and stale mutation guard')
            assert host.call('enableSystemProxy')['ok']
            new_port = free_port()
            assert host.call('apply', new_port, 2)['ok']
            assert read()['proxy'] == f'127.0.0.1:{new_port}'
            with socket.socket() as occupied:
                occupied.bind(('127.0.0.1', 0)); occupied.listen()
                failed = host.call('apply', occupied.getsockname()[1], 3)
                assert not failed['ok'] and failed['error']['rollbackStatus'] == 'restored'
                assert read()['proxy'] == f'127.0.0.1:{new_port}'
            assert host.call('stop')['ok']
            assert read() == synthetic
            print('PASS port change, failed apply rollback and stop restore')
            assert host.call('start', port, 4)['ok']
            assert host.call('enableSystemProxy')['ok']
            host.close()
            assert read() == synthetic
            print('PASS EOF restores before releasing listener')
            host = Host(exe, root); hosts.append(host)
            assert host.call('start', port, 5)['ok']
            assert host.call('enableSystemProxy')['ok']
            host.kill()
            assert read()['proxy'] == f'127.0.0.1:{port}'
            result = subprocess.run([str(exe), '--recover-system-proxy'],
                env={**os.environ, 'FLVP_APP_SUPPORT_DIR': str(root)}, capture_output=True, timeout=15)
            assert result.returncode == 0 and read() == synthetic
            print('PASS crash recovery helper')
            host = Host(exe, root); hosts.append(host)
            assert host.call('start', port, 6)['ok']
            assert host.call('enableSystemProxy')['ok']
            host.kill()
            host = Host(exe, root); hosts.append(host)
            assert host.call('capabilities')['ok'] and read() == synthetic
            print('PASS next-start recovery')
            assert host.call('start', port, 7)['ok']
            assert host.call('enableSystemProxy')['ok']
            external = {**read(), 'proxy': '127.0.0.1:9'}
            write(external)
            assert not host.call('status')['result']['systemProxy']
            assert not host.call('disableSystemProxy')['ok']
            assert read() == external
            assert not host.call('stop')['ok']
            assert read() == external
            host.close()
            print('PASS external change never overwritten')
        finally:
            for host in hosts: host.kill()
            write(original)
            assert read() == original
            print('PASS original user settings restored')

if __name__ == '__main__': main()
