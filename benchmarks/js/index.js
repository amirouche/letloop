#!/usr/bin/env node

const http = require('http');
const url = require('url');

let count = 0;

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;

  if (pathname === '/' && (req.method === 'GET' || req.method === 'HEAD')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(`<html><body>
<h1>Count: ${count}</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method="POST" action="/increment">
<button type="submit">Increment</button>
</form>
<footer><small>JavaScript | Node.js ${process.version} | http (stdlib) / libuv ${process.versions.uv} | epoll</small></footer>
</body></html>`);
  } else if (pathname === '/increment' && req.method === 'POST') {
    count++;
    res.writeHead(302, { 'Location': '/' });
    res.end();
  } else if (pathname === '/sleep' && req.method === 'GET') {
    setTimeout(() => {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end('<html><body><h1>Slept 1 second (via setTimeout)</h1></body></html>');
    }, 1000);
  } else {
    res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end('<html><body><h1>Not Found</h1></body></html>');
  }
});

const port = process.argv[2];
if (!port) {
  console.error('usage: node index.js <port>');
  process.exit(1);
}

server.listen(parseInt(port), '127.0.0.1', () => {
  // Silence is golden
});
