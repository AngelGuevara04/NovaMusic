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

def resolve_web_dir():
    candidates = [
        os.path.join(base_dir, "NovaMusic-PC"),
        os.path.join(base_dir, "Instaladores", "PC", "NovaMusic-PC"),
        os.path.join(base_dir, "build", "web"),
        os.path.join(base_dir, "_internal", "web"),
    ]
    if hasattr(sys, "_MEIPASS"):
        candidates.append(os.path.join(sys._MEIPASS, "web"))
    for c in candidates:
        if os.path.exists(os.path.join(c, "index.html")):
            return c
    return candidates[0]

web_dir = resolve_web_dir()

MUSIC_DIR = os.path.join(os.path.expanduser("~"), "Music", "NovaMusic")
try:
    os.makedirs(MUSIC_DIR, exist_ok=True)
except Exception:
    pass

_stream_cache = {}
_cache_lock = threading.Lock()

def normalize_key(raw: str) -> str:
    if not raw:
        return ""
    s = raw.lower()
    s = re.sub(r'\[.*?\]|\(.*?\)', '', s)
    s = re.sub(r'feat\..*|ft\..*', '', s)
    s = re.sub(r'official|video|audio|lyrics|en vivo|letra|remastered', '', s)
    for a, b in [('á', 'a'), ('é', 'e'), ('í', 'i'), ('ó', 'o'), ('ú', 'u'), ('ñ', 'n')]:
        s = s.replace(a, b)
    s = re.sub(r'[^a-z0-9]', '', s)
    return s.strip()

def get_local_music_files():
    dirs = [
        MUSIC_DIR,
        os.path.join(os.path.expanduser("~"), "Downloads", "NovaMusic"),
    ]
    results = []
    seen_norms = set()
    for d in dirs:
        if not os.path.exists(d):
            continue
        try:
            for fname in os.listdir(d):
                lower = fname.lower()
                if lower.endswith(('.mp3', '.m4a', '.wav', '.webm')):
                    full_path = os.path.join(d, fname)
                    if not os.path.isfile(full_path):
                        continue
                    title_part = os.path.splitext(fname)[0].replace('_', ' ').strip()
                    norm = normalize_key(title_part)
                    if norm and norm not in seen_norms:
                        seen_norms.add(norm)
                        results.append({
                            "filename": fname,
                            "title": title_part,
                            "norm": norm,
                            "path": full_path,
                            "size": os.path.getsize(full_path),
                        })
        except Exception:
            pass
    return results

def find_local_audio_file(query_or_title: str):
    target_norm = normalize_key(query_or_title)
    if not target_norm:
        return None
    files = get_local_music_files()
    for f in files:
        fnorm = f["norm"]
        if fnorm == target_norm:
            return f["path"]
        if len(fnorm) >= 6 and len(target_norm) >= 6:
            if fnorm in target_norm or target_norm in fnorm:
                return f["path"]
    return None

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
            with urllib.request.urlopen(search_req, timeout=10) as r:
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
        with urllib.request.urlopen(player_req, timeout=10) as r:
            data = json.loads(r.read().decode("utf-8"))
            streaming_data = data.get("streamingData", {})
            adaptive = streaming_data.get("adaptiveFormats", [])
            formats = streaming_data.get("formats", [])
            # Priorizar audio puro de alta calidad si está disponible, o muxed
            audio_candidates = [
                f for f in adaptive
                if f.get("url") and "audio" in f.get("mimeType", "")
            ]
            if audio_candidates:
                audio_candidates.sort(key=lambda x: x.get("bitrate", 0), reverse=True)
                stream_url = audio_candidates[0]["url"]
                with _cache_lock:
                    _stream_cache[cache_key] = {"url": stream_url, "ts": now}
                return stream_url
            for f in formats:
                if f.get("url"):
                    stream_url = f["url"]
                    with _cache_lock:
                        _stream_cache[cache_key] = {"url": stream_url, "ts": now}
                    return stream_url
    except Exception:
        pass
    return None

def build_safe_filename(title: str, artist: str) -> str:
    clean_title = (title or "Cancion").strip()
    clean_artist = (artist or "").strip()
    generic_artists = {"", "artistas desconocido", "artista desconocido", "desconocido", "novamusic", "en la nube ☁️", "en la nube", "<unknown>", "unknown"}
    if clean_artist.lower() not in generic_artists and clean_artist.lower() not in clean_title.lower():
        combined = f"{clean_artist} - {clean_title}"
    else:
        combined = clean_title
    safe = re.sub(r'[<>:"/\\|?*]', '', combined)
    safe = re.sub(r'\s+', ' ', safe).strip()
    return safe or f"NovaMusic_{int(time.time())}"

class NovaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=web_dir, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def _send_json(self, status_code: int, payload: dict):
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _serve_local_file(self, file_path: str):
        try:
            file_size = os.path.getsize(file_path)
            range_hdr = self.headers.get("Range")
            start = 0
            end = file_size - 1
            status = 200
            if range_hdr and range_hdr.startswith("bytes="):
                parts = range_hdr.replace("bytes=", "").split("-")
                if parts[0]:
                    start = int(parts[0])
                if len(parts) > 1 and parts[1]:
                    end = int(parts[1])
                if end >= file_size:
                    end = file_size - 1
                status = 206

            length = max(0, end - start + 1)
            self.send_response(status)
            self.send_header("Content-Type", "audio/mpeg" if file_path.lower().endswith(".mp3") else "audio/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(length))
            if status == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
            self.end_headers()

            with open(file_path, "rb") as f:
                f.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = f.read(min(65536, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
            return True
        except Exception:
            return False

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/api/local-songs":
            files = get_local_music_files()
            self._send_json(200, {
                "ok": True,
                "music_dir": MUSIC_DIR,
                "keys": [f["norm"] for f in files],
                "songs": files,
            })
            return

        if parsed.path == "/api/save-local":
            params = urllib.parse.parse_qs(parsed.query)
            vid = params.get("id", [""])[0].strip()
            q = params.get("q", [""])[0].strip()
            title = params.get("title", [""])[0].strip()
            artist = params.get("artist", [""])[0].strip()
            if not q:
                q = f"{title} {artist}".strip()

            safe_base = build_safe_filename(title or q, artist)
            dest_path = os.path.join(MUSIC_DIR, f"{safe_base}.mp3")

            if os.path.exists(dest_path) and os.path.getsize(dest_path) > 10240:
                self._send_json(200, {
                    "ok": True,
                    "cached": True,
                    "filename": f"{safe_base}.mp3",
                    "path": dest_path,
                    "norm": normalize_key(safe_base),
                })
                return

            stream_url = resolve_yt_stream(video_id=vid, query=q)
            if not stream_url:
                self._send_json(404, {"ok": False, "error": "No se encontró el stream de audio"})
                return

            try:
                os.makedirs(MUSIC_DIR, exist_ok=True)
                temp_path = dest_path + ".part"
                headers = {
                    "User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
                }
                req = urllib.request.Request(stream_url, headers=headers)
                with urllib.request.urlopen(req, timeout=25) as upstream, open(temp_path, "wb") as out_f:
                    while True:
                        chunk = upstream.read(65536)
                        if not chunk:
                            break
                        out_f.write(chunk)

                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    if os.path.exists(dest_path):
                        os.remove(dest_path)
                    os.replace(temp_path, dest_path)
                    self._send_json(200, {
                        "ok": True,
                        "filename": f"{safe_base}.mp3",
                        "path": dest_path,
                        "norm": normalize_key(safe_base),
                    })
                else:
                    self._send_json(500, {"ok": False, "error": "Archivo descargado vacío"})
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})
            return

        if parsed.path == "/api/download-file":
            params = urllib.parse.parse_qs(parsed.query)
            vid = params.get("id", [""])[0].strip()
            q = params.get("q", [""])[0].strip()
            title = params.get("title", [""])[0].strip()
            artist = params.get("artist", [""])[0].strip()
            if not q:
                q = f"{title} {artist}".strip()

            safe_base = build_safe_filename(title or q, artist)
            dest_path = os.path.join(MUSIC_DIR, f"{safe_base}.mp3")

            if not (os.path.exists(dest_path) and os.path.getsize(dest_path) > 10240):
                stream_url = resolve_yt_stream(video_id=vid, query=q)
                if not stream_url:
                    self.send_response(404)
                    self.end_headers()
                    return
                try:
                    os.makedirs(MUSIC_DIR, exist_ok=True)
                    headers = {
                        "User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
                    }
                    req = urllib.request.Request(stream_url, headers=headers)
                    with urllib.request.urlopen(req, timeout=25) as upstream, open(dest_path, "wb") as out_f:
                        while True:
                            chunk = upstream.read(65536)
                            if not chunk:
                                break
                            out_f.write(chunk)
                except Exception:
                    pass

            if os.path.exists(dest_path):
                try:
                    fsize = os.path.getsize(dest_path)
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/mpeg")
                    self.send_header("Content-Length", str(fsize))
                    encoded_name = urllib.parse.quote(f"{safe_base}.mp3")
                    self.send_header("Content-Disposition", f"attachment; filename=\"{safe_base}.mp3\"; filename*=UTF-8''{encoded_name}")
                    self.end_headers()
                    with open(dest_path, "rb") as f:
                        while True:
                            chunk = f.read(65536)
                            if not chunk:
                                break
                            self.wfile.write(chunk)
                    return
                except Exception:
                    pass
            self.send_response(404)
            self.end_headers()
            return

        if parsed.path == "/api/stream":
            params = urllib.parse.parse_qs(parsed.query)
            vid = params.get("id", [""])[0].strip()
            q = params.get("q", [""])[0].strip()

            # 1. Si ya está descargada en la PC, reproducirla directamente del disco duro (0 latencia y soporte offline)
            if q:
                local_file = find_local_audio_file(q)
                if local_file and os.path.exists(local_file):
                    if self._serve_local_file(local_file):
                        return

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
