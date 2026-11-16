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

# Permitir reproducción remota inmediata sin requerir clic previo (Spotify Connect)
# y evitar que Windows/Edge suspenda los temporizadores cuando la ventana está en segundo plano
os.environ["WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"] = (
    "--autoplay-policy=no-user-gesture-required "
    "--disable-background-timer-throttling "
    "--disable-backgrounding-occluded-windows "
    "--disable-renderer-backgrounding"
)

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
                    fsize = os.path.getsize(full_path)
                    if fsize < 10240:
                        continue
                    title_part = os.path.splitext(fname)[0].replace('_', ' ').strip()
                    norm = normalize_key(title_part)
                    short_norm = ""
                    rev_norm = ""
                    if " - " in title_part:
                        parts = title_part.split(" - ", 1)
                        short_norm = normalize_key(parts[1])
                        rev_norm = normalize_key(f"{parts[1]} {parts[0]}")
                    if norm and norm not in seen_norms:
                        seen_norms.add(norm)
                        results.append({
                            "filename": fname,
                            "title": title_part,
                            "norm": norm,
                            "short_norm": short_norm,
                            "rev_norm": rev_norm,
                            "path": full_path,
                            "size": fsize,
                        })
        except Exception:
            pass
    return results

def find_local_audio_file(query_or_title: str, title: str = "", artist: str = ""):
    candidates = []
    if title and artist:
        candidates.append(normalize_key(build_safe_filename(title, artist)))
        candidates.append(normalize_key(f"{artist} {title}"))
        candidates.append(normalize_key(f"{title} {artist}"))
    if title:
        candidates.append(normalize_key(title))
    if query_or_title:
        candidates.append(normalize_key(query_or_title))

    candidates = [c for c in candidates if c]
    if not candidates:
        return None

    files = get_local_music_files()
    # 1. Coincidencia exacta por cualquiera de las llaves normalizadas
    for c in candidates:
        for f in files:
            if c == f["norm"] or (f.get("short_norm") and c == f["short_norm"]) or (f.get("rev_norm") and c == f["rev_norm"]):
                return f["path"]

    # 2. Coincidencia por subcadena para nombres largos
    for c in candidates:
        if len(c) < 5:
            continue
        for f in files:
            fnorm = f["norm"]
            snorm = f.get("short_norm") or ""
            if len(fnorm) >= 5 and (fnorm in c or c in fnorm):
                return f["path"]
            if len(snorm) >= 5 and (snorm in c or c in snorm):
                return f["path"]
    return None

