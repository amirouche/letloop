import io.vertx.core.Vertx;
import io.vertx.core.VertxOptions;
import io.vertx.core.http.HttpMethod;
import io.vertx.core.http.HttpServer;
import io.vertx.ext.web.Router;

public class Server {
    private static int count = 0;

    public static void main(String[] args) {
        int port = Integer.parseInt(args[0]);

        VertxOptions options = new VertxOptions().setEventLoopPoolSize(1);
        Vertx vertx = Vertx.vertx(options);
        Router router = Router.router(vertx);

        router.route(HttpMethod.GET, "/").handler(ctx -> {
            String body = "<html><body>\n" +
                "<h1>Count: " + count + "</h1>\n" +
                "<p>Press Ctrl-C for graceful shutdown</p>\n" +
                "<form method=\"POST\" action=\"/increment\">\n" +
                "<button type=\"submit\">Increment</button>\n" +
                "</form>\n" +
                "<footer><small>Java " + System.getProperty("java.version") +
                " | Vert.x | event-loop | single-threaded</small></footer>\n" +
                "</body></html>";
            ctx.response()
                .putHeader("content-type", "text/html; charset=utf-8")
                .end(body);
        });

        router.route(HttpMethod.POST, "/increment").handler(ctx -> {
            count++;
            ctx.response()
                .setStatusCode(302)
                .putHeader("location", "/")
                .end();
        });

        router.route(HttpMethod.GET, "/sleep").handler(ctx -> {
            vertx.setTimer(1000, id -> {
                ctx.response()
                    .putHeader("content-type", "text/html; charset=utf-8")
                    .end("<html><body><h1>Slept 1 second (via Vert.x timer)</h1></body></html>");
            });
        });

        router.route().handler(ctx -> {
            ctx.response()
                .setStatusCode(404)
                .putHeader("content-type", "text/html; charset=utf-8")
                .end("<html><body><h1>Not Found</h1></body></html>");
        });

        vertx.createHttpServer()
            .requestHandler(router)
            .listen(port, "127.0.0.1");
    }
}
