# M-01 | deployProxyAndDistributeBySignature() 的摘要计算不符合 EIP-712 规范

**项目名称：** Sparkn  
**漏洞等级：** Medium（中危）  
**漏洞类型：** EIP-712 编码不规范 / 签名兼容性缺陷  
**受影响合约：** `src/ProxyFactory.sol`  
**受影响函数：** `deployProxyAndDistributeBySignature()`  
**测试文件：** `test/M01EIP712Digest.t.sol`  
**测试工具：** Foundry  


## 1. Summary / 漏洞摘要

Sparkn 使用 EIP-712 域分隔机制验证 Organizer 对奖金分配操作的授权签名。

然而，`ProxyFactory.deployProxyAndDistributeBySignature()` 在计算签名摘要时，直接使用 `keccak256(abi.encode(contestId, data))` 作为结构化消息哈希。

这一计算方式没有包含 EIP-712 要求的 `typeHash`，也没有按照 EIP-712 规范对动态类型 `bytes data` 单独计算哈希。

因此，Sparkn 原始实现产生的签名摘要，与按照相应 EIP-712 结构化消息规则计算的摘要不同。

这会导致标准 EIP-712 签名工具与协议内部签名验证逻辑之间存在兼容性问题。即使 Organizer 使用正确私钥对约定的结构化消息签名，Factory 仍可能拒绝该签名。

本地 Foundry 测试已验证两种摘要不同，并成功复现 Factory 拒绝标准结构化签名的行为。

## 2. Root Cause / 漏洞根本原因

问题位于 `ProxyFactory.sol` 的 `deployProxyAndDistributeBySignature()`。

原始合约使用：

```solidity
bytes32 digest = _hashTypedDataV4(
    keccak256(abi.encode(contestId, data))
);

if (ECDSA.recover(digest, signature) != organizer)
    revert ProxyFactory__InvalidSignature();
```

`_hashTypedDataV4()` 负责将 EIP-712 Domain Separator 与传入的消息哈希组合，生成最终签名摘要。

但它不会自动为业务消息补充 `typeHash`，也不会自动执行动态字段的 EIP-712 编码。

按照 EIP-712 规范，结构化消息哈希应遵循：

```text
structHash = keccak256(
    abi.encode(
        typeHash,
        encodedField1,
        encodedField2,
        ...
    )
)
```

例如，采用如下结构化类型：

```solidity
Distribute(bytes32 contestId,bytes data)
```

对应的编码方式应为：

```solidity
bytes32 typeHash = keccak256(
    "Distribute(bytes32 contestId,bytes data)"
);

bytes32 structHash = keccak256(
    abi.encode(
        typeHash,
        contestId,
        keccak256(data)
    )
);

bytes32 digest = _hashTypedDataV4(structHash);
```

两种写法有两个关键区别：

**第一，缺少 TypeHash。**

原始实现没有将结构化消息的类型信息纳入 `structHash`。

**第二，动态 bytes 字段编码不符合规范。**

原始实现直接将 `bytes data` 参与普通 ABI 编码，而标准 EIP-712 结构化编码要求先对该动态字段计算 `keccak256(data)`。

因此：

```text
Sparkn 原始 structHash
≠
标准 EIP-712 structHash
```

最终：

```text
Sparkn Digest
≠
标准 EIP-712 Digest
```

根本原因是：**合约虽然使用了 OpenZeppelin 的 EIP-712 摘要封装函数，却没有正确实现业务消息本身的 EIP-712 结构化编码。**

## 3. Impact / 漏洞影响

### 3.1 标准签名兼容性问题

使用标准 EIP-712 结构化消息签名的客户端，会生成与 Sparkn 原始实现不同的签名摘要。

当该签名提交至 `ProxyFactory` 时，合约按照自己的非标准摘要进行签名恢复，可能得到与 Organizer 不一致的地址，从而触发：

```solidity
revert ProxyFactory__InvalidSignature();
```

本地 PoC 已经验证此行为。

### 3.2 前端与钱包集成风险

采用标准 `eth_signTypedData`、`eth_signTypedData_v4` 或兼容 EIP-712 的签名工具时，如果前端按照正常结构化消息编码而没有适配 Sparkn 的特殊算法，就可能生成无法通过链上验证的签名。

