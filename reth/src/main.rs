use reth::api::FullNodeComponents;
use reth_exex::ExExContext;
use reth_node_ethereum::EthereumNode;

async fn t1_exex<Node: FullNodeComponents>(mut _ctx: ExExContext<Node>) -> eyre::Result<()> {
    #[allow(clippy::empty_loop)]
    loop {}
}

fn main() -> eyre::Result<()> {
    reth::cli::Cli::parse_args().run(|builder, _| async move {
        let handle = builder
            .node(EthereumNode::default())
            .install_exex("t1",  |ctx| async move { Ok(t1_exex(ctx)) })
            .launch()
            .await?;

        handle.wait_for_node_exit().await
    })
}
