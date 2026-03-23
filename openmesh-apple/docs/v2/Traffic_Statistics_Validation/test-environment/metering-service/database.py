import sqlite3
from datetime import datetime
from contextlib import contextmanager

DATABASE_PATH = 'metering.db'

def init_db():
    """初始化数据库表"""
    conn = sqlite3.connect(DATABASE_PATH)
    cursor = conn.cursor()

    # 创建用户流量表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            user_id TEXT PRIMARY KEY,
            provider_id TEXT NOT NULL DEFAULT 'provider_a',
            total_quota INTEGER NOT NULL,
            used_upload INTEGER DEFAULT 0,
            used_download INTEGER DEFAULT 0,
            remaining INTEGER NOT NULL,
            price_rate REAL NOT NULL DEFAULT 100.0,
            purchased_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL
        )
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_user_provider ON users(user_id, provider_id)
    ''')

    # 创建流量上报记录表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS traffic_reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            node_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            upload_bytes INTEGER NOT NULL,
            download_bytes INTEGER NOT NULL,
            reported_at TIMESTAMP NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(user_id)
        )
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_reports_user ON traffic_reports(user_id)
    ''')

    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_reports_node ON traffic_reports(node_id)
    ''')

    conn.commit()
    conn.close()
    print("Database initialized successfully")

@contextmanager
def get_db():
    """获取数据库连接的上下文管理器"""
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()

def get_user(user_id):
    """查询用户"""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM users WHERE user_id = ?', (user_id,))
        return cursor.fetchone()

def create_user(user_id, usdc_amount, price_rate=100.0, provider_id='provider_a'):
    """创建用户"""
    # 计算流量配额：1 USDC = price_rate MB
    quota_mb = usdc_amount * price_rate
    quota_bytes = int(quota_mb * 1024 * 1024)

    now = datetime.now().isoformat()

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO users (user_id, provider_id, total_quota, remaining, price_rate, purchased_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (user_id, provider_id, quota_bytes, quota_bytes, price_rate, now, now))

    return get_user(user_id)

def update_user_traffic(user_id, upload_bytes, download_bytes):
    """更新用户流量使用"""
    total_bytes = upload_bytes + download_bytes
    now = datetime.now().isoformat()

    with get_db() as conn:
        cursor = conn.cursor()

        # 检查用户是否存在
        cursor.execute('SELECT remaining FROM users WHERE user_id = ?', (user_id,))
        row = cursor.fetchone()
        if not row:
            return None, "User not found"

        remaining = row['remaining']

        # 检查流量是否充足
        if remaining < total_bytes:
            return None, "Insufficient quota"

        # 更新流量
        cursor.execute('''
            UPDATE users
            SET used_upload = used_upload + ?,
                used_download = used_download + ?,
                remaining = remaining - ?,
                updated_at = ?
            WHERE user_id = ?
        ''', (upload_bytes, download_bytes, total_bytes, now, user_id))

        return get_user(user_id), None

def recharge_user(user_id, amount_mb):
    """充值用户流量"""
    amount_bytes = int(amount_mb * 1024 * 1024)
    now = datetime.now().isoformat()

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute('''
            UPDATE users
            SET total_quota = total_quota + ?,
                remaining = remaining + ?,
                updated_at = ?
            WHERE user_id = ?
        ''', (amount_bytes, amount_bytes, now, user_id))

        if cursor.rowcount == 0:
            return None

    return get_user(user_id)

def delete_user(user_id):
    """删除用户"""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute('DELETE FROM users WHERE user_id = ?', (user_id,))
        return cursor.rowcount > 0

def record_traffic_report(node_id, user_id, upload_bytes, download_bytes):
    """记录流量上报"""
    now = datetime.now().isoformat()

    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO traffic_reports (node_id, user_id, upload_bytes, download_bytes, reported_at)
            VALUES (?, ?, ?, ?, ?)
        ''', (node_id, user_id, upload_bytes, download_bytes, now))

def get_all_users():
    """获取所有用户"""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM users')
        return cursor.fetchall()

def get_node_stats():
    """获取节点统计"""
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT
                node_id,
                COUNT(*) as total_reports,
                SUM(upload_bytes) as total_upload,
                SUM(download_bytes) as total_download
            FROM traffic_reports
            GROUP BY node_id
        ''')
        return cursor.fetchall()
