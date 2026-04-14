#!/usr/bin/env node

const path = require('path');
const envPath = path.join(__dirname, '../.env');
require('dotenv').config({ path: envPath, override: true });

const { ethers } = require('ethers');

const CONTRACT_ADDRESS = process.env.VPN_SUBSCRIPTION_CONTRACT;
const RPC_URL = 'https://sepolia.base.org';
const IDENTITY_ADDRESS = '0x729e71ff357ccefAa31635931621531082A698f6';

const CONTRACT_ABI = [
  'function cancelSubscription(address identityAddress) external'
];

async function cancelSubscription() {
  console.log('🚀 取消订阅...\n');

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const privateKey = process.env.OWNER_PRIVATE_KEY;
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log('📝 钱包地址:', wallet.address);
  console.log('📝 VPN 身份:', IDENTITY_ADDRESS);
  console.log('📝 合约地址:', CONTRACT_ADDRESS);

  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, wallet);

  console.log('\n⏳ 发送取消交易...');
  const tx = await contract.cancelSubscription(IDENTITY_ADDRESS);
  console.log('📝 交易哈希:', tx.hash);
  console.log('⏳ 等待确认...');

  const receipt = await tx.wait();
  console.log('✅ 交易已确认! Gas 使用:', receipt.gasUsed.toString());
  console.log('\n✅ 订阅已取消（自动续费已关闭）');
}

cancelSubscription().catch(console.error);
