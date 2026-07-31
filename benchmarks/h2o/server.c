#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "h2o.h"
#include "h2o/http1.h"

static int count = 0;
static h2o_globalconf_t config;
static h2o_context_t ctx;
static h2o_accept_ctx_t accept_ctx;

static int handle_request(h2o_handler_t *self, h2o_req_t *req)
{
    int is_get = h2o_memis(req->method.base, req->method.len, H2O_STRLIT("GET"));
    int is_post = h2o_memis(req->method.base, req->method.len, H2O_STRLIT("POST"));

    if (is_get && h2o_memis(req->path_normalized.base, req->path_normalized.len, H2O_STRLIT("/"))) {
        char body[512];
        int len = snprintf(body, sizeof(body),
            "<html><body>\n"
            "<h1>Count: %d</h1>\n"
            "<p>Press Ctrl-C for graceful shutdown</p>\n"
            "<form method=\"POST\" action=\"/increment\">\n"
            "<button type=\"submit\">Increment</button>\n"
            "</form>\n"
            "<footer><small>C | h2o (libh2o-evloop) | evloop | single-threaded | gcc</small></footer>\n"
            "</body></html>", count);
        req->res.status = 200;
        req->res.reason = "OK";
        /* Declare the body length: without it h2o frames the response
         * as Transfer-Encoding: chunked, unlike every other
         * implementation in the suite which sends Content-Length. */
        req->res.content_length = len;
        h2o_add_header(&req->pool, &req->res.headers, H2O_TOKEN_CONTENT_TYPE, NULL,
                       H2O_STRLIT("text/html; charset=utf-8"));
        h2o_send_inline(req, body, len);
        return 0;
    }

    if (is_post && h2o_memis(req->path_normalized.base, req->path_normalized.len, H2O_STRLIT("/increment"))) {
        count++;
        req->res.status = 302;
        req->res.reason = "Found";
        req->res.content_length = 0;
        h2o_add_header(&req->pool, &req->res.headers, H2O_TOKEN_LOCATION, NULL,
                       H2O_STRLIT("/"));
        h2o_send_inline(req, H2O_STRLIT(""));
        return 0;
    }

    if (is_get && h2o_memis(req->path_normalized.base, req->path_normalized.len, H2O_STRLIT("/sleep"))) {
        sleep(1);
        req->res.status = 200;
        req->res.reason = "OK";
        req->res.content_length = sizeof("<html><body><h1>Slept 1 second (via sleep)</h1></body></html>") - 1;
        h2o_add_header(&req->pool, &req->res.headers, H2O_TOKEN_CONTENT_TYPE, NULL,
                       H2O_STRLIT("text/html; charset=utf-8"));
        h2o_send_inline(req, H2O_STRLIT("<html><body><h1>Slept 1 second (via sleep)</h1></body></html>"));
        return 0;
    }

    req->res.status = 404;
    req->res.reason = "Not Found";
    req->res.content_length = sizeof("<html><body><h1>Not Found</h1></body></html>") - 1;
    h2o_add_header(&req->pool, &req->res.headers, H2O_TOKEN_CONTENT_TYPE, NULL,
                   H2O_STRLIT("text/html; charset=utf-8"));
    h2o_send_inline(req, H2O_STRLIT("<html><body><h1>Not Found</h1></body></html>"));
    return 0;
}

static void on_accept(h2o_socket_t *listener, const char *err)
{
    h2o_socket_t *sock;
    if (err != NULL)
        return;
    if ((sock = h2o_evloop_socket_accept(listener)) == NULL)
        return;
    h2o_accept(&accept_ctx, sock);
}

static int create_listener(int port)
{
    struct sockaddr_in addr;
    int fd, reuseaddr_flag = 1;

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(0x7f000001);
    addr.sin_port = htons(port);

    if ((fd = socket(AF_INET, SOCK_STREAM, 0)) == -1 ||
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseaddr_flag, sizeof(reuseaddr_flag)) != 0 ||
        bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 ||
        listen(fd, SOMAXCONN) != 0) {
        return -1;
    }

    h2o_socket_t *sock = h2o_evloop_socket_create(ctx.loop, fd, H2O_SOCKET_FLAG_DONT_READ);
    h2o_socket_read_start(sock, on_accept);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <port>\n", argv[0]);
        return 1;
    }

    int port = atoi(argv[1]);

    signal(SIGPIPE, SIG_IGN);

    h2o_config_init(&config);
    h2o_hostconf_t *hostconf = h2o_config_register_host(&config, h2o_iovec_init(H2O_STRLIT("default")), 65535);

    h2o_pathconf_t *pathconf = h2o_config_register_path(hostconf, "/", 0);
    h2o_handler_t *handler = h2o_create_handler(pathconf, sizeof(*handler));
    handler->on_req = handle_request;

    h2o_context_init(&ctx, h2o_evloop_create(), &config);
    accept_ctx.ctx = &ctx;
    accept_ctx.hosts = config.hosts;

    if (create_listener(port) != 0) {
        fprintf(stderr, "failed to listen on port %d: %s\n", port, strerror(errno));
        return 1;
    }

    while (h2o_evloop_run(ctx.loop, INT32_MAX) == 0)
        ;

    return 0;
}
