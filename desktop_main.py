import os
import sys
import json
import re
import time
import urllib.parse
import urllib.request
import threading
import http.server
import socket
import webview

PORT = 8085

def get_base_dir():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))

base_dir = get_base_dir()
web_dir = os.path.join(base_dir, "NovaMusic-PC")
if not os.path.exists(web_dir):
    web_dir = os.path.join(base_dir, "build", "web")

_stream_cache = {}
_cache_lock = threading.Lock()

def resolve_yt_stream(video_id="", query=""):
    cache_key = f"{video_id}|{query}".strip().lower()
    now = time.time()
    with _cache_lock:
        cached = _stream_cache.get(cache_key)
        if cached and (now - cached["ts"] < 1500):
            return cached["url"]

    try:
        if not video_id and query:
            search_req = urllib.request.Request(
                "https://www.youtube.com/youtubei/v1/search?prettyPrint=false",
                data=json.dumps({
                    "context": {
                        "client": {
                            "clientName": "WEB",
                            "clientVersion": "2.20250101.00.00"
                        }
                    },
                    "query": f"{query} official audio"
                }).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(search_req, timeout=8) as r:
                text = r.read().decode("utf-8", errors="ignore")
                m = re.search(r'"videoId":"([a-zA-Z0-9_-]{11})"', text)
                if m:
                    video_id = m.group(1)

        if not video_id:
            return None

        player_req = urllib.request.Request(
            "https://www.youtube.com/youtubei/v1/player?prettyPrint=false",
            data=json.dumps({
                "context": {
                    "client": {
                        "clientName": "ANDROID",
                        "clientVersion": "20.10.38",
                        "androidSdkVersion": 34
                    }
                },
                "videoId": video_id
            }).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
            },
        )
        with urllib.request.urlopen(player_req, timeout=8) as r:
            data = json.loads(r.read().decode("utf-8"))
            formats = data.get("streamingData", {}).get("formats", [])
            for f in formats:
                if f.get("url"):
                    stream_url = f["url"]
                    with _cache_lock:
                        _stream_cache[cache_key] = {"url": stream_url, "ts": now}
                    return stream_url
    except Exception:
        pass
    return None

class NovaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=web_dir, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/stream":
            params = urllib.parse.parse_qs(parsed.query)
            vid = params.get("id", [""])[0].strip()
            q = params.get("q", [""])[0].strip()
            stream_url = resolve_yt_stream(video_id=vid, query=q)
            if not stream_url:
                self.send_response(404)
                self.end_headers()
                return

            headers = {
                "User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
            }
            range_hdr = self.headers.get("Range")
            if range_hdr:
                headers["Range"] = range_hdr

            try:
                req = urllib.request.Request(stream_url, headers=headers)
                with urllib.request.urlopen(req, timeout=12) as upstream:
                    self.send_response(upstream.status)
                    self.send_header("Content-Type", upstream.headers.get("Content-Type", "audio/mp4"))
                    self.send_header("Accept-Ranges", "bytes")
                    if upstream.headers.get("Content-Length"):
                        self.send_header("Content-Length", upstream.headers.get("Content-Length"))
                    if upstream.headers.get("Content-Range"):
                        self.send_header("Content-Range", upstream.headers.get("Content-Range"))
                    self.end_headers()
                    while True:
                        chunk = upstream.read(65536)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
            except Exception:
                pass
            return

        return super().do_GET()

    def log_message(self, format, *args):
        pass

def start_local_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", PORT))
        s.close()
    except OSError:
        return

    http.server.ThreadingHTTPServer.allow_reuse_address = True
    try:
        with http.server.ThreadingHTTPServer(("127.0.0.1", PORT), NovaHandler) as httpd:
            httpd.serve_forever()
    except Exception:
        pass

if __name__ == "__main__":
    server_thread = threading.Thread(target=start_local_server, daemon=True)
    server_thread.start()

    window = webview.create_window(
        title="NovaMusic",
        url=f"http://127.0.0.1:{PORT}",
        width=1240,
        height=820,
        min_size=(920, 620),
        background_color="#121212",
        text_select=False,
    )

    webview.start(gui="edgechromium", debug=False)
    sys.exit(0)
