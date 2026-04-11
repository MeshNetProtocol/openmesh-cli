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
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const express = require('express');
const { CdpClient } = require('@coinbase/cdp-sdk');
const { ethers } = require('ethers');

// ============================================================================
// 配置
// ============================================================================

const PORT = process.env.PORT || 8080;
const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const USDC_ADDRESS = process.env.USDC_CONTRACT;
const PAYMASTER_ENDPOINT = process.env.CDP_PAYMASTER_ENDPOINT;
const SERVER_WALLET_ACCOUNT_NAME = process.env.CDP_SERVER_WALLET_ACCOUNT_NAME;

// EIP-712 Domain
const DOMAIN = {
  name: 'VPNSubscription',
  version: '1',
  chainId: 84532, // Base Sepolia
  verifyingContract: CONTRACT_ADDRESS,
};

// EIP-712 Types
const SUBSCRIBE_INTENT_TYPES = {
  SubscribeIntent: [
    { name: 'user', type: 'address' },
    { name: 'identityAddress', type: 'address' },
    { name: 'planId', type: 'uint256' },
    { name: 'maxAmount', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
  ],
};

const CANCEL_INTENT_TYPES = {
  CancelIntent: [
    { name: 'user', type: 'address' },
    { name: 'nonce', type: 'uint256' },
  ],
};

// ============================================================================
// CDP Client 初始化
// ============================================================================

let cdpClient;
let serverWalletAccount;

async function initializeCDP() {
  console.log('📡 初始化 CDP Client...');

  cdpClient = new CdpClient({
    apiKeyId: process.env.CDP_API_KEY_ID,
    apiKeySecret: process.env.CDP_API_KEY_SECRET,
    walletSecret: process.env.CDP_WALLET_SECRET,
  });

  console.log('✅ CDP Client 初始化成功');

  console.log('🔨 获取 CDP Server Wallet...');
  serverWalletAccount = await cdpClient.evm.getOrCreateAccount({
    name: SERVER_WALLET_ACCOUNT_NAME,
  });

  console.log('✅ Server Wallet 获取成功');
  console.log('  Address:', serverWalletAccount.address);
  console.log('  Network:', serverWalletAccount.network || 'base-sepolia');
}

// ============================================================================
// 合约 ABI (只包含需要的函数)
// ============================================================================

const CONTRACT_ABI = [
  'function permitAndSubscribe(address user, address identityAddress, uint256 planId, uint256 maxAmount, uint256 permitDeadline, uint256 intentNonce, bytes calldata intentSig, uint8 permitV, bytes32 permitR, bytes32 permitS) external',
  'function executeRenewal(address user) external',
  'function cancelFor(address user, uint256 nonce, bytes calldata sig) external',
  'function finalizeExpired(address user, bool forceClosed) external',
  'function intentNonces(address user) external view returns (uint256)',
  'function cancelNonces(address user) external view returns (uint256)',
  'function subscriptions(address user) external view returns (address identityAddress, uint96 lockedPrice, uint256 planId, uint256 lockedPeriod, uint256 startTime, uint256 expiresAt, bool autoRenewEnabled, bool isActive)',
];

// ============================================================================
// Express App
// ============================================================================

const app = express();
app.use(express.json());

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

// ============================================================================
// API: 获取配置信息
// ============================================================================

app.get('/api/config', (req, res) => {
  res.json({
    contractAddress: CONTRACT_ADDRESS,
    usdcAddress: USDC_ADDRESS,
    network: 'base-sepolia',
    chainId: 84532,
  });
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
// API: 订阅
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
    // TODO: 实现 CDP SDK 的交易发送
    // 目前 CDP SDK 的 Go/Node.js 版本可能还不支持直接发送交易
    // 需要使用 CDP API 或等待 SDK 更新

    // 临时响应
    res.json({
      success: true,
      message: 'Subscription request received',
      userAddress,
      identityAddress,
      planId,
      // txHash: txHash, // TODO: 返回实际的交易哈希
    });

  } catch (error) {
    console.error('订阅失败:', error);
    res.status(500).json({ error: 'Subscription failed', detail: error.message });
  }
});

// ============================================================================
// API: 取消订阅
// ============================================================================

app.post('/api/cancel', async (req, res) => {
  try {
    const { userAddress, nonce, sig } = req.body;

    console.log('📝 收到取消订阅请求:', { userAddress, nonce });

    // 验证必填字段
    if (!userAddress || nonce === undefined || !sig) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // 验证地址格式
    if (!ethers.isAddress(userAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    // 验证 CancelIntent 签名
    console.log('🔍 验证 CancelIntent 签名...');
    const cancelMessage = {
      user: userAddress,
      nonce: BigInt(nonce),
    };

    const recoveredAddress = ethers.verifyTypedData(
      DOMAIN,
      CANCEL_INTENT_TYPES,
      cancelMessage,
      sig
    );

    if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) {
      return res.status(400).json({ error: 'Invalid signature' });
    }

    console.log('✅ CancelIntent 签名验证成功');

    // 编码合约调用数据
    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('cancelFor', [
      userAddress,
      nonce,
      sig,
    ]);

    console.log('📤 通过 CDP Server Wallet 发送交易...');

    // TODO: 通过 CDP Server Wallet 发送交易

    res.json({
      success: true,
      message: 'Cancel request received',
      userAddress,
      // txHash: txHash, // TODO: 返回实际的交易哈希
    });

  } catch (error) {
    console.error('取消订阅失败:', error);
    res.status(500).json({ error: 'Cancel failed', detail: error.message });
  }
});

// ============================================================================
// API: 查询订阅状态
// ============================================================================

app.get('/api/subscription/:address', async (req, res) => {
  try {
    const { address } = req.params;

    if (!ethers.isAddress(address)) {
      return res.status(400).json({ error: 'Invalid address' });
    }

    // 查询链上订阅状态
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    const subscription = await contract.subscriptions(address);

    res.json({
      identityAddress: subscription[0],
      lockedPrice: subscription[1].toString(),
      planId: subscription[2].toString(),
      lockedPeriod: subscription[3].toString(),
      startTime: subscription[4].toString(),
      expiresAt: subscription[5].toString(),
      autoRenewEnabled: subscription[6],
      isActive: subscription[7],
    });

  } catch (error) {
    console.error('查询订阅失败:', error);
    res.status(500).json({ error: 'Query failed', detail: error.message });
  }
});

// ============================================================================
// 定时任务: 自动续费
// ============================================================================

async function renewalTask() {
  console.log('🔄 执行自动续费任务...');

  // TODO: 实现自动续费逻辑
  // 1. 查询即将到期的订阅 (expiresAt <= now + 24h)
  // 2. 预检资金
  // 3. 到期后调用 executeRenewal
  // 4. 失败计数 >= 3 时调用 finalizeExpired
}

// 每小时执行一次续费任务
setInterval(renewalTask, 60 * 60 * 1000);

// ============================================================================
// 启动服务
// ============================================================================

async function start() {
  try {
    await initializeCDP();

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
      console.log(`  GET  /api/intent-nonce?address=<address>`);
      console.log(`  GET  /api/cancel-nonce?address=<address>`);
      console.log(`  POST /api/subscribe`);
      console.log(`  POST /api/cancel`);
      console.log(`  GET  /api/subscription/:address`);
      console.log('');
      console.log('💡 提示:');
      console.log('  - 所有交易通过 CDP Paymaster 赞助 gas (0 ETH)');
      console.log('  - 自动续费任务每小时执行一次');
      console.log('');
    });
  } catch (error) {
    console.error('❌ 服务启动失败:', error);
    process.exit(1);
  }
}

start();
