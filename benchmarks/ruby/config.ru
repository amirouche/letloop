$count = 0

app = proc do |env|
  method = env["REQUEST_METHOD"]
  path = env["PATH_INFO"]

  case [method, path]
  when ["GET", "/"]
    body = "<html><body>\n" \
           "<h1>Count: #{$count}</h1>\n" \
           "<p>Press Ctrl-C for graceful shutdown</p>\n" \
           "<form method=\"POST\" action=\"/increment\">\n" \
           "<button type=\"submit\">Increment</button>\n" \
           "</form>\n" \
           "<footer><small>Ruby #{RUBY_VERSION} | Falcon (async) | fibers | single-process</small></footer>\n" \
           "</body></html>"
    [200, {"content-type" => "text/html; charset=utf-8"}, [body]]

  when ["POST", "/increment"]
    $count += 1
    [302, {"location" => "/"}, [""]]

  when ["GET", "/sleep"]
    sleep 1
    [200, {"content-type" => "text/html; charset=utf-8"},
     ["<html><body><h1>Slept 1 second (via Async::Task sleep)</h1></body></html>"]]

  else
    [404, {"content-type" => "text/html; charset=utf-8"},
     ["<html><body><h1>Not Found</h1></body></html>"]]
  end
end

run app
