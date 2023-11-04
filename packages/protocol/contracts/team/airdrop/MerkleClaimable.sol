// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { OwnableUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { MerkleProofUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/MerkleProofUpgradeable.sol";

import { Proxied } from "../../common/Proxied.sol";

/// @title MerkleClaimable
/// Contract for managing Taiko token airdrop for eligible users
// TODO(dani): add claimStart and claimEnd timestamp so claim() can only be
// called between these two timestamps.
// Better to add non-reentrance guard to claim().

abstract contract MerkleClaimable is OwnableUpgradeable {
    mapping(bytes32 => bool) public isClaimed;
    bytes32 public merkleRoot;

    event Claimed(bytes32 hash);

    error CLAIMED_ALREADY();
    error INVALID_PROOF();

    function claim(bytes calldata data, bytes32[] calldata proof) external {
        bytes32 hash = keccak256(abi.encode("CLAIM)TAIKO_AIRDROP", data));
        if (isClaimed[hash]) revert CLAIMED_ALREADY();

        if (!MerkleProofUpgradeable.verify(proof, merkleRoot, hash)) {
            revert INVALID_PROOF();
        }

        isClaimed[hash] = true;
        _claimWithData(data);
        emit Claimed(hash);
    }

    function _init(bytes32 _merkleRoot) internal {
        OwnableUpgradeable.__Ownable_init();
        merkleRoot = _merkleRoot;
    }

    /// @dev Must revert in case of errors.
    function _claimWithData(bytes calldata data) internal virtual;
}