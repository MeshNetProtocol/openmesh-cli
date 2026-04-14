/**
 * 自动续费模块
 *
 * 定时检查即将到期的订阅并自动续费
 * 通过 CDP Server Wallet + Paymaster 实现 0 ETH 续费
 */

const { ethers } = require('ethers');
const { sendTransactionViaCDP } = require('./cdp-transaction');

// 合约 ABI
const CONTRACT_ABI = [
  'function executeRenewal(address identityAddress) external',
  'function finalizeExpired(address identityAddress, bool forceClosed) external',
  'function subscriptions(address identityAddress) external view returns (address identityAddress, address payerAddress, uint96 lockedPrice, uint256 planId, uint256 lockedPeriod, uint256 startTime, uint256 expiresAt, bool autoRenewEnabled, bool isActive)',
  'function getUserIdentities(address user) external view returns (address[] memory)',
  'function getSubscription(address identityAddress) external view returns (address user, uint256 planId, uint256 startTime, uint256 endTime, bool isActive, bool autoRenew, uint256 nextPlanId, uint256 trafficUsedDaily, uint256 trafficUsedMonthly, uint256 lastResetDaily, uint256 lastResetMonthly)',
];

/**
 * 自动续费服务
 */
class RenewalService {
  constructor({ cdpClient, serverWalletAccount, contractAddress, paymasterEndpoint }) {
    this.cdpClient = cdpClient;
    this.serverWalletAccount = serverWalletAccount;
    this.contractAddress = contractAddress;
    this.paymasterEndpoint = paymasterEndpoint;

    // 配置
    this.checkIntervalSeconds = parseInt(process.env.RENEWAL_CHECK_INTERVAL_SECONDS || '60');
    this.precheckHours = parseInt(process.env.RENEWAL_PRECHECK_HOURS || '24');
    this.maxRenewalFails = parseInt(process.env.MAX_RENEWAL_FAILS || '3');

    // 内存存储 (生产环境应使用数据库)
    this.subscriptions = new Map(); // userAddress -> { failCount, lastCheck, ... }

    console.log('🔄 自动续费服务配置:');
    console.log(`  检查间隔: ${this.checkIntervalSeconds} 秒`);
    console.log(`  预检时间: ${this.precheckHours} 小时`);
    console.log(`  最大失败次数: ${this.maxRenewalFails}`);
  }

  /**
   * 启动自动续费定时任务
   */
  start() {
    console.log('🚀 启动自动续费定时任务...');

    // 立即执行一次
    this.tick();

    // 定时执行
    this.intervalId = setInterval(() => {
      this.tick();
    }, this.checkIntervalSeconds * 1000);

    console.log(`✅ 自动续费任务已启动 (每 ${this.checkIntervalSeconds} 秒执行一次)`);
  }

