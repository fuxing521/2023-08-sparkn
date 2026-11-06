# Sparkn — Smart Contract Security Research

**Historical Audit Reproduction | Solidity · EVM · Foundry**

Independent smart contract security research based on the publicly disclosed 2023 Sparkn audit contest.

**Language:** English | [简体中文](./README-CN.md)

---

## 1. Overview

This repository documents an independent, local reproduction and technical analysis of selected security findings from the historical **Sparkn** smart contract audit contest.

Sparkn uses deterministic CREATE2 Proxy deployments to manage contest prize distributions. Prize tokens can be transferred to a predicted Proxy address before deployment. A Proxy subsequently delegates execution to a Distributor implementation, which distributes ERC20 rewards to winners and pays the remaining commission to a designated Stadium address.

The research focuses on:

- Signature authorization and ECDSA verification.
- EIP-712 structured-data encoding.
- Proxy execution and `delegatecall`.
- CREATE2 address prediction and pre-funding.
- ERC20 reward distribution and accounting.
- Transaction rollback and denial-of-service conditions.
- Reproducible vulnerability testing with Foundry.

**Research output:**

- 3 historical security findings reproduced and analyzed.
- 3 English findings and 3 Chinese findings.
- 3 dedicated vulnerability PoC test files.
- 1 additional CREATE2 pre-funding research test.
- 8 passing tests across four individually executed Foundry test suites.

All demonstrations use local test accounts and simulated assets.

## 2. Security Findings

The severity labels below refer to the **historical contest classifications**, not newly assigned ratings.

### H-01 — Cross-Implementation Signature Reuse

**Severity:** High (Historical Rating)

**Affected Contract:** `src/ProxyFactory.sol`

**Root Cause:** The Organizer's signed digest does not bind the `implementation` address, although that address is part of the contest's CREATE2 deployment identity.

**Verified Behavior:** A single valid Organizer signature successfully authorizes distributions through two different registered Distributor implementations.

**Evidence:** Two local Foundry tests passed.

**Reports and PoC:**

- [Foundry PoC](./test/F01SignatureScope.t.sol)
- [English Finding](./findings/H01-Signature-Reuse-Across-Implementations.md)
- [中文 Finding](./findings/H01-Signature-Reuse-Across-Implementations-CN.md)

### M-01 — Non-Standard EIP-712 Digest Calculation

**Severity:** Medium (Historical Rating)

**Affected Contract:** `src/ProxyFactory.sol`

**Root Cause:** The implementation computes its message hash without the EIP-712 structure type hash and the required hashing of the dynamic `bytes` field.

**Verified Behavior:** The original Sparkn digest differs from the digest calculated using the selected standards-compliant EIP-712 schema. A signature generated from the standard digest is rejected by the original Factory.

**Evidence:** Two local Foundry tests passed.

**Reports and PoC:**

- [Foundry PoC](./test/M01EIP712Digest.t.sol)
- [English Finding](./findings/M01-Nonstandard-EIP712-Digest.md)
- [中文 Finding](./findings/M01-Nonstandard-EIP712-Digest-CN.md)

### M-02 — Stadium Blacklist Blocks Prize Distribution

**Severity:** Medium (Historical Rating)

**Affected Contract:** `src/Distributor.sol`

**Root Cause:** Winner payouts depend on a mandatory commission transfer to the fixed Stadium address.

**Verified Behavior:** A mock ERC20 restriction on the Stadium recipient causes the distribution to revert, rolling back previous winner transfers.

**Evidence:** Two local Foundry unit tests passed.

**Scope Limitation:** This PoC directly tests Distributor logic and does not execute the complete Proxy deployment path.

**Reports and PoC:**

- [Foundry PoC](./test/M02StadiumBlacklist.t.sol)
- [English Finding](./findings/M02-Stadium-Blacklist-Blocks-Distribution.md)
- [中文 Finding](./findings/M02-Stadium-Blacklist-Blocks-Distribution-CN.md)

---

## 3. Additional Security Research

### CREATE2 Pre-Funding Address Mismatch

**Category:** Supplemental Security Research — Not a Confirmed Protocol Vulnerability

Sparkn allows sponsors to pre-fund deterministic Proxy addresses before contract deployment.

This study compares two scenarios:

1. Tokens are transferred to an incorrect predicted address, leaving the actual registered Proxy without the intended funds.
2. Tokens are transferred to the correct predicted address, allowing the Factory to deploy the Proxy and distribute rewards.

**Verified Behavior:** The wrong-address scenario fails to distribute the misplaced tokens, while the correctly funded deployment succeeds.

