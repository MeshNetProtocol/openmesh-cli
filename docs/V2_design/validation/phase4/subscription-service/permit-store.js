/**
 * Permit 和 Charge 状态存储（基于 JSON 文件）
 * 用于追踪订阅流程中的 permit 和 charge 状态，避免重复操作
 */

const fs = require('fs');
const path = require('path');

const STORE_PATH = path.join(__dirname, 'permits.json');

// 内存缓存
let store = {
  permits: {} // key: `${identityAddress}_${planId}`, value: permit record
};

function loadStore() {
  try {
    if (fs.existsSync(STORE_PATH)) {
      const data = fs.readFileSync(STORE_PATH, 'utf8');
      store = JSON.parse(data);
      console.log('✅ Permit 存储加载成功');
    } else {
      console.log('📝 创建新的 Permit 存储');
      saveStore();
    }
  } catch (error) {
    console.error('❌ 加载 Permit 存储失败:', error);
    store = { permits: {} };
  }
}

function saveStore() {
  try {
    fs.writeFileSync(STORE_PATH, JSON.stringify(store, null, 2), 'utf8');
  } catch (error) {
    console.error('❌ 保存 Permit 存储失败:', error);
  }
}

function getKey(identityAddress, planId) {
  return `${identityAddress.toLowerCase()}_${planId}`;
}

function createOrUpdatePermit(data) {
  const {
    identityAddress,
    userAddress,
    planId,
    expectedAllowance,
    targetAllowance,
    deadline,
  } = data;

  const key = getKey(identityAddress, planId);
  const now = Date.now();

  if (!store.permits[key]) {
    store.permits[key] = {
      identityAddress: identityAddress.toLowerCase(),
      userAddress: userAddress.toLowerCase(),
      planId,
      permitStatus: 'pending',
      permitTxHash: null,
      expectedAllowance,
      targetAllowance,
      deadline,
      chargeStatus: 'pending',
      chargeId: null,
      chargeTxHash: null,
      chargeAmount: null,
      createdAt: now,
      updatedAt: now,
    };
  } else {
    store.permits[key].userAddress = userAddress.toLowerCase();
    store.permits[key].expectedAllowance = expectedAllowance;
    store.permits[key].targetAllowance = targetAllowance;
    store.permits[key].deadline = deadline;
    store.permits[key].updatedAt = now;
  }

  saveStore();
  return store.permits[key];
}

function updatePermitStatus(identityAddress, planId, status, txHash) {
  const key = getKey(identityAddress, planId);
  if (store.permits[key]) {
    store.permits[key].permitStatus = status;
    store.permits[key].permitTxHash = txHash;
    store.permits[key].updatedAt = Date.now();
    saveStore();
  }
}

function updateChargeStatus(identityAddress, planId, status, chargeId, txHash, amount) {
  const key = getKey(identityAddress, planId);
  if (store.permits[key]) {
    store.permits[key].chargeStatus = status;
    store.permits[key].chargeId = chargeId;
    store.permits[key].chargeTxHash = txHash;
    store.permits[key].chargeAmount = amount;
    store.permits[key].updatedAt = Date.now();
    saveStore();
  }
}

function getPermitStatus(identityAddress, planId) {
  const key = getKey(identityAddress, planId);
  return store.permits[key] || null;
}

module.exports = {
  loadStore,
  createOrUpdatePermit,
  updatePermitStatus,
  updateChargeStatus,
  getPermitStatus,
};
