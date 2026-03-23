use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse, Response},
    routing::{get, post},
    Router,
};
use std::sync::Arc;
use tokio::sync::Mutex;

type Counter = Arc<Mutex<u32>>;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: {} <port>", args[0]);
        std::process::exit(1);
    }

    let port = args[1].parse::<u16>().expect("invalid port");
    let counter: Counter = Arc::new(Mutex::new(0));

    let app = Router::new()
        .route("/", get(root))
        .route("/increment", post(increment))
        .route("/sleep", get(sleep))
        .fallback(not_found)
        .with_state(counter);

    let listener = tokio::net::TcpListener::bind(format!("127.0.0.1:{}", port))
        .await
        .expect("failed to bind");

    axum::serve(listener, app)
        .await
        .expect("server error");
}

async fn root(State(counter): State<Counter>) -> impl IntoResponse {
    let c = *counter.lock().await;
    Html(format!(
        "<html><body>\n\
         <h1>Count: {}</h1>\n\
         <p>Press Ctrl-C for graceful shutdown</p>\n\
         <form method=\"POST\" action=\"/increment\">\n\
         <button type=\"submit\">Increment</button>\n\
         </form>\n\
         <footer><small>Rust | axum 0.7 / tokio 1 (single-threaded) / mio | epoll | async/await | cargo build --release</small></footer>\n\
         </body></html>",
        c
    ))
}

async fn increment(State(counter): State<Counter>) -> Response {
    {
        let mut c = counter.lock().await;
        *c += 1;
    }
    axum::response::Redirect::permanent("/").into_response()
}

async fn sleep(State(_counter): State<Counter>) -> impl IntoResponse {
    tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
    Html("<html><body><h1>Slept 1 second (via tokio::time::sleep)</h1></body></html>")
}

async fn not_found() -> impl IntoResponse {
    (
        StatusCode::NOT_FOUND,
        Html("<html><body><h1>Not Found</h1></body></html>"),
    )
}
