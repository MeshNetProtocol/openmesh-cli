/**
 * Permit 和 Charge 状态存储（基于 JSON 文件）
 * 用于追踪订阅流程中的 permit 和 charge 状态，避免重复操作
 */

const fs = require('fs');
const path = require('path');

const STORE_PATH = path.join(__dirname, 'permits.json');

// 内存缓存
let store = {
  permits: {}, // key: `${identityAddress}_${planId}`, value: permit record
  authorizedAllowances: {} // key: `${userAddress}_${identityAddress}`, value: authorized amount
};

function loadStore() {
  try {
    if (fs.existsSync(STORE_PATH)) {
      const data = fs.readFileSync(STORE_PATH, 'utf8');
      store = JSON.parse(data);
      // 确保 authorizedAllowances 字段存在
      if (!store.authorizedAllowances) {
        store.authorizedAllowances = {};
      }
      console.log('✅ Permit 存储加载成功');
    } else {
      console.log('📝 创建新的 Permit 存储');
      saveStore();
    }
  } catch (error) {
    console.error('❌ 加载 Permit 存储失败:', error);
    store = { permits: {}, authorizedAllowances: {} };
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

function getAllowanceKey(userAddress, identityAddress) {
  return `${userAddress.toLowerCase()}_${identityAddress.toLowerCase()}`;
}

function getAuthorizedAllowance(userAddress, identityAddress) {
  const key = getAllowanceKey(userAddress, identityAddress);
  return store.authorizedAllowances[key] || 0;
}

function addAuthorizedAllowance(userAddress, identityAddress, amount) {
  const key = getAllowanceKey(userAddress, identityAddress);
  const current = store.authorizedAllowances[key] || 0;
  store.authorizedAllowances[key] = current + amount;
  saveStore();
}

function deductAuthorizedAllowance(userAddress, identityAddress, amount) {
  const key = getAllowanceKey(userAddress, identityAddress);
  const current = store.authorizedAllowances[key] || 0;
  store.authorizedAllowances[key] = Math.max(0, current - amount);
  saveStore();
}

function getUserSubscriptions(userAddress) {
  const normalizedUser = userAddress.toLowerCase();
  const subscriptions = [];

  for (const [key, permit] of Object.entries(store.permits)) {
    if (permit.userAddress === normalizedUser && permit.chargeStatus === 'completed') {
      subscriptions.push({
        identityAddress: permit.identityAddress,
        planId: permit.planId,
        permitStatus: permit.permitStatus,
        chargeStatus: permit.chargeStatus,
        chargeAmount: permit.chargeAmount,
        chargeTxHash: permit.chargeTxHash,
        createdAt: permit.createdAt,
        updatedAt: permit.updatedAt,
      });
    }
  }

  return subscriptions;
}

module.exports = {
  loadStore,
  createOrUpdatePermit,
  updatePermitStatus,
  updateChargeStatus,
  getPermitStatus,
  getAuthorizedAllowance,
  addAuthorizedAllowance,
  deductAuthorizedAllowance,
  getUserSubscriptions,
};
