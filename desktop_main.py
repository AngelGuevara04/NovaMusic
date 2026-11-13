import os
import sys
import threading
import http.server
import socketserver
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

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=web_dir, **kwargs)

    def log_message(self, format, *args):
        pass

def start_local_server():
    # Comprobar si el puerto ya está en uso
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", PORT))
        s.close()
    except OSError:
        return  # Ya hay un servidor activo en 8085

    socketserver.TCPServer.allow_reuse_address = True
    try:
        with socketserver.TCPServer(("127.0.0.1", PORT), QuietHandler) as httpd:
            httpd.serve_forever()
    except Exception:
        pass

if __name__ == "__main__":
    # Iniciar servidor en hilo daemon
    server_thread = threading.Thread(target=start_local_server, daemon=True)
    server_thread.start()

    icon_path = os.path.join(base_dir, "app_icon.ico")
    if not os.path.exists(icon_path):
        icon_path = os.path.join(base_dir, "windows", "runner", "resources", "app_icon.ico")

    # Crear ventana nativa de Windows con WebView2
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
