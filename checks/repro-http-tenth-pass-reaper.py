"""Tenth-pass HTTP reproducer: the idle reaper against connections that
close themselves while it sweeps.

Opens N idle connections and waits for the reaper (30-35 s). At the
first one the server closes, the client closes all the others itself
and at once opens fresh connections, each sending one GET. A fresh
connection is owed a 200: it is seconds old. Usage: reaper.py PORT [N]"""
import select, socket, sys, time

PORT = int(sys.argv[1])
N = int(sys.argv[2]) if len(sys.argv) > 2 else 6000
FRESH = 400

old = []
for i in range(N):
    s = socket.create_connection(("127.0.0.1", PORT))
    s.setblocking(False)
    old.append(s)
print("opened %d idle connections, waiting for the reaper" % N, flush=True)

ep = select.epoll()
for s in old:
    ep.register(s.fileno(), select.EPOLLIN)
t0 = time.time()
ep.poll(60)
print("first close from the server after %.1f s" % (time.time() - t0), flush=True)
ep.close()
for s in old:
    s.close()

ok, empty, reset, other = 0, 0, 0, 0
fresh = []
for i in range(FRESH):
    try:
        s = socket.create_connection(("127.0.0.1", PORT))
        s.sendall(b"GET /fresh HTTP/1.1\r\nHost: x\r\n\r\n")
        fresh.append(s)
    except OSError:
        other += 1
for s in fresh:
    s.settimeout(3)
    try:
        data = s.recv(4096)
        if data.startswith(b"HTTP/1.1 200"):
            ok += 1
        elif not data:
            empty += 1
        else:
            other += 1
    except ConnectionResetError:
        reset += 1
    except socket.timeout:
        other += 1
    s.close()
print("fresh connections: %d answered 200, %d closed with no response, %d reset, %d other"
      % (ok, empty, reset, other))
sys.exit(0 if ok == FRESH else 1)
