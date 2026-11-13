#!/usr/bin/env python3
"""RustMod Forge build server: compiles generated native mods (.hnmod) on a PC.

A phone cannot rebuild Horizon, so RustMod Forge's Settings › Build can point at this server.
It runs `cargo check` of the mod's [api] crate as a member of a local Horizon checkout (the way
the launcher stages trait mods) and answers {"ran", "success", "log"}.

    git clone https://github.com/horizon-rust/horizon && cd horizon
    git checkout 6c4c0347f9926e3b1d5994e7fb8b1ba5e68ddf70   # the revision RustMod Forge targets
    cargo check -p horizon-client                            # warm the cache once
    FORGE_TOKEN=some-secret python3 forge-build-server.py --horizon /path/to/horizon --port 8787

Then expose it over HTTPS (or use http://10.x / 127.0.0.1 on a trusted LAN) and enter the URL and
token in the app. The server only compiles: it never runs the mod. Native mods are not sandboxed,
so only build code you are willing to compile on that machine.
"""
import argparse
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BYTES = 64 << 20
ID = re.compile(r"^[a-z0-9_]{1,64}$")


def check(horizon: str, data: bytes) -> dict:
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        manifest = json.loads(z.read("horizon-native.json"))
        mod_id = manifest["id"]
        if not ID.match(mod_id):
            return {"ran": False, "success": False, "log": "bad mod id"}
        with tempfile.TemporaryDirectory() as tmp:
            for name in z.namelist():
                parts = name.split("/")
                if name.startswith("/") or ".." in parts or "\\" in name:
                    return {"ran": False, "success": False, "log": f"refused path {name}"}
            z.extractall(tmp)
            api = os.path.join(tmp, "mixins", mod_id, "api")
            staged = os.path.join(horizon, "native-crates", f"rmf-{mod_id}")
            shutil.rmtree(staged, ignore_errors=True)
            shutil.copytree(api, staged)
            cargo_toml = os.path.join(staged, "Cargo.toml")
            text = open(cargo_toml).read()
            text = re.sub(r"horizon-client = \{[^}]*\}", 'horizon-client = { path = "../../crates/horizon-client" }', text)
            open(cargo_toml, "w").write(text)
            package = re.search(r'name = "([^"]+)"', text).group(1)
            root = os.path.join(horizon, "Cargo.toml")
            original = open(root).read()
            lock = os.path.join(horizon, "Cargo.lock")
            original_lock = open(lock).read() if os.path.exists(lock) else None
            member = f'"native-crates/rmf-{mod_id}"'
            try:
                if member not in original:
                    open(root, "w").write(original.replace("members = [", f"members = [\n    {member},", 1))
                proc = subprocess.run(["cargo", "check", "-p", package, "--message-format=short"], cwd=horizon,
                                      capture_output=True, text=True, timeout=3600)
                log = (proc.stdout + proc.stderr)[-20000:]
                return {"ran": True, "success": proc.returncode == 0, "log": log}
            finally:
                open(root, "w").write(original)
                if original_lock is not None:
                    open(lock, "w").write(original_lock)
                shutil.rmtree(staged, ignore_errors=True)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        token = os.environ.get("FORGE_TOKEN", "")
        if token and self.headers.get("Authorization") != f"Bearer {token}":
            return self.reply(401, {"ran": False, "success": False, "log": "unauthorized"})
        if self.path.rstrip("/") != "/check":
            return self.reply(404, {"ran": False, "success": False, "log": "not found"})
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BYTES:
            return self.reply(413, {"ran": False, "success": False, "log": "bad size"})
        try:
            self.reply(200, check(self.server.horizon, self.rfile.read(length)))
        except Exception as e:  # report, never crash the server
            self.reply(200, {"ran": False, "success": False, "log": f"{type(e).__name__}: {e}"})

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--horizon", required=True, help="a Horizon checkout at the targeted revision")
    p.add_argument("--port", type=int, default=8787)
    p.add_argument("--host", default="127.0.0.1")
    a = p.parse_args()
    server = ThreadingHTTPServer((a.host, a.port), Handler)
    server.horizon = os.path.abspath(a.horizon)
    print(f"RustMod Forge build server on {a.host}:{a.port}, Horizon at {server.horizon}")
    server.serve_forever()


if __name__ == "__main__":
    main()
