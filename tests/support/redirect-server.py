#!/usr/bin/env python3
"""A stand-in source that answers with a redirect instead of a manifest.

Three routes, one per way this plugin has to behave when the source does not
answer where it said it would:

  /local     302 to a plain HTTP address on this machine. The target of a
             redirect is chosen by whoever answers, so this is the case the
             plugin refuses: talking to it would mean the reply decides which
             address on this machine or on the local network is contacted.
  /elsewhere 302 to another host, over https. Also refused: a redirect is a hop
             out of the host the settings named.
  /manifest  200 with the manifest given on the command line. The control case:
             no redirect, so the reading has to work exactly as before.

Every request path is appended to the log file named on the command line, so a
test can assert which addresses were actually contacted rather than only what
curl was asked to do. Binds port 0, writes its port to the file given, and
touches nothing outside 127.0.0.1. Standard library only.
"""

import http.server
import socketserver
import sys

MANIFEST_PATH = ""
LOG_PATH = ""
PORT = 0


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):  # the suite prints its own lines
        pass

    def _log(self):
        if LOG_PATH:
            with open(LOG_PATH, "a", encoding="utf-8") as fh:
                fh.write(self.path + "\n")

    def _redirect(self, location):
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

    def do_GET(self):
        self._log()

        if self.path == "/local":
            self._redirect("http://127.0.0.1:%d/manifest" % PORT)
            return

        if self.path == "/elsewhere":
            self._redirect("https://example.invalid/manifest")
            return

        if self.path == "/manifest":
            with open(MANIFEST_PATH, "rb") as fh:
                body = fh.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_error(404)


def main():
    global MANIFEST_PATH, LOG_PATH, PORT
    port_file, MANIFEST_PATH, LOG_PATH = sys.argv[1], sys.argv[2], sys.argv[3]
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler) as httpd:
        PORT = int(httpd.server_address[1])
        with open(port_file, "w", encoding="utf-8") as fh:
            fh.write(str(PORT))
        httpd.serve_forever()


if __name__ == "__main__":
    main()
