import type {BunRequest} from "bun";
import {AuthService} from "../core/AuthService.ts";
import type {AuthAttempt, AuthBlob} from "./types.ts";

export class AuthController {
    constructor(private readonly authService: AuthService) { }

    public async currentNonce(req: BunRequest): Promise<Response> {
        const username = new URL(req.url).searchParams.get("username");
        if (!username) {
            return new Response("Missing username", { status: 400 });
        }
        const body = JSON.stringify({ nonce: this.authService.nextNonce(username) });

        return new Response(body, { status: 200, headers: { "Content-Type": "application/json" } });
    }

    public validateAuthAttempt(blobHeader: string | null, sig: `0x${string}`): AuthAttempt | null {
        if (!blobHeader || !sig) {
            return null;
        }

        let authBlob: AuthBlob;
        try {
            authBlob = JSON.parse(blobHeader) as AuthBlob;
        } catch {
            return null;
        }

        const { username, nonce } = authBlob;
        if (!username || !nonce) {
            return null;
        }

        return {
            username, blobHeader, nonce, sig
        };
    }
}
