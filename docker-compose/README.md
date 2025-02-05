# Setup

1. Currently we are using vanilla `reth`, so you only need to make sure you have `docker` installed.

2. Generate the JWT secret:  
   Use the provided script to create a secure JWT secret.

3. Configure the environment file:  
   - Use `env.tmp` as a template to create your `.env` file.  
   - Ensure all required variables are correctly populated.

4. Start the application:  
   Run the following command to start the services using Docker Compose:  
   ```bash
   docker compose --env-file ./reth/env.tmp --profile reth up -d
   ```
   To stop use
   ```bash
   docker compose --profile reth down
   ```
   To stop and delete volumes use
   ```bash
   docker compose --profile reth down -v
   ```

5. If you want to run your node with Blockscout
   ```
   docker compose --env-file ./reth/env.tmp --profile reth --profile blockscout up -d
   ```
   **Note**:
   If you are not accessing blockscout at `localhost`, you need to change `localhost` to the public IP/DNS you want to access it at in `./blockscout/envs/common-frontend.env` for the following fields: `NEXT_PUBLIC_API_HOST`, `NEXT_PUBLIC_STATS_API_HOST`, `NEXT_PUBLIC_APP_HOST`, `NEXT_PUBLIC_VISUALIZE_API_HOST`.
   
   To stop everything use
   ```bash
   docker compose --profile reth --profile blockscout down
   ```
   To stop and remove volumes use
   ```bash
   docker compose --profile reth --profile blockscout down -v
   ```

   To stop blockscout services only use
   ```bash
   docker compose --profile blockscout down
   ```
   To stop and remove volumes use
   ```bash
   docker compose --profile blockscout down -v
   ```

   You can also quickly restart blockscout wihout impacting reth
   ```bash
   docker compose --profile blockscout restart
   ```
