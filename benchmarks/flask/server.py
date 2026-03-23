#!/usr/bin/env python3

import sys
import platform
from flask import Flask, redirect, request

app = Flask(__name__)
count = 0


@app.route("/")
def root():
    global count
    return f"""<html><body>
<h1>Count: {count}</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method="POST" action="/increment">
<button type="submit">Increment</button>
</form>
<footer><small>Python {platform.python_version()} | Flask / gunicorn | sync workers</small></footer>
</body></html>"""


@app.post("/increment")
def increment():
    global count
    count += 1
    return redirect("/", code=302)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: server.py <port>", file=sys.stderr)
        sys.exit(1)

    port = int(sys.argv[1])
    app.run(host="127.0.0.1", port=port)
