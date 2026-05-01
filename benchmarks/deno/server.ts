let count = 0;

const port = parseInt(Deno.args[0]);
if (!port) {
  console.error("usage: deno run --allow-net server.ts <port>");
  Deno.exit(1);
}

Deno.serve({ port, hostname: "127.0.0.1" }, (req: Request): Response | Promise<Response> => {
  const url = new URL(req.url);

  if (url.pathname === "/" && (req.method === "GET" || req.method === "HEAD")) {
    return new Response(
      `<html><body>
<h1>Count: ${count}</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method="POST" action="/increment">
<button type="submit">Increment</button>
</form>
<footer><small>TypeScript | Deno ${Deno.version.deno} / V8 ${Deno.version.v8} | Deno.serve (builtin) / tokio | epoll | async/await</small></footer>
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
});
