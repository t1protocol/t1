import { expect } from 'chai';
import { keccak2, decodeBytesToMerkleProof, encodeMerkleProofToBytes,
         updateBranchWithNewMessage, recoverBranchFromProof, WithdrawTrie, MAX_HEIGHT } from '../src/merkle';
import { keccak256 } from 'ethereumjs-util';
import * as crypto from 'crypto';

function randomHash(): Buffer {
  return crypto.randomBytes(32);
}

describe('Merkle Utilities', () => {
  describe('keccak2', () => {
    it('should throw an error if inputs are not 32-byte Buffers', () => {
      const not32Bytes = Buffer.alloc(31, 0);
      const exactly32Bytes = Buffer.alloc(32, 0);

      expect(() => keccak2(not32Bytes, exactly32Bytes))
        .to.throw('Hash "a" must be a 32-byte Buffer');

      expect(() => keccak2(exactly32Bytes, not32Bytes))
        .to.throw('Hash "b" must be a 32-byte Buffer');
    });

    it('should return the keccak256 of the concatenation of two 32-byte Buffers', () => {
      const hashA = Buffer.alloc(32, 1);
      const hashB = Buffer.alloc(32, 2);
      const result = keccak2(hashA, hashB);

      expect(result.length).to.equal(32);
      // We can also verify that result matches keccak256 of the concatenation
      const manual = keccak256(Buffer.concat([hashA, hashB]));
      expect(result.equals(manual)).to.be.true;
    });
  });

  describe('decodeBytesToMerkleProof', () => {
    it('should throw if proofBytes length is not multiple of 32', () => {
      const invalidProof = Buffer.alloc(33, 0);
      expect(() => decodeBytesToMerkleProof(invalidProof))
        .to.throw('Proof bytes must be a multiple of 32');
    });

    it('should split proofBytes into 32-byte chunks', () => {
      const proofBytes = Buffer.alloc(96, 5); // 3 chunks of 32
      const proof = decodeBytesToMerkleProof(proofBytes);
      expect(proof).to.have.length(3);
      expect(proof[0].length).to.equal(32);
      expect(proof[1].length).to.equal(32);
      expect(proof[2].length).to.equal(32);
    });
  });

  describe('encodeMerkleProofToBytes', () => {
    it('should concatenate an array of 32-byte Buffers', () => {
      const chunk1 = Buffer.alloc(32, 1);
      const chunk2 = Buffer.alloc(32, 2);
      const chunk3 = Buffer.alloc(32, 3);

      const proof = [chunk1, chunk2, chunk3];
      const encoded = encodeMerkleProofToBytes(proof);

      expect(encoded.length).to.equal(96); // 3*32
      expect(encoded.slice(0, 32).equals(chunk1)).to.be.true;
      expect(encoded.slice(32, 64).equals(chunk2)).to.be.true;
      expect(encoded.slice(64, 96).equals(chunk3)).to.be.true;
    });
  });
});

describe('Merkle Branch Functions', () => {
  describe('updateBranchWithNewMessage', () => {
    it('should throw if msgHash is not 32 bytes', () => {
      const zeroes = [Buffer.alloc(32, 0)];
      const branches = [Buffer.alloc(32, 0)];
      expect(() => updateBranchWithNewMessage(zeroes, branches, 0, Buffer.alloc(31, 0)))
        .to.throw('msgHash must be a 32-byte Buffer');
    });

    it('should return a Merkle proof array', () => {
      // Minimal test with index=0
      const zeroes = [Buffer.alloc(32, 0)];
      const branches = [Buffer.alloc(32, 0)];
      const msgHash = randomHash();

      const proof = updateBranchWithNewMessage(zeroes, branches, 0, msgHash);
      // For index 0 with only one level, proof should be empty or trivial
      expect(proof).to.be.an('array');
    });
  });

  describe('recoverBranchFromProof', () => {
    it('should throw if msgHash is not 32 bytes', () => {
      expect(() => recoverBranchFromProof([], 0, Buffer.alloc(31, 0)))
        .to.throw('msgHash must be a 32-byte Buffer');
    });

    it('should return an array of 64 Buffers', () => {
      // Even with an empty proof, we should get 64 branches, each 32 bytes (except for the top).
      const msgHash = randomHash();
      const branches = recoverBranchFromProof([], 0, msgHash);
      expect(branches).to.have.length(64);
      for (const branch of branches) {
        expect(branch.length).to.equal(32);
      }
    });
  });
});

