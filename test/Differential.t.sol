// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// One test contract drives the same action sequence against both systems.
// MetaMask side is compiled here (pinned 0.8.23). Coinbase SpendPermissionManager needs >=0.8.28,
// so it is compiled separately (src/SpImports.sol) and loaded with vm.deployCode behind an interface.
//
// MetaMask side follows what MetaMask's Smart Accounts Kit produces (MetaMask/smart-accounts-kit @ 555dd20):
// - Delegator: HybridDeleGator behind an ERC1967Proxy, initialize(owner, [], [], []), as the kit's docs show for an
//   EOA signer and as DF/test/utils/BaseTest.t.sol deployDeleGator_Hybrid does.
// - Caveats: the kit's ERC-20 periodic scope, in its order: ValueLteEnforcer(0), then ERC20PeriodTransferEnforcer
//   (packages/smart-accounts-kit/src/caveatBuilder/scope/erc20PeriodicScope.ts L24-33).

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { ModeLib } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";

import { DelegationManager } from "df/DelegationManager.sol";
import { IDelegationManager } from "df/interfaces/IDelegationManager.sol";
import { HybridDeleGator } from "df/HybridDeleGator.sol";
import { ERC20PeriodTransferEnforcer } from "df/enforcers/ERC20PeriodTransferEnforcer.sol";
import { ValueLteEnforcer } from "df/enforcers/ValueLteEnforcer.sol";
import { AllowedCalldataEnforcer } from "df/enforcers/AllowedCalldataEnforcer.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Delegation, Caveat, ModeCode } from "df/utils/Types.sol";

import { CoinbaseSmartWallet } from "smart-wallet/CoinbaseSmartWallet.sol";
import { CoinbaseSmartWalletFactory } from "smart-wallet/CoinbaseSmartWalletFactory.sol";

interface ISpendPermissionManager {
    struct SpendPermission {
        address account;
        address spender;
        address token;
        uint160 allowance;
        uint48 period;
        uint48 start;
        uint48 end;
        uint256 salt;
        bytes extraData;
    }

    function approve(SpendPermission calldata p) external returns (bool);
    function revoke(SpendPermission calldata p) external;
    function spend(SpendPermission memory p, uint160 value) external;
}

