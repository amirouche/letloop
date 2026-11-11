"""Tenth-pass HTTP reproducer: the accept loop when the process is out
of file descriptors. Start the server under a low `ulimit -n`, then run
this: it holds more connections than the server can accept, and prints
the CPU time the server burns while it has nothing to do but wait.
Usage: emfile.py PORT SERVER_PID"""
import os, socket, sys, time

PORT, PID = int(sys.argv[1]), int(sys.argv[2])
TICK = os.sysconf("SC_CLK_TCK")

def cpu():
    f = open("/proc/%d/stat" % PID).read().rsplit(")", 1)[1].split()
    return (int(f[11]) + int(f[12])) / TICK

a = cpu(); time.sleep(3); b = cpu()
print("idle, no connections:      %.2f s of CPU in 3 s" % (b - a))
held = []
for i in range(120):
    s = socket.socket(); s.settimeout(1)
    try:
        s.connect(("127.0.0.1", PORT)); held.append(s)
    except OSError:
        break
time.sleep(0.5)
a = cpu(); time.sleep(3); b = cpu()
print("out of descriptors, idle:  %.2f s of CPU in 3 s (%d connections held)" % (b - a, len(held)))
for s in held:
    s.close()
time.sleep(1)
s = socket.create_connection(("127.0.0.1", PORT)); s.settimeout(3)
s.sendall(b"GET /after HTTP/1.1\r\nHost: x\r\n\r\n")
try:
    print("after they close:          %r" % s.recv(200).split(b"\r\n")[0])
except Exception as e:
    print("after they close:          no answer (%s)" % e)