这增加了钱包、前端及第三方工具的集成难度。

### 3.3 签名授权语义不一致

缺少 `typeHash` 使签名消息不具备标准 EIP-712 所要求的完整结构化类型绑定。

这削弱了协议对标准结构化签名机制的兼容性，并使相关授权逻辑更难被标准工具独立验证。

### 3.4 影响范围说明

本次测试已证明摘要差异及标准结构化签名被拒绝。

但尚未证明：

- 攻击者能够伪造 Organizer 签名。
- 该编码差异可直接导致奖金被盗。
- 签名可以在不同比赛之间成功重放。
- 真实生产环境已经发生资金损失。

签名未绑定 Implementation、缺少 nonce 或 deadline 等问题，应作为独立风险分别分析，不应全部归因于本 Finding。

## 4. Proof of Concept (PoC) / 漏洞验证

### 4.1 Test Environment / 测试环境

**测试框架：** Foundry  
**Solidity 版本：** 0.8.18  
**测试文件：** `test/M01EIP712Digest.t.sol`  
**原始业务合约：** `src/ProxyFactory.sol`  
**模拟合约：** `test/mock/MockERC20.sol`  
**签名工具：** `vm.sign()`、`vm.addr()`、`ecrecover()`

本次研究使用本地 Foundry 测试环境，不涉及真实资产或未经授权的链上操作。

### 4.2 Test Scenario / 测试场景

测试包含两个独立场景。

**场景 A：比较 Sparkn 与标准 EIP-712 摘要。**

使用相同的 `contestId`、`data`、Domain Separator 和签名账户，分别计算：

1. Sparkn 原始摘要。
2. 按照 `Distribute(bytes32 contestId,bytes data)` 类型定义计算的标准 EIP-712 摘要。

随后使用 `vm.sign()` 分别对两个摘要签名，并使用 `ecrecover()` 验证签名与摘要的对应关系。

预期两个摘要不相等，且针对其中一个摘要生成的签名不能直接作为另一个摘要的有效授权签名。

**场景 B：验证 Factory 拒绝标准签名。**

使用标准 EIP-712 结构化摘要生成签名，然后调用原始 `ProxyFactory.deployProxyAndDistributeBySignature()`。

预期 Factory 在签名校验阶段抛出 `ProxyFactory__InvalidSignature()`。

本场景主要验证签名校验分支，不测试后续 Proxy 部署及奖金分配。

### 4.3 Foundry PoC / 测试代码

**关键代码一：计算两个结构化摘要。**

```solidity
bytes32 sparknStructHash = keccak256(
    abi.encode(contestId, data)
);

bytes32 typeHash = keccak256(
    "Distribute(bytes32 contestId,bytes data)"
);

bytes32 standardStructHash = keccak256(
    abi.encode(
        typeHash,
        contestId,
        keccak256(data)
    )
);
```

**关键代码二：计算最终 Digest。**

```solidity
bytes32 sparknDigest = keccak256(
    abi.encodePacked(
        hex"1901",
        domainSeparator,
        sparknStructHash
    )
);

bytes32 standardDigest = keccak256(
    abi.encodePacked(
        hex"1901",
        domainSeparator,
        standardStructHash
    )
);
```

**关键代码三：对比摘要。**

```solidity
assertNotEq(
    sparknStructHash,
    standardStructHash
);

assertNotEq(
    sparknDigest,
    standardDigest
);
```

**关键代码四：Factory 拒绝标准签名。**

```solidity
vm.expectRevert(
    bytes4(
        keccak256(
            "ProxyFactory__InvalidSignature()"
        )
    )
);

factory.deployProxyAndDistributeBySignature(
    organizer,
    contestId,
    address(0xBEEF),
    signature,
    data
);
```

完整 PoC 位于：

`test/M01EIP712Digest.t.sol`

### 4.4 Key Assertions / 关键断言

**断言一：`assertNotEq(sparknStructHash, standardStructHash)`**

证明两种结构化消息编码产生不同的哈希值。

**断言二：`assertNotEq(sparknDigest, standardDigest)`**

证明采用相同 Domain Separator 时，最终签名摘要依然不同。

**断言三：`ecrecover()` 交叉验证**

