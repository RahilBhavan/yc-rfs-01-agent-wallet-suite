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
//
// Every rejection is checked against the exact revert data, so a setup error cannot pass as an expected refusal.
// Each test ends with one ROW line (tab-separated) that script/reproduce.py turns into the results table:
// case, name, class, MetaMask outcome, Coinbase outcome, agree/differ, file:line.

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { ModeLib } from "@erc7579/lib/ModeLib.sol";
import { ExecutionLib } from "@erc7579/lib/ExecutionLib.sol";
import { Execution } from "@erc7579/interfaces/IERC7579Account.sol";

import { DelegationManager } from "df/DelegationManager.sol";
import { IDelegationManager } from "df/interfaces/IDelegationManager.sol";
import { HybridDeleGator } from "df/HybridDeleGator.sol";
import { ERC20PeriodTransferEnforcer } from "df/enforcers/ERC20PeriodTransferEnforcer.sol";
import { NativeTokenPeriodTransferEnforcer } from "df/enforcers/NativeTokenPeriodTransferEnforcer.sol";
import { ValueLteEnforcer } from "df/enforcers/ValueLteEnforcer.sol";
import { AllowedCalldataEnforcer } from "df/enforcers/AllowedCalldataEnforcer.sol";
import { ExactCalldataEnforcer } from "df/enforcers/ExactCalldataEnforcer.sol";
import { TimestampEnforcer } from "df/enforcers/TimestampEnforcer.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Delegation, Caveat, ModeCode } from "df/utils/Types.sol";

import { CoinbaseSmartWallet } from "smart-wallet/CoinbaseSmartWallet.sol";
import { CoinbaseSmartWalletFactory } from "smart-wallet/CoinbaseSmartWalletFactory.sol";
import { MultiOwnable } from "smart-wallet/MultiOwnable.sol";

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

    struct PeriodSpend {
        uint48 start;
        uint48 end;
        uint160 spend;
    }

    error ZeroValue();
    error UnauthorizedSpendPermission();
    error BeforeSpendPermissionStart(uint48 currentTimestamp, uint48 start);
    error AfterSpendPermissionEnd(uint48 currentTimestamp, uint48 end);
    error ExceededSpendPermission(uint256 value, uint256 allowance);

    function approve(SpendPermission calldata p) external returns (bool);
    function approveWithRevoke(
        SpendPermission calldata permissionToApprove,
        SpendPermission calldata permissionToRevoke,
        PeriodSpend calldata expectedLastUpdatedPeriod
    )
        external
        returns (bool);
    function revoke(SpendPermission calldata p) external;
    function spend(SpendPermission memory p, uint160 value) external;
    function getCurrentPeriod(SpendPermission memory p) external view returns (PeriodSpend memory);
}

