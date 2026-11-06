# Sparkn — 智能合约安全研究作品集

**历史审计漏洞复现｜Solidity · EVM · Foundry**

基于 2023 年 Sparkn 公开审计比赛的独立智能合约安全研究项目。

**语言切换：** [English](./README.md) | 简体中文

---

## 1. 项目简介

本项目基于 **Sparkn 2023 年公开智能合约审计比赛**，对部分历史安全问题进行独立代码分析、本地漏洞复现和技术总结。

Sparkn 采用 CREATE2 创建确定性 Proxy 地址，允许 Sponsor 在 Proxy 正式部署前，提前向预测地址转入 ERC20 奖金。

后续通过 ProxyFactory 部署 Proxy，再由 Proxy 使用 `delegatecall` 执行 Distributor 的奖金分配逻辑，将代币转给获奖者及指定的 Stadium 手续费接收地址。

本项目主要研究：

- 签名授权与 ECDSA 验证。
- EIP-712 结构化数据编码。
- Proxy 与 `delegatecall` 执行机制。
- CREATE2 地址预测及预存资金。
- ERC20 奖金分配与资金会计。
- 事务回滚、拒绝服务与业务逻辑风险。
- Foundry 漏洞测试及审计证据整理。

**已完成研究成果：**

- 3 项历史公开安全问题的本地复现与分析。
- 3 份英文 Finding 和 3 份中文 Finding。
- 3 个独立漏洞 PoC 测试文件。
- 1 个 CREATE2 预存地址补充研究案例。
- 4 组 Foundry 测试，合计 8 项测试通过。

全部验证均使用本地环境、测试账户及模拟代币完成。

---

## 2. 安全漏洞研究成果

以下评级沿用**历史审计比赛的原始评级**，不代表本次研究独立重新评定的严重程度。

### H-01 — 签名可跨不同 Implementation 重复使用

**漏洞等级：** High（高危，历史评级）

**受影响合约：** `src/ProxyFactory.sol`

**漏洞根本原因：** Organizer 签名摘要没有绑定 `implementation` 地址，而该地址又是比赛注册及 CREATE2 Proxy 身份的一部分。

**已验证行为：** 同一个有效 Organizer 签名，可以用于两个不同且已注册的 Distributor Implementation，并分别成功完成 Proxy 部署和奖金分配。

**测试结果：** 2 PASS，0 FAIL。

**研究文件：**

- [Foundry 测试代码](./test/F01SignatureScope.t.sol)
- [中文 Finding](./findings/H01-Signature-Reuse-Across-Implementations-CN.md)
- [English Finding](./findings/H01-Signature-Reuse-Across-Implementations.md)

### M-01 — EIP-712 摘要编码不符合标准

**漏洞等级：** Medium（中危，历史评级）

**受影响合约：** `src/ProxyFactory.sol`

**漏洞根本原因：** 结构化消息哈希计算缺少 EIP-712 所要求的 TypeHash，并且未按照规范单独哈希动态 `bytes` 字段。

**已验证行为：** Sparkn 原始 Digest 与按照选定标准 EIP-712 结构计算的 Digest 不相等。使用标准结构化摘要生成的签名被原始 Factory 拒绝。

**测试结果：** 2 PASS，0 FAIL。

**研究文件：**

- [Foundry 测试代码](./test/M01EIP712Digest.t.sol)
- [中文 Finding](./findings/M01-Nonstandard-EIP712-Digest-CN.md)
- [English Finding](./findings/M01-Nonstandard-EIP712-Digest.md)

### M-02 — Stadium 被代币列入黑名单导致奖金分配失败

**漏洞等级：** Medium（中危，历史评级）

**受影响合约：** `src/Distributor.sol`

**漏洞根本原因：** Distributor 强制向固定的 Stadium 地址发送剩余代币作为手续费，导致获奖者奖金发放依赖该地址的收款能力。

**已验证行为：** 当模拟 ERC20 禁止 Stadium 收款时，手续费转账失败，引起整笔分配回滚，获奖者之前的转账也被撤销。

**测试结果：** 2 PASS，0 FAIL。

**验证范围：** 当前为 Distributor 单元 PoC，没有执行完整的 Factory → Proxy → Distributor 集成路径。

**研究文件：**

- [Foundry 测试代码](./test/M02StadiumBlacklist.t.sol)
- [中文 Finding](./findings/M02-Stadium-Blacklist-Blocks-Distribution-CN.md)
- [English Finding](./findings/M02-Stadium-Blacklist-Blocks-Distribution.md)

---

## 3. 补充安全研究

### CREATE2 预存奖金地址不匹配风险

**研究分类：** 补充安全研究，暂不作为独立确认的协议漏洞。

Sparkn 使用 CREATE2 计算 Proxy 的确定性地址，Sponsor 可以在 Proxy 部署前向该地址预存奖励代币。

本研究通过两个场景验证：

**场景一：错误地址预存奖金**

将 1,000 个模拟 Token 转入错误参数计算出的 Proxy 预测地址。

Factory 后续根据正确的比赛注册信息部署另一 Proxy，由于实际使用的 Proxy 没有收到奖金，分配失败。

**场景二：正确地址预存奖金**

将 1,000 个模拟 Token 转入正确的 Proxy 预测地址。

