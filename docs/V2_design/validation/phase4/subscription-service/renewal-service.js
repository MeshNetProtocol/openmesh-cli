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
  'function executeRenewal(address user) external',
  'function finalizeExpired(address user, bool forceClosed) external',
  'function subscriptions(address user) external view returns (address identityAddress, uint96 lockedPrice, uint256 planId, uint256 lockedPeriod, uint256 startTime, uint256 expiresAt, bool autoRenewEnabled, bool isActive)',
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
      // 查询链上订阅状态
      const provider = new ethers.JsonRpcProvider(this.paymasterEndpoint);
      const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, provider);
      const subscription = await contract.subscriptions(userAddress);

      const expiresAt = Number(subscription[5]);
      const autoRenewEnabled = subscription[6];
      const isActive = subscription[7];

      if (!isActive) {
        console.log(`  [${userAddress}] 订阅未激活,跳过`);
        return;
      }

      if (!autoRenewEnabled) {
        console.log(`  [${userAddress}] 自动续费已关闭,跳过`);
        return;
      }

      const now = Math.floor(Date.now() / 1000);
      const timeUntilExpiry = expiresAt - now;
      const precheckSeconds = this.precheckHours * 3600;

      // 阶段一: 到期前预检
      if (timeUntilExpiry > 0 && timeUntilExpiry <= precheckSeconds) {
        await this.precheckSubscription(userAddress, subscription);
      }

      // 阶段二: 已到期,执行续费
      if (timeUntilExpiry <= 0) {
        await this.renewSubscription(userAddress, subscription);
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
   */
  async renewSubscription(userAddress, subscription) {
    console.log(`  [${userAddress}] 🔄 执行续费...`);

    const subData = this.subscriptions.get(userAddress) || { failCount: 0 };

    // 检查失败次数
    if (subData.failCount >= this.maxRenewalFails) {
      console.log(`  [${userAddress}] ❌ 失败次数已达上限 (${subData.failCount}),执行强制停服`);
      await this.forceCloseSubscription(userAddress);
      return;
    }

    try {
      // 编码合约调用
      const iface = new ethers.Interface(CONTRACT_ABI);
      const calldata = iface.encodeFunctionData('executeRenewal', [userAddress]);

      // 通过 CDP Server Wallet 发送交易
      const txResult = await sendTransactionViaCDP({
        account: this.serverWalletAccount,
        contractAddress: this.contractAddress,
        calldata,
        network: 'base-sepolia',
      });

      console.log(`  [${userAddress}] ✅ 续费成功! TX: ${txResult.transactionHash}`);

      // 重置失败计数
      subData.failCount = 0;
      subData.lastRenewalAt = Date.now();
      this.subscriptions.set(userAddress, subData);

    } catch (error) {
      console.error(`  [${userAddress}] ❌ 续费失败:`, error.message);

      // 增加失败计数
      subData.failCount = (subData.failCount || 0) + 1;
      this.subscriptions.set(userAddress, subData);

      console.log(`  [${userAddress}] 失败次数: ${subData.failCount}/${this.maxRenewalFails}`);
    }
  }

  /**
   * 强制停服 (失败次数超限)
   */
  async forceCloseSubscription(userAddress) {
    console.log(`  [${userAddress}] 🛑 强制停服...`);

    try {
      // 编码合约调用
      const iface = new ethers.Interface(CONTRACT_ABI);
      const calldata = iface.encodeFunctionData('finalizeExpired', [
        userAddress,
        true, // forceClosed = true
      ]);

      // 通过 CDP Server Wallet 发送交易
      const txResult = await sendTransactionViaCDP({
        account: this.serverWalletAccount,
        contractAddress: this.contractAddress,
        calldata,
        network: 'base-sepolia',
      });

      console.log(`  [${userAddress}] ✅ 强制停服成功! TX: ${txResult.transactionHash}`);

      // 从监控列表中移除
      this.subscriptions.delete(userAddress);

    } catch (error) {
      console.error(`  [${userAddress}] ❌ 强制停服失败:`, error.message);
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
