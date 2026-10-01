"""A stand-in for an Agent Memory context's /mcp endpoint, for testing hooks.

Logs every request as a JSON line and answers JSON-RPC tools/call: recall
returns two hits (one empty, which the hook must drop), anything else an ok.
With "sse" as the third argument it answers as a server-sent event.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port, log_path = int(sys.argv[1]), sys.argv[2]
sse = len(sys.argv) > 3 and sys.argv[3] == "sse"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        with open(log_path, "a") as log:
            log.write(json.dumps({"path": self.path, "auth": self.headers.get("Authorization"), "body": body}) + "\n")
        if body.get("params", {}).get("name") == "recall":
            result = {"structuredContent": {"hits": [
                {"text": "The project deploys with   make release.", "source": "fact"},
                {"text": "", "source": "fact"},
            ]}}
        else:
            result = {"structuredContent": {"ok": True}}
        reply = json.dumps({"jsonrpc": "2.0", "id": body.get("id"), "result": result})
        if sse:
            out, kind = f"event: message\ndata: {reply}\n\n".encode(), "text/event-stream"
        else:
            out, kind = reply.encode(), "application/json"
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
