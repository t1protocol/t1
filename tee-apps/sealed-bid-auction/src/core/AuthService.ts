import crypto from "node:crypto";
import {hashMessage, recoverAddress} from "viem";
import type {AuthAttempt} from "../api/types.ts";

export class AuthService {
    private readonly authenticatedSolvers: Set<string> = new Set();
    private readonly nonces: Map<string, string> = new Map();

    public isLoggedIn(solverAddress: string) {
        return this.authenticatedSolvers.has(solverAddress);
    }

    public async login(authAttempt: AuthAttempt): Promise<{solverAddress: string, username: string} | null> {
        const key = authAttempt.username.toLowerCase();

        let solverAddress: string;
        try {
            const hash = hashMessage(authAttempt.blobHeader);
            solverAddress = await recoverAddress({ hash, signature: authAttempt.sig });
        } catch (err) {
            return null;
        }

        solverAddress = solverAddress.toLowerCase();

        if (!this.consumeNonce(key, authAttempt.nonce)) {
            return null;
        }
        this.authenticatedSolvers.add(solverAddress);

        console.log(`WebSocket auth success for user "${authAttempt.username}" with address ${solverAddress}`);

        return {solverAddress, username: authAttempt.username};
    }

    public logout(solverAddress: string) {
        this.authenticatedSolvers.delete(solverAddress);
    }

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