contract TestToken is ERC20 {
    constructor() ERC20("Test", "TST") { }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

// Case 13: a spender contract that calls spend twice in one transaction.
contract DoubleSpender {
    function spendTwice(
        ISpendPermissionManager spm,
        ISpendPermissionManager.SpendPermission calldata p,
        uint160 a,
        uint160 b
    )
        external
    {
        spm.spend(p, a);
        spm.spend(p, b);
    }
}

contract DifferentialTest is Test {
    uint256 constant ALLOWANCE = 100;
    uint256 constant PERIOD = 1 days;
    uint256 START;
    address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    TestToken token;
    address spender = makeAddr("spender");
    address x = makeAddr("x");
    address sink = makeAddr("sink");

    // MetaMask side
    DelegationManager dm;
    ERC20PeriodTransferEnforcer periodEnforcer;
    NativeTokenPeriodTransferEnforcer nativePeriodEnforcer;
    ValueLteEnforcer valueLteEnforcer;
    AllowedCalldataEnforcer allowedCalldataEnforcer;
    ExactCalldataEnforcer exactCalldataEnforcer;
    TimestampEnforcer timestampEnforcer;
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
        nativePeriodEnforcer = new NativeTokenPeriodTransferEnforcer();
        valueLteEnforcer = new ValueLteEnforcer();
        allowedCalldataEnforcer = new AllowedCalldataEnforcer();
        exactCalldataEnforcer = new ExactCalldataEnforcer();
        timestampEnforcer = new TimestampEnforcer();
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
    function _sdkPeriodicCaveats() internal view returns (Caveat[] memory) {
        return _caveats(ALLOWANCE, START);
    }

    function _caveats(uint256 amount, uint256 start) internal view returns (Caveat[] memory caveats) {
        caveats = new Caveat[](2);
        caveats[0] = Caveat({ enforcer: address(valueLteEnforcer), terms: abi.encode(uint256(0)), args: hex"" });
        caveats[1] = Caveat({
            enforcer: address(periodEnforcer),
            terms: abi.encodePacked(address(token), amount, PERIOD, start),
            args: hex""
        });
    }

    // The bundle plus the expiry caveat the ERC-7715 snap appends: TimestampEnforcer(after = 0, before = end).
    function _withEnd(Caveat[] memory base, uint256 end) internal view returns (Caveat[] memory caveats) {
        caveats = new Caveat[](base.length + 1);
        for (uint256 i; i < base.length; ++i) {
            caveats[i] = base[i];
        }
        caveats[base.length] = Caveat({
            enforcer: address(timestampEnforcer),
            terms: abi.encodePacked(uint128(0), uint128(end)),
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

    function _mmSpend(Delegation memory d, uint256 amt) internal returns (bool ok, bytes memory err) {
        return _mmTransfer(d, spender, amt);
    }

    function _mmTransfer(Delegation memory d, address to, uint256 amt) internal returns (bool ok, bytes memory err) {
        return _mmExec(d, address(token), 0, abi.encodeCall(IERC20.transfer, (to, amt)));
    }

    function _mmExec(
        Delegation memory d,
        address target,
        uint256 value,
        bytes memory data
    )
        internal
        returns (bool ok, bytes memory err)
    {
        bytes[] memory execs = new bytes[](1);
        execs[0] = ExecutionLib.encodeSingle(target, value, data);
        return _mmRedeem(d, execs);
    }

    // One redeemDelegations call with one single-call execution per entry of execs, all under delegation d.
    function _mmRedeem(Delegation memory d, bytes[] memory execs) internal returns (bool ok, bytes memory err) {
        Delegation[] memory chain = new Delegation[](1);
        chain[0] = d;
        bytes[] memory ctx = new bytes[](execs.length);
        ModeCode[] memory modes = new ModeCode[](execs.length);
        for (uint256 i; i < execs.length; ++i) {
            ctx[i] = abi.encode(chain);
            modes[i] = ModeLib.encodeSimpleSingle();
        }
        vm.prank(spender);
        try dm.redeemDelegations(ctx, modes, execs) {
            ok = true;
        } catch (bytes memory e) {
            err = e;
        }
    }

    function _mmDisable(Delegation memory d) internal {
        vm.prank(mmWallet);
        HybridDeleGator(payable(mmWallet)).disableDelegation(d);
    }

    // ---------- Coinbase helpers ----------
    function _permission(uint256 salt) internal view returns (ISpendPermissionManager.SpendPermission memory) {
        return _permission(uint160(ALLOWANCE), uint48(START), type(uint48).max, salt);
    }

    function _permission(
        uint160 allowance,
        uint48 start,
        uint48 end,
        uint256 salt
    )
        internal
        view
        returns (ISpendPermissionManager.SpendPermission memory p)
    {
        p = ISpendPermissionManager.SpendPermission({
            account: address(wallet),
            spender: spender,
            token: address(token),
            allowance: allowance,
            period: uint48(PERIOD),
            start: start,
            end: end,
            salt: salt,
            extraData: hex""
        });
    }

    function _cbApprove(ISpendPermissionManager.SpendPermission memory p) internal returns (bool) {
        vm.prank(address(wallet));
        return spm.approve(p);
    }

    function _cbSpend(ISpendPermissionManager.SpendPermission memory p, uint256 amt) internal returns (bool ok, bytes memory err) {
        vm.prank(spender);
        try spm.spend(p, uint160(amt)) {
            ok = true;
        } catch (bytes memory e) {
            err = e;
        }
    }

    // ---------- Revert data ----------
    function _mmErr(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    function _enfErr(string memory reason) internal pure returns (bytes memory) {
        return _mmErr(string.concat("ERC20PeriodTransferEnforcer:", reason));
    }

    function _cbExceeded(uint256 total, uint256 allowance) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ISpendPermissionManager.ExceededSpendPermission.selector, total, allowance);
    }

    function _assertRevert(bool ok, bytes memory err, bytes memory expected, string memory claim) internal {
        assertFalse(ok, claim);
        assertEq(err, expected, string.concat(claim, ": revert reason"));
    }

    function _moved(address from) internal view returns (uint256) {
        return 1_000 - token.balanceOf(from);
    }

    // ---------- Result rows ----------
    function _row(
        uint256 id,
        string memory name,
        string memory class,
        string memory mm,
        string memory cb,
        bool agree,
        string memory cite
    )
        internal
        view
    {
        console.log(
            string.concat(
                "ROW\t",
                vm.toString(id),
                "\t",
                name,
                "\t",
                class,
                "\t",
                mm,
                "\t",
                cb,
                "\t",
                agree ? "agree" : "differ",
                "\t",
                cite
            )
        );
    }

    // Case 1: spend full allowance one second before the boundary, then 1 more on each side of it.
    function test_case1_periodBoundary() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);

        vm.warp(START + PERIOD - 1);
        (bool mmFull,) = _mmSpend(d, ALLOWANCE);
        (bool cbFull,) = _cbSpend(p, ALLOWANCE);
        assertTrue(mmFull, "MM full spend at end of period 1");
        assertTrue(cbFull, "CB full spend at end of period 1");
        (bool mmOver, bytes memory mmErr) = _mmSpend(d, 1);
        (bool cbOver, bytes memory cbErr) = _cbSpend(p, 1);
        _assertRevert(mmOver, mmErr, _enfErr("transfer-amount-exceeded"), "MM +1 same period");
        _assertRevert(cbOver, cbErr, _cbExceeded(101, 100), "CB +1 same period");

        vm.warp(START + PERIOD);
        (bool mmNext,) = _mmSpend(d, 1);
        (bool cbNext,) = _cbSpend(p, 1);
        assertTrue(mmNext, "MM +1 at first second of period 2");
        assertTrue(cbNext, "CB +1 at first second of period 2");

        _row(
            1,
            "period boundary",
            "like-for-like",
            "100 at S+P-1 ok; +1 transfer-amount-exceeded; +1 at S+P ok",
            "100 at S+P-1 ok; +1 ExceededSpendPermission; +1 at S+P ok",
            mmFull == cbFull && mmOver == cbOver && mmNext == cbNext,
            "lib/sp/src/SpendPermissionManager.sol:540; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:254"
        );
    }

    // Case 2: zero-value spend.
    function test_case2_zeroValue() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);
        (bool mm,) = _mmSpend(d, 0);
        (bool cb, bytes memory cbErr) = _cbSpend(p, 0);
        assertTrue(mm, "MM accepts transfer(spender, 0) under the kit's periodic scope");
        _assertRevert(cb, cbErr, abi.encodeWithSelector(ISpendPermissionManager.ZeroValue.selector), "CB refuses a zero spend");
        assertEq(_moved(mmWallet), 0, "MM: nothing moved");
        assertEq(_moved(address(wallet)), 0, "CB: nothing moved");

        _row(
            2,
            "zero-value spend",
            "like-for-like",
            "transfer(spender, 0) at S+10 accepted",
            "spend(0) at S+10 reverted ZeroValue",
            mm == cb,
            "lib/sp/src/SpendPermissionManager.sol:692; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:210"
        );
    }

    // Case 3: pause and resume inside one period. Total moved in the period?
    function test_case3_pauseResumeSamePeriod() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);

        (bool ok,) = _mmSpend(d, 60);
        assertTrue(ok, "MM first 60");
        (ok,) = _cbSpend(p, 60);
        assertTrue(ok, "CB first 60");

        // MetaMask: the account disables, then re-enables the same delegation through its own
        // disableDelegation / enableDelegation (DF DeleGatorCore L364-375, onlyEntryPointOrSelf), which call the manager.
        _mmDisable(d);
        (bool mmPaused, bytes memory err) = _mmSpend(d, 1);
        _assertRevert(
            mmPaused, err, abi.encodeWithSelector(IDelegationManager.CannotUseADisabledDelegation.selector), "MM disabled"
        );
        vm.prank(mmWallet);
        HybridDeleGator(payable(mmWallet)).enableDelegation(d);

        // Coinbase: revoke; re-approving the same permission returns false (revocation is permanent),
        // so "resume" means approving a new permission (salt 1).
        vm.prank(address(wallet));
        spm.revoke(p);
        (bool cbPaused, bytes memory cbErr) = _cbSpend(p, 1);
        _assertRevert(
            cbPaused,
            cbErr,
            abi.encodeWithSelector(ISpendPermissionManager.UnauthorizedSpendPermission.selector),
            "CB revoked"
        );
        assertFalse(_cbApprove(p), "CB re-approve of revoked hash");
        ISpendPermissionManager.SpendPermission memory p2 = _permission(1);
        assertTrue(_cbApprove(p2));

        (bool mm, bytes memory mmErr) = _mmSpend(d, 60);
        (bool cb,) = _cbSpend(p2, 60);
        _assertRevert(mm, mmErr, _enfErr("transfer-amount-exceeded"), "MM second 60 after resume: counter survived");
        assertTrue(cb, "CB second 60 under the new permission");
        assertEq(_moved(mmWallet), 60, "MM moved 60 in the period");
        assertEq(_moved(address(wallet)), 120, "CB moved 120 in the period");

        _row(
            3,
            "pause and resume in one period",
            "revocation model",
            "60 ok; disable+enable; 60 transfer-amount-exceeded; 60 moved",
            "60 ok; revoke; new salt; 60 ok; 120 moved",
            _moved(mmWallet) == _moved(address(wallet)),
            "lib/df/src/DelegationManager.sol:90; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:190; lib/sp/src/SpendPermissionManager.sol:658"
        );
    }

    // Case 4: first spend exactly at the start timestamp (setUp leaves block.timestamp == START).
    function test_case4_exactlyAtStart() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        assertEq(block.timestamp, START);
        (bool mm,) = _mmSpend(d, 1);
        (bool cb,) = _cbSpend(p, 1);
        assertTrue(mm, "MM accepts a spend at t == S");
        assertTrue(cb, "CB accepts a spend at t == S");

        _row(
            4,
            "exactly at start",
            "like-for-like",
            "1 at S ok",
            "1 at S ok",
            mm == cb,
            "lib/sp/src/SpendPermissionManager.sol:519; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:199"
        );
    }

    // Case 5: one second before the start.
    function test_case5_beforeStart() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START - 1);
        (bool mm, bytes memory mmErr) = _mmSpend(d, 1);
        (bool cb, bytes memory cbErr) = _cbSpend(p, 1);
        _assertRevert(mm, mmErr, _enfErr("transfer-not-started"), "MM refuses a spend at S-1");
        _assertRevert(
            cb,
            cbErr,
            abi.encodeWithSelector(
                ISpendPermissionManager.BeforeSpendPermissionStart.selector, uint48(START - 1), uint48(START)
            ),
            "CB refuses a spend at S-1"
        );

        _row(
            5,
            "one second before start",
            "like-for-like",
            "1 at S-1 transfer-not-started",
            "1 at S-1 BeforeSpendPermissionStart",
            mm == cb,
            "lib/sp/src/SpendPermissionManager.sol:519; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:199"
        );
    }

    // Case 6: end boundary. Coinbase end = S+5P. MetaMask adds TimestampEnforcer(after = 0, before = S+5P).
    // The bare kit bundle has no end, reported alongside.
    function test_case6_endBoundary() public {
        uint256 end = START + 5 * PERIOD;
        Delegation memory d = _sign(_withEnd(_sdkPeriodicCaveats(), end), 0);
        Delegation memory bare = _delegation(1);
        ISpendPermissionManager.SpendPermission memory p = _permission(uint160(ALLOWANCE), uint48(START), uint48(end), 0);
        _cbApprove(p);

        vm.warp(end - 1);
        (bool mmLast,) = _mmSpend(d, 1);
        (bool cbLast,) = _cbSpend(p, 1);
        assertTrue(mmLast, "MM with end caveat accepts at end-1");
        assertTrue(cbLast, "CB accepts at end-1");

        vm.warp(end);
        (bool mmEnd, bytes memory mmErr) = _mmSpend(d, 1);
        (bool cbEnd, bytes memory cbErr) = _cbSpend(p, 1);
        _assertRevert(mmEnd, mmErr, _mmErr("TimestampEnforcer:expired-delegation"), "MM with end caveat refuses at end");
        _assertRevert(
            cbEnd,
            cbErr,
            abi.encodeWithSelector(ISpendPermissionManager.AfterSpendPermissionEnd.selector, uint48(end), uint48(end)),
            "CB refuses at end"
        );
        (bool mmBare,) = _mmSpend(bare, 1);
        assertTrue(mmBare, "MM bare bundle has no end and accepts at S+5P");

        _row(
            6,
            "end boundary",
            "like-for-like",
            "with TimestampEnforcer: 1 at end-1 ok; 1 at end expired-delegation (bare bundle: ok at end)",
            "1 at end-1 ok; 1 at end AfterSpendPermissionEnd",
            mmLast == cbLast && mmEnd == cbEnd,
            "lib/sp/src/SpendPermissionManager.sol:521; lib/df/src/enforcers/TimestampEnforcer.sol:45"
        );
    }

    // Case 7: the last period is cut short by the end; does it keep the full allowance?
    function test_case7_truncatedLastPeriod() public {
        uint256 end = START + PERIOD + PERIOD / 2;
        Delegation memory d = _sign(_withEnd(_sdkPeriodicCaveats(), end), 0);
        ISpendPermissionManager.SpendPermission memory p = _permission(uint160(ALLOWANCE), uint48(START), uint48(end), 0);
        _cbApprove(p);

        vm.warp(START + PERIOD);
        (bool mmFull,) = _mmSpend(d, ALLOWANCE);
        (bool cbFull,) = _cbSpend(p, ALLOWANCE);
        assertTrue(mmFull, "MM full allowance in the truncated last period");
        assertTrue(cbFull, "CB full allowance in the truncated last period");
        ISpendPermissionManager.PeriodSpend memory cur = spm.getCurrentPeriod(p);
        assertEq(cur.end, end, "CB: last period truncated at end");

        vm.warp(end - 1);
        (bool mmOver, bytes memory mmErr) = _mmSpend(d, 1);
        (bool cbOver, bytes memory cbErr) = _cbSpend(p, 1);
        _assertRevert(mmOver, mmErr, _enfErr("transfer-amount-exceeded"), "MM +1 in the last period");
        _assertRevert(cbOver, cbErr, _cbExceeded(101, 100), "CB +1 in the last period");

        _row(
            7,
            "truncated last period",
            "like-for-like",
            "100 at S+P ok; +1 at end-1 transfer-amount-exceeded",
            "100 at S+P ok (period ends at end); +1 at end-1 ExceededSpendPermission",
            mmFull == cbFull && mmOver == cbOver,
            "lib/sp/src/SpendPermissionManager.sol:546; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:254"
        );
    }

    // Case 8: raise the allowance mid-period from 100 to 150 after spending 60.
    function test_case8_allowanceChangeMidPeriod() public {
        uint256 raised = 150;
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);
        (bool ok,) = _mmSpend(d, 60);
        assertTrue(ok, "MM 60 under A=100");
        (ok,) = _cbSpend(p, 60);
        assertTrue(ok, "CB 60 under A=100");

        // MetaMask: disable the old delegation, sign a new one with periodAmount 150.
        _mmDisable(d);
        Delegation memory d2 = _sign(_caveats(raised, START), 0);
        // Coinbase: approveWithRevoke, with the expected last period of the old permission.
        ISpendPermissionManager.SpendPermission memory p2 = _permission(uint160(raised), uint48(START), type(uint48).max, 0);
        vm.prank(address(wallet));
        assertTrue(
            spm.approveWithRevoke(
                p2, p, ISpendPermissionManager.PeriodSpend({ start: uint48(START), end: uint48(START + PERIOD), spend: 60 })
            )
        );

        (bool mm,) = _mmSpend(d2, raised);
        (bool cb,) = _cbSpend(p2, raised);
        assertTrue(mm, "MM 150 under the new delegation");
        assertTrue(cb, "CB 150 under the new permission");
        bool same = mm == cb;

        bytes memory mmErr;
        bytes memory cbErr;
        (mm, mmErr) = _mmSpend(d, 1);
        (cb, cbErr) = _cbSpend(p, 1);
        _assertRevert(
            mm, mmErr, abi.encodeWithSelector(IDelegationManager.CannotUseADisabledDelegation.selector), "MM old disabled"
        );
        _assertRevert(
            cb, cbErr, abi.encodeWithSelector(ISpendPermissionManager.UnauthorizedSpendPermission.selector), "CB old revoked"
        );
        same = same && mm == cb;
        (mm, mmErr) = _mmSpend(d2, 1);
        (cb, cbErr) = _cbSpend(p2, 1);
        _assertRevert(mm, mmErr, _enfErr("transfer-amount-exceeded"), "MM new +1");
        _assertRevert(cb, cbErr, _cbExceeded(151, 150), "CB new +1");
        same = same && mm == cb;

        assertEq(_moved(mmWallet), 210, "MM moved 210 in one period");
        assertEq(_moved(address(wallet)), 210, "CB moved 210 in one period");

        _row(
            8,
            "allowance change mid-period",
            "like-for-like",
            "60 ok; disable, sign A=150; 150 ok; 210 moved in the period",
            "60 ok; approveWithRevoke A=150; 150 ok; 210 moved in the period",
            same && _moved(mmWallet) == _moved(address(wallet)),
            "lib/sp/src/SpendPermissionManager.sol:367; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:190"
        );
    }

    // Case 9: three idle periods do not carry over.
    function test_case9_longIdleNoRollover() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);
        (bool ok,) = _mmSpend(d, 10);
        assertTrue(ok);
        (ok,) = _cbSpend(p, 10);
        assertTrue(ok);

        vm.warp(START + 4 * PERIOD + 10);
        (bool mmDouble, bytes memory mmErr) = _mmSpend(d, 2 * ALLOWANCE);
        (bool cbDouble, bytes memory cbErr) = _cbSpend(p, 2 * ALLOWANCE);
        _assertRevert(mmDouble, mmErr, _enfErr("transfer-amount-exceeded"), "MM 2A after idle periods");
        _assertRevert(cbDouble, cbErr, _cbExceeded(200, 100), "CB 2A after idle periods");
        (bool mmOne,) = _mmSpend(d, ALLOWANCE);
        (bool cbOne,) = _cbSpend(p, ALLOWANCE);
        assertTrue(mmOne, "MM A after idle periods");
        assertTrue(cbOne, "CB A after idle periods");

        _row(
            9,
            "long idle, no rollover",
            "like-for-like",
            "10 in period 1; 200 in period 5 transfer-amount-exceeded; 100 ok",
            "10 in period 1; 200 in period 5 ExceededSpendPermission; 100 ok",
            mmDouble == cbDouble && mmOne == cbOne,
            "lib/sp/src/SpendPermissionManager.sol:551; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:258"
        );
    }

    // Case 10: the agent pays a third address X. The kit's periodic scope does not pin the recipient.
    // Coinbase's spend has no recipient argument; funds always go to the spender.
    function test_case10_recipient() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.warp(START + 10);

        (bool mm,) = _mmTransfer(d, x, 50);
        assertTrue(mm, "MM transfer(X, 50) under the kit's periodic scope");
        assertEq(token.balanceOf(x), 50, "MM: X received 50");

        (bool cb,) = _cbSpend(p, 50);
        assertTrue(cb);
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
        (bool ok, bytes memory err) = _mmTransfer(dPayee, x, 10);
        _assertRevert(ok, err, _mmErr("AllowedCalldataEnforcer:invalid-calldata"), "MM with payee rule: X refused");
        (ok,) = _mmTransfer(dPayee, spender, 10);
        assertTrue(ok, "MM with payee rule: payee accepted");

        _row(
            10,
            "recipient",
            "recipient (CB cannot name one)",
            "transfer(X, 50) ok, X got 50 (payee rule: X refused)",
            "spend(50) paid the spender; X cannot be named",
            false,
            "lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:209; lib/sp/src/SpendPermissionManager.sol:425"
        );
    }

    // Case 11: native-token periodic permission used to make an ERC-20 call with value 0.
    // The kit's native periodic scope is [ExactCalldata("0x"), NativeTokenPeriodTransfer(amount, duration, start)]
    // (smart-accounts-kit caveatBuilder/scope/nativeTokenPeriodicScope.ts L50-57).
    function test_case11_nativeTwinArbitraryCalldata() public {
        vm.deal(mmWallet, 1 ether);
        vm.deal(address(wallet), 1 ether);
        bytes memory nativeTerms = abi.encodePacked(ALLOWANCE, PERIOD, START);
        Caveat[] memory sdk = new Caveat[](2);
        sdk[0] = Caveat({ enforcer: address(exactCalldataEnforcer), terms: hex"", args: hex"" });
        sdk[1] = Caveat({ enforcer: address(nativePeriodEnforcer), terms: nativeTerms, args: hex"" });
        Caveat[] memory bareCaveats = new Caveat[](1);
        bareCaveats[0] = sdk[1];
        Delegation memory d = _sign(sdk, 0);
        Delegation memory bare = _sign(bareCaveats, 1);
        vm.warp(START + 10);

        bytes memory tokenCall = abi.encodeCall(IERC20.transfer, (x, 1_000));
        (bool mm, bytes memory mmErr) = _mmExec(d, address(token), 0, tokenCall);
        _assertRevert(mm, mmErr, _mmErr("ExactCalldataEnforcer:invalid-calldata"), "MM kit native scope refuses calldata");
        (bool mmNative,) = _mmExec(d, spender, 1, hex"");
        assertTrue(mmNative, "MM kit native scope sends 1 wei");
        assertEq(spender.balance, 1, "MM: spender got 1 wei");
        (bool mmBare,) = _mmExec(bare, address(token), 0, tokenCall);
        assertTrue(mmBare, "MM bare native enforcer accepts the ERC-20 call");
        assertEq(token.balanceOf(x), 1_000, "MM bare: X received the wallet's 1000 TST");

        // Coinbase: a native permission has no calldata input; spend only forwards native token to the spender.
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        p.token = NATIVE_TOKEN;
        _cbApprove(p);
        (bool cb,) = _cbSpend(p, 1);
        assertTrue(cb, "CB native spend of 1 wei");
        assertEq(spender.balance, 2, "CB: spender got 1 more wei");
        assertEq(_moved(address(wallet)), 0, "CB moved no TST");

        _row(
            11,
            "native twin with ERC-20 calldata",
            "no CB calldata path",
            "kit scope: token.transfer(X, 1000) invalid-calldata, 0 TST moved (bare enforcer: ok, 1000 TST moved)",
            "native spend has no calldata input; spend(1) moved 1 wei, 0 TST",
            !mm && _moved(address(wallet)) == 0,
            "lib/df/src/enforcers/ExactCalldataEnforcer.sol:44; lib/df/src/enforcers/NativeTokenPeriodTransferEnforcer.sol:169; lib/sp/src/SpendPermissionManager.sol:731"
        );
    }

    // Case 12: the delegate tries approve or transferFrom instead of transfer.
    function test_case12_wrongMethod() public {
        Delegation memory d = _delegation(0);
        vm.warp(START + 10);
        (bool mmApprove, bytes memory err1) = _mmExec(d, address(token), 0, abi.encodeCall(IERC20.approve, (x, 50)));
        _assertRevert(mmApprove, err1, _enfErr("invalid-method"), "MM refuses approve");
        (bool mmFrom, bytes memory err2) =
            _mmExec(d, address(token), 0, abi.encodeCall(IERC20.transferFrom, (mmWallet, x, 50)));
        _assertRevert(mmFrom, err2, _enfErr("invalid-execution-length"), "MM refuses transferFrom (100-byte calldata)");

        // Coinbase: the manager has no call-passing entry point. The spender is not a wallet owner, so a direct
        // wallet.execute(approve) is refused by the wallet itself.
        vm.prank(spender);
        (bool cb, bytes memory cbErr) = address(wallet).call(
            abi.encodeCall(CoinbaseSmartWallet.execute, (address(token), 0, abi.encodeCall(IERC20.approve, (x, 50))))
        );
        _assertRevert(cb, cbErr, abi.encodeWithSelector(MultiOwnable.Unauthorized.selector), "CB spender cannot call the wallet");
        assertEq(token.allowance(mmWallet, x), 0);
        assertEq(token.allowance(address(wallet), x), 0);

        _row(
            12,
            "wrong method",
            "no CB method path",
            "approve invalid-method; transferFrom invalid-execution-length",
            "no entry point; spender's wallet.execute(approve) Unauthorized",
            mmApprove == cb && mmFrom == cb,
            "lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:183; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:188; lib/sp/lib/smart-wallet/src/CoinbaseSmartWallet.sol:80"
        );
    }

    function _expectBatchModeRefused(Delegation memory d) internal {
        Execution[] memory batch = new Execution[](1);
        batch[0] = Execution({ target: address(token), value: 0, callData: abi.encodeCall(IERC20.transfer, (spender, 1)) });
        Delegation[] memory chain = new Delegation[](1);
        chain[0] = d;
        bytes[] memory ctx = new bytes[](1);
        ctx[0] = abi.encode(chain);
        ModeCode[] memory modes = new ModeCode[](1);
        modes[0] = ModeLib.encodeSimpleBatch();
        bytes[] memory execs = new bytes[](1);
        execs[0] = ExecutionLib.encodeBatch(batch);
        vm.prank(spender);
        vm.expectRevert(bytes("CaveatEnforcer:invalid-call-type"));
        dm.redeemDelegations(ctx, modes, execs);
    }

    // Case 13: two spends in one transaction count against one period budget on both sides.
    function test_case13_twoSpendsOneTx() public {
        Delegation memory d = _delegation(0);
        DoubleSpender ds = new DoubleSpender();
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        p.spender = address(ds);
        _cbApprove(p);
        vm.warp(START + 10);

        bytes[] memory two60 = new bytes[](2);
        two60[0] = ExecutionLib.encodeSingle(address(token), 0, abi.encodeCall(IERC20.transfer, (spender, 60)));
        two60[1] = two60[0];
        (bool mmOver, bytes memory mmErr) = _mmRedeem(d, two60);
        _assertRevert(mmOver, mmErr, _enfErr("transfer-amount-exceeded"), "MM 60+60 in one redeemDelegations");
        (bool cbOver, bytes memory cbErr) =
            address(ds).call(abi.encodeCall(DoubleSpender.spendTwice, (spm, p, uint160(60), uint160(60))));
        _assertRevert(cbOver, cbErr, _cbExceeded(120, 100), "CB 60+60 in one transaction");
        assertEq(_moved(mmWallet), 0, "MM: whole tx rolled back");
        assertEq(_moved(address(wallet)), 0, "CB: whole tx rolled back");

        bytes[] memory two50 = new bytes[](2);
        two50[0] = ExecutionLib.encodeSingle(address(token), 0, abi.encodeCall(IERC20.transfer, (spender, 50)));
        two50[1] = two50[0];
        (bool mmFit,) = _mmRedeem(d, two50);
        assertTrue(mmFit, "MM 50+50 in one tx");
        ds.spendTwice(spm, p, 50, 50);
        assertEq(_moved(mmWallet), 100);
        assertEq(_moved(address(wallet)), 100);

        // A batch-mode execution is refused outright by the caveats (only single-call mode counts).
        _expectBatchModeRefused(d);

        _row(
            13,
            "two spends in one transaction",
            "like-for-like",
            "60+60 in one redeemDelegations transfer-amount-exceeded, 0 moved; 50+50 ok",
            "60+60 from a spender contract ExceededSpendPermission, 0 moved; 50+50 ok",
            mmOver == cbOver && _moved(mmWallet) == _moved(address(wallet)),
            "lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:218; lib/sp/src/SpendPermissionManager.sol:712"
        );
    }

    // Case 14: start = 0 in the configuration.
    function test_case14_zeroStart() public {
        ISpendPermissionManager.SpendPermission memory p = _permission(uint160(ALLOWANCE), 0, type(uint48).max, 0);
        bool cbApproved = _cbApprove(p);
        assertTrue(cbApproved, "CB approves start = 0");
        vm.warp(START + 10);
        (bool cb,) = _cbSpend(p, ALLOWANCE);
        assertTrue(cb, "CB spends under start = 0");
        assertEq(spm.getCurrentPeriod(p).start, START + 10 - ((START + 10) % PERIOD), "CB periods aligned to t = 0");

        // The kit refuses startDate 0 before signing (delegation-core erc20TokenPeriodTransfer.ts L103-104; not run
        // here). A hand-built delegation with startDate 0 is refused at first redemption.
        Delegation memory d = _sign(_caveats(ALLOWANCE, 0), 0);
        (bool mm, bytes memory mmErr) = _mmSpend(d, 1);
        _assertRevert(mm, mmErr, _enfErr("invalid-zero-start-date"), "MM refuses startDate 0");

        _row(
            14,
            "zero start in config",
            "configuration (kit refuses to build it)",
            "hand-built startDate 0: invalid-zero-start-date",
            "start 0 approved; spend(100) ok",
            mm == cb,
            "lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:194; lib/sp/src/SpendPermissionManager.sol:651"
        );
    }

    // Case 15: a per-period amount above uint160.
    function test_case15_amountAboveUint160() public {
        uint256 big = uint256(type(uint160).max) + 1;
        token.mint(mmWallet, big);
        Delegation memory d = _sign(_caveats(big, START), 0);
        vm.warp(START + 10);
        (bool mm,) = _mmSpend(d, big);
        assertTrue(mm, "MM accepts periodAmount and a spend of 2^160");
        assertEq(token.balanceOf(spender), big);

        // Coinbase's allowance field is uint160. The same struct with allowance 2^160 in that word fails ABI
        // decoding, which reverts with no data.
        bytes memory wide = abi.encodePacked(
            ISpendPermissionManager.approve.selector,
            abi.encode(
                WidePermission({
                    account: address(wallet),
                    spender: spender,
                    token: address(token),
                    allowance: big,
                    period: uint48(PERIOD),
                    start: uint48(START),
                    end: type(uint48).max,
                    salt: 0,
                    extraData: hex""
                })
            )
        );
        vm.prank(address(wallet));
        (bool cb, bytes memory cbErr) = address(spm).call(wide);
        _assertRevert(cb, cbErr, hex"", "CB cannot take an allowance of 2^160");

        _row(
            15,
            "amount above uint160",
            "expressibility (CB is uint160)",
            "periodAmount 2^160 signed; spend of 2^160 ok",
            "allowance 2^160 does not decode (uint160 field); approve reverts",
            mm == cb,
            "lib/sp/src/SpendPermissionManager.sol:37; lib/df/src/enforcers/ERC20PeriodTransferEnforcer.sol:157"
        );
    }

    struct WidePermission {
        address account;
        address spender;
        address token;
        uint256 allowance;
        uint48 period;
        uint48 start;
        uint48 end;
        uint256 salt;
        bytes extraData;
    }

    // Case 16: the token transfer itself fails (balance below the spend). The counter must not move.
    function test_case16_underlyingTransferFails() public {
        Delegation memory d = _delegation(0);
        ISpendPermissionManager.SpendPermission memory p = _permission(0);
        _cbApprove(p);
        vm.prank(mmWallet);
        token.transfer(sink, 950);
        vm.prank(address(wallet));
        token.transfer(sink, 950);
        vm.warp(START + 10);

        (bool mm, bytes memory mmErr) = _mmSpend(d, 60);
        (bool cb, bytes memory cbErr) = _cbSpend(p, 60);
        _assertRevert(
            mm,
            mmErr,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, mmWallet, 50, 60),
            "MM spend of 60 with balance 50"
        );
        _assertRevert(
            cb,
            cbErr,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(wallet), 50, 60),
            "CB spend of 60 with balance 50"
        );
        (uint256 mmAvailable,,) =
            periodEnforcer.getAvailableAmount(dm.getDelegationHash(d), address(dm), d.caveats[1].terms);
        uint256 cbSpent = spm.getCurrentPeriod(p).spend;
        assertEq(mmAvailable, 100, "MM counter did not move");
        assertEq(cbSpent, 0, "CB counter did not move");

        _row(
            16,
            "underlying transfer fails",
            "like-for-like",
            "60 with balance 50: ERC20InsufficientBalance; 100 still available",
            "60 with balance 50: ERC20InsufficientBalance; 0 spent in period",
            mm == cb && mmAvailable == ALLOWANCE - cbSpent,
            "lib/df/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol:195; lib/sp/src/SpendPermissionManager.sol:424"
        );
    }
}
