import crypto from "node:crypto";

export class AuthService {
    private readonly nonces: Map<string, string> = new Map();

    public nextNonce(username: string): string {
        const key = username.toLowerCase();
        let nonce = this.nonces.get(key);
        if (!nonce) {
            nonce = crypto.randomUUID();
            this.nonces.set(key, nonce);
        }

        return nonce;
    }

    public consumeNonce(key: string, expected: string): boolean {
        const current = this.nonces.get(key);
        if (!current || current !== expected) return false;
        this.nonces.set(key, crypto.randomUUID());

        return true;
    }
}