use axum::{routing::get, Router};
use std::{net::SocketAddr, time::Duration};
use tokio::{net::TcpListener, time::timeout};

#[tokio::main]
async fn main() {
    let app = Router::new().route("/", get(healthcheck));

    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    let listener = TcpListener::bind(addr).await.unwrap();
    println!("Listening on {}", addr);

    axum::serve(listener, app).await.unwrap();
}

async fn healthcheck() -> &'static str {
    let client = reqwest::Client::new();
    let payload = r#"{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}"#;
    let res = timeout(
        Duration::from_secs(2),
        client
            .post("http://127.0.0.1:8545")
            .header("Content-Type", "application/json")
            .body(payload)
            .send(),
    )
    .await;

    match res {
        Ok(Ok(resp)) if resp.status().is_success() => "OK",
        _ => panic!("Reth node croaked 💔"),
    }
}