  /**
   * 停止自动续费定时任务
   */
  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      console.log('⏹️  自动续费任务已停止');
    }
  }

  /**
   * 执行一次检查
   */
  async tick() {
    const now = Date.now();
    console.log(`\n⏰ [${new Date().toISOString()}] 执行自动续费检查...`);

    try {
      // 获取所有需要检查的订阅
      // TODO: 生产环境应从数据库查询
      const addresses = Array.from(this.subscriptions.keys());

      if (addresses.length === 0) {
        console.log('  没有需要检查的订阅');
        return;
      }

      console.log(`  检查 ${addresses.length} 个订阅...`);

      for (const userAddress of addresses) {
        await this.checkSubscription(userAddress);
      }

      console.log('✅ 自动续费检查完成');
    } catch (error) {
      console.error('❌ 自动续费检查失败:', error.message);
    }
  }

  /**
   * 检查单个订阅
   */
  async checkSubscription(userAddress) {
    try {
      // ✅ V2 修改：查询用户的所有订阅身份
      const provider = new ethers.JsonRpcProvider(this.paymasterEndpoint);
      const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, provider);

      const identities = await contract.getUserIdentities(userAddress);

      if (identities.length === 0) {
        console.log(`  [${userAddress}] 没有订阅`);
        return;
      }

      console.log(`  [${userAddress}] 检查 ${identities.length} 个订阅...`);

      // ✅ V2 修改：检查每个身份的订阅状态
      for (const identityAddress of identities) {
        const subscription = await contract.subscriptions(identityAddress);

        const expiresAt = Number(subscription[6]);
        const autoRenewEnabled = subscription[7];
        const isActive = subscription[8];

        if (!isActive) {
          console.log(`  [${identityAddress}] 订阅未激活,跳过`);
          continue;
        }

        if (!autoRenewEnabled) {
          console.log(`  [${identityAddress}] 自动续费已关闭,跳过`);
          continue;
        }

        const now = Math.floor(Date.now() / 1000);
        const timeUntilExpiry = expiresAt - now;
        const precheckSeconds = this.precheckHours * 3600;

        // 阶段一: 到期前预检
        if (timeUntilExpiry > 0 && timeUntilExpiry <= precheckSeconds) {
          await this.precheckSubscription(identityAddress, subscription);
        }

        // 阶段二: 已到期,执行续费
        if (timeUntilExpiry <= 0) {
          await this.renewSubscription(identityAddress, subscription);
        }
      }
    } catch (error) {
      console.error(`  [${userAddress}] 检查失败:`, error.message);
    }
  }

  /**
   * 预检订阅 (到期前检查资金)
   */
  async precheckSubscription(userAddress, subscription) {
    const expiresAt = Number(subscription[5]);
    const now = Math.floor(Date.now() / 1000);
    const hoursUntilExpiry = Math.floor((expiresAt - now) / 3600);

    console.log(`  [${userAddress}] 预检: ${hoursUntilExpiry} 小时后到期`);

    // TODO: 检查用户的 USDC 余额和授权额度
    // 如果不足,发送提醒通知

    // 记录预检时间
    const subData = this.subscriptions.get(userAddress) || {};
    subData.lastPrecheckAt = Date.now();
    this.subscriptions.set(userAddress, subData);
  }

  /**
   * 执行续费
   * ✅ V2.1 更新：支持 nextPlanId (待生效的套餐变更)
   */
  async renewSubscription(identityAddress, subscription) {
    console.log(`  [${identityAddress}] 🔄 执行续费...`);

    const subData = this.subscriptions.get(identityAddress) || { failCount: 0 };

    // 检查失败次数
    if (subData.failCount >= this.maxRenewalFails) {
      console.log(`  [${identityAddress}] ❌ 失败次数已达上限 (${subData.failCount}),执行强制停服`);
      await this.forceCloseSubscription(identityAddress);
      return;
    }

    try {
      // ✅ V2.1 新增：检查是否有待生效的套餐变更
      const provider = new ethers.JsonRpcProvider(this.paymasterEndpoint);
      const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, provider);
      const fullSubscription = await contract.getSubscription(identityAddress);

      const nextPlanId = Number(fullSubscription.nextPlanId);
      if (nextPlanId > 0) {
        console.log(`  [${identityAddress}] 📋 检测到待生效的套餐变更: planId ${subscription[3]} -> ${nextPlanId}`);
      }

      // 编码合约调用
      const iface = new ethers.Interface(CONTRACT_ABI);
      const calldata = iface.encodeFunctionData('executeRenewal', [identityAddress]);

      // 通过 CDP Smart Account 发送 UserOperation (0 gas)
      console.log(`  [${identityAddress}] 📤 发送 UserOperation (Paymaster 赞助 gas)...`);
      const userOp = await this.cdpClient.evm.sendUserOperation({
        smartAccount: this.serverWalletAccount,
        network: 'base-sepolia',
        calls: [{
          to: this.contractAddress,
          data: calldata,
          value: BigInt(0),
        }],
        paymasterUrl: process.env.CDP_PAYMASTER_URL,
      });

      console.log(`  [${identityAddress}] ⏳ 等待 UserOperation 确认...`);
      const receipt = await this.cdpClient.evm.waitForUserOperation({
        smartAccountAddress: this.serverWalletAccount.address,
        userOpHash: userOp.userOpHash,
      });

      if (receipt.status !== 'complete') {
        throw new Error(`UserOperation failed: ${receipt.status}`);
      }

      if (nextPlanId > 0) {
        console.log(`  [${identityAddress}] ✅ 续费成功并应用套餐变更! 新套餐: ${nextPlanId}, TX: ${receipt.transactionHash}`);
      } else {
        console.log(`  [${identityAddress}] ✅ 续费成功! TX: ${receipt.transactionHash}`);
      }

      // 重置失败计数
      subData.failCount = 0;
      subData.lastRenewalAt = Date.now();
      this.subscriptions.set(identityAddress, subData);

    } catch (error) {
      console.error(`  [${identityAddress}] ❌ 续费失败:`, error.message);

      // 增加失败计数
      subData.failCount = (subData.failCount || 0) + 1;
      this.subscriptions.set(identityAddress, subData);

      console.log(`  [${identityAddress}] 失败次数: ${subData.failCount}/${this.maxRenewalFails}`);
    }
  }

  /**
   * 强制停服 (失败次数超限)
   */
  async forceCloseSubscription(identityAddress) {
    console.log(`  [${identityAddress}] 🛑 强制停服...`);

    try {
      // 编码合约调用
      const iface = new ethers.Interface(CONTRACT_ABI);
      const calldata = iface.encodeFunctionData('finalizeExpired', [
        identityAddress,
        true, // forceClosed = true
      ]);

      // 通过 CDP Server Wallet 发送交易
      const txResult = await sendTransactionViaCDP({
        account: this.serverWalletAccount,
        contractAddress: this.contractAddress,
        calldata,
        network: 'base-sepolia',
      });

      console.log(`  [${identityAddress}] ✅ 强制停服成功! TX: ${txResult.transactionHash}`);

      // 从监控列表中移除
      this.subscriptions.delete(identityAddress);

    } catch (error) {
      console.error(`  [${identityAddress}] ❌ 强制停服失败:`, error.message);
    }
  }

  /**
   * 添加订阅到监控列表
   */
  addSubscription(userAddress) {
    if (!this.subscriptions.has(userAddress)) {
      this.subscriptions.set(userAddress, {
        failCount: 0,
        addedAt: Date.now(),
      });
      console.log(`📝 添加订阅到监控列表: ${userAddress}`);
    }
  }

  /**
   * 从监控列表移除订阅
   */
  removeSubscription(userAddress) {
    if (this.subscriptions.has(userAddress)) {
      this.subscriptions.delete(userAddress);
      console.log(`🗑️  从监控列表移除订阅: ${userAddress}`);
    }
  }

  /**
   * 获取监控状态
   */
  getStatus() {
    return {
      checkIntervalSeconds: this.checkIntervalSeconds,
      precheckHours: this.precheckHours,
      maxRenewalFails: this.maxRenewalFails,
      subscriptionCount: this.subscriptions.size,
      subscriptions: Array.from(this.subscriptions.entries()).map(([address, data]) => ({
        address,
        failCount: data.failCount,
        lastCheck: data.lastCheck,
        lastRenewalAt: data.lastRenewalAt,
      })),
    };
  }
}

module.exports = {
  RenewalService,
};
