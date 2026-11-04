import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = "VM diameter-adapter (IPv6), client=%s\n" % self.client_address[0]
        body += "".join("%s: %s\n" % (k, v) for k, v in self.headers.items())
        self.send_response(200); self.end_headers(); self.wfile.write(body.encode())
    def log_message(self, *a): pass
class S(HTTPServer):
    address_family = socket.AF_INET6
S(("::", 8000), H).serve_forever()
