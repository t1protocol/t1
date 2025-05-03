# End to end tests
## Setup

Run `bun install` to setup typechain

Run `cp .env.sample .env` and fill out `.env` with necessary params (contract addresses and such)

## Run tests
| ENV    | Command                   | Description                                                                                     |
|--------|---------------------------|-------------------------------------------------------------------------------------------------|
| Canary | `bun run test:e2e:canary` | Run inside `./t1/e2e`. We assume user has already ran docker environment and deployed smart contracts to run tests against Canary |
