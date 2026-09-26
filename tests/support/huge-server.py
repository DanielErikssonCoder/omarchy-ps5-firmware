#!/usr/bin/env python3
"""A stand-in source for the test suite.

Two routes, each hostile in the way this plugin has to survive:

  /declared   a reply that announces a size far past the plugin's limit
  /stream     a reply that announces no size at all and keeps sending until
              the client hangs up

It binds port 0 and writes the port it was given to the file named on the
command line, so a test never has to guess a free port. Standard library only,
and nothing outside 127.0.0.1 is touched.
"""

import http.server
import socketserver
import sys

BLOCK = 64 * 1024
STREAM_BYTES = 16 * 1024 * 1024


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):  # the suite prints its own lines
        pass

    def do_GET(self):
        if self.path == "/declared":
            # 512 MiB announced up front. The plugin must refuse this before a
            # single byte reaches the disk.
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(512 * 1024 * 1024))
            self.end_headers()
            return

        if self.path == "/stream":
            # No size announced, 16 MiB actually sent: the disk has to be
            # protected by the read side and not by the announcement.
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            block = b"0" * BLOCK
            try:
                for _ in range(STREAM_BYTES // BLOCK):
                    self.wfile.write(b"%x\r\n" % BLOCK + block + b"\r\n")
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                pass  # the client stopped reading, which is the point
            self.close_connection = True
            return

        self.send_error(404)


def main():
    port_file = sys.argv[1]
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler) as httpd:
        with open(port_file, "w", encoding="utf-8") as fh:
            fh.write(str(httpd.server_address[1]))
        httpd.serve_forever()


if __name__ == "__main__":
    main()
