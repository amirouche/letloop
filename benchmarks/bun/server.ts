let count = 0;

const port = parseInt(Bun.argv[2]);
if (!port) {
  console.error("usage: bun server.ts <port>");
  process.exit(1);
}

Bun.serve({
  port,
  hostname: "127.0.0.1",
  fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/" && (req.method === "GET" || req.method === "HEAD")) {
      return new Response(
        `<html><body>
<h1>Count: ${count}</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method="POST" action="/increment">
<button type="submit">Increment</button>
</form>
<footer><small>JavaScript | Bun ${Bun.version} | Bun.serve (builtin) | epoll | async/await</small></footer>
</body></html>`,
        { headers: { "Content-Type": "text/html; charset=utf-8" } },
      );
    }

    if (url.pathname === "/increment" && req.method === "POST") {
      count++;
      return new Response(null, {
        status: 302,
        headers: { Location: "/" },
      });
    }

    if (url.pathname === "/sleep" && req.method === "GET") {
      return new Promise((resolve) =>
        setTimeout(
          () =>
            resolve(
              new Response(
                "<html><body><h1>Slept 1 second (via setTimeout)</h1></body></html>",
                { headers: { "Content-Type": "text/html; charset=utf-8" } },
              ),
            ),
          1000,
        ),
      );
    }

    return new Response("<html><body><h1>Not Found</h1></body></html>", {
      status: 404,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  },
});
