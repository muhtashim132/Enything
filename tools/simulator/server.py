#!/usr/bin/env python3
"""
Enything 100x Realtime Multi-Shop Simulation Server (Bandipora)
Serves the simulator GUI on http://localhost:8899 and provides
environment configuration (Supabase URL, Anon Key, Mapbox token) to the browser.
"""

import http.server
import socketserver
import json
import os
from pathlib import Path

PORT = 8899
BASE_DIR = Path(__file__).resolve().parent

def load_env():
    env_vars = {
        "SUPABASE_URL": os.environ.get("SUPABASE_URL", "https://hvtujaatwhyxielrlztr.supabase.co"),
        "SUPABASE_ANON_KEY": os.environ.get("SUPABASE_ANON_KEY", ""),
        "MAPBOX_TOKEN": os.environ.get("MAPBOX_TOKEN", ""),
        "ORS_API_KEY": os.environ.get("ORS_API_KEY", "")
    }
    env_file = BASE_DIR.parent.parent / ".env"
    if env_file.exists():
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env_vars[k.strip()] = v.strip()
    return env_vars

ENV = load_env()

class SimulatorHTTPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BASE_DIR), **kwargs)

    def do_GET(self):
        if self.path == "/config":
            body = json.dumps(ENV).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            http.server.SimpleHTTPRequestHandler.end_headers(self)
            self.wfile.write(body)
            return
        return super().do_GET()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, apikey")
        self.send_header("Content-Length", "0")
        http.server.SimpleHTTPRequestHandler.end_headers(self)

def run_server():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), SimulatorHTTPHandler) as httpd:
        print(f"\n" + "="*70)
        print(f"🚀 ENYTHING 100x REALTIME BANDIPORA SIMULATOR SERVER RUNNING")
        print(f"📡 URL: http://localhost:{PORT}")
        print(f"📍 Location: Bandipora, J&K (3 Shops + Customer + Rider)")
        print(f"="*70 + "\n")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down simulator server gracefully...")
            httpd.shutdown()

if __name__ == "__main__":
    run_server()
