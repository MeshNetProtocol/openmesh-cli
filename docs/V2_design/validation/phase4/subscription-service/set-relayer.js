#!/usr/bin/env node

/**
 * 设置合约的 Relayer 地址
 */

const path = require('path');
const envPath = path.join(__dirname, '../.env');
require('dotenv').config({ path: envPath, override: true });

const { ethers } = require('ethers');

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const RPC_URL = 'https://sepolia.base.org';
const NEW_RELAYER_ADDRESS = '0x10AB796695843043CF303Cc8C7a58E9498023768'; // CDP Server Wallet 地址

// 合约 ABI
const CONTRACT_ABI = [
  'function setRelayer(address newRelayer) external',
  'function relayer() external view returns (address)'
];

async function setRelayer() {
  console.log('🚀 开始设置 Relayer 地址...\n');

  // 连接到 Base Sepolia
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  // 使用 owner 私钥创建钱包
  const privateKey = process.env.OWNER_PRIVATE_KEY;
  if (!privateKey) {
    console.error('❌ 错误: 未找到 OWNER_PRIVATE_KEY 环境变量');
    process.exit(1);
  }

  const wallet = new ethers.Wallet(privateKey, provider);
  console.log('📝 使用钱包地址:', wallet.address);

  // 连接合约
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, wallet);
  console.log('📝 合约地址:', CONTRACT_ADDRESS);

  // 检查当前 relayer
  console.log('\n🔍 检查当前 Relayer...');
  const currentRelayer = await contract.relayer();
  console.log('当前 Relayer:', currentRelayer);
  console.log('新 Relayer:', NEW_RELAYER_ADDRESS);

  if (currentRelayer.toLowerCase() === NEW_RELAYER_ADDRESS.toLowerCase()) {
    console.log('✅ Relayer 地址已经正确,无需更新');
    return;
  }

  console.log('\n⏳ 发送交易更新 Relayer...');

  try {
    const tx = await contract.setRelayer(NEW_RELAYER_ADDRESS);
    console.log('📝 交易哈希:', tx.hash);
    console.log('⏳ 等待确认...');

    const receipt = await tx.wait();
    console.log('✅ 交易已确认! Gas 使用:', receipt.gasUsed.toString());

    // 验证更新
    console.log('\n🔍 验证更新...');
    const newRelayer = await contract.relayer();
    console.log('✅ Relayer 已更新为:', newRelayer);

    console.log('\n✅ 完成! 现在可以正常订阅了。');

  } catch (error) {
    console.error('❌ 错误:', error.message);
    if (error.reason) {
      console.error('原因:', error.reason);
    }
    process.exit(1);
  }
}

setRelayer();
