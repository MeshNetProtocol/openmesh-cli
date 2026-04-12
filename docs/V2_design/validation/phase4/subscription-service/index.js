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
const { encodeFunctionData } = require('viem');

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

  // 第一步: 创建 Owner Account (EOA)
  console.log('🔨 获取 Owner Account (EOA)...');
  const ownerAccount = await cdpClient.evm.getOrCreateAccount({
    name: 'openmesh-vpn-owner',
  });
  console.log('✅ Owner Account 创建成功:', ownerAccount.address);

  // 第二步: 创建 Smart Account (使用 Owner Account)
  console.log('🔨 获取 CDP Smart Account (支持 Paymaster 0 gas)...');
  serverWalletAccount = await cdpClient.evm.getOrCreateSmartAccount({
    name: 'openmesh-vpn-smart',
    owner: ownerAccount,
  });

  console.log('✅ Smart Account 获取成功');
  console.log('  Smart Account Address:', serverWalletAccount.address);
  console.log('  Owner Account Address:', ownerAccount.address);
  console.log('  Network:', serverWalletAccount.network || 'base-sepolia');
  console.log('  Type: Smart Account (ERC-4337)');
  console.log('  Gas: 0 ETH (Paymaster 自动赞助)');
}

// ============================================================================
// 合约 ABI (viem 格式 - JSON ABI)
// ============================================================================

const CONTRACT_ABI = [
  {
    type: 'function',
    name: 'permitAndSubscribe',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'identityAddress', type: 'address' },
      { name: 'planId', type: 'uint256' },
      { name: 'maxAmount', type: 'uint256' },
      { name: 'permitDeadline', type: 'uint256' },
      { name: 'intentNonce', type: 'uint256' },
      { name: 'intentSig', type: 'bytes' },
      { name: 'permitV', type: 'uint8' },
      { name: 'permitR', type: 'bytes32' },
      { name: 'permitS', type: 'bytes32' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'intentNonces',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'subscriptions',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [
      { name: 'identityAddress', type: 'address' },
      { name: 'lockedPrice', type: 'uint96' },
      { name: 'planId', type: 'uint256' },
      { name: 'lockedPeriod', type: 'uint256' },
      { name: 'startTime', type: 'uint256' },
      { name: 'expiresAt', type: 'uint256' },
      { name: 'autoRenewEnabled', type: 'bool' },
      { name: 'isActive', type: 'bool' },
    ],
  },
];

// ============================================================================
// Express App
// ============================================================================

const app = express();
app.use(express.json());

// 全局请求日志中间件 - 捕获所有请求
app.use((req, res, next) => {
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
// API: 准备订阅签名数据
// ============================================================================

app.post('/api/subscription/prepare', async (req, res) => {
  try {
    const { userAddress, planId, identityAddress } = req.body;

    if (!userAddress || !planId || !identityAddress) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (!ethers.isAddress(userAddress) || !ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    // 获取用户的 nonce
    const provider = new ethers.JsonRpcProvider(PAYMASTER_ENDPOINT);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);
    const intentNonce = await contract.intentNonces(userAddress);

    // 计算 maxAmount (USDC 有 6 位小数)
    const maxAmount = planId === 1 ? '5000000' : '50000000'; // 5 or 50 USDC
    const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    // 返回 EIP-712 签名数据
    res.json({
      domain: DOMAIN,
      types: SUBSCRIBE_INTENT_TYPES,
      value: {
        user: userAddress,
        identityAddress: identityAddress,
        planId: parseInt(planId),
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
  console.log('📦 Request Body:', JSON.stringify(req.body, null, 2));

  try {
    const { userAddress, planId, identityAddress, intentSignature, permitSignature, maxAmount, deadline, nonce } = req.body;

    console.log('📝 收到订阅请求:', { userAddress, identityAddress, planId });

    if (!userAddress || !planId || !identityAddress || !intentSignature || !permitSignature || !maxAmount || !deadline || nonce === undefined) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (!ethers.isAddress(userAddress) || !ethers.isAddress(identityAddress)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    // 验证 SubscribeIntent 签名 (使用前端传来的原始数据)
    console.log('🔍 验证 SubscribeIntent 签名...');
    const intentMessage = {
      user: userAddress,
      identityAddress: identityAddress,
      planId: BigInt(planId),
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
    const permitSig = ethers.Signature.from(permitSignature);

    console.log('🔍 调试信息:');
    console.log('  userAddress:', userAddress);
    console.log('  identityAddress:', identityAddress);
    console.log('  planId:', planId, 'BigInt:', BigInt(planId));
    console.log('  maxAmount:', maxAmount, 'BigInt:', BigInt(maxAmount));
    console.log('  deadline:', deadline, 'BigInt:', BigInt(deadline));
    console.log('  nonce:', nonce, 'BigInt:', BigInt(nonce));
    console.log('  intentSignature:', intentSignature);
    console.log('  permitSig.v:', permitSig.v);
    console.log('  permitSig.r:', permitSig.r);
    console.log('  permitSig.s:', permitSig.s);

    // 构造合约调用数据 (使用 viem)
    const calldata = encodeFunctionData({
      abi: CONTRACT_ABI,
      functionName: 'permitAndSubscribe',
      args: [
        userAddress,
        identityAddress,
        BigInt(planId),
        BigInt(maxAmount),
        BigInt(deadline),
        BigInt(nonce),
        intentSignature,
        permitSig.v,
        permitSig.r,
        permitSig.s
      ],
    });

    console.log('📦 Calldata:', calldata);
    console.log('📤 通过 CDP Smart Account 发送 UserOperation (Paymaster 赞助 gas)...');
    console.log('🔑 Paymaster URL:', process.env.CDP_PAYMASTER_URL);

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

    res.json({
      success: true,
      txHash: receipt.transactionHash,
      userOperationHash: userOp.userOpHash,
      subscription: {
        userAddress,
        identityAddress,
        planId,
        expiresAt: Math.floor(Date.now() / 1000) + (planId === 1 ? 30 * 86400 : 365 * 86400)
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

app.get('/api/debug/paymaster', async (req, res) => {
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
      message: 'Subscription cancelled successfully',
      userAddress,
      transactionHash: txResult.transactionHash,
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

const { RenewalService } = require('./renewal-service');
let renewalService;

function startRenewalService() {
  renewalService = new RenewalService({
    cdpClient,
    serverWalletAccount,
    contractAddress: CONTRACT_ADDRESS,
    paymasterEndpoint: PAYMASTER_ENDPOINT,
  });

  renewalService.start();
}

// API: 获取自动续费状态
app.get('/api/renewal/status', (req, res) => {
  if (!renewalService) {
    return res.json({ error: 'Renewal service not started' });
  }

  res.json(renewalService.getStatus());
});

// API: 手动触发续费检查 (用于测试)
app.post('/api/renewal/trigger', async (req, res) => {
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
app.post('/api/renewal/add', (req, res) => {
  if (!renewalService) {
    return res.status(500).json({ error: 'Renewal service not started' });
  }

  const { userAddress } = req.body;
  if (!userAddress) {
    return res.status(400).json({ error: 'Missing userAddress' });
  }

  renewalService.addSubscription(userAddress);
  res.json({ success: true, message: 'Subscription added to monitoring' });
});

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
      console.log(`  POST /api/subscription/prepare`);
      console.log(`  POST /api/subscription/subscribe`);
      console.log(`  POST /api/subscription/cancel`);
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
      console.log('');

      // 启动自动续费服务
      startRenewalService();
    });
  } catch (error) {
    console.error('❌ 服务启动失败:', error);
    process.exit(1);
  }
}

start();
