// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../../common/EssentialContract.sol";
import "../../libs/LibAddress.sol";
import "../TaikoData.sol";
import "../TaikoToken.sol";
import "./IHook.sol";

/// @title AssignmentHook
/// A hook that handles prover assignment varification and fee processing.
contract AssignmentHook is EssentialContract, IHook {
    using LibAddress for address;

    struct ProverAssignment {
        address feeToken;
        uint64 expiry;
        uint64 maxBlockId;
        uint64 maxProposedIn;
        bytes32 metaHash;
        TaikoData.TierFee[] tierFees;
        bytes signature;
    }

    struct Input {
        ProverAssignment assignment;
        uint256 tip;
    }

    // Max gas paying the prover. This should be large enough to prevent the
    // worst cases, usually block proposer shall be aware the risks and only
    // choose provers that cannot consume too much gas when receiving Ether.
    uint256 public constant MAX_GAS_PAYING_PROVER = 200_000;

    event BlockAssigned(
        address indexed assignedProver, TaikoData.BlockMetadata meta, ProverAssignment assignment
    );

    error HOOK_ASSIGNMENT_EXPIRED();
    error HOOK_ASSIGNMENT_INVALID_SIG();
    error HOOK_ASSIGNMENT_INSUFFICIENT_FEE();
    error HOOK_TIER_NOT_FOUND();

    function init(address _addressManager) external initializer {
        EssentialContract._init(_addressManager);
    }

    function onBlockProposed(
        TaikoData.Block memory blk,
        TaikoData.BlockMetadata memory meta,
        bytes memory data
    )
        external
        payable
        nonReentrant
        onlyFromNamed("taiko")
    {
        Input memory input = abi.decode(data, (Input));
        ProverAssignment memory assignment = input.assignment;

        // Check assignment validity
        if (
            block.timestamp > assignment.expiry
                || assignment.metaHash != 0 && blk.metaHash != assignment.metaHash
                || assignment.maxBlockId != 0 && meta.id > assignment.maxBlockId
                || assignment.maxProposedIn != 0 && block.number > assignment.maxProposedIn
        ) {
            revert HOOK_ASSIGNMENT_EXPIRED();
        }

        // Hash the assignment with the blobHash, this hash will be signed by
        // the prover, therefore, we add a string as a prefix.
        bytes32 hash = hashAssignment(assignment, msg.sender, meta.blobHash);

        if (!blk.assignedProver.isValidSignature(hash, assignment.signature)) {
            revert HOOK_ASSIGNMENT_INVALID_SIG();
        }

        // Send the liveness bond to the Taiko contract
        TaikoToken tko = TaikoToken(resolve("taiko_token", false));
        tko.transferFrom(blk.assignedProver, msg.sender, blk.livenessBond);

        // Find the prover fee using the minimal tier
        uint256 proverFee = _getProverFee(assignment.tierFees, meta.minTier);

        // The proposer irrevocably pays a fee to the assigned prover, either in
        // Ether or ERC20 tokens.
        uint256 refund;
        if (assignment.feeToken == address(0)) {
            if (msg.value < proverFee + input.tip) {
                revert HOOK_ASSIGNMENT_INSUFFICIENT_FEE();
            }

            unchecked {
                refund = msg.value - proverFee - input.tip;
            }

            // Paying Ether
            blk.assignedProver.sendEther(proverFee, MAX_GAS_PAYING_PROVER);
        } else {
            if (msg.value < input.tip) {
                revert HOOK_ASSIGNMENT_INSUFFICIENT_FEE();
            }
            unchecked {
                refund = msg.value - input.tip;
            }
            // Paying ERC20 tokens
            ERC20Upgradeable(assignment.feeToken).transferFrom(
                msg.sender, blk.assignedProver, proverFee
            );
        }

        // block.coinbase can be address(0) in tests
        if (input.tip != 0 && block.coinbase != address(0)) {
            address(block.coinbase).sendEther(input.tip);
        }

        if (refund != 0) {
            msg.sender.sendEther(refund);
        }

        emit BlockAssigned(blk.assignedProver, meta, assignment);
    }

    function hashAssignment(
        ProverAssignment memory assignment,
        address taikoAddress,
        bytes32 blobHash
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "PROVER_ASSIGNMENT",
                taikoAddress,
                blobHash,
                assignment.feeToken,
                assignment.expiry,
                assignment.maxBlockId,
                assignment.maxProposedIn,
                assignment.tierFees
            )
        );
    }

    function _getProverFee(
        TaikoData.TierFee[] memory tierFees,
        uint16 tierId
    )
        private
        pure
        returns (uint256)
    {
        for (uint256 i; i < tierFees.length; ++i) {
            if (tierFees[i].tier == tierId) return tierFees[i].fee;
        }
        revert HOOK_TIER_NOT_FOUND();
    }
}

/// @title ProxiedAssignmentHook
/// @notice Proxied version of the parent contract.
contract ProxiedAssignmentHook is Proxied, AssignmentHook { }