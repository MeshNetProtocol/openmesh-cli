const { ethers } = require('ethers');
require('dotenv').config({ path: '.env' });

const VAULT_CONTRACT = "0x92879A3a144b7894332ee2648E3BcB0616De6040";
const USDC_CONTRACT = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
const RPC_URL = "https://sepolia.base.org";
const IDENTITY_ADDRESS = "0x1234567890123456789012345678901234567890";

async function testSubscription() {
  console.log("==========================================");
  console.log("测试智能合约订阅和取消订阅");
  console.log("==========================================\n");

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(process.env.OWNER_PRIVATE_KEY, provider);
  
  console.log("用户地址:", wallet.address);
  console.log("Identity:", IDENTITY_ADDRESS);
  console.log("");

  // 1. 查询当前 USDC allowance
  console.log("1. 查询当前 USDC allowance...");
  const usdcContract = new ethers.Contract(USDC_CONTRACT, [
    "function allowance(address,address) view returns (uint256)",
    "function nonces(address) view returns (uint256)"
  ], provider);
  
  const currentAllowance = await usdcContract.allowance(wallet.address, VAULT_CONTRACT);
  console.log("   当前 allowance:", currentAllowance.toString());

  // 2. 查询 Vault authorizedAllowance
  console.log("2. 查询 Vault authorizedAllowance...");
  const vaultContract = new ethers.Contract(VAULT_CONTRACT, [
    "function authorizedAllowance(address,address) view returns (uint256)"
  ], provider);
  
  const vaultAllowance = await vaultContract.authorizedAllowance(wallet.address, IDENTITY_ADDRESS);
  console.log("   Vault authorizedAllowance:", vaultAllowance.toString());

  // 3. 计算 targetAllowance (增加 1 USDC)
  const targetAllowance = currentAllowance + 1000000n;
  console.log("3. 计算 targetAllowance:", targetAllowance.toString(), "(增加 1 USDC)");

  // 4. 查询 USDC nonce
  console.log("4. 查询 USDC nonce...");
  const nonce = await usdcContract.nonces(wallet.address);
  console.log("   USDC nonce:", nonce.toString());

  // 5. 计算 deadline
  const deadline = Math.floor(Date.now() / 1000) + 86400;
  console.log("5. Deadline:", deadline);

  // 6. 生成 permit 签名
  console.log("6. 生成 permit 签名...");
  const domain = {
    name: 'USDC',
    version: '2',
    chainId: 84532,
    verifyingContract: USDC_CONTRACT
  };

  const types = {
    Permit: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' }
    ]
  };

  const value = {
    owner: wallet.address,
    spender: VAULT_CONTRACT,
    value: targetAllowance,
    nonce: nonce,
    deadline: deadline
  };

  const signature = await wallet.signTypedData(domain, types, value);
  const sig = ethers.Signature.from(signature);
  
  console.log("   signature:", signature);
  console.log("   v:", sig.v);
  console.log("   r:", sig.r);
  console.log("   s:", sig.s);
  console.log("");

  console.log("==========================================");
  console.log("订阅测试准备完成！");
  console.log("==========================================");
  console.log("");
  console.log("签名参数:");
  console.log("  user:", wallet.address);
  console.log("  identityAddress:", IDENTITY_ADDRESS);
  console.log("  expectedAllowance:", currentAllowance.toString());
  console.log("  targetAllowance:", targetAllowance.toString());
  console.log("  deadline:", deadline);
  console.log("  v:", sig.v);
  console.log("  r:", sig.r);
  console.log("  s:", sig.s);
  console.log("");
  console.log("这些参数可以用于调用 authorizeChargeWithPermit");
  console.log("（需要使用 relayer 私钥调用，因为有 onlyRelayer 修饰符）");
}

testSubscription().catch(console.error);
