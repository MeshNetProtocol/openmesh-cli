#!/usr/bin/env node

/**
 * 创建 CDP Server Wallet (使用 CdpClient)
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { CdpClient } = require('@coinbase/cdp-sdk');

async function createCDPWallet() {
  console.log('🔐 创建 CDP Server Wallet...\n');

  const apiKeyId = process.env.CDP_API_KEY_ID;
  const apiKeySecret = process.env.CDP_API_KEY_SECRET;
  const walletSecret = process.env.CDP_WALLET_SECRET;

  console.log('配置信息:');
  console.log('  API Key ID:', apiKeyId);
  console.log('  API Key Secret:', apiKeySecret ? '已设置' : '未设置');
  console.log('  Wallet Secret:', walletSecret ? '已设置' : '未设置');
  console.log('');

  if (!apiKeyId || !apiKeySecret) {
    console.error('❌ 错误: CDP API 凭证未设置');
    console.error('请在 .env 文件中设置 CDP_API_KEY_ID 和 CDP_API_KEY_SECRET');
    process.exit(1);
  }

  if (!walletSecret) {
    console.error('❌ 错误: CDP_WALLET_SECRET 未设置');
    console.error('请在 .env 文件中设置 CDP_WALLET_SECRET');
    process.exit(1);
  }

  try {
    console.log('📡 初始化 CDP Client...');
    const cdp = new CdpClient({
      apiKeyId: apiKeyId,
      apiKeySecret: apiKeySecret,
      walletSecret: walletSecret,
    });
    console.log('✅ CDP Client 初始化成功!\n');

    console.log('🔨 创建新的 Server Account...');
    const accountName = `openmesh-vpn-${Date.now()}`;
    console.log('  Account Name:', accountName);

    const account = await cdp.evm.getOrCreateAccount({
      name: accountName,
    });

    console.log('✅ Server Account 创建成功!');
    console.log('');
    console.log('Account 信息:');
    console.log('  Account Name:', accountName);
    console.log('  Address:', account.address);
    console.log('  Network:', account.network || 'base-sepolia');
    console.log('');

    console.log('✅ 完成!');
    console.log('');
    console.log('💡 提示:');
    console.log('1. 请将 Account Name 保存到安全的地方');
    console.log('2. 可以使用 list_cdp_wallets.js 查看所有 accounts');
    console.log('3. Address:', account.address);

  } catch (error) {
    console.error('❌ 创建失败:', error.message);
    console.error('');
    console.error('错误详情:', error);

    if (error.message.includes('429')) {
      console.error('');
      console.error('💡 提示: 遇到速率限制错误');
      console.error('这可能是因为:');
      console.error('1. API Key 权限不足');
      console.error('2. 账户需要完成某些配置');
      console.error('3. 需要添加支付方式');
      console.error('');
      console.error('请检查 CDP Portal: https://portal.cdp.coinbase.com/');
    }

    process.exit(1);
  }
}

createCDPWallet().catch(console.error);