describe('WithdrawTrie', () => {
  it('should initialize with the correct zeroes array', () => {
    const trie = new WithdrawTrie();

    // zeroes[0] is 32 bytes of 0
    expect(trie['zeroes'][0].equals(Buffer.alloc(32, 0))).to.be.true;

    // zeroes[i] = keccak2(zeroes[i-1], zeroes[i-1])
    for (let i = 1; i < MAX_HEIGHT; i++) {
      const expected = keccak2(trie['zeroes'][i - 1], trie['zeroes'][i - 1]);
      expect(trie['zeroes'][i].equals(expected)).to.be.true;
    }
  });

  it('should properly Initialize using existing proof', () => {
    const trie = new WithdrawTrie();
    const msgHash = randomHash();
    const currentMessageNonce = 5;
    // Suppose we have a proof of length 3 => 3*32 = 96 bytes
    const dummyProofBytes = Buffer.alloc(96, 7);

    trie.Initialize(currentMessageNonce, msgHash, dummyProofBytes);

    // After init, NextMessageNonce should be currentMessageNonce + 1
    expect(trie.NextMessageNonce).to.equal(currentMessageNonce + 1);

    // The internal height should be the length of proof (3)
    expect(trie['height']).to.equal(3);
  });

  it('should AppendMessages and return Merkle proofs', () => {
    const trie = new WithdrawTrie();
    // Start from an empty trie
    expect(trie.MessageRoot().equals(Buffer.alloc(32, 0))).to.be.true;

    // Append some messages
    const hashes = [randomHash(), randomHash(), randomHash()];
    const proofs = trie.AppendMessages(hashes);

    const hexProofs = proofs.map(proof => proof.toString('hex'));
    console.log("proofs as hex:", hexProofs);

    // We should get an array of the same length as `hashes`
    expect(proofs).to.have.length(hashes.length);

    // NextMessageNonce should have increased by `hashes.length`
    expect(trie.NextMessageNonce).to.equal(hashes.length);

    // The trie now has a nonzero root (likely)
    expect(trie.MessageRoot().equals(Buffer.alloc(32, 0))).to.be.false;
  });

  it('should throw if NextMessageNonce >= Number.MAX_SAFE_INTEGER', () => {
    const trie = new WithdrawTrie();
    // Force NextMessageNonce near the limit
    trie['NextMessageNonce'] = Number.MAX_SAFE_INTEGER;
    const hashes = [randomHash()];

    expect(() => trie.AppendMessages(hashes)).to.throw('NextMessageNonce exceeds maximum safe integer value');
  });

  it('should produce the correct root when two known hashes are appended', () => {
  // The two leaf hashes you provided:
  const hashA = Buffer.from(
    '72530d2135620c0c7ddfac2cc523ae31c2901f62ce0109d2f74ab99f1756b51f',
    'hex'
  );
  const hashB = Buffer.from(
    '3bb63288619c7896198f42167e192d5365da04f5fd5e9f418ea31bafc1f3bf53',
    'hex'
  );

  const hashC = Buffer.from(
    '6dae1726e96e70a2bbe52917a67d578c67958b774160cc29f34e16843793703b',
    'hex'
  );

  // The expected Merkle root (in hex, 32 bytes => 64 hex chars).
  const expectedRootHex =
    '77ca755fbc2499f32c71f55d967145ca263c415261a1e52c7cca5c25db2e2753';

  // Create a fresh trie
  const trie = new WithdrawTrie();

  // Append the two known messages
  let proofs = trie.AppendMessages([hashA, hashB, hashC]);
  const hexProofs = proofs.map(proof => proof.toString('hex'));
  console.log("proofs as hex:", hexProofs);

  // Check that the resulting root matches the expected root
  const actualRootHex = trie.MessageRoot().toString('hex');
  expect(actualRootHex).to.equal(expectedRootHex);
});

});

