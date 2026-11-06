# M-02 | A Blacklisted STADIUM_ADDRESS Can Block Prize Distribution

## Basic Information

Project: Sparkn

Severity: Medium

Vulnerability Category: Denial of Service (DoS) / Business Logic

Affected Contract: src/Distributor.sol

Affected Functions: distribute(), _distribute(), _commissionTransfer()

Test File: test/M02StadiumBlacklist.t.sol

Testing Framework: Foundry


**Original Source:** [Cyfrin/2023-08-sparkn — Distributor.sol](https://github.com/Cyfrin/2023-08-sparkn/blob/main/src/Distributor.sol)

**Local PoC:** [M02StadiumBlacklist.t.sol](../test/M02StadiumBlacklist.t.sol)

## 1. Summary

Sparkn's `Distributor` contract distributes ERC20 rewards to contest winners and transfers the remaining tokens to a fixed `STADIUM_ADDRESS` as the protocol commission.

If a supported reward token restricts transfers to `STADIUM_ADDRESS`, the mandatory commission transfer reverts, causing the entire prize distribution transaction to fail.

Consequently, previously executed winner transfers are rolled back, even when the winners themselves are eligible to receive the token.

If the restriction persists and no applicable recovery mechanism is available, prize funds may remain inaccessible through the intended distribution flow.

This is a conditional denial-of-service issue arising from the protocol's dependency on the token-level transfer permissions of a fixed fee recipient.

## 2. Root Cause

The `_distribute()` function transfers rewards to winners before unconditionally invoking `_commissionTransfer()`:

```solidity
for (uint256 i; i < winnersLength;) {
    uint256 amount =
        totalAmount * percentages[i] / BASIS_POINTS;

    erc20.safeTransfer(winners[i], amount);

    unchecked {
        ++i;
    }
}

_commissionTransfer(erc20);
```

The commission transfer is implemented as follows:

```solidity
function _commissionTransfer(IERC20 token) internal {
    token.safeTransfer(
        STADIUM_ADDRESS,
        token.balanceOf(address(this))
    );
}
```

`STADIUM_ADDRESS` is immutable in the deployed Distributor instance.

The distribution flow does not provide an alternative fee recipient or an independent mechanism to handle a failed commission payment.

When the reward token rejects a transfer to Stadium, `safeTransfer()` causes the transaction to revert. Because EVM transactions are atomic, earlier transfers to winners are reverted as well.

**The root cause is the strict coupling of all winner payouts to the transferability of the remaining reward balance to a single immutable fee recipient.**

## 3. Impact

The issue can have the following consequences:

1. **Distribution failure:** A blacklisted fee recipient prevents the entire payout transaction from completing.
2. **Winner payout denial:** Eligible winners do not receive their rewards because earlier transfers are reverted.
3. **Persistent service disruption:** Subsequent distribution attempts may continue to fail for as long as the token restriction remains active.
4. **Fund accessibility risk:** Pre-funded rewards may remain at the relevant holding address until the restriction is lifted or another applicable recovery mechanism is available.

## 4. Proof of Concept (PoC)

### 4.1 Test Environment

The reproduction uses a local Foundry environment with:

- The original Sparkn `ProxyFactory.sol` and `Distributor.sol`.
- A custom `StadiumBlockedToken` ERC20 mock.
- Two winner addresses and a designated Stadium address.
- `vm.prank()` to simulate the Factory caller.
- 1,000 units of a locally minted test token.

This is a **Distributor unit-level PoC**.

The test directly funds the Distributor instance and invokes `distribute()` with a simulated Factory caller. It does not exercise the complete Factory → Proxy → `delegatecall` execution path.

In Sparkn's intended deployment flow, contest rewards are pre-funded to the predicted Proxy address. The direct funding used here is limited to the unit-test setup.

### 4.2 Test Scenario

The test uses the following distribution:

| Recipient | Percentage | Expected Amount |
|---|---:|---:|
| Winner A | 60% | 600 tokens |
| Winner B | 35% | 350 tokens |
| Stadium | 5% | 50 tokens |
| **Total** | **100%** | **1,000 tokens** |

**Baseline scenario:** The token permits transfers to Stadium. Both winners and the fee recipient receive their expected amounts.

**Failure scenario:** The mock token is configured to reject transfers to Stadium. The same distribution is expected to revert, leaving both winner balances unchanged and retaining all 1,000 test tokens at the Distributor address.

### 4.3 Foundry PoC

The mock ERC20 enforces the restriction with:

```solidity
if (blockStadium && to == stadium) {
    revert BlockedRecipient(to);
}
```

The primary regression-style reproduction test is:

```solidity
function testBlockedStadiumRollsBackWinners() public {
    token.setBlockStadium(true);

    vm.expectRevert(
        abi.encodeWithSelector(
            StadiumBlockedToken.BlockedRecipient.selector,
            stadium
        )
    );

    _distribute();

    assertEq(token.balanceOf(winnerA), 0);
    assertEq(token.balanceOf(winnerB), 0);
    assertEq(token.balanceOf(stadium), 0);

    assertEq(
        token.balanceOf(address(distributor)),
        1000e18
    );
}
```

The companion `testNormalDistribution()` establishes the expected payout behavior without the transfer restriction.

The complete source is available at `test/M02StadiumBlacklist.t.sol`.

### 4.4 Key Assertions

| Assertion | Purpose |
|---|---|
| `vm.expectRevert(...)` | Confirms that the mock's Stadium transfer restriction triggers the revert |
| Winner A balance equals zero | Confirms that Winner A's payout was rolled back |
| Winner B balance equals zero | Confirms that Winner B's payout was rolled back |
| Stadium balance equals zero | Confirms that the fee payment was not completed |
| Distributor balance equals 1,000 tokens | Confirms that the test funds remain intact after the reverted transaction |

### 4.5 Test Execution

Command executed:

```bash
forge test --match-contract M02StadiumBlacklistTest -vv
```

Observed Foundry output:

```text
[PASS] testBlockedStadiumRollsBackWinners()
[PASS] testNormalDistribution()

Suite result: ok. 2 passed; 0 failed; 0 skipped
```

### 4.6 Test Results and Analysis

Both local Foundry tests passed.

The baseline test confirms that the expected 60% / 35% / 5% distribution completes when Stadium can receive the reward token.

The failure test confirms that rejecting the Stadium transfer causes a revert and rolls back the previously executed winner payments.

**Verified behavior:** The blacklisted fee recipient blocks unit-level distribution, winner balances remain unchanged, and test funds are preserved.

**Limitations:** The PoC does not cover full Proxy integration, real-world token-blacklist likelihood, all recovery paths, a patched implementation, or actual on-chain losses.

Accordingly, the evidence establishes the core failure mechanism without claiming to prove every possible downstream economic consequence.

## 5. Recommendation

The protocol should reduce the dependency between winner payouts and the ability of one fixed address to receive protocol fees.

Recommended mitigations include:

1. Introduce a strictly controlled mechanism to migrate or update the commission recipient, with appropriate authorization and event logging.
2. Consider an independently accounted fee-settlement mechanism that permits delayed collection when the fee recipient cannot receive the token.
3. Establish compatibility and risk controls for whitelisted reward tokens that support blacklisting or transfer restrictions.
4. Provide an auditable and permission-controlled recovery procedure for contests whose rewards cannot be distributed normally.

Any deferred-fee design must preserve reward accounting and ensure that the protocol's outstanding commission obligations remain enforceable.

**Expected behavior after remediation:** A temporarily restricted fee recipient should not automatically make otherwise valid winner rewards indefinitely inaccessible. An authorized, auditable resolution mechanism should be available.

## 6. Fix Verification

**Status: Not Performed.**

The original Sparkn business contracts were not modified as part of this research.

No patched implementation or post-fix regression test was executed.

Future verification should cover successful payout processing, restricted fee recipients, deferred commission settlement, and conservation of funds.

This report does not claim that the issue has been fixed.

## 7. Conclusion

Sparkn's Distributor depends on a fixed commission recipient being able to receive the reward token.

When the token rejects the Stadium transfer, the mandatory commission payment reverts the entire distribution transaction, preventing otherwise eligible winners from receiving their rewards.

The local Foundry PoC reproduced the behavior with **2 passing tests and 0 failures**.

This constitutes a conditional denial-of-service and fund-accessibility risk. Prolonged inaccessibility is possible, but permanent fund lockup has not been independently established by the present PoC.


