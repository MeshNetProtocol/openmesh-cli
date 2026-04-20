/**
 * 自动续费模块
 *
 * 定时检查即将到期的订阅并自动续费
 * 通过 CDP Server Wallet + Paymaster 实现 0 ETH 续费
 */

const { ethers } = require('ethers');
const { sendTransactionViaCDP } = require('./cdp-transaction');
// ✅ 修复：contract-abi.json 格式是 {abi: [...]}，需要提取 abi 字段
const CONTRACT_ABI = require('./contract-abi.json');

function formatTimestamp(ts) {
  if (!Number.isFinite(ts) || ts <= 0) return 'n/a';
  return `${new Date(ts * 1000).toISOString()} (${ts})`;
}

/**
 * 自动续费服务
 */
class RenewalService {
  constructor({ cdpClient, serverWalletAccount, contractAddress, paymasterEndpoint, subscriptionSet }) {
    this.cdpClient = cdpClient;
    this.serverWalletAccount = serverWalletAccount;
    this.contractAddress = contractAddress;
    this.paymasterEndpoint = paymasterEndpoint;
    this.subscriptionSet = subscriptionSet; // 使用事件驱动的订阅列表

    // 配置
    this.checkIntervalSeconds = parseInt(process.env.RENEWAL_CHECK_INTERVAL_SECONDS || '60');
    this.precheckHours = parseInt(process.env.RENEWAL_PRECHECK_HOURS || '24');
    this.maxRenewalFails = parseInt(process.env.MAX_RENEWAL_FAILS || '3');

    // 内存存储失败计数 (生产环境应使用数据库)
    this.failCounts = new Map(); // identityAddress -> failCount

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
      // 从事件驱动的订阅列表获取所有需要检查的订阅
      const identityAddresses = Array.from(this.subscriptionSet);

      if (identityAddresses.length === 0) {
        console.log('  没有需要检查的订阅');
        return;
      }

      console.log(`  检查 ${identityAddresses.length} 个订阅...`);

      // 初始化 provider 和 contract
      const provider = new ethers.JsonRpcProvider(this.paymasterEndpoint);
      const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, provider);

      for (const identityAddress of identityAddresses) {
        await this.checkSubscriptionByIdentity(identityAddress, contract);
      }

