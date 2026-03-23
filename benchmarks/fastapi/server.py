#!/usr/bin/env python3

import sys
import asyncio
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from starlette.staticfiles import StaticFiles

app = FastAPI()
count = 0


@app.get("/")
async def root():
    global count
    import platform
    return HTMLResponse(f"""<html><body>
<h1>Count: {count}</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method="POST" action="/increment">
<button type="submit">Increment</button>
</form>
<footer><small>Python {platform.python_version()} | FastAPI / uvicorn / uvloop | epoll | async/await</small></footer>
</body></html>""")


@app.post("/increment")
async def increment():
    global count
    count += 1
    return RedirectResponse(url="/", status_code=302)


@app.get("/sleep")
async def sleep_route():
    await asyncio.sleep(1)
    return HTMLResponse("<html><body><h1>Slept 1 second (via asyncio.sleep)</h1></body></html>")


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def catch_all(path: str):
    return HTMLResponse("<html><body><h1>Not Found</h1></body></html>", status_code=404)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: server.py <port>", file=sys.stderr)
        sys.exit(1)

    port = int(sys.argv[1])

    import uvicorn
    try:
        import uvloop
        asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
    except ImportError:
        pass

    uvicorn.run(
        app,
        host="127.0.0.1",
        port=port,
        log_level="critical",
        access_log=False,
    )
