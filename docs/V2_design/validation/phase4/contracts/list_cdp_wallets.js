#!/usr/bin/env node

/**
 * 列出现有的 CDP Server Wallets
 */

const { Coinbase, Wallet } = require('@coinbase/coinbase-sdk');

async function listWallets() {
  console.log('🔍 查询现有的 CDP Server Wallets...\n');

  const apiKeyId = process.env.CDP_API_KEY_ID;
  const apiKeySecret = process.env.CDP_API_KEY_SECRET;

  if (!apiKeyId || !apiKeySecret) {
    console.error('❌ 错误: 请设置环境变量 CDP_API_KEY_ID 和 CDP_API_KEY_SECRET');
    process.exit(1);
  }

  try {
    // 初始化 Coinbase SDK
    Coinbase.configure({
      apiKeyName: apiKeyId,
      privateKey: apiKeySecret,
    });

    // 列出所有钱包
    console.log('📋 正在获取钱包列表...\n');
    const wallets = await Wallet.listWallets();

    if (!wallets || wallets.length === 0) {
      console.log('❌ 没有找到任何钱包');
      console.log('\n提示: 你可能需要等待速率限制重置后再创建新钱包');
      console.log('或者联系 CDP 支持增加配额');
      return;
    }

    console.log(`✅ 找到 ${wallets.length} 个钱包:\n`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    for (const wallet of wallets) {
      const address = await wallet.getDefaultAddress();
      console.log(`\n📦 Wallet ID: ${wallet.getId()}`);
      console.log(`   Network: ${wallet.getNetworkId()}`);
      console.log(`   Address: ${address.getId()}`);
    }

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('\n💡 使用建议:');
    console.log('1. 如果有 base-sepolia 网络的钱包,可以直接使用其地址');
    console.log('2. 将地址配置到 .env 文件:');
    console.log('   RELAYER_ADDRESS=<上面的地址>');

  } catch (error) {
    console.error('\n❌ 查询失败:', error.message);
    if (error.httpCode === 429) {
      console.error('\n⚠️  速率限制: 请稍后再试');
    }
  }
}

listWallets().catch(console.error);
