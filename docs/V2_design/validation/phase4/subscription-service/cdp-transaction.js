/**
 * CDP 交易发送模块
 *
 * 使用 CDP SDK 的 sendTransaction 方法
 * Paymaster 会根据 Policy 自动赞助 gas (0 ETH)
 */

/**
 * 通过 CDP Server Wallet 发送交易
 *
 * @param {Object} params
 * @param {Object} params.cdpClient - CDP Client 实例
 * @param {Object} params.account - CDP EvmServerAccount 实例
 * @param {string} params.contractAddress - 目标合约地址
 * @param {string} params.calldata - 编码后的合约调用数据
 * @param {string} params.network - 网络 (base-sepolia)
 * @returns {Promise<Object>} 交易结果 { transactionHash }
 */
async function sendTransactionViaCDP({
  cdpClient,
  account,
  contractAddress,
  calldata,
  network = 'base-sepolia',
}) {
  console.log('📤 通过 CDP Server Wallet 发送交易...');
  console.log('  From (Server Wallet):', account.address);
  console.log('  To (Contract):', contractAddress);
  console.log('  Network:', network);

  try {
    // 使用 CDP SDK 的 sendUserOperation 方法
    // CDP 会自动处理:
    // - 签名 (使用托管的私钥)
    // - Nonce 管理
    // - Gas 估算
    // - Paymaster 赞助 (根据 Policy 配置)

    const userOp = await cdpClient.evm.sendUserOperation({
      smartAccount: account,
      network,
      calls: [{
        to: contractAddress,
        data: calldata,
        value: BigInt(0),
      }],
      paymasterUrl: process.env.CDP_PAYMASTER_URL,
    });

    console.log('✅ UserOperation 已发送:', userOp.userOpHash);
    console.log('⏳ 等待 UserOperation 确认...');

    const receipt = await cdpClient.evm.waitForUserOperation({
      smartAccountAddress: account.address,
      userOpHash: userOp.userOpHash,
    });

    if (receipt.status !== 'complete') {
      throw new Error(`UserOperation failed: ${receipt.status}`);
    }

    console.log('✅ 交易已确认!');
    console.log('  Transaction Hash:', receipt.transactionHash);

    return {
      transactionHash: receipt.transactionHash,
      status: receipt.status,
    };

  } catch (error) {
    console.error('❌ 发送交易失败:', error.message);
    console.error('  错误详情:', error);
    throw error;
  }
}

module.exports = {
  sendTransactionViaCDP,
};
