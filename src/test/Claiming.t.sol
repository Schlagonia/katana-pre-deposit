// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {KatanaDistributor} from "../KatanaDistributor.sol";
import {L1Claimer} from "../L1Claimer.sol";
import {IPolygonZkEVMBridge} from "../interfaces/IPolygonZkEVMBridge.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ClaimingTest is Setup {
    KatanaDistributor public katanaDistributor;
    L1Claimer public l1Claimer;

    // Events
    event RootUpdated(bytes32 indexed newRoot);
    event Withdrawn(
        address indexed token,
        address indexed to,
        uint256 indexed amount
    );
    event RewardsClaimed(
        address indexed token,
        address indexed account,
        address indexed recipient,
        uint256 amount
    );
    event ClaimContractSet(
        address indexed vault,
        address indexed claimContract
    );
    event BridgeEvent(
        uint8 leafType,
        uint32 originNetwork,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes metadata,
        uint32 depositCount
    );

    // Constants
    address public constant ZKEVM_BRIDGE =
        0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;
    uint32 public constant ROLLUP_ID = 20;

    address public user2 = makeAddr("user2");

    uint256 public amount1;
    uint256 public amount2;

    // Test data
    bytes32 public testRoot;
    bytes32[] public tProof;

    bytes32 leaf1;
    bytes32 leaf2;

    function setUp() public override {
        super.setUp();

        l1Claimer = new L1Claimer(management);
        katanaDistributor = new KatanaDistributor(
            management,
            address(preDepositVault),
            address(l1Claimer)
        );

        amount1 = 1000 * 10 ** decimals;
        amount2 = 2000 * 10 ** decimals;

        // Create deposits to get vault shares
        airdrop(asset, address(user), amount1);
        vm.prank(user);
        asset.approve(address(depositRelayer), amount1);
        vm.prank(user);
        depositRelayer.deposit(address(asset), amount1);

        airdrop(asset, address(user2), amount2);
        vm.prank(user2);
        asset.approve(address(depositRelayer), amount2);
        vm.prank(user2);
        depositRelayer.deposit(address(asset), amount2);

        // Create valid Merkle tree
        // Leaf hashes: keccak256(abi.encodePacked(account, amount))
        leaf1 = keccak256(bytes.concat(keccak256(abi.encode(user, amount1))));
        leaf2 = keccak256(bytes.concat(keccak256(abi.encode(user2, amount2))));

        // Root: keccak256(abi.encodePacked(leaf1, leaf2))
        bytes32 a = leaf1 > leaf2 ? leaf2 : leaf1;
        bytes32 b = leaf1 > leaf2 ? leaf1 : leaf2;
        testRoot = keccak256(abi.encodePacked(a, b));

        // For user to prove leaf1, they need leaf2 as proof
        // For user2 to prove leaf2, they need leaf1 as proof
        tProof = new bytes32[](1);
        tProof[0] = leaf2; // Proof for user's claim (leaf1)
    }

    // Helper function to get proof for a specific user
    function getProofForUser(
        address _user,
        uint256 _amount
    ) public view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);

        if (_user == user) {
            proof[0] = leaf2; // Proof for user's claim (leaf1)
        } else if (_user == user2) {
            proof[0] = leaf1; // Proof for user2's claim (leaf2)
        }

        return proof;
    }

    // ============ L1Claimer Tests ============

    function test_setClaimContract() public {
        vm.startPrank(management);

        vm.expectEmit(true, true, false, false);
        emit ClaimContractSet(
            address(preDepositVault),
            address(katanaDistributor)
        );

        l1Claimer.setClaimContract(
            address(preDepositVault),
            address(katanaDistributor)
        );
        assertEq(
            l1Claimer.claimContracts(address(preDepositVault)),
            address(katanaDistributor)
        );

        vm.stopPrank();
    }

    function test_RevertWhen_NonGovernanceSetsClaimContract() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        l1Claimer.setClaimContract(
            address(preDepositVault),
            address(katanaDistributor)
        );
    }

    function test_l1Claimer_claim() public {
        // Set claim contract first
        vm.prank(management);
        l1Claimer.setClaimContract(
            address(preDepositVault),
            address(katanaDistributor)
        );

        uint256 amount = amount1;
        address recipient = user;
        bytes32[] memory proof = getProofForUser(user, amount);

        // Expect Bridge event
        uint256 depositCount = IPolygonZkEVMBridge(ZKEVM_BRIDGE).depositCount();
        vm.expectEmit(true, true, true, true, address(ZKEVM_BRIDGE));
        emit BridgeEvent(
            1,
            uint32(0),
            address(l1Claimer),
            uint32(ROLLUP_ID),
            address(katanaDistributor),
            0,
            abi.encode(address(this), amount, recipient, proof),
            uint32(depositCount)
        );

        l1Claimer.claim(address(preDepositVault), amount, recipient, proof);
    }

    function test_RevertWhen_ClaimingWithoutClaimContract() public {
        uint256 amount = 1000 * 10 ** decimals;
        address recipient = user;

        vm.expectRevert("!claimContract");
        l1Claimer.claim(address(preDepositVault), amount, recipient, tProof);
    }

    function test_multiClaim() public {
        // Set claim contracts
        vm.startPrank(management);
        l1Claimer.setClaimContract(
            address(preDepositVault),
            address(katanaDistributor)
        );
        l1Claimer.setClaimContract(
            address(stbVault),
            address(katanaDistributor)
        );
        vm.stopPrank();

        address[] memory vaults = new address[](2);
        vaults[0] = address(preDepositVault);
        vaults[1] = address(stbVault);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10 ** decimals;
        amounts[1] = 2000 * 10 ** decimals;

        address[] memory recipients = new address[](2);
        recipients[0] = user;
        recipients[1] = keeper;

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = tProof;
        proofs[1] = tProof;

        l1Claimer.multiClaim(vaults, amounts, recipients, proofs);
    }

    function test_RevertWhen_MultiClaimInvalidLength() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(preDepositVault);
        vaults[1] = address(stbVault);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10 ** decimals;

        address[] memory recipients = new address[](2);
        recipients[0] = user;
        recipients[1] = keeper;

        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = tProof;
        proofs[1] = tProof;

        vm.expectRevert("!length");
        l1Claimer.multiClaim(vaults, amounts, recipients, proofs);
    }

    // ============ KatanaDistributor Tests ============

    function test_updateRoot() public {
        bytes32 newRoot = 0x5555555555555555555555555555555555555555555555555555555555555555;

        vm.startPrank(management);

        vm.expectEmit(true, false, false, false);
        emit RootUpdated(newRoot);

        katanaDistributor.updateRoot(newRoot);
        assertEq(katanaDistributor.currentRoot(), newRoot);

        vm.stopPrank();
    }

    function test_RevertWhen_NonGovernanceUpdatesRoot() public {
        bytes32 newRoot = 0x5555555555555555555555555555555555555555555555555555555555555555;

        vm.prank(user);
        vm.expectRevert("!governance");
        katanaDistributor.updateRoot(newRoot);
    }

    function test_withdrawTokens() public {
        uint256 amount = 1000 * 10 ** decimals;

        // Airdrop tokens to distributor
        airdrop(asset, address(katanaDistributor), amount);

        uint256 preBalance = asset.balanceOf(management);

        vm.startPrank(management);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(address(asset), management, amount);

        katanaDistributor.withdrawTokens(address(asset), management, amount);

        assertEq(asset.balanceOf(management), preBalance + amount);
        assertEq(asset.balanceOf(address(katanaDistributor)), 0);

        vm.stopPrank();
    }

    function test_RevertWhen_NonGovernanceWithdraws() public {
        vm.prank(user);
        vm.expectRevert("!governance");
        katanaDistributor.withdrawTokens(address(asset), user, 1000);
    }

    function test_katanaDistributor_claim() public {
        // Set root
        vm.prank(management);
        katanaDistributor.updateRoot(testRoot);

        uint256 amount = amount1;

        // Airdrop vault tokens to distributor
        airdrop(
            ERC20(address(preDepositVault)),
            address(katanaDistributor),
            amount
        );

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(address(preDepositVault), user, user, amount);

        vm.prank(user);
        katanaDistributor.claim(amount, tProof);

        assertEq(ERC20(address(preDepositVault)).balanceOf(user), amount);
        assertTrue(katanaDistributor.claimed(user));
    }

    function test_katanaDistributor_claim_user2() public {
        // Set root
        vm.prank(management);
        katanaDistributor.updateRoot(testRoot);

        uint256 amount = amount2;

        // Airdrop vault tokens to distributor
        airdrop(
            ERC20(address(preDepositVault)),
            address(katanaDistributor),
            amount
        );

        // Get proof for user2
        bytes32[] memory proof = getProofForUser(user2, amount);

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(address(preDepositVault), user2, user2, amount);

        vm.prank(user2);
        katanaDistributor.claim(amount, proof);

        assertEq(ERC20(address(preDepositVault)).balanceOf(user2), amount);
        assertTrue(katanaDistributor.claimed(user2));
    }

    function test_claim_withRecipient() public {
        // Set root
        vm.prank(management);
        katanaDistributor.updateRoot(testRoot);

        uint256 amount = amount1;
        address recipient = keeper;
        bytes32[] memory proof = getProofForUser(user, amount);

        // Airdrop vault tokens to distributor
        airdrop(
            ERC20(address(preDepositVault)),
            address(katanaDistributor),
            amount
        );

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(address(preDepositVault), user, recipient, amount);

        vm.prank(user);
        katanaDistributor.claim(amount, recipient, proof);

        assertEq(ERC20(address(preDepositVault)).balanceOf(recipient), amount);
        assertTrue(katanaDistributor.claimed(user));
    }

    function test_RevertWhen_ClaimingAlreadyClaimed() public {
        // Set root
        vm.prank(management);
        katanaDistributor.updateRoot(testRoot);

        uint256 amount = amount1;
        bytes32[] memory proof = getProofForUser(user, amount);
        // Airdrop vault tokens to distributor
        airdrop(
            ERC20(address(preDepositVault)),
            address(katanaDistributor),
            amount
        );

        // First claim
        vm.prank(user);
        katanaDistributor.claim(amount, proof);

        // Second claim should fail
        vm.prank(user);
        vm.expectRevert("Already claimed");
        katanaDistributor.claim(amount, proof);
    }

    function test_RevertWhen_ClaimingInvalidProof() public {
        // Set root
        vm.prank(management);
        katanaDistributor.updateRoot(testRoot);

        uint256 amount = amount1;

        // Airdrop vault tokens to distributor
        airdrop(
            ERC20(address(preDepositVault)),
            address(katanaDistributor),
            amount
        );

        // Use invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(
            0x9999999999999999999999999999999999999999999999999999999999999999
        );

        vm.prank(user);
        vm.expectRevert("Invalid proof");
        katanaDistributor.claim(amount, invalidProof);
    }

    function test_onMessageReceived() public {
        // Set root
        vm.prank(management);
        katanaDistributor.updateRoot(testRoot);

        uint256 amount = amount1;
        address recipient = management;
        bytes32[] memory proof = getProofForUser(user, amount);
        // Airdrop vault tokens to distributor
        airdrop(
            ERC20(address(preDepositVault)),
            address(katanaDistributor),
            amount
        );

        bytes memory data = abi.encode(user, amount, recipient, proof);

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(address(preDepositVault), user, recipient, amount);

        vm.prank(ZKEVM_BRIDGE);
        katanaDistributor.onMessageReceived(address(l1Claimer), 0, data);

        assertEq(ERC20(address(preDepositVault)).balanceOf(recipient), amount);
        assertTrue(katanaDistributor.claimed(user));
    }

    function test_RevertWhen_NonBridgeCallsOnMessageReceived() public {
        bytes memory data = abi.encode(user, amount1, user, tProof);

        vm.prank(user);
        vm.expectRevert("!bridge");
        katanaDistributor.onMessageReceived(address(l1Claimer), 0, data);
    }

    function test_RevertWhen_NonL1ClaimerCallsOnMessageReceived() public {
        bytes memory data = abi.encode(user, amount1, user, tProof);

        vm.prank(ZKEVM_BRIDGE);
        vm.expectRevert("!l1Claimer");
        katanaDistributor.onMessageReceived(user, 0, data);
    }

    function test_RevertWhen_NonMainnetCallsOnMessageReceived() public {
        bytes memory data = abi.encode(user, amount1, user, tProof);

        vm.prank(ZKEVM_BRIDGE);
        vm.expectRevert("!mainnet");
        katanaDistributor.onMessageReceived(address(l1Claimer), 1, data);
    }

    // ============ Integration Tests ============

    function test_fullClaimFlow() public {
        // Setup L1Claimer
        vm.prank(management);
        l1Claimer.setClaimContract(
            address(preDepositVault),
            address(katanaDistributor)
        );

        // Setup KatanaDistributor
        vm.prank(management);
        katanaDistributor.updateRoot(testRoot);

        uint256 amount = amount1;
        address recipient = management;
        bytes32[] memory proof = getProofForUser(user, amount);

        // Airdrop vault tokens to distributor
        airdrop(
            ERC20(address(preDepositVault)),
            address(katanaDistributor),
            amount
        );

        // L1Claimer sends claim
        l1Claimer.claim(address(preDepositVault), amount, recipient, proof);

        // Simulate bridge message received
        bytes memory data = abi.encode(user, amount, recipient, proof);

        uint256 preBalance = ERC20(address(preDepositVault)).balanceOf(
            recipient
        );

        vm.prank(ZKEVM_BRIDGE);
        katanaDistributor.onMessageReceived(address(l1Claimer), 0, data);

        // Verify claim was successful
        assertEq(
            ERC20(address(preDepositVault)).balanceOf(recipient),
            preBalance + amount
        );
        assertTrue(katanaDistributor.claimed(user));
    }
}