def resolve_yt_stream(video_id="", query=""):
    cache_key = f"{video_id}|{query}".strip().lower()
    now = time.time()
    with _cache_lock:
        cached = _stream_cache.get(cache_key)
        if cached and (now - cached["ts"] < 1500):
            return cached["url"]

    android_ua = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
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

        if video_id:
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
                    "User-Agent": android_ua
                },
            )
            with urllib.request.urlopen(player_req, timeout=10) as r:
                data = json.loads(r.read().decode("utf-8"))
                streaming_data = data.get("streamingData", {})
                formats = streaming_data.get("formats", [])
                adaptive = streaming_data.get("adaptiveFormats", [])

                # IMPORTANTE: Priorizar `formats` (muxed MP4) porque `adaptiveFormats` en ANDROID
                # recibe bloqueo SABR (HTTP 403 Forbidden), mientras que `formats` responde 200 OK inmediato.
                candidate_urls = []
                for f in formats:
                    if f.get("url"):
                        candidate_urls.append(f["url"])
                audio_candidates = [
                    f for f in adaptive
                    if f.get("url") and "audio" in f.get("mimeType", "")
                ]
                audio_candidates.sort(key=lambda x: x.get("bitrate", 0), reverse=True)
                for f in audio_candidates:
                    candidate_urls.append(f["url"])

                for cand_url in candidate_urls:
                    try:
                        probe_req = urllib.request.Request(
                            cand_url,
                            headers={"User-Agent": android_ua, "Range": "bytes=0-64"},
                        )
                        with urllib.request.urlopen(probe_req, timeout=5) as pr:
                            if pr.status in (200, 206):
                                with _cache_lock:
                                    _stream_cache[cache_key] = {"url": cand_url, "ts": now}
                                return cand_url
                    except Exception:
                        continue
    except Exception:
        pass

    # Respaldo con yt_dlp si está disponible en el sistema
    try:
        import yt_dlp
        target = f"https://www.youtube.com/watch?v={video_id}" if video_id else f"ytsearch1:{query} official audio"
        ydl_opts = {
            "format": "bestaudio[ext=m4a]/bestaudio/best",
            "quiet": True,
            "no_warnings": True,
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(target, download=False)
            if "entries" in info and info["entries"]:
                info = info["entries"][0]
            dl_url = info.get("url")
            if dl_url:
                with _cache_lock:
                    _stream_cache[cache_key] = {"url": dl_url, "ts": now}
                return dl_url
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
            content_type = "audio/mpeg"
            try:
                with open(file_path, "rb") as hf:
                    head16 = hf.read(16)
                    if b"ftyp" in head16:
                        content_type = "audio/mp4"
                    elif b"OggS" in head16:
                        content_type = "audio/ogg"
                    elif b"\x1a\x45\xdf\xa3" in head16:
                        content_type = "audio/webm"
            except Exception:
                pass

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
            self.send_header("Content-Type", content_type)
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

        if parsed.path == "/api/session":
            params = urllib.parse.parse_qs(parsed.query)
            data_dir = os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "NovaMusic")
            os.makedirs(data_dir, exist_ok=True)
            session_file = os.path.join(data_dir, "session.json")

            if params.get("clear", [""])[0] == "1":
                try:
                    if os.path.exists(session_file):
                        os.remove(session_file)
                except Exception:
                    pass
                self._send_json(200, {"ok": True, "username": ""})
                return

            new_user = params.get("username", [""])[0].strip()
            if new_user:
                try:
                    with open(session_file, "w", encoding="utf-8") as sf:
                        json.dump({"username": new_user}, sf)
                except Exception:
                    pass
                self._send_json(200, {"ok": True, "username": new_user})
                return

            saved_user = ""
            try:
                if os.path.exists(session_file):
                    with open(session_file, "r", encoding="utf-8") as sf:
                        saved_user = (json.load(sf).get("username") or "").strip()
            except Exception:
                pass
            self._send_json(200, {"ok": True, "username": saved_user})
            return

        if parsed.path == "/api/app-update":
            params = urllib.parse.parse_qs(parsed.query)
            zip_url = params.get("url", [""])[0].strip()
            if not zip_url:
                self._send_json(400, {"ok": False, "error": "Falta URL de actualización"})
                return
            try:
                import tempfile
                import zipfile
                import shutil
                import subprocess

                tmp_root = os.path.join(tempfile.gettempdir(), "novamusic_pc_update")
                if os.path.exists(tmp_root):
                    shutil.rmtree(tmp_root, ignore_errors=True)
                os.makedirs(tmp_root, exist_ok=True)
                zip_path = os.path.join(tmp_root, "update.zip")
                extract_dir = os.path.join(tmp_root, "files")

                req = urllib.request.Request(zip_url, headers={"User-Agent": "NovaMusic-PC-Updater"})
                with urllib.request.urlopen(req, timeout=120) as resp, open(zip_path, "wb") as out_f:
                    while True:
                        chunk = resp.read(65536)
                        if not chunk:
                            break
                        out_f.write(chunk)

                with zipfile.ZipFile(zip_path, "r") as zf:
                    zf.extractall(extract_dir)

                exe_path = os.path.join(base_dir, "NovaMusic.exe")
                bat_path = os.path.join(tmp_root, "apply_update.bat")
                bat_content = (
                    "@echo off\n"
                    "timeout /t 2 /nobreak >nul\n"
                    "taskkill /f /im NovaMusic.exe >nul 2>&1\n"
                    "timeout /t 1 /nobreak >nul\n"
                    f"xcopy /E /Y /I \"{extract_dir}\\*\" \"{base_dir}\\\" >nul\n"
                    f"start \"\" \"{exe_path}\"\n"
                    "del \"%~f0\" >nul 2>&1\n"
                )
                with open(bat_path, "w", encoding="utf-8") as bf:
                    bf.write(bat_content)

                self._send_json(200, {"ok": True})

                def _launch_and_exit():
                    time.sleep(0.6)
                    subprocess.Popen(
                        ["cmd", "/c", bat_path],
                        creationflags=0x08000000,
                        close_fds=True,
                    )
                    time.sleep(0.3)
                    os._exit(0)

                threading.Thread(target=_launch_and_exit, daemon=True).start()
            except Exception as e:
                self._send_json(500, {"ok": False, "error": str(e)})
            return

        if parsed.path == "/api/local-songs":
            files = get_local_music_files()
            all_keys = []
            for f in files:
                if f.get("norm"):
                    all_keys.append(f["norm"])
                if f.get("short_norm"):
                    all_keys.append(f["short_norm"])
                if f.get("rev_norm"):
                    all_keys.append(f["rev_norm"])
            self._send_json(200, {
                "ok": True,
                "music_dir": MUSIC_DIR,
                "keys": list(dict.fromkeys(all_keys)),
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
            title = params.get("title", [""])[0].strip()
            artist = params.get("artist", [""])[0].strip()

            # 1. Si ya está descargada en la PC, reproducirla directamente del disco duro (0 latencia y soporte offline)
            local_file = find_local_audio_file(q, title=title, artist=artist)
            if local_file and os.path.exists(local_file):
                if self._serve_local_file(local_file):
                    return

            stream_url = resolve_yt_stream(video_id=vid, query=q or f"{title} {artist}".strip())
            if not stream_url:
                self.send_response(404)
                self.end_headers()
                return

            # Si no estaba guardada en Music/NovaMusic, guardarla automáticamente en segundo plano
            def _bg_cache_song():
                try:
                    safe_base = build_safe_filename(title or q, artist)
                    dest_path = os.path.join(MUSIC_DIR, f"{safe_base}.mp3")
                    if os.path.exists(dest_path) and os.path.getsize(dest_path) > 10240:
                        return
                    os.makedirs(MUSIC_DIR, exist_ok=True)
                    tmp_p = dest_path + ".bgpart"
                    bg_req = urllib.request.Request(
                        stream_url,
                        headers={"User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"},
                    )
                    with urllib.request.urlopen(bg_req, timeout=25) as up, open(tmp_p, "wb") as out_f:
                        while True:
                            ch = up.read(65536)
                            if not ch:
                                break
                            out_f.write(ch)
                    if os.path.exists(tmp_p) and os.path.getsize(tmp_p) > 10240:
                        if os.path.exists(dest_path):
                            os.remove(dest_path)
                        os.replace(tmp_p, dest_path)
                except Exception:
                    pass

            if title or q:
                threading.Thread(target=_bg_cache_song, daemon=True).start()

            headers = {
                "User-Agent": "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
            }
            range_hdr = self.headers.get("Range")
            if range_hdr:
                headers["Range"] = range_hdr

            try:
                req = urllib.request.Request(stream_url, headers=headers)
                with urllib.request.urlopen(req, timeout=12) as upstream:
                    ctype = upstream.headers.get("Content-Type", "audio/mp4")
                    if "video/mp4" in ctype:
                        ctype = ctype.replace("video/mp4", "audio/mp4")
                    self.send_response(upstream.status)
                    self.send_header("Content-Type", ctype)
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

    webview_storage = os.path.join(
        os.environ.get("LOCALAPPDATA", os.path.expanduser("~")),
        "NovaMusic",
        "WebViewData",
    )
    os.makedirs(webview_storage, exist_ok=True)
    webview.start(
        gui="edgechromium",
        debug=False,
        private_mode=False,
        storage_path=webview_storage,
    )
    sys.exit(0)
