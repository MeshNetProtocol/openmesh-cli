#!/usr/bin/env node

/**
 * VPN Subscription Service
 *
 * 实现功能:
 * 1. 订阅 API - 通过 CDP Server Wallet + Paymaster 实现 0 ETH 订阅
 * 2. 取消 API - 用户零 gas 取消订阅
 * 3. 自动续费 - 定时任务自动续费,0 ETH
 * 4. 清理过期订阅 - 释放链上状态
 */

const path = require('path');
const envPath = path.join(__dirname, '../.env');
const result = require('dotenv').config({ path: envPath, override: true });
console.log('📝 Loaded .env from:', envPath);
if (result.error) {
  console.error('❌ Failed to load .env:', result.error);
}
const express = require('express');
const { CdpClient } = require('@coinbase/cdp-sdk');
const { ethers } = require('ethers');
const { encodeFunctionData } = require('viem');
const permitStore = require('./permit-store');

// ============================================================================
// 配置
// ============================================================================

const PORT = process.env.PORT || 8080;
const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
console.log('🔍 Final CONTRACT_ADDRESS used by backend:', CONTRACT_ADDRESS);
const USDC_ADDRESS = process.env.USDC_CONTRACT;
const PAYMASTER_ENDPOINT = process.env.CDP_PAYMASTER_ENDPOINT;
const SERVER_WALLET_ACCOUNT_NAME = process.env.CDP_SERVER_WALLET_ACCOUNT_NAME || 'openmesh-vpn-smart';
const FALLBACK_SERVER_WALLET_ACCOUNT_NAME = 'openmesh-vpn-smart';

// 套餐配置 (VPNCreditVaultV4 不存储套餐，由服务端管理)
const PLANS = [
  {
    plan_id: 'plan-30min-01',
    name: '30分钟套餐 - 0.1 USDC',
    period_seconds: 1800, // 30分钟
    amount_usdc: 0.1,
    amount_usdc_base_units: 100000, // 0.1 USDC = 100000 (6 decimals)
  },
  {
    plan_id: 'plan-30min-02',
    name: '30分钟套餐 - 0.2 USDC',
    period_seconds: 1800,
    amount_usdc: 0.2,
    amount_usdc_base_units: 200000,
  },
  {
    plan_id: 'plan-30min-03',
    name: '30分钟套餐 - 0.3 USDC',
    period_seconds: 1800,
    amount_usdc: 0.3,
    amount_usdc_base_units: 300000,
  },
];

// EIP-712 Domain
const DOMAIN = {
  name: 'VPNSubscription',
  version: '2',  // ✅ V2: 版本号改为 2
  chainId: 84532, // Base Sepolia
  verifyingContract: CONTRACT_ADDRESS,
};