      console.log('✅ 自动续费检查完成');
    } catch (error) {
      console.error('❌ 自动续费检查失败:', error.message);
    }
  }

  /**
   * 检查单个订阅（通过 identityAddress）
   * V4 版本：从 permits.json 读取订阅信息并计算到期时间
   */
  async checkSubscriptionByIdentity(identityAddress, contract) {
    try {
      const permitStore = require('./permit-store');

      // 清除 permits.json 缓存，确保读取最新数据
      delete require.cache[require.resolve('./permits.json')];

      // 从 permits.json 中查找该 identity 的所有订阅记录
      const allPermits = require('./permits.json').permits || {};
      let subscription = null;

      for (const [key, permit] of Object.entries(allPermits)) {
        if (permit.identityAddress.toLowerCase() === identityAddress.toLowerCase() &&
            permit.chargeStatus === 'completed') {
          subscription = permit;
          break;
        }
      }

      if (!subscription) {
        console.log(`  [${identityAddress}] 未找到已完成的订阅记录`);
        return;
      }

      // 获取套餐信息
      const PLANS = require('./index.js').PLANS || [
        { plan_id: 'plan-30min-01', period_seconds: 1800, amount_usdc_base_units: 100000 }
      ];
      const plan = PLANS.find(p => p.plan_id === subscription.planId);
      if (!plan) {
        console.log(`  [${identityAddress}] 未找到套餐信息: ${subscription.planId}`);
        return;
      }

      // 计算到期时间：首次扣费时间 + 套餐周期
      const now = Math.floor(Date.now() / 1000);
      const chargeTime = Math.floor(subscription.updatedAt / 1000);
      const expiresAt = chargeTime + plan.period_seconds;
      const timeUntilExpiry = expiresAt - now;

      console.log(`  [${identityAddress}] 套餐: ${plan.plan_id}, 周期: ${plan.period_seconds}s`);
      console.log(`  [${identityAddress}] 扣费时间: ${formatTimestamp(chargeTime)}, 到期时间: ${formatTimestamp(expiresAt)}`);
      console.log(`  [${identityAddress}] 距离到期: ${timeUntilExpiry}s (${Math.floor(timeUntilExpiry / 60)}分钟)`);

      if (timeUntilExpiry <= 0) {
        console.log(`  [${identityAddress}] 订阅已到期，触发自动续费`);
        await this.renewSubscriptionV4(identityAddress, subscription, plan);
        return;
      }

      console.log(`  [${identityAddress}] 距离到期还有 ${timeUntilExpiry} 秒,跳过`);
    } catch (error) {
      console.error(`  [${identityAddress}] 检查失败:`, error.message);
    }
  }

  /**
   * 预检订阅 (到期前检查资金)
   */
  async precheckSubscription(userAddress, subscription) {
    const expiresAt = Number(subscription[6]);
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
   * 执行续费 - V4 版本
   * V4 合约使用 charge 函数进行续费扣费
   */
  async renewSubscriptionV4(identityAddress, subscription, plan) {
    console.log(`  [${identityAddress}] 🔄 执行续费...`);

    const failCount = this.failCounts.get(identityAddress) || 0;

    // 检查失败次数
    if (failCount >= this.maxRenewalFails) {
      console.log(`  [${identityAddress}] ❌ 失败次数已达上限 (${failCount}),停止自动续费`);
      return;
    }

    try {
      // 生成新的 chargeId
      const chargeId = '0x' + Array.from(crypto.getRandomValues(new Uint8Array(32)))
        .map(b => b.toString(16).padStart(2, '0')).join('');

      console.log(`  [${identityAddress}] 📝 生成 chargeId: ${chargeId}`);
      console.log(`  [${identityAddress}] 📝 扣费金额: ${plan.amount_usdc_base_units / 1e6} USDC`);

      // 调用 charge 函数
      const iface = new ethers.Interface(CONTRACT_ABI);
      const calldata = iface.encodeFunctionData('charge', [
        chargeId,
        identityAddress,
        plan.amount_usdc_base_units
      ]);

      // 通过 CDP Smart Account 发送交易
      console.log(`  [${identityAddress}] 📤 发送续费交易 (Paymaster 赞助 gas)...`);
      const txResult = await sendTransactionViaCDP({
        cdpClient: this.cdpClient,
        account: this.serverWalletAccount,
        contractAddress: this.contractAddress,
        calldata: calldata,
      });

      console.log(`  [${identityAddress}] ✅ 续费成功! TX: ${txResult.transactionHash}`);

      // 更新 permits.json 中的记录
      const permitStore = require('./permit-store');

      // 重新加载 permits.json 以获取最新数据
      delete require.cache[require.resolve('./permits.json')];

      permitStore.updateChargeStatus(
        identityAddress,
        subscription.planId,
        'completed',
        chargeId,
        txResult.transactionHash,
        plan.amount_usdc_base_units
      );

      // 扣减授权额度
      permitStore.deductAuthorizedAllowance(
        subscription.userAddress,
        identityAddress,
        plan.amount_usdc_base_units
      );

      // 重置失败计数
      this.failCounts.delete(identityAddress);

    } catch (error) {
      console.error(`  [${identityAddress}] ❌ 续费失败:`, error.message);

      // 增加失败计数
      this.failCounts.set(identityAddress, failCount + 1);

      console.log(`  [${identityAddress}] 失败次数: ${failCount + 1}/${this.maxRenewalFails}`);
    }
  }

  /**
   * 执行续费 - 旧版本（保留用于兼容）
   * ✅ V2.2：使用 executeRenewal 走当前 permit/lockedPrice 续费主线
   */
  async renewSubscription(identityAddress, subscription) {
    console.log(`  [${identityAddress}] 🔄 执行续费...`);

    const failCount = this.failCounts.get(identityAddress) || 0;

    // 检查失败次数
    if (failCount >= this.maxRenewalFails) {
      console.log(`  [${identityAddress}] ❌ 失败次数已达上限 (${failCount}),执行强制停服`);
      await this.forceCloseSubscription(identityAddress);
      return;
    }

    try {
      const provider = new ethers.JsonRpcProvider(this.paymasterEndpoint);
      const contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, provider);
      const fullSubscription = await contract.getSubscription(identityAddress);

      const planId = Number(fullSubscription.planId);
      const lockedPeriod = Number(fullSubscription.lockedPeriod);
      const expiresAt = Number(fullSubscription.expiresAt);
      const renewedAt = Number(fullSubscription.renewedAt);
      const now = Math.floor(Date.now() / 1000);

      console.log(`  [${identityAddress}] 续费前链上状态: planId=${planId}, autoRenew=${fullSubscription.autoRenewEnabled}`);
      console.log(`  [${identityAddress}] 续费前时间: now=${formatTimestamp(now)}, renewedAt=${formatTimestamp(renewedAt)}, expiresAt=${formatTimestamp(expiresAt)}, lockedPeriod=${lockedPeriod}s`);

      const iface = new ethers.Interface(CONTRACT_ABI);
      const calldata = iface.encodeFunctionData('executeRenewal', [identityAddress]);
      console.log(`  [${identityAddress}] 📝 使用 executeRenewal 续费`);

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

      const postSubscription = await contract.getSubscription(identityAddress);
      console.log(`  [${identityAddress}] 续费后时间: renewedAt=${formatTimestamp(Number(postSubscription.renewedAt))}, expiresAt=${formatTimestamp(Number(postSubscription.expiresAt))}`);
      console.log(`  [${identityAddress}] ✅ 续费成功! TX: ${receipt.transactionHash}`);

      // 重置失败计数
      this.failCounts.delete(identityAddress);

    } catch (error) {
      console.error(`  [${identityAddress}] ❌ 续费失败:`, error.message);

      // 增加失败计数
      this.failCounts.set(identityAddress, failCount + 1);

      console.log(`  [${identityAddress}] 失败次数: ${failCount + 1}/${this.maxRenewalFails}`);
    }
  }

  /**
   * 强制停服 (失败次数超限)
   *
   * 注意：根据新的设计原则，过期订阅不需要清理，可以直接被新订阅覆盖。
   * 这里只是记录失败并从监控列表中移除，不调用合约的 finalizeExpired()。
   */
  async forceCloseSubscription(identityAddress) {
    console.log(`  [${identityAddress}] 🛑 续费失败次数超限，停止自动续费监控`);

    try {
      // 清除失败计数
      this.failCounts.delete(identityAddress);

      // 从订阅监控列表中移除
      this.subscriptionSet.delete(identityAddress);

      console.log(`  [${identityAddress}] ✅ 已从自动续费监控列表中移除`);
      console.log(`  [${identityAddress}] 💡 订阅将在到期后自然过期，用户可以随时重新订阅`);

    } catch (error) {
      console.error(`  [${identityAddress}] ❌ 移除监控失败:`, error.message);
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
      subscriptionCount: this.subscriptionSet.size,
      subscriptions: Array.from(this.subscriptionSet).map(identityAddress => ({
        identityAddress,
        failCount: this.failCounts.get(identityAddress) || 0,
      })),
    };
  }
}

module.exports = {
  RenewalService,
};
