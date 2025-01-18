import { expect } from 'chai';
import {
  keccak2,
  decodeBytesToMerkleProof,
  encodeMerkleProofToBytes,
  updateBranchWithNewMessage,
  recoverBranchFromProof,
  WithdrawTrie,
  MAX_HEIGHT,
} from '../src/merkle';
import { keccak256 } from 'ethereumjs-util';

// Define some fixed 32-byte hashes for testing:
const hashA = Buffer.from(
  '72530d2135620c0c7ddfac2cc523ae31c2901f62ce0109d2f74ab99f1756b51f',
  'hex'
);
const hashB = Buffer.from(
  '3bb63288619c7896198f42167e192d5365da04f5fd5e9f418ea31bafc1f3bf53',
  'hex'
);
// Updated hashC as requested:
const hashC = Buffer.from(
  '6dae1726e96e70a2bbe52917a67d578c67958b774160cc29f34e16843793703b',
  'hex'
);

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
      const hashX = Buffer.alloc(32, 1);
      const hashY = Buffer.alloc(32, 2);
      const result = keccak2(hashX, hashY);

      expect(result.length).to.equal(32);
      // Verify that result matches keccak256 of (hashX || hashY)
      const manual = keccak256(Buffer.concat([hashX, hashY]));
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
      // Pass 31 bytes intentionally
      expect(() => updateBranchWithNewMessage(zeroes, branches, 0, Buffer.alloc(31, 0)))
        .to.throw('msgHash must be a 32-byte Buffer');
    });

    it('should return a Merkle proof array', () => {
      const zeroes = [Buffer.alloc(32, 0)];
      const branches = [Buffer.alloc(32, 0)];

      // Use hashA as our fixed 32-byte input
      const proof = updateBranchWithNewMessage(zeroes, branches, 0, hashA);
      // For index 0 with only one level, proof should be an array (possibly empty)
      expect(proof).to.be.an('array');
    });
  });

  describe('recoverBranchFromProof', () => {
    it('should throw if msgHash is not 32 bytes', () => {
      // Pass 31 bytes intentionally
      expect(() => recoverBranchFromProof([], 0, Buffer.alloc(31, 0)))
        .to.throw('msgHash must be a 32-byte Buffer');
    });

    it('should return an array of 64 Buffers', () => {
      // Use hashB as our fixed 32-byte input
      const branches = recoverBranchFromProof([], 0, hashB);
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

    // zeroes[i] = keccak2(zeroes[i - 1], zeroes[i - 1])
    for (let i = 1; i < MAX_HEIGHT; i++) {
      const expected = keccak2(trie['zeroes'][i - 1], trie['zeroes'][i - 1]);
      expect(trie['zeroes'][i].equals(expected)).to.be.true;
    }
  });

  it('should properly Initialize using existing proof', () => {
    const trie = new WithdrawTrie();
    const currentMessageNonce = 5;
    // Suppose we have a proof of length 3 => 3*32 = 96 bytes
    const dummyProofBytes = Buffer.alloc(96, 7);

    // Initialize with hashA
    trie.Initialize(currentMessageNonce, hashA, dummyProofBytes);

    // After init, NextMessageNonce should be currentMessageNonce + 1
    expect(trie.NextMessageNonce).to.equal(currentMessageNonce + 1);

    // The internal height should be the length of the proof (3)
    expect(trie['height']).to.equal(3);
  });

  it('should AppendMessages and return Merkle proofs', () => {
    const trie = new WithdrawTrie();
    // Start from an empty trie
    expect(trie.MessageRoot().equals(Buffer.alloc(32, 0))).to.be.true;

    // Append some fixed messages
    const hashes = [hashA, hashB, hashC];
    const proofs = trie.AppendMessages(hashes);

    // We should get an array of the same length as `hashes`
    expect(proofs).to.have.length(hashes.length);

    // NextMessageNonce should have increased by `hashes.length`
    expect(trie.NextMessageNonce).to.equal(hashes.length);

    // The trie now should have a nonzero root
    expect(trie.MessageRoot().equals(Buffer.alloc(32, 0))).to.be.false;
  });

  it('should throw if NextMessageNonce >= Number.MAX_SAFE_INTEGER', () => {
    const trie = new WithdrawTrie();
    // Force NextMessageNonce near the limit
    trie['NextMessageNonce'] = Number.MAX_SAFE_INTEGER;
    const hashes = [hashA];

    expect(() => trie.AppendMessages(hashes)).to.throw(
      'NextMessageNonce exceeds maximum safe integer value'
    );
  });

  it('should produce the correct root when three known hashes are appended', () => {
    // The two leaf hashes we already defined: hashA, hashB
    // The expected Merkle root (in hex, 32 bytes => 64 hex chars).
    const expectedRootHex =
      '77ca755fbc2499f32c71f55d967145ca263c415261a1e52c7cca5c25db2e2753';

    // Create a fresh trie
    const trie = new WithdrawTrie();

    // Append the two known messages
    trie.AppendMessages([hashA, hashB, hashC]);

    // Check that the resulting root matches the expected root
    const actualRootHex = trie.MessageRoot().toString('hex');
    expect(actualRootHex).to.equal(expectedRootHex);
  });

  it('should produce the known proof for hashC after appending hashA, hashB, hashC', () => {
    // Create a fresh trie
    const trie = new WithdrawTrie();

    // Append hashA, hashB, hashC
    const proofs = trie.AppendMessages([hashA, hashB, hashC]);

    //  The proof for hashC is the last item in `proofs`
    const proofForHashC = proofs[2];

    // The known expected proof (64 bytes total: two 32-byte chunks).
    // Split it here for readability; but it's just one long hex string.
    const expectedProofHex = [
      '0000000000000000000000000000000000000000000000000000000000000000',
      'eac9b33976a25627817774db946ec33e0268bea17c0eed2346fa659afd9aa5cc',
    ].join('');

    // 6. Compare the hex representation
    expect(proofForHashC.toString('hex')).to.equal(expectedProofHex);
  });

});
