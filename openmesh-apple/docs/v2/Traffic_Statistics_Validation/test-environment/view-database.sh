#!/bin/bash
# 查看记账服务数据库内容
# 用法: ./view-database.sh

DB_PATH="metering-service/metering.db"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ 数据库文件不存在: $DB_PATH"
    exit 1
fi

echo "📊 记账服务数据库内容"
echo "===================="
echo ""

echo "👥 用户列表:"
echo "----------------------------------------"
sqlite3 "$DB_PATH" <<EOF
.mode column
.headers on
SELECT
    user_id,
    ROUND(total_quota/1024.0/1024.0, 2) as total_mb,
    ROUND(used_upload/1024.0/1024.0, 2) as upload_mb,
    ROUND(used_download/1024.0/1024.0, 2) as download_mb,
    ROUND(remaining/1024.0/1024.0, 2) as remaining_mb,
    price_rate
FROM users;
EOF
echo ""

echo "📈 流量上报记录:"
echo "----------------------------------------"
sqlite3 "$DB_PATH" <<EOF
.mode column
.headers on
SELECT
    id,
    node_id,
    user_id,
    ROUND(upload_bytes/1024.0/1024.0, 2) as upload_mb,
    ROUND(download_bytes/1024.0/1024.0, 2) as download_mb,
    reported_at
FROM traffic_reports
ORDER BY id DESC
LIMIT 10;
EOF
echo ""

echo "📊 统计汇总:"
echo "----------------------------------------"
sqlite3 "$DB_PATH" <<EOF
SELECT
    '总用户数: ' || COUNT(*) as stat
FROM users
UNION ALL
SELECT
    '总上报次数: ' || COUNT(*) as stat
FROM traffic_reports
UNION ALL
SELECT
    '总流量 (MB): ' || ROUND(SUM(upload_bytes + download_bytes)/1024.0/1024.0, 2) as stat
FROM traffic_reports;
EOF
echo ""
