"""Local-only real forwarding and lifecycle checks. No network settings changed."""
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import queue
import select
import socket
import socketserver
import struct
import subprocess
import threading
from pathlib import Path


def exact(sock, count):
    result = b""
    while len(result) < count:
        chunk = sock.recv(count - len(result))
        if not chunk:
            raise EOFError("Unexpected socket closure")
        result += chunk
    return result


def header(sock):
    data = b""
    while not data.endswith(b"\r\n\r\n"):
        data += exact(sock, 1)
        if len(data) > 32768:
            raise ValueError("Header too long")
    return data


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


BODY = b"FLVPcore actual proxy forwarding verified"


class Origin(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *_):
        pass


class Upstream(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        client.settimeout(5)
        if self.server.kind == "socks5":
            version, count = exact(client, 2)
            assert version == 5 and 0 in exact(client, count)
            client.sendall(b"\x05\x00")
            version, command, _, address_type = exact(client, 4)
            assert version == 5 and command == 1
            if address_type == 1:
                address = socket.inet_ntoa(exact(client, 4))
            elif address_type == 3:
                address = exact(client, exact(client, 1)[0]).decode()
            else:
                raise ValueError("Unexpected address family")
            port = struct.unpack("!H", exact(client, 2))[0]
        else:
            request = header(client).split(b"\r\n", 1)[0].decode()
            method, authority, _ = request.split()
            assert method == "CONNECT"
            address, port = authority.rsplit(":", 1)
            port = int(port)
        with socket.create_connection((address, port), timeout=5) as remote:
            self.server.hits += 1
            if self.server.kind == "socks5":
                client.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")
            else:
                client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            while True:
                readable, _, _ = select.select([client, remote], [], [], 5)
                if not readable:
                    return
                for source in readable:
                    data = source.recv(65536)
                    if not data:
                        return
                    (remote if source is client else client).sendall(data)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def request_through(mixed, origin, protocol):
    with socket.create_connection(("127.0.0.1", mixed), timeout=5) as sock:
        sock.settimeout(5)
        if protocol == "socks5":
            sock.sendall(b"\x05\x01\x00")
            assert exact(sock, 2) == b"\x05\x00"
            sock.sendall(b"\x05\x01\x00\x01\x7f\x00\x00\x01" + struct.pack("!H", origin))
            reply = exact(sock, 4)
            assert reply[:2] == b"\x05\x00", reply
            size = {1: 4, 4: 16}.get(reply[3])
            if size is None:
                size = exact(sock, 1)[0]
            exact(sock, size + 2)
            target = "/verified"
        elif protocol == "connect":
            sock.sendall(f"CONNECT 127.0.0.1:{origin} HTTP/1.1\r\nHost: 127.0.0.1:{origin}\r\n\r\n".encode())
            assert b"200" in header(sock).split(b"\r\n", 1)[0]
            target = "/verified"
        else:
            target = f"http://127.0.0.1:{origin}/verified"
        sock.sendall(f"GET {target} HTTP/1.1\r\nHost: 127.0.0.1:{origin}\r\nConnection: close\r\n\r\n".encode())
        response = b""
        while chunk := sock.recv(8192):
            response += chunk
        assert response.startswith(b"HTTP/1.0 200") or response.startswith(b"HTTP/1.1 200"), response
        assert response.endswith(BODY), response


def config(port, upstream=None):
    return {"mixed-port": port, "allow-lan": False, "bind-address": "127.0.0.1",
            "mode": "rule", "log-level": "warn", "ipv6": False, "dns": {"enable": False},
            "tun": {"enable": False, "auto-route": False},
            "proxies": [upstream] if upstream else [],
            "proxy-groups": [{"name": "PROXY", "type": "select", "proxies": ["node_test", "DIRECT"] if upstream else ["DIRECT"]}],
            "rules": ["MATCH,PROXY" if upstream else "MATCH,DIRECT"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", type=Path, default=Path(__file__).resolve().parents[1] /
                        "native/core-host/target/release/flvp-core-host.exe")
    args = parser.parse_args()
    process = subprocess.Popen([str(args.host.resolve())], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
    responses = queue.Queue()
    diagnostics = []
    threading.Thread(target=lambda: [responses.put(line) for line in process.stdout], daemon=True).start()
    threading.Thread(target=lambda: [diagnostics.append(line) for line in process.stderr], daemon=True).start()
    state = {"generation": 0, "appliedRevision": 0}
    checks = []

    def call(operation, config_value=None, revision=0, stale=False):
        arguments = {}
        if config_value is not None:
            text = json.dumps(config_value, separators=(",", ":"))
            arguments = {"config": text, "configHash": hashlib.sha256(text.encode()).hexdigest(), "revision": revision}
        envelope = {"requestId": str(len(checks)), "operation": operation,
                    "expectedGeneration": 999 if stale else state["generation"],
                    "expectedAppliedRevision": state["appliedRevision"], "arguments": arguments}
        process.stdin.write(json.dumps(envelope) + "\n")
        process.stdin.flush()
        response = json.loads(responses.get(timeout=20))
        current = response.get("result") if response["ok"] else response.get("status")
        if current and "state" in current:
            state.update(current)
        return response

    servers = []
    try:
        origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        servers.append(origin)
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        mixed = free_port()
        caps = call("capabilities")["result"]
        assert caps["ordinaryProxy"] and not caps["vpn"] and not caps["tun"] and not caps["systemProxy"]
        checks.append("truthful capabilities")
        assert call("start", config(mixed), 1)["ok"]
        for protocol in ("http", "connect", "socks5"):
            request_through(mixed, origin.server_port, protocol)
            checks.append(f"DIRECT via mixed {protocol}")
        revision = 1
        for kind in ("socks5", "http"):
            upstream = Server(("127.0.0.1", 0), Upstream)
            upstream.kind = kind
            upstream.hits = 0
            servers.append(upstream)
            threading.Thread(target=upstream.serve_forever, daemon=True).start()
            revision += 1
            candidate = config(mixed, {"name": "node_test", "type": kind, "server": "127.0.0.1",
                                       "port": upstream.server_address[1]})
            assert call("apply", candidate, revision)["ok"]
            request_through(mixed, origin.server_port, "socks5")
            assert upstream.hits == 1
            checks.append(f"PROXY via {kind} upstream")
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            occupied.listen()
            failed = call("apply", config(occupied.getsockname()[1]), revision + 1)
            assert not failed["ok"] and failed["error"]["rollbackStatus"] == "restored", failed
            assert state["appliedRevision"] == revision
            request_through(mixed, origin.server_port, "http")
            request_through(mixed, origin.server_port, "socks5")
        checks.append("failed apply restored working forwarding")
        assert call("stop", stale=True)["error"]["code"] == "STATE_CONFLICT"
        checks.append("stale stop rejected")
        assert call("status")["result"]["upload"] > 0
        checks.append("real traffic accounting")
        process.stdin.close()
        assert process.wait(timeout=8) == 0
        with socket.socket() as released:
            released.bind(("127.0.0.1", mixed))
        checks.append("EOF releases owned listener")
        print(json.dumps({"passed": len(checks), "checks": checks}, indent=2))
    except Exception:
        print("".join(diagnostics[-10:]))
        raise
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        for server in servers:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
