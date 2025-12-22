# sealed-bid-auction

Sealed Bid auction implementation. Privacy of a bid is achieved by running the app inside a TEE - so the bids are protected even from a machine operator with admin rights.

### To install:
```bash
bun install
```
Save TLS key in `key.pem` and certificate in `cert.pem` . Consider using CloudFlare Origin Server Certificate (of course if you use CloudFlare) 

To configure:

```bash
cp .env.template .env
```
... and fill in the values in `.env`.

### To run:

Start server:
```bash
bun run server
```

Start a bot simulating two Solvers streaming prices:
```bash
bun run bot
```
