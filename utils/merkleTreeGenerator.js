const { MerkleTree } = require('merkletreejs')
const ethers = require('ethers')
const fs = require('fs');
const keccak = require('keccak256')
const path = require('path');

/**
 * Reservation Merkle Tree Generator
 * 
 * Generates a merkle tree used to verify username reservations in the Namespace contract. A 
 * reservation can be claimed by generating a leaf, which is simply the hash of the address and 
 * username and a proof, which proves that it belonds to the merkle tree. The contract holds the 
 * root of the tree and can verify that the proof is valid, allowing the username to be claimed.
 * 
 * WARNING: The number of reservations must be a power of 2 so that it forms a balanced merkle tree
 * because unbalanced trees are vulnerable to forgery attacks. 
 */

const reservations = [
    { address: "0x0000000000000000000000000000000000000123", username: "alice" }, 
    { address: "0x0000000000000000000000000000000000000456", username: "bob" },
    { address: "0x0000000000000000000000000000000000000789", username: "charlie" },
    { address: "0x0000000000000000000000000000000000000ABC", username: "david" },
];

/**
 * Generates a leaf of the Merkle tree.
 * 
 * The values are hashed and packed with the solidityKeccack256, and the 0x is truncated before
 * turning it into a Buffer value.
 * 
 * SECURITY TODO: Is using a solidityKeccack256 for the leaves and keccak256 for nodes sufficient 
 * to prevent second pre-image attacks?
 */
const generateLeaf = (address, username) => {
    const bytes16Username = ethers.utils.formatBytes32String(username).slice(0, 34);

    const truncatedHex = ethers.utils.solidityKeccak256(
        ["address", "bytes16"], 
        [address, bytes16Username]
    ).slice(2);
    return Buffer.from(truncatedHex, "hex");
}

// 1. Generate each leaf and populate the Merkle Tree.
const leaves = reservations.map((res) => generateLeaf(res.address, res.username));
const tree = new MerkleTree(leaves, keccak, { sortPairs: true })
const root = tree.getHexRoot();


// 2. Write the tree to a file.
fs.writeFileSync(
    path.join(__dirname, "../out/tree.json"),
    JSON.stringify({ root, tree })
);

// 3. Generate a proof for a specific leaf and verify it against the tree.
const reservation = reservations[1];
const leaf = generateLeaf(reservation.address, reservation.username);
const proof = tree.getHexProof(leaf)

console.log("Proof: ", proof);
console.log("Is Proof Correct", tree.verify(proof, leaf, root))
