#!/usr/bin/env node

/**
 * 测试 CDP API 配置是否正确
 */

const { Coinbase } = require('@coinbase/coinbase-sdk');

async function testCDPConfig() {
  console.log('🔍 测试 CDP API 配置...\n');

  const apiKeyId = process.env.CDP_API_KEY_ID;
  const apiKeySecret = process.env.CDP_API_KEY_SECRET;

  console.log('配置信息:');
  console.log('  API Key ID:', apiKeyId);
  console.log('  API Key Secret:', apiKeySecret ? '已设置 (' + apiKeySecret.length + ' 字符)' : '未设置');
  console.log('');

  if (!apiKeyId || !apiKeySecret) {
    console.error('❌ 错误: CDP API 凭证未设置');
    process.exit(1);
  }

  try {
    console.log('📡 初始化 Coinbase SDK...');

    // 尝试配置 SDK
    Coinbase.configure({
      apiKeyName: apiKeyId,
      privateKey: apiKeySecret,
    });

    console.log('✅ SDK 初始化成功!');
    console.log('');
    console.log('💡 提示:');
    console.log('如果 API Key ID 格式不正确,应该是:');
    console.log('  organizations/{org_id}/apiKeys/{key_id}');
    console.log('');
    console.log('当前格式:', apiKeyId);
    console.log('');

    if (!apiKeyId.startsWith('organizations/')) {
      console.log('⚠️  警告: API Key ID 格式可能不正确');
      console.log('请检查 CDP Portal 中的完整 API Key Name');
    }

  } catch (error) {
    console.error('❌ 配置失败:', error.message);
    console.error('');
    console.error('错误详情:', error);
  }
}

testCDPConfig().catch(console.error);