**Evidence:** Two local Foundry tests passed.

This test illustrates address prediction and pre-funding risks. It does not independently establish a protocol-level vulnerability or permanent fund loss.

**Test:** [CREATE2PrefundAddressMismatch.t.sol](./test/CREATE2PrefundAddressMismatch.t.sol)

---

## 4. Testing and Reproduction

### Requirements

- Foundry (`forge`)
- Solidity compiler compatible with `0.8.18`
- Project dependencies, including `forge-std` and OpenZeppelin Contracts

Run commands from the project root directory.

### H-01: Signature Reuse

```bash
forge test --match-contract F01SignatureScopeTest -vv
```

**Observed result:** 2 passed, 0 failed.

### M-01: EIP-712 Digest Compatibility

```bash
forge test --match-contract M01EIP712DigestTest -vv
```

**Observed result:** 2 passed, 0 failed.

### M-02: Stadium Blacklist

```bash
forge test --match-contract M02StadiumBlacklistTest -vv
```

**Observed result:** 2 passed, 0 failed.

### Additional CREATE2 Research

```bash
forge test --match-contract CREATE2PrefundAddressMismatchTest -vv
```

**Observed result:** 2 passed, 0 failed.

### Complete Project Test Suite

```bash
forge test
```

This command runs the broader project test suite. The eight passing results above were observed from the four individually executed research test suites; they should not be interpreted as verification that every original repository test passes.

For detailed call traces:

```bash
forge test --match-contract F01SignatureScopeTest -vvvv
```

---

## 5. Research Scope and Technical Skills

### Solidity and EVM

- Solidity contract analysis
- Contract calls and `delegatecall`
- Proxy execution context
- EVM transaction atomicity
- ABI encoding and function selectors

### Cryptographic Authorization

- ECDSA signing and signature recovery
- EIP-712 domain separation
- Structured-data hashing
- Authorization scope analysis
- Cross-implementation signature reuse

### Smart Contract Testing

- Foundry unit and integration-style testing
- `vm.sign()`, `vm.prank()`, and `vm.warp()`
- Expected revert testing
- Mock ERC20 tokens
- State and balance assertions
- Reproducible proof-of-concept design

### Protocol Analysis

- CREATE2 address derivation
- Pre-deployment funding
- ERC20 reward distribution
- Fee accounting
- Trust boundaries and business-logic assumptions

---

## 6. Repository Structure

```text
2023-08-sparkn/
├── src/
│   ├── ProxyFactory.sol
│   ├── Proxy.sol
│   └── Distributor.sol
│
├── test/
│   ├── F01SignatureScope.t.sol
│   ├── M01EIP712Digest.t.sol
│   ├── M02StadiumBlacklist.t.sol
│   ├── CREATE2PrefundAddressMismatch.t.sol
│   └── ...
│
├── findings/
│   ├── H01-Signature-Reuse-Across-Implementations.md
│   ├── H01-Signature-Reuse-Across-Implementations-CN.md
│   ├── M01-Nonstandard-EIP712-Digest.md
│   ├── M01-Nonstandard-EIP712-Digest-CN.md
│   ├── M02-Stadium-Blacklist-Blocks-Distribution.md
│   └── M02-Stadium-Blacklist-Blocks-Distribution-CN.md
│
├── README.md
├── README-CN.md
└── foundry.toml
```

The original project files and testing infrastructure are retained where applicable.

---

## 7. Attribution and Research Disclosure

This project is an independent educational and technical reproduction of previously disclosed security findings from the **2023 Sparkn audit contest**.

The historical vulnerabilities were not originally discovered by the author of this research repository.

The original Sparkn contracts and project materials remain attributable to their respective creators.

The research findings document local verification results, observed behavior, testing limitations, and proposed mitigations.

No unauthorized interaction with deployed protocols or real assets was performed.

A passing PoC demonstrates the behavior asserted by that test. It does not automatically establish every potential exploit scenario or prove that the original contracts have been fixed.

**Remediation Status:** The historical business contracts were not patched as part of these reproductions, and post-fix regression testing has not been performed.

---

## 8. Original Project Documentation and References

- [Original Sparkn Repository](https://github.com/Cyfrin/2023-08-sparkn)
- [CodeHawks — Sparkn Historical Audit Report](https://www.codehawks.com/report/cllcnja1h0001lc08z7w0orxx)
- [Original Test Documentation](./test/README.md)
- [EIP-712 Specification](https://eips.ethereum.org/EIPS/eip-712)
- [Foundry Documentation](https://book.getfoundry.sh/)

---

**中文版：** [README-CN.md](./README-CN.md)
