#!/usr/bin/env python3
"""A stand-in for Sony's update hosts, for the test suite.

Sony serves one small XML file per region. This server holds that directory
instead: a request for `/list/<code>/updatelist.xml` answers with `<dir>/<code>.xml`
when that file exists, and 404 when it does not. Every request path is appended to
the log file named on the command line, so a test can assert how often each region
was asked rather than only what came back.

That is enough to exercise every way a regional list can behave: a region that
answers, a region that answers with a version another region has not caught up
with, a region that answers with something that is not a list at all, a region
that answers with another region's list, and a region that does not answer.

Standard library only, binds port 0, writes its port to the file given, and
touches nothing outside 127.0.0.1.
"""

import http.server
import os
import socketserver
import sys
from urllib.parse import urlparse

ROOT = ""
LOG_PATH = ""


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):  # the suite prints its own lines
        pass

    def _log(self):
        if LOG_PATH:
            with open(LOG_PATH, "a", encoding="utf-8") as fh:
                fh.write(self.path + "\n")

    def do_GET(self):
        self._log()

        parts = [p for p in urlparse(self.path).path.split("/") if p]
        body = None
        if len(parts) == 3 and parts[0] == "list" and parts[2] == "updatelist.xml":
            candidate = os.path.join(ROOT, parts[1] + ".xml")
            if os.path.isfile(candidate):
                with open(candidate, "rb") as fh:
                    body = fh.read()

        if body is None:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    global ROOT, LOG_PATH
    port_file, ROOT, LOG_PATH = sys.argv[1], sys.argv[2], sys.argv[3]
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler) as httpd:
        with open(port_file, "w", encoding="utf-8") as fh:
            fh.write(str(httpd.server_address[1]))
        httpd.serve_forever()


if __name__ == "__main__":
    main()
