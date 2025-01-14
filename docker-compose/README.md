# Setup

1. Refer to the Notion page for detailed setup instructions [WIP]. For now, use the following link: [GCP Devnet Setup](https://www.notion.so/t1protocol/GCP-devnet-setup-114231194dc3805897a6d53108141a6a).  
   **Note**:  
   - Do not run Kurtosis.
   - Installing Kurtosis is not required.

2. Generate the JWT secret:  
   Use the provided script to create a secure JWT secret.

3. Configure the environment file:  
   - Use `env.tmp` as a template to create your `.env` file.  
   - Ensure all required variables are correctly populated.

4. Start the application:  
   Run the following command to start the services using Docker Compose:  
   ```bash
   docker compose --env-file .env up -d
   ```