// EIP-712 Types
const SUBSCRIBE_INTENT_TYPES = {
  SubscribeIntent: [
    { name: 'user', type: 'address' },
    { name: 'identityAddress', type: 'address' },
    { name: 'planId', type: 'uint256' },
    { name: 'isYearly', type: 'bool' },
    { name: 'maxAmount', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
  ],
};

// ✅ V2 修改：CancelIntent 新增 identityAddress 字段
const CANCEL_INTENT_TYPES = {
  CancelIntent: [
    { name: 'user', type: 'address' },
    { name: 'identityAddress', type: 'address' },  // V2 新增
    { name: 'nonce', type: 'uint256' },
  ],
};

// ✅ V2.1 新增：套餐升降级签名 Types
const UPGRADE_INTENT_TYPES = {
  UpgradeIntent: [
    { name: 'user', type: 'address' },
    { name: 'identityAddress', type: 'address' },
    { name: 'newPlanId', type: 'uint256' },
    { name: 'isYearly', type: 'bool' },
    { name: 'maxAmount', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
  ],
};

const DOWNGRADE_INTENT_TYPES = {
  DowngradeIntent: [
    { name: 'user', type: 'address' },
    { name: 'identityAddress', type: 'address' },
    { name: 'newPlanId', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
  ],
};

const CANCEL_CHANGE_INTENT_TYPES = {
  CancelChangeIntent: [
    { name: 'user', type: 'address' },
    { name: 'identityAddress', type: 'address' },
    { name: 'nonce', type: 'uint256' },
  ],
};

// ============================================================================
// CDP Client 初始化
// ============================================================================

let cdpClient;
let serverWalletAccount;

async function assertRelayerMatchesServerWallet() {
  console.log('🔍 校验链上 relayer 与当前 Smart Account 是否一致...');

  const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
  const configuredRelayer = await contract.relayer();
  const expectedRelayer = serverWalletAccount.address;

  if (configuredRelayer.toLowerCase() !== expectedRelayer.toLowerCase()) {
    throw new Error(
      `Relayer mismatch: contract relayer=${configuredRelayer}, server wallet=${expectedRelayer}. Please call setRelayer(${expectedRelayer}) before starting the service.`
    );
  }

  console.log(`✅ Relayer 校验通过: ${configuredRelayer}`);
}

async function initializeCDP() {
  console.log('📡 初始化 CDP Client...');

  cdpClient = new CdpClient({
    apiKeyId: process.env.CDP_API_KEY_ID,
    apiKeySecret: process.env.CDP_API_KEY_SECRET,
    walletSecret: process.env.CDP_WALLET_SECRET,
  });

  console.log('✅ CDP Client 初始化成功');

  // 第一步: 创建 Owner Account (EOA)
  console.log('🔨 获取 Owner Account (EOA)...');
  const ownerAccount = await cdpClient.evm.getOrCreateAccount({
    name: 'openmesh-vpn-owner',
  });
  console.log('✅ Owner Account 创建成功:', ownerAccount.address);

  // 第二步: 获取 Smart Account (使用 Owner Account)
  const smartAccountNames = [
    SERVER_WALLET_ACCOUNT_NAME,
    FALLBACK_SERVER_WALLET_ACCOUNT_NAME,
  ].filter((name, index, arr) => Boolean(name) && arr.indexOf(name) === index);

  let smartAccountError = null;
  for (const smartAccountName of smartAccountNames) {
    try {
      console.log(`🔨 获取 CDP Smart Account (${smartAccountName})...`);
      serverWalletAccount = await cdpClient.evm.getOrCreateSmartAccount({
        name: smartAccountName,
        owner: ownerAccount,
      });

      if (smartAccountName !== SERVER_WALLET_ACCOUNT_NAME) {
        console.warn(`⚠️  已回退到 Smart Account 名称: ${smartAccountName}`);
      }
      smartAccountError = null;
      break;
    } catch (error) {
      smartAccountError = error;
      const msg = error?.errorMessage || error?.message || '';
      const duplicateOwnerError = msg.includes('Multiple smart wallets with the same owner is not supported');

      // 只有在 owner 冲突时才尝试下一个候选名称
      if (!duplicateOwnerError || smartAccountName === smartAccountNames[smartAccountNames.length - 1]) {
        throw error;
      }

      console.warn(`⚠️  Smart Account 名称 ${smartAccountName} 不可用，尝试回退名称...`);
    }
  }

  if (!serverWalletAccount) {
    throw smartAccountError || new Error('Failed to get Smart Account');
  }

  console.log('✅ Smart Account 获取成功');
  console.log('  Smart Account Address:', serverWalletAccount.address);
  console.log('  Owner Account Address:', ownerAccount.address);
  console.log('  Network:', serverWalletAccount.network || 'base-sepolia');
  console.log('  Type: Smart Account (ERC-4337)');
  console.log('  Gas: 0 ETH (Paymaster 自动赞助)');
}

// ============================================================================
// 事件监听和订阅列表维护
// ============================================================================

// 订阅列表（内存存储，由链上事件驱动）
const subscriptionSet = new Set();
const EVENT_SYNC_START_BLOCK = parseInt(process.env.EVENT_SYNC_START_BLOCK || '19000000');
const EVENT_SYNC_BATCH_SIZE = parseInt(process.env.EVENT_SYNC_BATCH_SIZE || '900');
const EVENT_SYNC_INTERVAL_SECONDS = parseInt(process.env.EVENT_SYNC_INTERVAL_SECONDS || '30');
const EVENT_SYNC_INITIAL_WINDOW_BLOCKS = parseInt(process.env.EVENT_SYNC_INITIAL_WINDOW_BLOCKS || '5000');
let eventSyncContract = null;
let eventSyncInFlight = false;
let lastSyncedBlock = EVENT_SYNC_START_BLOCK - 1;
let historicalBackfillNextBlock = EVENT_SYNC_START_BLOCK;
let historicalBackfillToBlock = EVENT_SYNC_START_BLOCK - 1;
const identityLatestEventPosition = new Map();

function getEventPosition(event) {
  return (event.blockNumber * 1_000_000) + event.logIndex;
}

function applySubscriptionEvent(eventName, args, eventPosition) {
  const identityAddress = args?.identityAddress || args?.[1];
  if (!identityAddress) return;

  const normalizedIdentity = identityAddress.toLowerCase();
  const prevPosition = identityLatestEventPosition.get(normalizedIdentity) ?? -1;
  if (eventPosition <= prevPosition) {
    return;
  }
  identityLatestEventPosition.set(normalizedIdentity, eventPosition);

  if (eventName === 'SubscriptionCreated') {
    subscriptionSet.add(normalizedIdentity);
    console.log(`  ✅ [事件同步] 添加订阅: ${normalizedIdentity}`);
    return;
  }

  // ✅ V2.4: SubscriptionForceClosed 和 SubscriptionExpired 事件已删除
  if (eventName === 'SubscriptionCancelled') {
    subscriptionSet.delete(normalizedIdentity);
    console.log(`  ⚠️ [事件同步] 移除订阅: ${normalizedIdentity}`);
  }
}

async function syncEventRange(contract, fromBlock, toBlock) {
  // ✅ V2.4: 只监听保留的事件（SubscriptionForceClosed 和 SubscriptionExpired 已删除）
  const [created, cancelled] = await Promise.all([
    contract.queryFilter(contract.filters.SubscriptionCreated(), fromBlock, toBlock),
    contract.queryFilter(contract.filters.SubscriptionCancelled(), fromBlock, toBlock),
  ]);

  const allEvents = [
    ...created.map(e => ({ type: 'SubscriptionCreated', event: e })),
    ...cancelled.map(e => ({ type: 'SubscriptionCancelled', event: e })),
  ];

  allEvents.sort((a, b) => {
    if (a.event.blockNumber !== b.event.blockNumber) {
      return a.event.blockNumber - b.event.blockNumber;
    }
    return a.event.logIndex - b.event.logIndex;
  });

  for (const { type, event } of allEvents) {
    applySubscriptionEvent(type, event.args, getEventPosition(event));
  }
}

async function backfillHistoricalEvents(contract) {
  if (historicalBackfillNextBlock > historicalBackfillToBlock) {
    return false;
  }

  const chunkEnd = Math.min(
    historicalBackfillNextBlock + EVENT_SYNC_BATCH_SIZE - 1,
    historicalBackfillToBlock
  );

  await syncEventRange(contract, historicalBackfillNextBlock, chunkEnd);
  historicalBackfillNextBlock = chunkEnd + 1;

  return historicalBackfillNextBlock <= historicalBackfillToBlock;
}

async function syncFromChain(contract, fromBlock = null) {
  const startBlock = fromBlock ?? (lastSyncedBlock + 1);
  const latest = await contract.runner.getBlockNumber();

  if (startBlock > latest) {
    return;
  }

  for (let chunkStart = startBlock; chunkStart <= latest; chunkStart += EVENT_SYNC_BATCH_SIZE) {
    const chunkEnd = Math.min(chunkStart + EVENT_SYNC_BATCH_SIZE - 1, latest);
    await syncEventRange(contract, chunkStart, chunkEnd);
    lastSyncedBlock = chunkEnd;
  }
}

async function initializeEventListeners() {
  console.log('🔄 初始化事件同步器...');

  // 初始化合约实例（用于事件同步）
  const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
  eventSyncContract = contract;

  // ✅ V2.4: getAllActiveSubscriptions() 已删除，改为从事件日志重建订阅列表
  // 合约不再维护活跃订阅列表，服务端通过监听事件来维护
  console.log('  从事件日志重建订阅列表...');

  // 从合约部署区块开始扫描所有历史事件
  const fromBlock = EVENT_SYNC_START_BLOCK;
  console.log(`  扫描区块范围: ${fromBlock} -> latest`);
  await syncFromChain(contract, fromBlock);

  // 更新 lastSyncedBlock 为当前区块
  lastSyncedBlock = await contract.runner.getBlockNumber();

  console.log(`✅ 事件同步器初始化完成（当前订阅数: ${subscriptionSet.size}）`);

  // 定时增量同步（只同步新事件，用于实时更新）
  setInterval(async () => {
    if (eventSyncInFlight || !eventSyncContract) return;

    eventSyncInFlight = true;
    try {
      await syncFromChain(eventSyncContract, lastSyncedBlock + 1);
    } catch (error) {
      console.error('⚠️ 事件增量同步失败:', error.message);
    } finally {
      eventSyncInFlight = false;
    }
  }, EVENT_SYNC_INTERVAL_SECONDS * 1000);
}

// ============================================================================
// 合约 ABI (从编译产物提取的完整 ABI)
// ============================================================================

// ✅ 修复：使用从合约编译产物提取的完整 ABI，避免手写 ABI 导致的类型不匹配
// ✅ 修复：contract-abi.json 格式是 {abi: [...]}，需要提取 abi 字段
const CONTRACT_ABI = require('./contract-abi.json').abi;
const app = express();
app.use(express.json());

// ✅ 挂载前端静态页面，使得用户可以直接打开 localhost:8080 访问界面
app.use(express.static(path.join(__dirname, '../frontend')));

// 全局请求日志中间件 - 捕获所有请求
app.use((req, _res, next) => {
  console.log(`🌐 ${req.method} ${req.url}`);
  if (req.method === 'POST') {
    console.log('📦 Body:', JSON.stringify(req.body, null, 2));
  }
  next();
});

// CORS
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

/**
 * 统一的订阅状态判断函数（兼容 ethers 返回的对象/元组）
 *
 * 核心设计原则：
 * - 合约只保存关键事实，不保存派生状态
 * - 订阅状态通过 expiresAt 和 autoRenewEnabled 推导
 * - 不依赖已删除的字段（isSuspended, nextRenewalAt 等）
 *
 * @param {Object|Array} subscription - 订阅对象或元组
 * @returns {Object} 标准化的订阅状态
 */
function getSubscriptionStatus(subscription) {
  const now = Math.floor(Date.now() / 1000);

  // 兼容 ethers 返回的对象/元组格式
  // 新的 Subscription 结构体（9 个字段）：
  // [0] identityAddress, [1] payerAddress, [2] lockedPrice, [3] planId,
  // [4] lockedPeriod, [5] startTime, [6] expiresAt, [7] renewedAt, [8] autoRenewEnabled
  const startTime = Number(subscription.startTime ?? subscription[5] ?? 0);
  const expiresAt = Number(subscription.expiresAt ?? subscription[6] ?? 0);
  const renewedAt = Number(subscription.renewedAt ?? subscription[7] ?? 0);
  const autoRenewEnabled = Boolean(subscription.autoRenewEnabled ?? subscription[8]);

  // 核心判断逻辑：只看 expiresAt 和 autoRenewEnabled
  const isExpired = expiresAt <= now;
  const isActive = expiresAt > now;

  let status;
  if (isExpired) {
    status = 'expired';
  } else if (autoRenewEnabled) {
    status = 'active';  // 当前有效且会续费
  } else {
    status = 'cancelled';  // 当前有效但已取消续费
  }

  return {
    startTime,
    expiresAt,
    renewedAt,
    autoRenewEnabled,
    status,           // 'active' | 'cancelled' | 'expired'
    isActive,         // 当前是否有效（expiresAt > now）
    isExpired,        // 是否已过期（expiresAt <= now）
    isSubscribed: isActive,  // 与合约 permitAndSubscribe 的门槛保持一致
  };
}

// ============================================================================
// API: 获取套餐列表
// ============================================================================

app.get('/api/plans', (_req, res) => {
  res.json({
    success: true,
    plans: PLANS,
  });
});

// ============================================================================
// API: VPNCreditVaultV4 订阅流程
// ============================================================================

// 查询订阅状态
app.get('/api/v4/subscription/status', async (req, res) => {
  try {
    const { identityAddress, planId } = req.query;

    if (!identityAddress || !planId) {
      return res.status(400).json({ error: 'Missing identityAddress or planId' });
    }

    const status = permitStore.getPermitStatus(identityAddress, planId);

    res.json({
      success: true,
      status: status || { permitStatus: 'none', chargeStatus: 'none' },
    });
  } catch (error) {
    console.error('查询状态失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// 准备订阅参数
app.post('/api/v4/subscription/prepare', async (req, res) => {
  try {
    const { identityAddress, planId, currentAllowance } = req.body;

    if (!identityAddress || !planId) {
      return res.status(400).json({ error: 'Missing identityAddress or planId' });
    }

    const plan = PLANS.find(p => p.plan_id === planId);
    if (!plan) {
      return res.status(404).json({ error: 'Plan not found' });
    }

    // 检查是否已有 permit 记录
    const existingStatus = permitStore.getPermitStatus(identityAddress, planId);

    if (existingStatus && existingStatus.permitStatus === 'completed') {
      // 已经 permit 成功，返回已有信息
      return res.json({
        success: true,
        identityAddress,
        planId,
        plan,
        needsPermit: false,
        existingPermit: existingStatus,
        targetAllowance: plan.amount_usdc_base_units * 3,
        deadline: existingStatus.deadline,
        usdcAddress: USDC_ADDRESS,
        vaultAddress: CONTRACT_ADDRESS,
      });
    }

    const deadline = Math.floor(Date.now() / 1000) + 3600; // 1小时后过期

    res.json({
      success: true,
      identityAddress,
      planId,
      plan,
      needsPermit: true,
      targetAllowance: plan.amount_usdc_base_units * 3, // 3个周期的额度
      deadline,
      usdcAddress: USDC_ADDRESS,
      vaultAddress: CONTRACT_ADDRESS,
    });
  } catch (error) {
    console.error('准备订阅失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// 提交授权（调用 authorizeChargeWithPermit）
app.post('/api/v4/subscription/authorize', async (req, res) => {
  try {
    const {
      userAddress,
      identityAddress,
      planId,
      expectedAllowance,
      targetAllowance,
      deadline,
      v, r, s,
    } = req.body;

    console.log('📝 收到授权请求:', { userAddress, identityAddress, planId, targetAllowance });

    if (!userAddress || !identityAddress || !planId || targetAllowance === undefined || !deadline || !v || !r || !s) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // 保存 permit 记录
    permitStore.createOrUpdatePermit({
      identityAddress,
      userAddress,
      planId,
      expectedAllowance,
      targetAllowance,
      deadline,
    });

    // 编码合约调用
    const iface = new ethers.Interface([
      'function authorizeChargeWithPermit(address user, address identityAddress, uint256 expectedAllowance, uint256 targetAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s)'
    ]);

    const calldata = iface.encodeFunctionData('authorizeChargeWithPermit', [
      userAddress,
      identityAddress,
      expectedAllowance || 0,
      targetAllowance,
      deadline,
      v,
      r,
      s,
    ]);

    console.log('📤 通过 CDP Server Wallet 发送授权交易...');

    const { sendTransactionViaCDP } = require('./cdp-transaction');
    const txResult = await sendTransactionViaCDP({
      cdpClient,
      account: serverWalletAccount,
      contractAddress: CONTRACT_ADDRESS,
      calldata,
      network: 'base-sepolia',
    });

    // 更新 permit 状态为成功
    permitStore.updatePermitStatus(identityAddress, planId, 'completed', txResult.transactionHash);

    res.json({
      success: true,
      transactionHash: txResult.transactionHash,
      identityAddress,
      userAddress,
    });

  } catch (error) {
    console.error('授权失败:', error);

    // 更新 permit 状态为失败
    if (req.body.identityAddress && req.body.planId) {
      permitStore.updatePermitStatus(req.body.identityAddress, req.body.planId, 'failed', null);
    }

    res.status(500).json({ error: error.message });
  }
});

// 执行扣费（调用 charge）
app.post('/api/v4/subscription/charge', async (req, res) => {
  try {
    const { identityAddress, planId, amount, chargeId } = req.body;

    console.log('📝 收到扣费请求:', { identityAddress, planId, amount, chargeId });

    if (!identityAddress || !planId || !amount || !chargeId) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // 编码合约调用
    const iface = new ethers.Interface([
      'function charge(bytes32 chargeId, address identityAddress, uint256 amount)'
    ]);

    const calldata = iface.encodeFunctionData('charge', [
      chargeId,
      identityAddress,
      amount,
    ]);

    console.log('📤 通过 CDP Server Wallet 发送扣费交易...');

    const { sendTransactionViaCDP } = require('./cdp-transaction');
    const txResult = await sendTransactionViaCDP({
      cdpClient,
      account: serverWalletAccount,
      contractAddress: CONTRACT_ADDRESS,
      calldata,
      network: 'base-sepolia',
    });

    // 更新 charge 状态为成功
    permitStore.updateChargeStatus(identityAddress, planId, 'completed', chargeId, txResult.transactionHash, amount);

    res.json({
      success: true,
      transactionHash: txResult.transactionHash,
      identityAddress,
      amount,
    });

  } catch (error) {
    console.error('扣费失败:', error);

    // 更新 charge 状态为失败
    if (req.body.identityAddress && req.body.planId) {
      permitStore.updateChargeStatus(req.body.identityAddress, req.body.planId, 'failed', req.body.chargeId, null, req.body.amount);
    }

    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: 获取配置信息
// ============================================================================

app.get('/api/config', (_req, res) => {
  res.json({
    contractAddress: CONTRACT_ADDRESS,
    usdcAddress: USDC_ADDRESS,
    network: 'base-sepolia',
    chainId: 84532,
  });
});

// ============================================================================
// API: 准备订阅签名数据
// ============================================================================

app.post('/api/subscription/prepare', async (req, res) => {
  try {
    const { userAddress, planId, identityAddress, isYearly } = req.body;

    if (!userAddress || !planId || !identityAddress) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (!ethers.isAddress(userAddress) || !ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    const parsedPlanId = Number(planId);
    if (!Number.isInteger(parsedPlanId) || parsedPlanId <= 0) {
      return res.status(400).json({ error: 'Invalid planId' });
    }

    // 获取用户 nonce 前，先检查 identity 当前链上状态，避免直接进入 userOp 报错
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    const plan = await contract.getPlan(parsedPlanId);
    if (!plan.isActive) {
      return res.status(400).json({ error: 'Plan is not available' });
    }

    const existingSubscription = await contract.getSubscription(identityAddress);
    const existingState = getSubscriptionStatus(existingSubscription);

    if (existingState.isSubscribed) {
      return res.status(409).json({
        error: 'Identity already subscribed',
        detail: {
          identityAddress,
          expiresAt: existingState.expiresAt,
          autoRenewEnabled: existingState.autoRenewEnabled,
          status: existingState.status,
          isActive: existingState.isActive,
        }
      });
    }

    const intentNonce = await contract.intentNonces(userAddress);

    // 授权额度：无限额
    // 安全边界由合约 executeRenewal 保证，每次只扣 lockedPrice
    const maxAmount = ethers.MaxUint256.toString(); 
    const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    // 返回 EIP-712 签名数据
    res.json({
      domain: DOMAIN,
      types: SUBSCRIBE_INTENT_TYPES,
      value: {
        user: userAddress,
        identityAddress: identityAddress,
        planId: parsedPlanId,
        isYearly: Boolean(isYearly),
        maxAmount: maxAmount,
        deadline: deadline,
        nonce: intentNonce.toString()
      }
    });
  } catch (error) {
    console.error('准备签名失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: 获取 Intent Nonce
// ============================================================================

app.get('/api/intent-nonce', async (req, res) => {
  try {
    const { address } = req.query;

    if (!address || !ethers.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    // 通过 CDP 查询链上 nonce
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    const nonce = await contract.intentNonces(address);

    res.json({ nonce: nonce.toString() });
  } catch (error) {
    console.error('获取 intent nonce 失败:', error);
    res.status(500).json({ error: 'Failed to get intent nonce', detail: error.message });
  }
});

// ============================================================================
// API: 获取 Cancel Nonce
// ============================================================================

app.get('/api/cancel-nonce', async (req, res) => {
  try {
    const { address } = req.query;

    if (!address || !ethers.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    // 通过 CDP 查询链上 nonce
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    const nonce = await contract.cancelNonces(address);

    res.json({ nonce: nonce.toString() });
  } catch (error) {
    console.error('获取 cancel nonce 失败:', error);
    res.status(500).json({ error: 'Failed to get cancel nonce', detail: error.message });
  }
});

// ============================================================================
// API: 简化订阅接口 (前端使用)
// ============================================================================

app.post('/api/subscription/subscribe', async (req, res) => {
  console.log('📥 收到 POST /api/subscription/subscribe 请求');

  try {
    const { userAddress, planId, identityAddress, isYearly, intentSignature, permitSignature, maxAmount, deadline, nonce } = req.body;

    if (!userAddress || !planId || !identityAddress || !intentSignature || !permitSignature || maxAmount === undefined || !deadline || nonce === undefined) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const parsedPlanId = Number(planId);
    if (!Number.isInteger(parsedPlanId) || parsedPlanId <= 0) {
      return res.status(400).json({ error: 'Invalid planId' });
    }

    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    const plan = await contract.getPlan(parsedPlanId);
    if (!plan.isActive) {
      return res.status(400).json({ error: 'Plan is not available' });
    }

    const existingSubscription = await contract.getSubscription(identityAddress);
    const existingState = getSubscriptionStatus(existingSubscription);
    if (existingState.isSubscribed) {
      return res.status(409).json({
        error: 'Identity already subscribed',
        detail: {
          identityAddress,
          expiresAt: existingState.expiresAt,
          autoRenewEnabled: existingState.autoRenewEnabled,
          status: existingState.status,
          isActive: existingState.isActive,
        }
      });
    }

    // 验证 SubscribeIntent 签名
    console.log('🔍 验证 SubscribeIntent 签名...');
    const intentMessage = {
      user: userAddress,
      identityAddress: identityAddress,
      planId: BigInt(parsedPlanId),
      isYearly: Boolean(isYearly),
      maxAmount: BigInt(maxAmount),
      deadline: BigInt(deadline),
      nonce: BigInt(nonce),
    };

    const recoveredAddress = ethers.verifyTypedData(
      DOMAIN,
      SUBSCRIBE_INTENT_TYPES,
      intentMessage,
      intentSignature
    );

    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) {
      return res.status(400).json({ error: 'Invalid intent signature' });
    }

    console.log('✅ SubscribeIntent 签名验证通过');

    // 分解 Permit 签名
    let permitV = 0, permitR = ethers.ZeroHash, permitS = ethers.ZeroHash;
    if (permitSignature && maxAmount > 0) {
      const permitSig = ethers.Signature.from(permitSignature);
      permitV = permitSig.v;
      permitR = permitSig.r;
      permitS = permitSig.s;
    }

    // 构造合约调用数据 (使用 viem)
    const calldata = encodeFunctionData({
      abi: CONTRACT_ABI,
      functionName: 'permitAndSubscribe',
      args: [
        userAddress,
        identityAddress,
        BigInt(parsedPlanId),
        Boolean(isYearly),
        BigInt(maxAmount),
        BigInt(deadline),
        BigInt(nonce),
        intentSignature,
        permitV,
        permitR,
        permitS
      ],
    });

    console.log('📦 Calldata:', calldata);
    console.log('📤 通过 CDP Smart Account 发送 UserOperation (Paymaster 赞助 gas)...');
    console.log('🔑 Paymaster URL:', process.env.CDP_PAYMASTER_URL);

    // ✅ 修复：删除错误的 approve 逻辑
    // 真正有效的用户授权只有合约里的 permit (VPNSubscriptionV2.sol:246)
    // 用户通过前端签名 EIP-2612 Permit，合约执行 permit 写入授权
    // 后端不需要也不应该代用户 approve

    // 通过 CDP Smart Account 发送 UserOperation (ERC-4337)
    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount,
      network: 'base-sepolia',
      calls: [{
        to: CONTRACT_ADDRESS,
        data: calldata,
        value: BigInt(0),
      }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL,
    });

    // sendUserOperation 返回 userOpHash (不是 userOperationHash)
    console.log('✅ UserOperation 已发送:', userOp.userOpHash);

    // 等待 UserOperation 确认
    // waitForUserOperation 需要 { smartAccountAddress, userOpHash }，不需要 network
    console.log('⏳ 等待 UserOperation 确认...');
    const receipt = await cdpClient.evm.waitForUserOperation({
      smartAccountAddress: serverWalletAccount.address,
      userOpHash: userOp.userOpHash,
    });

    // 成功状态是 'complete'，不是 'success'
    if (receipt.status !== 'complete') {
      throw new Error(`UserOperation failed on-chain: ${receipt.status}`);
    }

    console.log('✅ UserOperation 已确认!');
    console.log('  Transaction Hash:', receipt.transactionHash);

    const chainSubscription = await contract.getSubscription(identityAddress);
    const subscriptionStatus = getSubscriptionStatus(chainSubscription);

    res.json({
      success: true,
      txHash: receipt.transactionHash,
      userOperationHash: userOp.userOpHash,
      subscription: {
        userAddress,
        identityAddress,
        planId: Number(chainSubscription.planId ?? chainSubscription[3] ?? parsedPlanId),
        expiresAt: Number(chainSubscription.expiresAt ?? chainSubscription[6] ?? 0),
        autoRenewEnabled: Boolean(chainSubscription.autoRenewEnabled ?? chainSubscription[8]),
        status: subscriptionStatus.status,
        isActive: subscriptionStatus.isActive,
      }
    });

  } catch (error) {
    // 打印完整错误信息，帮助诊断
    console.error('❌ 订阅失败 message:', error.message);
    console.error('❌ 订阅失败 stack:', error.stack);
    console.error('❌ 订阅失败 details:', JSON.stringify(error, Object.getOwnPropertyNames(error), 2));
    res.status(500).json({ error: error.message, detail: error.stack });
  }
});

// ============================================================================
// API: 测试 Paymaster 连通性 (调试用)
// ============================================================================

app.get('/api/debug/paymaster', async (_req, res) => {
  try {
    const paymasterUrl = process.env.CDP_PAYMASTER_URL;
    console.log('🔍 测试 Paymaster URL:', paymasterUrl);

    if (!paymasterUrl) {
      return res.status(500).json({ error: 'CDP_PAYMASTER_URL 未设置' });
    }

    // 发送一个 pm_getPaymasterStubData 请求测试连通性
    const testPayload = {
      jsonrpc: '2.0',
      id: 1,
      method: 'pm_getPaymasterStubData',
      params: [
        {
          sender: serverWalletAccount ? serverWalletAccount.address : '0x0000000000000000000000000000000000000000',
          nonce: '0x0',
          initCode: '0x',
          callData: '0x',
          callGasLimit: '0x0',
          verificationGasLimit: '0x0',
          preVerificationGas: '0x0',
          maxFeePerGas: '0x0',
          maxPriorityFeePerGas: '0x0',
        },
        '0x0000000071727De22E5E9d8BAf0edAc6f37da032', // EntryPoint v0.7
        '0x14A34',  // Base Sepolia chainId hex
        { sponsorshipPolicyId: '' },
      ],
    };

    const response = await fetch(paymasterUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(testPayload),
    });

    const data = await response.json();
    console.log('Paymaster 响应:', JSON.stringify(data, null, 2));

    res.json({
      paymasterUrl,
      smartAccountAddress: serverWalletAccount ? serverWalletAccount.address : null,
      contractAddress: CONTRACT_ADDRESS,
      httpStatus: response.status,
      paymasterResponse: data,
    });
  } catch (error) {
    console.error('Paymaster 测试失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: 订阅 (完整版,需要两个签名)
// ============================================================================

app.post('/api/subscribe', async (req, res) => {
  try {
    const {
      userAddress,
      identityAddress,
      planId,
      maxAmount,
      permitDeadline,
      intentNonce,
      intentSig,
      permitSig,
      idempotencyKey,
    } = req.body;

    console.log('📝 收到订阅请求:', {
      userAddress,
      identityAddress,
      planId,
      idempotencyKey,
    });

    // 验证必填字段
    if (!userAddress || !identityAddress || !planId || !maxAmount || !permitDeadline || intentNonce === undefined || !intentSig || !permitSig) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // 验证地址格式
    if (!ethers.isAddress(userAddress) || !ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    // TODO: 幂等性检查 (IdempotencyKey)
    // TODO: identityAddress 唯一性检查 (DB)

    // 验证 SubscribeIntent 签名
    console.log('🔍 验证 SubscribeIntent 签名...');
    const intentMessage = {
      user: userAddress,
      identityAddress: identityAddress,
      planId: BigInt(planId),
      maxAmount: BigInt(maxAmount),
      deadline: BigInt(permitDeadline),
      nonce: BigInt(intentNonce),
    };

    const recoveredAddress = ethers.verifyTypedData(
      DOMAIN,
      SUBSCRIBE_INTENT_TYPES,
      intentMessage,
      intentSig
    );

    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) {
      return res.status(400).json({ error: 'Invalid intent signature' });
    }

    console.log('✅ SubscribeIntent 签名验证成功');

    // 解析 permit 签名
    const permitSigBytes = ethers.getBytes(permitSig);
    const permitV = permitSigBytes[64];
    const permitR = ethers.hexlify(permitSigBytes.slice(0, 32));
    const permitS = ethers.hexlify(permitSigBytes.slice(32, 64));

    // 编码合约调用数据
    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('permitAndSubscribe', [
      userAddress,
      identityAddress,
      planId,
      maxAmount,
      permitDeadline,
      intentNonce,
      intentSig,
      permitV,
      permitR,
      permitS,
    ]);

    console.log('📤 通过 CDP Server Wallet 发送交易...');
    console.log('  使用 Paymaster 赞助 gas (0 ETH)');

    // 通过 CDP Server Wallet 发送交易
    const { sendTransactionViaCDP } = require('./cdp-transaction');

    const txResult = await sendTransactionViaCDP({
      account: serverWalletAccount,
      contractAddress: CONTRACT_ADDRESS,
      calldata,
      network: 'base-sepolia',
    });

    res.json({
      success: true,
      message: 'Subscription created successfully',
      userAddress,
      identityAddress,
      planId,
      transactionHash: txResult.transactionHash,
    });

  } catch (error) {
    console.error('订阅失败:', error);
    res.status(500).json({ error: 'Subscription failed', detail: error.message });
  }
});

// ============================================================================
// API: 取消订阅
// ============================================================================

// ✅ V2 修改：支持简化的取消订阅 API（需要用户签名）
app.post('/api/subscription/cancel', async (req, res) => {
  try {
    const { userAddress, identityAddress, nonce, signature } = req.body;

    console.log('📝 收到取消订阅请求:', { userAddress, identityAddress, nonce });

    // 验证必填字段
    if (!userAddress || !identityAddress || nonce === undefined || !signature) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // 验证地址格式
    if (!ethers.isAddress(userAddress) || !ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    // 预检查：查询订阅状态，如果已经取消则直接返回
    console.log('🔍 预检查订阅状态...');
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    try {
      const subscription = await contract.getSubscription(identityAddress);
      const subscriptionStatus = getSubscriptionStatus(subscription);

      console.log('📊 订阅状态:', {
        startTime: subscriptionStatus.startTime,
        expiresAt: subscriptionStatus.expiresAt,
        autoRenewEnabled: subscriptionStatus.autoRenewEnabled,
        status: subscriptionStatus.status,
        isActive: subscriptionStatus.isActive,
        payerAddress: subscription.payerAddress
      });

      // 如果订阅不存在或自动续费已关闭，直接返回成功
      if (subscriptionStatus.startTime === 0 || !subscriptionStatus.autoRenewEnabled) {
        console.log('ℹ️  订阅已取消或不存在，无需重复操作');
        return res.json({
          success: true,
          alreadyCancelled: true,
          message: '该订阅的自动续费已经关闭',
          identityAddress
        });
      }
    } catch (error) {
      console.log('⚠️  预检查失败，继续执行取消操作:', error.message);
      // 如果预检查失败，继续执行取消操作（可能是合约调用问题）
    }

    // 验证 CancelIntent 签名（V2: 包含 identityAddress）
    console.log('🔍 验证 CancelIntent 签名...');
    const cancelMessage = {
      user: userAddress,
      identityAddress: identityAddress,
      nonce: BigInt(nonce),
    };

    const recoveredAddress = ethers.verifyTypedData(
      DOMAIN,
      CANCEL_INTENT_TYPES,
      cancelMessage,
      signature
    );

    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) {
      return res.status(400).json({ error: 'Invalid signature' });
    }

    console.log('✅ CancelIntent 签名验证成功');

    // 编码合约调用数据（V2: 添加 identityAddress 参数）
    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('cancelFor', [
      userAddress,
      identityAddress,  // V2 新增参数
      nonce,
      signature,
    ]);

    console.log('📤 通过 CDP Smart Account 发送 UserOperation (Paymaster 赞助 gas)...');

    // 通过 CDP Smart Account 发送 UserOperation (ERC-4337)
    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount,
      network: 'base-sepolia',
      calls: [{
        to: CONTRACT_ADDRESS,
        data: calldata,
        value: BigInt(0),
      }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL,
    });

    console.log('✅ UserOperation 已发送:', userOp.userOpHash);

    // 等待 UserOperation 确认
    console.log('⏳ 等待 UserOperation 确认...');
    const receipt = await cdpClient.evm.waitForUserOperation({
      smartAccountAddress: serverWalletAccount.address,
      userOpHash: userOp.userOpHash,
    });

    if (receipt.status !== 'complete') {
      throw new Error(`UserOperation failed: ${receipt.status}`);
    }

    console.log('✅ 取消订阅成功!');
    console.log('  Transaction Hash:', receipt.transactionHash);

    res.json({
      success: true,
      txHash: receipt.transactionHash,
      userAddress,
      identityAddress,
    });

  } catch (error) {
    console.error('❌ 取消订阅失败:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: V2.1 套餐升降级与修改
// ============================================================================

// 1. 升级套餐 (立即生效，需要补差价，因此需要同时收取 intentSignature 和 permitSignature)
app.post('/api/subscription/upgrade', async (req, res) => {
  try {
    const { userAddress, identityAddress, newPlanId, isYearly, maxAmount, deadline, nonce, intentSignature, permitSignature } = req.body;
    
    if (!userAddress || !identityAddress || !newPlanId || maxAmount === undefined || !deadline || nonce === undefined || !intentSignature) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const upgradeMessage = {
      user: userAddress,
      identityAddress: identityAddress,
      newPlanId: BigInt(newPlanId),
      isYearly: Boolean(isYearly),
      maxAmount: BigInt(maxAmount),
      deadline: BigInt(deadline),
      nonce: BigInt(nonce)
    };

    const recoveredAddress = ethers.verifyTypedData(DOMAIN, UPGRADE_INTENT_TYPES, upgradeMessage, intentSignature);
    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) {
      return res.status(400).json({ error: 'Invalid UpgradeIntent signature' });
    }

    let permitV = 0, permitR = ethers.ZeroHash, permitS = ethers.ZeroHash;
    if (permitSignature && maxAmount > 0) {
      const permitSig = ethers.Signature.from(permitSignature);
      permitV = permitSig.v;
      permitR = permitSig.r;
      permitS = permitSig.s;
    }

    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('upgradeSubscription', [
      userAddress, identityAddress, newPlanId, Boolean(isYearly), maxAmount, deadline, nonce, intentSignature, permitV, permitR, permitS
    ]);

    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount, network: 'base-sepolia', calls: [{ to: CONTRACT_ADDRESS, data: calldata, value: BigInt(0) }], paymasterUrl: process.env.CDP_PAYMASTER_URL
    });
    const receipt = await cdpClient.evm.waitForUserOperation({ smartAccountAddress: serverWalletAccount.address, userOpHash: userOp.userOpHash });
    
    if (receipt.status !== 'complete') throw new Error(`UserOperation failed: ${receipt.status}`);
    
    // 通知 mock database (可选，但由于链上已生效，我们可以借机重置状态)
    require('./mock-db').trackIdentity(identityAddress);
    
    res.json({ success: true, txHash: receipt.transactionHash, userOperationHash: userOp.userOpHash, userAddress, identityAddress, newPlanId });
  } catch (error) {
    console.error('❌ 升级失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// 2. 降级套餐 (下月生效，只提交意向)
app.post('/api/subscription/downgrade', async (req, res) => {
  try {
    const { userAddress, identityAddress, newPlanId, nonce, intentSignature } = req.body;
    
    if (!userAddress || !identityAddress || !newPlanId || nonce === undefined || !intentSignature) return res.status(400).json({ error: 'Missing required fields' });
    
    const downgradeMessage = { user: userAddress, identityAddress: identityAddress, newPlanId: BigInt(newPlanId), nonce: BigInt(nonce) };
    const recoveredAddress = ethers.verifyTypedData(DOMAIN, DOWNGRADE_INTENT_TYPES, downgradeMessage, intentSignature);
    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) return res.status(400).json({ error: 'Invalid DowngradeIntent signature' });

    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('downgradeSubscription', [userAddress, identityAddress, newPlanId, nonce, intentSignature]);

    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount, network: 'base-sepolia', calls: [{ to: CONTRACT_ADDRESS, data: calldata, value: BigInt(0) }], paymasterUrl: process.env.CDP_PAYMASTER_URL
    });
    const receipt = await cdpClient.evm.waitForUserOperation({ smartAccountAddress: serverWalletAccount.address, userOpHash: userOp.userOpHash });
    if (receipt.status !== 'complete') throw new Error(`UserOperation failed: ${receipt.status}`);
    
    res.json({ success: true, txHash: receipt.transactionHash });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 3. 取消挂起的变动 (取消将要生效的降级)
app.post('/api/subscription/cancel-change', async (req, res) => {
  try {
    const { userAddress, identityAddress, nonce, intentSignature } = req.body;
    if (!userAddress || !identityAddress || nonce === undefined || !intentSignature) return res.status(400).json({ error: 'Missing required fields' });

    const cancelMessage = { user: userAddress, identityAddress: identityAddress, nonce: BigInt(nonce) };
    const recoveredAddress = ethers.verifyTypedData(DOMAIN, CANCEL_CHANGE_INTENT_TYPES, cancelMessage, intentSignature);
    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) return res.status(400).json({ error: 'Invalid CancelChangeIntent signature' });

    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('cancelPendingChange', [userAddress, identityAddress, nonce, intentSignature]);

    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount, network: 'base-sepolia', calls: [{ to: CONTRACT_ADDRESS, data: calldata, value: BigInt(0) }], paymasterUrl: process.env.CDP_PAYMASTER_URL
    });
    const receipt = await cdpClient.evm.waitForUserOperation({ smartAccountAddress: serverWalletAccount.address, userOpHash: userOp.userOpHash });
    if (receipt.status !== 'complete') throw new Error(`UserOperation failed: ${receipt.status}`);
    
    res.json({ success: true, txHash: receipt.transactionHash });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: V2.1 套餐管理
// ============================================================================

// 查询所有活跃套餐
app.get('/api/plans', async (_req, res) => {
  try {
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    // 查询套餐 ID 1-10 (扩展范围以包含测试套餐)
    const plans = [];
    for (let planId = 1; planId <= 10; planId++) {
      try {
        const plan = await contract.getPlan(planId);
        if (plan.isActive) {
          plans.push({
            planId,
            name: plan.name,
            pricePerMonth: plan.pricePerMonth.toString(),
            pricePerYear: plan.pricePerYear.toString(),
            trafficLimitDaily: plan.trafficLimitDaily.toString(),
            trafficLimitMonthly: plan.trafficLimitMonthly.toString(),
            tier: Number(plan.tier),
            isActive: plan.isActive
          });
        }
      } catch (error) {
        // 套餐不存在时忽略错误
        if (!error.message.includes('call revert exception')) {
          console.error(`查询套餐 ${planId} 失败:`, error.message);
        }
      }
    }

    res.json({ plans });
  } catch (error) {
    console.error('查询套餐列表失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// 查询单个套餐详情
app.get('/api/plan/:planId', async (req, res) => {
  try {
    const { planId } = req.params;
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    const plan = await contract.getPlan(planId);

    res.json({
      plan: {
        planId: parseInt(planId),
        name: plan.name,
        pricePerMonth: plan.pricePerMonth.toString(),
        pricePerYear: plan.pricePerYear.toString(),
        trafficLimitDaily: plan.trafficLimitDaily.toString(),
        trafficLimitMonthly: plan.trafficLimitMonthly.toString(),
        tier: Number(plan.tier),
        isActive: plan.isActive
      }
    });
  } catch (error) {
    console.error('查询套餐详情失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: V2.1 流量查询
// ============================================================================

// 查询单个身份的流量使用情况
app.get('/api/traffic/:identityAddress', async (req, res) => {
  try {
    const { identityAddress } = req.params;

    if (!ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    const sub = await contract.getSubscription(identityAddress);

    const startTime = Number(sub.startTime ?? sub[5] ?? 0);
    if (startTime === 0) {
      return res.json({
        success: true,
        identityAddress,
        dailyUsed: 0,
        monthlyUsed: 0,
        dailyLimit: 0,
        monthlyLimit: 0,
        status: 'expired',
      });
    }

    const plan = await contract.getPlan(sub.planId);

    // 流量追踪已移到服务端，暂时返回 0
    // TODO: 从服务端数据库读取流量数据
    const dailyUsed = 0;
    const monthlyUsed = 0;
    const dailyLimit = Number(plan.trafficLimitDaily ?? 0);
    const monthlyLimit = Number(plan.trafficLimitMonthly ?? 0);

    // 使用统一状态判断函数
    const subscriptionStatus = getSubscriptionStatus(sub);

    res.json({
      success: true,
      identityAddress,
      dailyUsed,
      monthlyUsed,
      dailyLimit,
      monthlyLimit,
      status: subscriptionStatus.status,
    });
  } catch (error) {
    console.error('查询流量失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// 记录流量使用 (VPN 服务器调用)
app.post('/api/traffic/record', async (req, res) => {
  try {
    const { identityAddress, bytesUsed } = req.body;

    if (!identityAddress || !bytesUsed) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (!ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    if (!trafficTracker) {
      return res.status(500).json({ error: 'Traffic tracker not initialized' });
    }

    trafficTracker.recordTraffic(identityAddress, parseInt(bytesUsed));
    res.json({ success: true, message: 'Traffic recorded' });
  } catch (error) {
    console.error('记录流量失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: V2.1 补差价计算
// ============================================================================

// 计算升级补差价
app.get('/api/subscription/proration', async (req, res) => {
  try {
    const { identityAddress, newPlanId, isYearly } = req.query;

    if (!identityAddress || !newPlanId) {
      return res.status(400).json({ error: 'Missing required parameters' });
    }

    if (!ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    const parsedNewPlanId = Number(newPlanId);
    if (!Number.isInteger(parsedNewPlanId) || parsedNewPlanId <= 0) {
      return res.status(400).json({ error: 'Invalid newPlanId' });
    }

    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    const yearly = String(isYearly) === 'true';
    const prorationAmount = await contract.calculateUpgradeProration(identityAddress, parsedNewPlanId, yearly);

    res.json({
      success: true,
      identityAddress,
      newPlanId: parsedNewPlanId,
      isYearly: yearly,
      prorationAmount: prorationAmount.toString()
    });
  } catch (error) {
    console.error('计算补差价失败:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// API: 查询订阅状态
// ============================================================================

// ✅ V2 新增：查询用户的所有订阅
app.get('/api/subscriptions/user/:address', async (req, res) => {
  try {
    const { address } = req.params;

    if (!ethers.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    // 查询用户的所有订阅身份
    const identities = await contract.getUserIdentities(address);

    // 查询每个身份的订阅详情
    const subscriptions = [];
    for (const identity of identities) {
      const sub = await contract.subscriptions(identity);
      const startTime = Number(sub[5]);
      if (startTime > 0) {
        // 新的 Subscription 结构体（9 个字段）
        // [0] identityAddress, [1] payerAddress, [2] lockedPrice, [3] planId,
        // [4] lockedPeriod, [5] startTime, [6] expiresAt, [7] renewedAt, [8] autoRenewEnabled
        const subscriptionStatus = getSubscriptionStatus(sub);
        subscriptions.push({
          identityAddress: sub[0],
          payerAddress: sub[1],
          lockedPrice: sub[2].toString(),
          planId: Number(sub[3]),
          lockedPeriod: Number(sub[4]),
          startTime: Number(sub[5]),
          expiresAt: Number(sub[6]),
          renewedAt: Number(sub[7]),
          autoRenewEnabled: Boolean(sub[8]),
          status: subscriptionStatus.status,
          isActive: subscriptionStatus.isActive,
        });
      }
    }

    res.json({ subscriptions });
  } catch (error) {
    console.error('查询用户订阅失败:', error);
    res.status(500).json({ error: 'Query failed', detail: error.message });
  }
});

// 别名端点：兼容前端的单数形式调用
app.get('/api/subscription/:address', async (req, res) => {
  try {
    const { address } = req.params;

    if (!ethers.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

    // 查询用户的所有订阅身份
    const identities = await contract.getUserIdentities(address);

    // 查询每个身份的订阅详情
    const subscriptions = [];
    for (const identity of identities) {
      const sub = await contract.subscriptions(identity);
      const startTime = Number(sub[5]);
      if (startTime > 0) {
        // 新的 Subscription 结构体（9 个字段）
        // [0] identityAddress, [1] payerAddress, [2] lockedPrice, [3] planId,
        // [4] lockedPeriod, [5] startTime, [6] expiresAt, [7] renewedAt, [8] autoRenewEnabled
        const subscriptionStatus = getSubscriptionStatus(sub);
        subscriptions.push({
          identityAddress: sub[0],
          payerAddress: sub[1],
          lockedPrice: sub[2].toString(),
          planId: Number(sub[3]),
          lockedPeriod: Number(sub[4]),
          startTime: Number(sub[5]),
          expiresAt: Number(sub[6]),
          renewedAt: Number(sub[7]),
          autoRenewEnabled: Boolean(sub[8]),
          status: subscriptionStatus.status,
          isActive: subscriptionStatus.isActive,
        });
      }
    }

    res.json({ subscriptions });
  } catch (error) {
    console.error('查询用户订阅失败:', error);
    res.status(500).json({ error: 'Query failed', detail: error.message });
  }
});

// ============================================================================
// 定时任务: 自动续费
// ============================================================================

const { RenewalService } = require('./renewal-service');
let renewalService;

function startRenewalService() {
  renewalService = new RenewalService({
    cdpClient,
    serverWalletAccount,
    contractAddress: CONTRACT_ADDRESS,
    paymasterEndpoint: PAYMASTER_ENDPOINT,
    subscriptionSet, // 传入事件驱动的订阅列表
  });

  renewalService.start();
}

// ============================================================================
// 流量追踪服务
// ============================================================================

const { TrafficTracker } = require('./traffic-tracker');
let trafficTracker;

function startTrafficTracker() {
  trafficTracker = new TrafficTracker({
    cdpClient,
    serverWalletAccount,
    contractAddress: CONTRACT_ADDRESS,
    paymasterEndpoint: PAYMASTER_ENDPOINT,
    provider: new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT),
  });

  trafficTracker.start();
}

// API: 获取自动续费状态
app.get('/api/renewal/status', (_req, res) => {
  if (!renewalService) {
    return res.json({ error: 'Renewal service not started' });
  }

  res.json(renewalService.getStatus());
});

// API: 手动触发续费检查 (用于测试)
app.post('/api/renewal/trigger', async (_req, res) => {
  if (!renewalService) {
    return res.status(500).json({ error: 'Renewal service not started' });
  }

  try {
    await renewalService.tick();
    res.json({ success: true, message: 'Renewal check triggered' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API: 添加订阅到监控列表 (用于测试)
app.post('/api/renewal/add', (_req, res) => {
  if (!renewalService) {
    return res.status(500).json({ error: 'Renewal service not started' });
  }

  const { identityAddress } = _req.body;
  if (!identityAddress || !ethers.isAddress(identityAddress)) {
    return res.status(400).json({ error: 'Missing or invalid identityAddress' });
  }

  subscriptionSet.add(identityAddress);
  res.json({ success: true, message: 'Subscription added to monitoring', identityAddress });
});

// ============================================================================
// 启动服务
// ============================================================================

async function start() {
  try {
    // 初始化 permit store
    permitStore.loadStore();

    await initializeCDP();
    await assertRelayerMatchesServerWallet();

    // 初始化事件监听和订阅列表同步
    await initializeEventListeners();

    app.listen(PORT, () => {
      console.log('');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log('🚀 VPN Subscription Service 启动成功!');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`📡 服务地址: http://localhost:${PORT}`);
      console.log(`📋 合约地址: ${CONTRACT_ADDRESS}`);
      console.log(`💰 USDC 地址: ${USDC_ADDRESS}`);
      console.log(`🔐 Server Wallet: ${serverWalletAccount.address}`);
      console.log(`🌐 网络: base-sepolia`);
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log('');
      console.log('📝 API 端点:');
      console.log(`  GET  /api/config`);
      console.log(`  POST /api/subscription/prepare`);
      console.log(`  POST /api/subscription/subscribe`);
      console.log(`  POST /api/subscription/cancel`);
      console.log(`  POST /api/subscription/upgrade`);
      console.log(`  POST /api/subscription/downgrade`);
      console.log(`  POST /api/subscription/cancel-change`);
      console.log(`  GET  /api/subscription/:address`);
      console.log(`  GET  /api/intent-nonce?address=<address>`);
      console.log(`  GET  /api/cancel-nonce?address=<address>`);
      console.log(`  POST /api/subscribe`);
      console.log(`  POST /api/cancel`);
      console.log(`  GET  /api/renewal/status`);
      console.log(`  POST /api/renewal/trigger`);
      console.log(`  POST /api/renewal/add`);
      console.log('');
      console.log('💡 提示:');
      console.log('  - 所有交易通过 CDP Paymaster 赞助 gas (0 ETH)');
      console.log(`  - 自动续费任务每 ${process.env.RENEWAL_CHECK_INTERVAL_SECONDS || 60} 秒执行一次`);
      console.log(`  - 流量追踪任务每 ${process.env.TRAFFIC_REPORT_INTERVAL_SECONDS || 300} 秒上报一次`);
      console.log('');

      // 启动自动续费服务
      startRenewalService();

      // 启动流量追踪服务
      startTrafficTracker();
    });
  } catch (error) {
    console.error('❌ 服务启动失败:', error);
    process.exit(1);
  }
}

start();
