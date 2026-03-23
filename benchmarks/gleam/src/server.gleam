import argv
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/otp/actor
import mist.{type ResponseData}

pub type CounterMsg {
  Increment
  Get(process.Subject(Int))
}

fn handle_counter(
  state: Int,
  message: CounterMsg,
) -> actor.Next(Int, CounterMsg) {
  case message {
    Increment -> actor.continue(state + 1)
    Get(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
  }
}

fn handle_request(
  req: request.Request(mist.Connection),
  counter: process.Subject(CounterMsg),
) -> Response(ResponseData) {
  case req.method, request.path_segments(req) {
    http.Get, [] -> {
      let count =
        actor.call(counter, 1000, fn(reply) { Get(reply) })
      let body =
        "<html><body>\n<h1>Count: "
        <> int.to_string(count)
        <> "</h1>\n<p>Press Ctrl-C for graceful shutdown</p>\n<form method=\"POST\" action=\"/increment\">\n<button type=\"submit\">Increment</button>\n</form>\n<footer><small>Gleam | mist + gleam_otp | BEAM | schedulers=1 | gleam build</small></footer>\n</body></html>"
      response.new(200)
      |> response.set_header("content-type", "text/html; charset=utf-8")
      |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
    }

    http.Post, ["increment"] -> {
      process.send(counter, Increment)
      response.new(302)
      |> response.set_header("location", "/")
      |> response.set_body(mist.Bytes(bytes_tree.new()))
    }

    http.Get, ["sleep"] -> {
      process.sleep(1000)
      let body =
        "<html><body><h1>Slept 1 second (via process.sleep)</h1></body></html>"
      response.new(200)
      |> response.set_header("content-type", "text/html; charset=utf-8")
      |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
    }

    _, _ -> {
      response.new(404)
      |> response.set_header("content-type", "text/html; charset=utf-8")
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string(
          "<html><body><h1>Not Found</h1></body></html>",
        )),
      )
    }
  }
}

pub fn main() {
  let assert [port_str] = argv.load().arguments
  let assert Ok(port) = int.parse(port_str)

  let assert Ok(counter) =
    actor.new(0)
    |> actor.on_message(handle_counter)
    |> actor.start()

  let counter_subject = counter.data

  let assert Ok(_) =
    mist.new(fn(req) { handle_request(req, counter_subject) })
    |> mist.port(port)
    |> mist.start()

  process.sleep_forever()
}