Factory 成功部署 Proxy，并按照约定比例完成奖金分配。

**测试结果：** 2 PASS，0 FAIL。

该研究证明了 CREATE2 参数一致性对于预存资金的重要性，但尚未证明协议自身存在独立漏洞，也没有证明资金永久无法恢复。

**测试文件：**

[CREATE2PrefundAddressMismatch.t.sol](./test/CREATE2PrefundAddressMismatch.t.sol)

---

## 4. 主要研究内容

### 4.1 签名授权安全

研究 ECDSA、EIP-712、签名摘要、授权范围和 Implementation 参数绑定。

通过实际 PoC 验证同一签名在不同 Implementation 配置中的重复使用问题。

### 4.2 Proxy 与 EVM 执行机制

分析 ProxyFactory、Proxy 和 Distributor 的调用关系。

重点理解：

- CREATE2 确定性地址。
- Proxy 部署前资金预存。
- `call()` 与 `delegatecall()` 的区别。
- `msg.sender` 和 `address(this)` 在代理执行中的含义。
- EVM 事务原子性与 Revert。

### 4.3 ERC20 奖金分配与会计

分析获奖者分配比例、协议手续费和资金余额变化。

通过模拟具有黑名单功能的 ERC20，验证外部代币行为可能对协议奖金分配造成的影响。

### 4.4 Foundry 审计测试

结合实际场景使用：

- `setUp()` 初始化测试环境。
- `vm.prank()` 模拟调用者。
- `vm.sign()` 生成测试签名。
- `vm.warp()` 模拟比赛结束时间。
- `vm.expectRevert()` 验证失败行为。
- `assertEq()`、`assertNotEq()`、`assertGt()` 检查状态及余额。

---

## 5. Foundry 测试与漏洞复现

### 5.1 环境要求

- Foundry（forge）
- 兼容 Solidity 0.8.18 的编译器
- 项目所需的 forge-std、OpenZeppelin 等依赖

在项目根目录打开 VS Code 终端并运行测试。

### H-01：签名跨 Implementation 复用

```bash
forge test --match-contract F01SignatureScopeTest -vv
```

**实际结果：** 2 PASS，0 FAIL。

### M-01：EIP-712 摘要编码差异

```bash
forge test --match-contract M01EIP712DigestTest -vv
```

**实际结果：** 2 PASS，0 FAIL。

### M-02：Stadium 黑名单分配失败

```bash
forge test --match-contract M02StadiumBlacklistTest -vv
```

**实际结果：** 2 PASS，0 FAIL。

### CREATE2 补充研究

```bash
forge test --match-contract CREATE2PrefundAddressMismatchTest -vv
```

**实际结果：** 2 PASS，0 FAIL。

### 运行整个 Foundry 项目测试

```bash
forge test
```

该命令用于运行项目的全部测试，包括原始仓库的其他测试。

当前已核对的是上述四组独立研究测试，共 8 项 PASS；尚不能据此宣称原始仓库全部测试都已通过。

如需查看详细调用过程，可以使用：

```bash
forge test --match-contract F01SignatureScopeTest -vvvv
```

---

## 6. 研究范围与能力展示

本项目重点展示以下技术研究能力。

**Solidity / EVM**

理解智能合约调用关系、ABI 编码、状态变化及底层调用机制。

**Proxy / CREATE2**

理解确定性部署、Implementation、Proxy 预测地址及预存资金。

**Signature Security**

能够分析 ECDSA 签名验证、EIP-712 摘要和授权参数绑定。

**Foundry Testing**

能够构建本地 PoC，模拟测试账户、生成签名、调整时间、验证 Revert 和资金余额。

**Business Logic & Accounting**

能够围绕实际资金流分析奖金分配、手续费、转账失败及状态回滚问题。

**Security Reporting**

能够将历史漏洞研究整理为结构统一、包含 PoC 证据及测试局限的中英文 Finding。

---

## 7. 项目结构与原始来源

### 主要目录

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

### 原始项目及参考资料

- [Sparkn 原始 GitHub 仓库](https://github.com/Cyfrin/2023-08-sparkn)
- [CodeHawks — Sparkn 历史审计报告](https://www.codehawks.com/report/cllcnja1h0001lc08z7w0orxx)
- [原始测试说明](./test/README.md)
- [EIP-712 官方规范](https://eips.ethereum.org/EIPS/eip-712)
- [Foundry 官方文档](https://book.getfoundry.sh/)

---

## 8. 研究声明

本项目属于对 **2023 年 Sparkn 公开历史审计比赛**的独立本地研究与漏洞复现。

H-01、M-01、M-02 均为历史公开问题，本研究不主张首次发现权。

原始业务合约和项目代码归相应开发者所有。本作品集保留原始项目来源，并明确区分原始合约与新增的研究测试。

本地 PoC 主要用于验证历史问题的技术机制、资金状态变化和安全影响。

测试通过只代表对应验证行为已经出现，不代表已证明所有潜在攻击后果。

本项目没有修改原始业务合约实施漏洞修复，也没有执行修复后回归测试。

所有安全测试均使用本地 Foundry 环境、模拟代币和测试账户，不涉及真实资产攻击或未经授权的链上操作。

---

**英文首页：** [README.md](./README.md)
