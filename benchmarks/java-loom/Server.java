import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpExchange;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

public class Server {
    private static final AtomicInteger count = new AtomicInteger(0);

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(args[0]);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());

        server.createContext("/", exchange -> {
            String method = exchange.getRequestMethod();
            String path = exchange.getRequestURI().getPath();

            if ("GET".equals(method) && "/".equals(path)) {
                handleRoot(exchange);
            } else if ("POST".equals(method) && "/increment".equals(path)) {
                handleIncrement(exchange);
            } else if ("GET".equals(method) && "/sleep".equals(path)) {
                handleSleep(exchange);
            } else {
                handleNotFound(exchange);
            }
        });

        server.start();
    }

    private static void handleRoot(HttpExchange exchange) throws IOException {
        String body = "<html><body>\n" +
            "<h1>Count: " + count.get() + "</h1>\n" +
            "<p>Press Ctrl-C for graceful shutdown</p>\n" +
            "<form method=\"POST\" action=\"/increment\">\n" +
            "<button type=\"submit\">Increment</button>\n" +
            "</form>\n" +
            "<footer><small>Java " + System.getProperty("java.version") +
            " | HttpServer (stdlib) | virtual threads | javac</small></footer>\n" +
            "</body></html>";
        sendResponse(exchange, 200, body);
    }

    private static void handleIncrement(HttpExchange exchange) throws IOException {
        exchange.getRequestBody().readAllBytes();
        count.incrementAndGet();
        exchange.getResponseHeaders().set("Location", "/");
        exchange.sendResponseHeaders(302, -1);
        exchange.close();
    }

    private static void handleSleep(HttpExchange exchange) throws IOException {
        try { Thread.sleep(1000); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        sendResponse(exchange, 200, "<html><body><h1>Slept 1 second (via Thread.sleep on virtual thread)</h1></body></html>");
    }

    private static void handleNotFound(HttpExchange exchange) throws IOException {
        sendResponse(exchange, 404, "<html><body><h1>Not Found</h1></body></html>");
    }

    private static void sendResponse(HttpExchange exchange, int code, String body) throws IOException {
        byte[] bytes = body.getBytes();
        exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
        exchange.sendResponseHeaders(code, bytes.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(bytes);
        }
    }
}
