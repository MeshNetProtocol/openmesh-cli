const fs = require('fs');
const path = require('path');

const DB_FILE = path.join(__dirname, 'db.json');

// 初始化或读取数据库
function loadDB() {
  if (fs.existsSync(DB_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
    } catch (e) {
      console.error('Failed to parse db.json, re-initializing...', e);
    }
  }
  
  const initData = {
    trafficBuffer: {},  // identityAddress -> bytesUsed (记录由于量多暂未上报的流量)
    lastResetCheck: {}, // identityAddress -> { daily: timestamp, monthly: timestamp } (上次检测流量重置的时间)
    pendingChanges: {}  // identityAddress -> { nextPlanId, intentSignature } (降级/升级的待生效意向)
  };
  saveDB(initData);
  return initData;
}

// 写入磁盘
function saveDB(data) {
  fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2), 'utf8');
}

// 辅助方法：增量存储流量
function addTrafficUsage(identityAddress, bytesUsed) {
  const db = loadDB();
  if (!db.trafficBuffer[identityAddress]) {
    db.trafficBuffer[identityAddress] = 0;
  }
  db.trafficBuffer[identityAddress] += bytesUsed;
  saveDB(db);
  return db.trafficBuffer[identityAddress];
}

// 辅助方法：清除待上报缓存
function clearTrafficUsage(identityAddress) {
  const db = loadDB();
  delete db.trafficBuffer[identityAddress];
  saveDB(db);
}

// 辅助方法：设置检测追踪
function trackIdentity(identityAddress) {
  const db = loadDB();
  if (!db.lastResetCheck[identityAddress]) {
    db.lastResetCheck[identityAddress] = {
      daily: Math.floor(Date.now() / 1000),
      monthly: Math.floor(Date.now() / 1000)
    };
    saveDB(db);
  }
}

module.exports = {
  loadDB,
  saveDB,
  addTrafficUsage,
  clearTrafficUsage,
  trackIdentity
};
