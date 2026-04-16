const { CdpClient } = require('@coinbase/cdp-sdk');
const ethers = require('ethers');
require('dotenv').config({ path: '../.env' });

// 配置
const CONTRACT_ADDRESS = '0xe96b8843e8F3dCce5156c1AA34233cfe49a5ff83';
const IDENTITY_ADDRESS = process.argv[2]; // 从命令行参数获取

// 合约 ABI（只需要 finalizeExpired 函数）
const CONTRACT_ABI = [
  {
    type: 'function',
    name: 'finalizeExpired',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'identityAddress', type: 'address' },
      { name: 'forceClosed', type: 'bool' }
    ],
    outputs: []
  }
];

async function cleanupExpiredSubscription() {
  if (!IDENTITY_ADDRESS) {
    console.error('❌ 请提供 VPN 身份地址作为参数');
    console.log('用法: node cleanup-expired.js <identity-address>');
    process.exit(1);
  }

  if (!ethers.isAddress(IDENTITY_ADDRESS)) {
    console.error('❌ 无效的地址格式');
    process.exit(1);
  }

  console.log(`🧹 清理过期订阅: ${IDENTITY_ADDRESS}`);
  console.log('');

  try {
    // 1. 初始化 CDP Client（使用与index.js相同的方式）
    const cdpClient = new CdpClient({
      apiKeyId: process.env.CDP_API_KEY_ID,
      apiKeySecret: process.env.CDP_API_KEY_SECRET,
      walletSecret: process.env.CDP_WALLET_SECRET,
    });

    console.log('✅ CDP Client 初始化成功');

    // 2. 获取 Owner Account
    const ownerAccount = await cdpClient.evm.getOrCreateAccount({
      name: 'openmesh-vpn-owner',
    });
    console.log('✅ Owner Account:', ownerAccount.address);

    // 3. 获取 Smart Account
    const serverWalletAccount = await cdpClient.evm.getOrCreateSmartAccount({
      name: 'openmesh-vpn-smart',
      owner: ownerAccount,
    });
    console.log('✅ Smart Account:', serverWalletAccount.address);
    console.log('');

    // 4. 编码交易数据
    const iface = new ethers.Interface(CONTRACT_ABI);
    const calldata = iface.encodeFunctionData('finalizeExpired', [
      IDENTITY_ADDRESS,
      true  // forceClosed = true
    ]);

    console.log('📤 发送清理交易...');

    // 5. 发送交易
    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: serverWalletAccount,
      network: 'base-sepolia',
      calls: [{
        to: CONTRACT_ADDRESS,
        data: calldata,
        value: BigInt(0)
      }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL
    });

    console.log('✅ UserOperation 已发送:', userOp.userOpHash);
    console.log('⏳ 等待确认...');

    // 6. 等待确认
    const receipt = await cdpClient.evm.waitForUserOperation({
      smartAccountAddress: serverWalletAccount.address,
      userOpHash: userOp.userOpHash
    });

    if (receipt.status !== 'complete') {
      throw new Error(`UserOperation failed: ${receipt.status}`);
    }

    console.log('');
    console.log('✅ 清理成功!');
    console.log(`   Transaction Hash: ${receipt.transactionHash}`);
    console.log('');
    console.log('🎉 现在可以使用该 VPN 身份重新订阅了!');

  } catch (error) {
    console.error('❌ 清理失败:', error.message);
    console.error(error);
    process.exit(1);
  }
}

cleanupExpiredSubscription();