contract TestToken is ERC20 {
    constructor() ERC20("Test", "TST") { }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

contract DifferentialTest is Test {
    uint256 constant ALLOWANCE = 100;
    uint256 constant PERIOD = 1 days;
    uint256 START;

    TestToken token;
    address spender = makeAddr("spender");
    address x = makeAddr("x");

    // MetaMask side
    DelegationManager dm;
    ERC20PeriodTransferEnforcer periodEnforcer;
    ValueLteEnforcer valueLteEnforcer;
    AllowedCalldataEnforcer allowedCalldataEnforcer;
    uint256 alicePk;
    address alice; // EOA owner of the HybridDeleGator
    address mmWallet; // the HybridDeleGator proxy: delegator and token holder

    // Coinbase side
    ISpendPermissionManager spm;
    CoinbaseSmartWallet wallet;

    function setUp() public {
        vm.warp(1_800_000_000);
        START = block.timestamp;
        token = new TestToken();

        dm = new DelegationManager(address(this));
        periodEnforcer = new ERC20PeriodTransferEnforcer();
        valueLteEnforcer = new ValueLteEnforcer();
        allowedCalldataEnforcer = new AllowedCalldataEnforcer();
        (alice, alicePk) = makeAddrAndKey("alice");
        HybridDeleGator impl = new HybridDeleGator(IDelegationManager(address(dm)), IEntryPoint(address(0)));
        mmWallet = address(
            new ERC1967Proxy(
                address(impl),
                abi.encodeWithSignature(
                    "initialize(address,string[],uint256[],uint256[])", alice, new string[](0), new uint256[](0), new uint256[](0)
                )
            )
        );
        token.mint(mmWallet, 1_000);

        address validator = deployCode("PublicERC6492Validator.sol:PublicERC6492Validator");
        spm = ISpendPermissionManager(deployCode("SpendPermissionManager.sol:SpendPermissionManager", abi.encode(validator, address(0))));
        CoinbaseSmartWalletFactory factory = new CoinbaseSmartWalletFactory(address(new CoinbaseSmartWallet()));
        bytes[] memory owners = new bytes[](1);
        address carol = makeAddr("carol");
        owners[0] = abi.encode(carol);
        wallet = factory.createAccount(owners, 0);
        vm.prank(carol);
        wallet.addOwnerAddress(address(spm));
        token.mint(address(wallet), 1_000);
    }

    // ---------- MetaMask helpers ----------
    // The kit's ERC-20 periodic scope: [ValueLte(maxValue = 0), ERC20PeriodTransfer(token, amount, duration, start)].
    function _sdkPeriodicCaveats() internal view returns (Caveat[] memory caveats) {
        caveats = new Caveat[](2);
        caveats[0] = Caveat({ enforcer: address(valueLteEnforcer), terms: abi.encode(uint256(0)), args: hex"" });
        caveats[1] = Caveat({
            enforcer: address(periodEnforcer),
            terms: abi.encodePacked(address(token), ALLOWANCE, PERIOD, START),
            args: hex""
        });
    }

    function _delegation(uint256 salt) internal view returns (Delegation memory) {
        return _sign(_sdkPeriodicCaveats(), salt);
    }

    function _sign(Caveat[] memory caveats, uint256 salt) internal view returns (Delegation memory d) {
        d = Delegation({
            delegate: spender,
            delegator: mmWallet,
            authority: dm.ROOT_AUTHORITY(),
            caveats: caveats,
            salt: salt,
            signature: hex""
        });
        bytes32 typed = MessageHashUtils.toTypedDataHash(dm.getDomainHash(), dm.getDelegationHash(d));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, typed);
        d.signature = abi.encodePacked(r, s, v);
    }

    function _mmSpend(Delegation memory d, uint256 amt) internal returns (bool ok) {
        ok = _mmTransfer(d, spender, amt);
    }

    function _mmTransfer(Delegation memory d, address to, uint256 amt) internal returns (bool ok) {
        Delegation[] memory chain = new Delegation[](1);
        chain[0] = d;
        bytes[] memory ctx = new bytes[](1);
        ctx[0] = abi.encode(chain);
        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleSingle();
        bytes[] memory execs = new bytes[](1);
        execs[0] = ExecutionLib.encodeSingle(address(token), 0, abi.encodeCall(IERC20.transfer, (to, amt)));
        vm.prank(spender);
        try dm.redeemDelegations(ctx, modes, execs) { ok = true; } catch { ok = false; }
    }

    // ---------- Coinbase helpers ----------
    function _permission(uint256 salt) internal view returns (ISpendPermissionManager.SpendPermission memory p) {
        p = ISpendPermissionManager.SpendPermission({
            account: address(wallet),
            spender: spender,
            token: address(token),
            allowance: uint160(ALLOWANCE),
            period: uint48(PERIOD),
            start: uint48(START),
            end: type(uint48).max,
            salt: salt,
            extraData: hex""
        });
    }

    function _cbApprove(ISpendPermissionManager.SpendPermission memory p) internal returns (bool) {
        vm.prank(address(wallet));
        return spm.approve(p);
    }

    function _cbSpend(ISpendPermissionManager.SpendPermission memory p, uint256 amt) internal returns (bool ok) {
        vm.prank(spender);
        try spm.spend(p, uint160(amt)) { ok = true; } catch { ok = false; }
    }

    // Case 1: spend full allowance one second before the boundary, then 1 more on each side of it.
    function test_case1_periodBoundary() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);

        vm.warp(START + PERIOD - 1);
        assertTrue(_mmSpend(d, ALLOWANCE), "MM full spend at end of period 1");
        assertTrue(_cbSpend(p, ALLOWANCE), "CB full spend at end of period 1");
        assertFalse(_mmSpend(d, 1), "MM +1 same period");
        assertFalse(_cbSpend(p, 1), "CB +1 same period");

        vm.warp(START + PERIOD);
        assertTrue(_mmSpend(d, 1), "MM +1 at first second of period 2");
        assertTrue(_cbSpend(p, 1), "CB +1 at first second of period 2");
    }

    // Case 2: zero-value spend.
    function test_case2_zeroValue() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);
        bool mm = _mmSpend(d, 0);
        bool cb = _cbSpend(p, 0);
        emit log_named_string("MM zero spend", mm ? "accepted" : "reverted");
        emit log_named_string("CB zero spend", cb ? "accepted" : "reverted");
        assertTrue(mm);
        assertFalse(cb);
    }

    // Case 3: pause and resume inside one period. Total moved in the period?
    function test_case3_pauseResumeSamePeriod() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);

        assertTrue(_mmSpend(d, 60));
        assertTrue(_cbSpend(p, 60));

        // MetaMask: the account disables, then re-enables the same delegation through its own
        // disableDelegation / enableDelegation (DF DeleGatorCore L364-375, onlyEntryPointOrSelf), which call the manager.
        vm.prank(mmWallet);
        HybridDeleGator(payable(mmWallet)).disableDelegation(d);
        assertFalse(_mmSpend(d, 1), "MM disabled");
        vm.prank(mmWallet);
        HybridDeleGator(payable(mmWallet)).enableDelegation(d);

        // Coinbase: revoke; re-approving the same permission returns false (revocation is permanent),
        // so "resume" means approving a new permission (salt 1).
        vm.prank(address(wallet));
        spm.revoke(p);
        assertFalse(_cbSpend(p, 1), "CB revoked");
        assertFalse(_cbApprove(p), "CB re-approve of revoked hash");
        ISpendPermissionManager.SpendPermission memory p2 = _permission(1);
        assertTrue(_cbApprove(p2));

        bool mm = _mmSpend(d, 60);
        bool cb = _cbSpend(p2, 60);
        emit log_named_string("MM second 60 after resume", mm ? "accepted" : "reverted");
        emit log_named_string("CB second 60 after resume", cb ? "accepted" : "reverted");
        emit log_named_uint("MM moved out of delegator this period", 1_000 - token.balanceOf(mmWallet));
        emit log_named_uint("CB moved out of wallet this period", 1_000 - token.balanceOf(address(wallet)));
        assertFalse(mm);
        assertTrue(cb);
    }

    // Case 10: the agent pays a third address X. The kit's periodic scope does not pin the recipient.
    // Coinbase's spend has no recipient argument; funds always go to the spender.
    function test_case10_recipient() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);

        bool mm = _mmTransfer(d, x, 50);
        emit log_named_string("MM transfer(X, 50) under the kit's periodic scope", mm ? "accepted" : "reverted");
        assertTrue(mm);
        assertEq(token.balanceOf(x), 50, "MM: X received 50");

        assertTrue(_cbSpend(p, 50));
        assertEq(token.balanceOf(spender), 50, "CB: funds went to the spender");
        assertEq(token.balanceOf(x), 50, "CB: X got nothing from Coinbase");

        // The ERC-7715 path can add an optional payee rule: AllowedCalldataEnforcer(startIndex 4, padded payee)
        // (snap-7715-permissions gator-permissions-snap/src/core/payeeCaveat.ts L40-51). With it, X is refused.
        Caveat[] memory base = _sdkPeriodicCaveats();
        Caveat[] memory withPayee = new Caveat[](3);
        withPayee[0] = base[0];
        withPayee[1] = base[1];
        withPayee[2] = Caveat({
            enforcer: address(allowedCalldataEnforcer),
            terms: abi.encodePacked(uint256(4), abi.encode(spender)),
            args: hex""
        });
        Delegation memory dPayee = _sign(withPayee, 1);
        assertFalse(_mmTransfer(dPayee, x, 10), "MM with payee rule: X refused");
        assertTrue(_mmTransfer(dPayee, spender, 10), "MM with payee rule: payee accepted");
    }
}
