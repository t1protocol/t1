import { keccak256 } from 'ethereumjs-util';
import assert from 'assert';

/**
 * A 32-byte hash stored in a Buffer.
 */
export type Hash = Buffer;

/**
 * keccak2:
 * Concatenate two 32-byte Buffers and compute their keccak256.
 * Returns a new 32-byte Buffer.
 */
export function keccak2(a: Hash, b: Hash): Hash {
  assert(Buffer.isBuffer(a) && a.length === 32, 'Hash "a" must be a 32-byte Buffer');
  assert(Buffer.isBuffer(b) && b.length === 32, 'Hash "b" must be a 32-byte Buffer');
  return keccak256(Buffer.concat([a, b]));
}

/**
 * Decodes a proof (in bytes) into a list of 32-byte Buffers.
 * E.g., if the proof is 96 bytes, we'll return an array of 3 Buffers (each 32 bytes).
 */
export function decodeBytesToMerkleProof(proofBytes: Buffer): Hash[] {
  assert(proofBytes.length % 32 === 0, 'Proof bytes must be a multiple of 32');
  const proofLength = proofBytes.length / 32;
  const proof: Hash[] = [];

  for (let i = 0; i < proofLength; i++) {
    proof.push(proofBytes.slice(i * 32, (i + 1) * 32));
  }

  return proof;
}

/**
 * Encodes a list of 32-byte Buffers (hashes) into one continuous byte array by concatenation.
 */
export function encodeMerkleProofToBytes(proof: Hash[]): Buffer {
  return Buffer.concat(proof);
}

/**
 * updateBranchWithNewMessage:
 * Update the local `branches` to include a new leaf (msgHash) at `index`.
 * Returns the Merkle proof for that new leaf.
 */
export function updateBranchWithNewMessage(
  zeroes: Hash[],
  branches: Hash[],
  index: number,
  msgHash: Hash
): Hash[] {
  assert(Buffer.isBuffer(msgHash) && msgHash.length === 32, 'msgHash must be a 32-byte Buffer');

  let root = msgHash;
  const merkleProof: Hash[] = [];
  let localIndex = index;
  let height = 0;

  while (localIndex > 0) {
    if (localIndex % 2 === 0) {
      branches[height] = root;
      merkleProof.push(zeroes[height]);
      root = keccak2(root, zeroes[height]);
    } else {
      root = keccak2(branches[height], root);
      merkleProof.push(branches[height]);
    }
    localIndex >>= 1;
    height++;
  }

  branches[height] = root;
  return merkleProof;
}

/**
 * recoverBranchFromProof:
 * Recovers the latest branches from a known merkle proof and message hash at a given index.
 */
export function recoverBranchFromProof(proof: Hash[], index: number, msgHash: Hash): Hash[] {
  assert(Buffer.isBuffer(msgHash) && msgHash.length === 32, 'msgHash must be a 32-byte Buffer');

  const branches = new Array<Hash>(64);
  let root = msgHash;
  let localIndex = index;
  let height = 0;

  while (localIndex > 0) {
    if (localIndex % 2 === 0) {
      branches[height] = root;
      root = keccak2(root, proof[height]);
    } else {
      branches[height] = proof[height];
      root = keccak2(proof[height], root);
    }
    localIndex >>= 1;
    height++;
  }

  branches[height] = root;
  for (height++; height < 64; height++) {
    branches[height] = Buffer.alloc(32, 0);
  }
  return branches;
}

/**
 * The maximum possible height of this withdrawal trie.
 */
export const MAX_HEIGHT = 40;

/**
 * WithdrawTrie is an append-only Merkle trie.
 */
export class WithdrawTrie {
  public NextMessageNonce: number;
  private height: number;
  private branches: Hash[];
  private zeroes: Hash[];

  constructor() {
    this.height = -1;
    this.NextMessageNonce = 0;
    this.zeroes = new Array<Hash>(MAX_HEIGHT);
    this.branches = new Array<Hash>(MAX_HEIGHT);

    this.zeroes[0] = Buffer.alloc(32, 0);
    for (let i = 1; i < MAX_HEIGHT; i++) {
      this.zeroes[i] = keccak2(this.zeroes[i - 1], this.zeroes[i - 1]);
    }
  }

  public Initialize(currentMessageNonce: number, msgHash: Hash, proofBytes: Buffer): void {
    assert(Number.isSafeInteger(currentMessageNonce) && currentMessageNonce >= 0, 'Invalid nonce');
    assert(Buffer.isBuffer(msgHash) && msgHash.length === 32, 'msgHash must be a 32-byte Buffer');

    const proof = decodeBytesToMerkleProof(proofBytes);
    this.branches = recoverBranchFromProof(proof, currentMessageNonce, msgHash);
    this.height = proof.length;
    this.NextMessageNonce = currentMessageNonce + 1;
  }

  public AppendMessages(hashes: Hash[]): Buffer[] {
    if (hashes.length === 0) return [];

    if (this.NextMessageNonce >= Number.MAX_SAFE_INTEGER) {
      throw new Error('NextMessageNonce exceeds maximum safe integer value');
    }

    const length = hashes.length;
    const cache: Hash[][] = Array.from({ length: MAX_HEIGHT }, () => []);

    if (this.NextMessageNonce !== 0) {
      let index = this.NextMessageNonce;
      for (let h = 0; h <= this.height; h++) {
        if (index % 2 === 1) {
          cache[h][index ^ 1] = this.branches[h];
        }
        index >>= 1;
      }
    }

    for (let i = 0; i < length; i++) {
      cache[0][this.NextMessageNonce + i] = hashes[i];
    }

    let minIndex = this.NextMessageNonce;
    let maxIndex = this.NextMessageNonce + length - 1;
    let h = 0;

    while (maxIndex > 0) {
      if (minIndex % 2 === 1) minIndex--;
      if (maxIndex % 2 === 0) cache[h][maxIndex ^ 1] = this.zeroes[h];

      for (let i = minIndex; i <= maxIndex; i += 2) {
        cache[h + 1][i >> 1] = keccak2(cache[h][i], cache[h][i ^ 1]);
      }

      minIndex >>= 1;
      maxIndex >>= 1;
      h++;
    }

    for (let i = 0; i < length; i++) {
      const proof = updateBranchWithNewMessage(
        this.zeroes,
        this.branches,
        this.NextMessageNonce,
        hashes[i]
      );
      this.height = proof.length;
      this.NextMessageNonce++;
    }

    return hashes.map((_, i) => {
      let index = this.NextMessageNonce + i - length;
      const merkleProof: Hash[] = [];
      for (let h = 0; h < this.height; h++) {
        merkleProof.push(cache[h][index ^ 1]);
        index >>= 1;
      }
      return encodeMerkleProofToBytes(merkleProof);
    });
  }

  public MessageRoot(): Hash {
    if (this.height === -1) return Buffer.alloc(32, 0);
    return this.branches[this.height];
  }
}

