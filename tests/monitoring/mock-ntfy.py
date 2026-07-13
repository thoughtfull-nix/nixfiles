import http.server


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        title = self.headers.get("X-Title", "")
        tags = self.headers.get("X-Tags", "")
        with open("/tmp/requests.log", "ab") as f:
            f.write(
                self.path.encode()
                + b"\ntitle="
                + title.encode()
                + b"\ntags="
                + tags.encode()
                + b"\n"
                + body
                + b"\n---\n"
            )
        # The ntfy client JSON-decodes the response body as a publish ack,
        # so an empty body makes it fail with an "EOF" decode error.
        response = b'{"id":"test","time":0,"event":"message","topic":"test-topic"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format, *args):
        pass


http.server.HTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
