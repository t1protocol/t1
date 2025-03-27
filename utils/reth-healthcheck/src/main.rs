use axum::{routing::get, Router};
use std::net::SocketAddr;
use tokio::net::TcpListener;
use axum::{http::StatusCode, response::IntoResponse};

#[tokio::main]
async fn main() {
    let app = Router::new().route("/", get(healthcheck));

    let addr = SocketAddr::from(([0, 0, 0, 0], 8082));
    let listener = TcpListener::bind(addr).await.unwrap();
    println!("Listening on {}", addr);

    axum::serve(listener, app).await.unwrap();
}

async fn healthcheck() -> impl IntoResponse {
    let client = reqwest::Client::new();
    let payload = r#"{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}"#;

    let res = client
        .post("http://127.0.0.1:8545")
        .header("Content-Type", "application/json")
        .body(payload)
        .send()
        .await;

    match res {
        Ok(resp) if resp.status().is_success() => (StatusCode::OK, "OK"),
        _ => (StatusCode::INTERNAL_SERVER_ERROR, "reth unhealthy"),
    }
}
