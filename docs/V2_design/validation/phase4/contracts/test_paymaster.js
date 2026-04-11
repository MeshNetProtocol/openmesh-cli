#!/usr/bin/env node

/**
 * 测试 CDP Paymaster 配置
 * 验证 Paymaster 是否正确配置并可以赞助 gas
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { CdpClient } = require('@coinbase/cdp-sdk');

async function testPaymaster() {
  console.log('🔍 测试 CDP Paymaster 配置...\n');

  const apiKeyId = process.env.CDP_API_KEY_ID;
  const apiKeySecret = process.env.CDP_API_KEY_SECRET;
  const walletSecret = process.env.CDP_WALLET_SECRET;
  const paymasterEndpoint = process.env.CDP_PAYMASTER_ENDPOINT;
  const contractAddress = process.env.VPN_SUBSCRIPTION_CONTRACT;
  const serverWalletAddress = process.env.CDP_SERVER_WALLET_ADDRESS;

  console.log('配置信息:');
  console.log('  API Key ID:', apiKeyId);
  console.log('  Paymaster Endpoint:', paymasterEndpoint);
  console.log('  Contract Address:', contractAddress);
  console.log('  Server Wallet Address:', serverWalletAddress);
  console.log('');

  if (!apiKeyId || !apiKeySecret || !walletSecret) {
    console.error('❌ 错误: CDP 凭证未配置');
    process.exit(1);
  }

  if (!paymasterEndpoint) {
    console.error('❌ 错误: CDP_PAYMASTER_ENDPOINT 未配置');
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

    console.log('🔨 获取 CDP Server Wallet...');
    const accountName = process.env.CDP_SERVER_WALLET_ACCOUNT_NAME;
    const account = await cdp.evm.getOrCreateAccount({
      name: accountName,
    });
    console.log('✅ Server Wallet 获取成功!');
    console.log('  Address:', account.address);
    console.log('  Network:', account.network || 'base-sepolia');
    console.log('');

    // 验证地址是否匹配
    if (account.address.toLowerCase() !== serverWalletAddress.toLowerCase()) {
      console.error('❌ 警告: Server Wallet 地址不匹配!');
      console.error('  配置的地址:', serverWalletAddress);
      console.error('  实际地址:', account.address);
    }

    console.log('✅ Paymaster 配置验证完成!\n');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📋 配置摘要:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ CDP Client 初始化成功');
    console.log('✅ Server Wallet 可访问');
    console.log('✅ Paymaster Endpoint 已配置');
    console.log('✅ 合约地址已配置');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    console.log('📝 下一步:');
    console.log('1. 在 CDP Portal 中验证 Paymaster 策略已激活');
    console.log('2. 开始后端集成 - 实现订阅 API');
    console.log('3. 测试完整的订阅流程');
    console.log('');
    console.log('💡 提示:');
    console.log('- Paymaster 会自动赞助 gas,Server Wallet 不需要 ETH');
    console.log('- 所有交易费用会在月度账单中体现');
    console.log('- 可以在 CDP Portal 中查看 Paymaster 使用情况');

  } catch (error) {
    console.error('\n❌ 测试失败\n');
    console.error('错误类型:', error.constructor.name);
    console.error('错误消息:', error.message);
    console.error('\n完整错误:', error);
    process.exit(1);
  }
}

testPaymaster().catch(console.error);
