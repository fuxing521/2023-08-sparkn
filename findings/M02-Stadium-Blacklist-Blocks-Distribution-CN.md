# M-02 | STADIUM_ADDRESS 被代币列入黑名单可导致奖金分配失败

## 基础信息

项目名称： Sparkn

漏洞等级： Medium（中危）

漏洞类型： 拒绝服务（DoS）/ 业务逻辑缺陷

受影响合约： src/Distributor.sol

受影响函数： distribute()、_distribute()、_commissionTransfer()

测试文件： test/M02StadiumBlacklist.t.sol

测试工具： Foundry



**原始源码：** [Cyfrin/2023-08-sparkn — Distributor.sol](https://github.com/Cyfrin/2023-08-sparkn/blob/main/src/Distributor.sol)

**本地 PoC：** [M02StadiumBlacklist.t.sol](../test/M02StadiumBlacklist.t.sol)

## 1. Summary / 漏洞摘要

Sparkn 使用 `Distributor` 合约向比赛获奖者分配 ERC20 奖金，并将剩余代币作为协议手续费转给固定的 `STADIUM_ADDRESS`。

如果奖励代币具有地址黑名单功能，并且 `STADIUM_ADDRESS` 被禁止接收该代币，那么手续费转账将失败，导致整个奖金分配事务回滚。

即使获奖者本身没有被禁止收款，之前执行的获奖者转账也会被撤销，造成奖金分配不可用。

当相关限制持续存在、又缺乏可用的恢复机制时，奖金可能长期无法分配。

该问题属于依赖特定 ERC20 行为触发的条件性拒绝服务风险。

## 2. Root Cause / 漏洞根本原因

`Distributor.sol` 的 `_distribute()` 首先按照分配比例向获奖者发送代币，然后无条件调用 `_commissionTransfer()`：

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

`_commissionTransfer()` 的实现如下：

```solidity
function _commissionTransfer(IERC20 token) internal {
    token.safeTransfer(
        STADIUM_ADDRESS,
        token.balanceOf(address(this))
    );
}
```

问题在于：

- `STADIUM_ADDRESS` 在 Distributor 部署时设置为 `immutable`，当前实例无法直接修改。
- 手续费支付是奖金分配流程中不可跳过的步骤。
- 当奖励代币拒绝向 Stadium 转账时，`safeTransfer()` 会导致分配事务失败。
- 事务回滚将撤销同一调用内此前成功执行的获奖者转账。

**根本原因是将全部获奖者的奖金发放与一个固定手续费接收地址的收款能力强制绑定，缺少适用的失败处理或资金恢复机制。**

## 3. Impact / 漏洞影响

当获准使用的奖励代币拒绝向 Stadium 地址转账时，可能产生以下影响：

1. **奖金分配失败：** 即使所有获奖者都可以正常接收代币，整笔分配仍会 Revert。
2. **获奖者无法领取奖金：** 由于 EVM 事务原子性，之前执行的获奖者转账全部撤销。
3. **协议可用性下降：** 只要 Stadium 收款限制持续存在，同样的分配操作就可能持续失败。
4. **资金可访问性风险：** 预存奖金可能长期滞留在相关持币地址，直至限制解除或通过适用的其他机制恢复。

## 4. Proof of Concept (PoC) / 漏洞验证

### 4.1 Test Environment / 测试环境

本次采用 Foundry 本地测试环境，使用：

- 原始 `ProxyFactory.sol` 和 `Distributor.sol`。
- 本地编写的 `StadiumBlockedToken` 模拟 ERC20。
- 两个模拟获奖者地址及一个 Stadium 地址。
- `vm.prank()` 模拟 Factory 的调用者身份。
- 1,000 个仅用于测试的模拟 Token。

本次为 **Distributor 单元 PoC**。测试直接向 Distributor 预存代币并调用 `distribute()`，未执行完整的 Factory → Proxy → delegatecall 路径。

在真实 Sparkn 业务流程中，奖金应预存于 Proxy 预测地址；本次局部测试不把 Distributor 的测试余额误称为真实协议的资金存放方式。

### 4.2 Test Scenario / 测试场景

测试设定：

| 项目 | 数值 |
|---|---:|
| 初始模拟奖金 | 1,000 Token |
| Winner A 分配比例 | 60% |
| Winner B 分配比例 | 35% |
| Stadium 剩余手续费 | 5% |

**正常场景：**

Winner A 收到 600 Token，Winner B 收到 350 Token，Stadium 收到 50 Token，Distributor 的测试余额为 0。

**异常场景：**

先调用 `setBlockStadium(true)`，使模拟 ERC20 拒绝向 Stadium 转账。

执行相同的分配后，预期转账触发 Revert，所有获奖者余额保持为 0，1,000 Token 仍留在 Distributor 的测试地址。

### 4.3 Foundry PoC / 测试代码

模拟 ERC20 的核心限制：

```solidity
if (blockStadium && to == stadium) {
    revert BlockedRecipient(to);
}
```

关键漏洞复现测试：

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

另一个正常分配测试 `testNormalDistribution()` 用于建立基准，确认在未启用黑名单时奖金能够正常发放。

完整测试代码见 `test/M02StadiumBlacklist.t.sol`。

### 4.4 Key Assertions / 关键断言

| 断言 | 验证目的 |
|---|---|
| `vm.expectRevert(...)` | 确认失败来源于 Stadium 收款限制 |
| `balanceOf(winnerA) == 0` | 确认 Winner A 的转账被撤销 |
| `balanceOf(winnerB) == 0` | 确认 Winner B 的转账被撤销 |
| `balanceOf(stadium) == 0` | 确认 Stadium 未收到手续费 |
| `balanceOf(distributor) == 1000e18` | 确认本次分配失败后原有测试资金完整保留 |

### 4.5 Test Execution / 测试执行

实际执行命令：

```bash
forge test --match-contract M02StadiumBlacklistTest -vv
```

终端记录：

```text
[PASS] testBlockedStadiumRollsBackWinners()
[PASS] testNormalDistribution()

Suite result: ok. 2 passed; 0 failed; 0 skipped
```

### 4.6 Test Results and Analysis / 测试结果分析

两项 Foundry 测试全部通过。

正常场景验证了奖金比例计算与基础转账行为。

异常场景验证了 Stadium 收款限制会使 Distributor 分配事务回滚，并撤销本次对获奖者执行的转账。

**已验证：**

- 模拟 ERC20 可以触发 Stadium 收款失败。
- Distributor 对该失败进行回滚。
- 获奖者未实际收到奖金。
- 测试资金未因回滚而减少。

**尚未验证：**

- 完整 ProxyFactory → Proxy → Distributor 集成执行。
- 真实 ERC20 发生 Stadium 黑名单限制的具体概率。
- 所有可能的资金恢复路径。
- 修复后行为及回归测试。
- 真实链上资产损失。

因此，本 PoC 证明了漏洞的核心业务机制，而不是全部潜在经济影响。

## 5. Recommendation / 修复建议

建议将获奖者奖金发放与协议手续费收款失败的处理适度解耦。

优先考虑以下改进：

1. 允许通过严格授权的治理流程更新或迁移手续费接收地址，并保留相应事件记录。
2. 为手续费转账失败提供经过审计的恢复方案，例如独立的待支付手续费账本和后续补领机制。
3. 对具有黑名单、冻结等限制的奖励代币建立兼容性评估与风险管理流程。
4. 对已预存奖金但无法正常分配的比赛提供明确、受权限约束的恢复流程。

若采用手续费延期支付设计，应确保获奖者不会获得超出其应得份额的资产，并持续追踪协议待收手续费，避免引入新的会计漏洞。

**预期修复行为：** Stadium 暂时无法收款时，不应无条件导致所有正常获奖者的奖金长期不可领取；协议应存在可审计且受控的处理机制。

## 6. Fix Verification / 修复验证

**状态：Not Performed / 尚未执行。**

本次研究未修改 Sparkn 原始业务合约，也未对任何修复版本执行回归测试。

后续修复验证应至少覆盖正常奖金发放、Stadium 收款受限、手续费后续结算及资金守恒等情况。

本报告不声称该漏洞已被修复。

## 7. Conclusion / 审计结论

Sparkn Distributor 的奖金分配流程依赖固定 Stadium 手续费接收地址能够正常接收奖励代币。

当该地址被代币禁止收款时，强制手续费转账将导致整个分配事务回滚，使原本具备收款条件的获奖者也无法获得奖金。

本地 Foundry 单元 PoC 已成功复现该异常行为，运行结果为 **2 PASS、0 FAIL**。

该风险属于条件性拒绝服务及资金可访问性问题，存在持续性奖金分配受阻的可能性，但不等同于已经证明资金永久锁死。



