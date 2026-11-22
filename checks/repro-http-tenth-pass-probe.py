"""Tenth-pass HTTP probes: one raw request each, printing every byte the
server sent back before it went quiet or closed. Usage: probe.py PORT"""
import socket, sys, time

PORT = int(sys.argv[1])

def probe(name, payload, wait=0.6):
    s = socket.create_connection(("127.0.0.1", PORT))
    s.sendall(payload)
    s.settimeout(wait)
    out, closed = b"", False
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                closed = True
                break
            out += chunk
    except socket.timeout:
        pass
    except ConnectionResetError:
        closed = "reset"
    s.close()
    statuses = [l for l in out.split(b"\r\n") if l.startswith(b"HTTP/1.1 ")]
    bodies = [l for l in out.split(b"\n") if l.startswith(b"M=")]
    print("-- %s" % name)
    print("   responses: %s" % [x.decode() for x in statuses])
    print("   dispatched: %s" % [x.decode() for x in bodies])
    print("   connection: %s, %d bytes back" % (
        {True: "closed by server", False: "left open", "reset": "reset"}[closed], len(out)))
    return out

H = b"Host: x\r\n"
probe("baseline GET", b"GET /a/b HTTP/1.1\r\n" + H + b"\r\n")
probe("chunked body: one request sent, 5 bytes 'hello' in one chunk",
      b"POST /upload HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n"
      b"5\r\nhello\r\n0\r\n\r\n")
probe("chunked body carrying a request line: one request sent",
      b"POST /upload HTTP/1.1\r\n" + H + b"Transfer-Encoding: chunked\r\n\r\n"
      b"GET /smuggled HTTP/1.1\r\n" + H + b"\r\n")
probe("Content-Length 4 and Transfer-Encoding chunked together",
      b"POST /upload HTTP/1.1\r\n" + H + b"Content-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n"
      b"0\r\n\r\nGET /smuggled HTTP/1.1\r\n" + H + b"\r\n")
probe("two Content-Length headers, 0 then 36",
      b"POST /upload HTTP/1.1\r\n" + H + b"Content-Length: 0\r\nContent-Length: 36\r\n\r\n"
      b"GET /smuggled HTTP/1.1\r\n" + H + b"\r\n")
probe("Content-Length: +5", b"POST /u HTTP/1.1\r\n" + H + b"Content-Length: +5\r\n\r\nhello")
probe("Content-Length: -1", b"POST /u HTTP/1.1\r\n" + H + b"Content-Length: -1\r\n\r\nhello")
probe("Content-Length: 5, 5", b"POST /u HTTP/1.1\r\n" + H + b"Content-Length: 5, 5\r\n\r\nhello")
probe("Content-Length: 0x5", b"POST /u HTTP/1.1\r\n" + H + b"Content-Length: 0x5\r\n\r\nhello")
out = probe("HEAD", b"HEAD /a HTTP/1.1\r\n" + H + b"\r\n")
print("   bytes after the head: %r" % out.split(b"\r\n\r\n", 1)[-1])
probe("malformed percent escape in the path", b"GET /%zz HTTP/1.1\r\n" + H + b"\r\n")
probe("truncated percent escape in the path", b"GET /a% HTTP/1.1\r\n" + H + b"\r\n")
probe("malformed percent escape in the query", b"GET /a?k=%zz HTTP/1.1\r\n" + H + b"\r\n")
probe("invalid UTF-8 in the path", b"GET /\xff\xfe HTTP/1.1\r\n" + H + b"\r\n")
probe("NUL in the path", b"GET /a%00b HTTP/1.1\r\n" + H + b"\r\n")
probe("HTTP/1.0 without keep-alive", b"GET /a HTTP/1.0\r\n\r\n")
probe("bare LF line endings", b"GET /a HTTP/1.1\nHost: x\n\n")
probe("unknown method", b"BREW /pot HTTP/1.1\r\n" + H + b"\r\n")
probe("absolute-form target", b"GET http://x/a/b?c=d HTTP/1.1\r\n" + H + b"\r\n")
probe("space before the colon", b"GET /a HTTP/1.1\r\n" + H + b"Content-Length : 5\r\n\r\nhello")