证明对一个摘要生成的签名，在对应摘要下能够恢复正确签名者，但不能直接在另一摘要下作为相同签名者的有效签名。

**断言四：`vm.expectRevert()`**

证明 Factory 在收到标准结构化摘要生成的签名后，执行结果符合预期的 `InvalidSignature` 错误。

### 4.5 Test Execution / 测试执行

实际执行命令：

```bash
forge test --match-contract M01EIP712DigestTest -vv
```

实际终端结果：

```text
[PASS] testCompareDigests()
[PASS] testFactoryRejectsStandardSignature()

Suite result: ok. 2 passed; 0 failed; 0 skipped
```

测试执行成功，两项测试均通过。

### 4.6 Test Results and Analysis / 测试结果分析

**已验证结果：**

1. Sparkn 原始 `structHash` 与标准 EIP-712 `structHash` 不相等。
2. 两种计算方式产生不同的最终 Digest。
3. 签名恢复结果与签署时使用的 Digest 绑定。
4. 使用标准结构化摘要签署的消息被原始 Factory 拒绝。
5. 两项 Foundry 测试全部通过。

**验证局限：**

1. 测试没有证明完整奖金分配流程的端到端影响。
2. 尚未直接调用浏览器钱包或链下 `eth_signTypedData_v4` 接口。
3. 测试中的 `Distribute` 是为对比选定的 EIP-712 结构类型。
4. 没有证明攻击者能够利用该编码差异直接获取资产。
5. 没有执行修复后回归测试。

因此，本次 PoC 成功复现的是**标准签名编码不兼容及相应链上验签失败行为**，而非直接资金盗取。

## 5. Recommendation / 修复建议

建议按照 EIP-712 规范完整实现结构化消息编码。

首先，为奖金分配授权定义明确的结构类型及对应 `TYPEHASH`：

```solidity
bytes32 constant DISTRIBUTE_TYPEHASH =
    keccak256(
        "Distribute(bytes32 contestId,bytes data)"
    );
```

然后正确计算结构化消息哈希：

```solidity
bytes32 structHash = keccak256(
    abi.encode(
        DISTRIBUTE_TYPEHASH,
        contestId,
        keccak256(data)
    )
);
```

最后再执行：

```solidity
bytes32 digest = _hashTypedDataV4(structHash);
```

同时建议：

1. 前端和链上合约使用完全一致的 EIP-712 Types、Domain 和消息字段。
2. 使用标准 EIP-712 客户端生成测试签名，与链上恢复结果进行对照。
3. 如需增加 Implementation、nonce、deadline 等字段，应根据独立的授权与重放风险分析设计。
4. 对已经投入使用的签名方案，制定兼容性迁移策略，避免直接修改摘要算法使旧签名意外失效。

**预期修复行为：**

当 Organizer 使用与协议公开类型定义一致的标准 EIP-712 方式签署消息时，Factory 应能够恢复正确的 Organizer 地址，并在其他业务条件满足时继续奖金分配流程。

## 6. Fix Verification / 修复验证

**验证状态：Not Performed（尚未执行）。**

本次研究未修改原始 `ProxyFactory.sol`，也未部署修复版本执行回归测试。

后续修复验证应至少确认：

1. 链上 Digest 与标准客户端计算的 Digest 一致。
2. 合法 Organizer 的标准 EIP-712 签名能够通过验证。
3. 错误签名仍然被拒绝。
4. 不同 Domain 或不同消息内容不能错误地复用签名。
5. 已有签名迁移策略不会引入新的授权风险。

本报告不声明该问题已经修复。

## 7. Conclusion / 审计结论

Sparkn 的 `deployProxyAndDistributeBySignature()` 虽然使用 EIP-712 域分隔机制，但业务消息的结构化哈希计算不符合 EIP-712 规范。

其实现缺少 `typeHash`，并且没有对动态 `bytes data` 字段采用规定的哈希编码方式。

本地 Foundry PoC 已确认：两种签名摘要不同，按所选标准结构化类型生成的签名无法直接通过原始 Factory 验证。

**测试结果：2 PASS，0 FAIL。**

本 Finding 复现了历史审计中报告的 EIP-712 兼容性问题，验证范围限于编码差异及签名校验行为。



