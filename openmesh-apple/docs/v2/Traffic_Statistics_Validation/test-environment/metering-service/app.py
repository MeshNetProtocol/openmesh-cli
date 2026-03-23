from flask import Flask, jsonify, request
from database import init_db, get_user, create_user, update_user_traffic, recharge_user, delete_user, record_traffic_report, get_all_users, get_node_stats
import logging

app = Flask(__name__)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 初始化数据库
init_db()

# ==================== 用户管理 API ====================

@app.route('/api/v1/users', methods=['POST'])
def add_user():
    """添加用户（预付费购买流量）"""
    data = request.get_json()

    user_id = data.get('user_id')
    usdc_amount = data.get('usdc_amount')
    price_rate = data.get('price_rate', 100.0)

    if not user_id or not usdc_amount:
        return jsonify({"error": "user_id and usdc_amount are required"}), 400

    try:
        # 检查用户是否已存在
        existing_user = get_user(user_id)
        if existing_user:
            return jsonify({"error": "User already exists"}), 409

        user = create_user(user_id, usdc_amount, price_rate)

        return jsonify({
            "user_id": user['user_id'],
            "total_quota": user['total_quota'],
            "remaining": user['remaining'],
            "price_rate": user['price_rate'],
            "purchased_at": user['purchased_at']
        }), 201
    except Exception as e:
        logger.error(f"Error creating user: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/v1/users/<user_id>', methods=['GET'])
def get_user_info(user_id):
    """查询用户流量"""
    user = get_user(user_id)

    if not user:
        return jsonify({"error": "User not found"}), 404

    return jsonify({
        "user_id": user['user_id'],
        "provider_id": user['provider_id'],
        "total_quota": user['total_quota'],
        "used_upload": user['used_upload'],
        "used_download": user['used_download'],
        "remaining": user['remaining'],
        "price_rate": user['price_rate'],
        "purchased_at": user['purchased_at'],
        "updated_at": user['updated_at']
    })

@app.route('/api/v1/users/<user_id>', methods=['DELETE'])
def remove_user(user_id):
    """删除用户"""
    success = delete_user(user_id)

    if not success:
        return jsonify({"error": "User not found"}), 404

    return '', 204

@app.route('/api/v1/users/<user_id>/recharge', methods=['POST'])
def recharge_user_quota(user_id):
    """充值流量"""
    data = request.get_json()
    amount_mb = data.get('amount_mb')

    if not amount_mb:
        return jsonify({"error": "amount_mb is required"}), 400

    try:
        user = recharge_user(user_id, amount_mb)

        if not user:
            return jsonify({"error": "User not found"}), 404

        return jsonify({
            "user_id": user['user_id'],
            "recharged": int(amount_mb * 1024 * 1024),
            "total_quota": user['total_quota'],
            "remaining": user['remaining']
        })
    except Exception as e:
        logger.error(f"Error recharging user: {e}")
        return jsonify({"error": str(e)}), 500

# ==================== 流量上报 API ====================

@app.route('/api/v1/metering/report', methods=['POST'])
def report_traffic():
    """上报流量统计"""
    data = request.get_json()

    node_id = data.get('node_id')
    user_id = data.get('user_id')
    upload_bytes = data.get('upload_bytes', 0)
    download_bytes = data.get('download_bytes', 0)

    if not node_id or not user_id:
        return jsonify({"error": "node_id and user_id are required"}), 400

    try:
        # 更新用户流量
        user, error = update_user_traffic(user_id, upload_bytes, download_bytes)

        if error:
            if error == "User not found":
                return jsonify({"error": error}), 404
            elif error == "Insufficient quota":
                # 流量不足
                existing_user = get_user(user_id)
                return jsonify({
                    "status": "insufficient",
                    "user_id": user_id,
                    "remaining": existing_user['remaining'] if existing_user else 0,
                    "action": "block"
                }), 403

        # 记录上报历史
        record_traffic_report(node_id, user_id, upload_bytes, download_bytes)

        return jsonify({
            "status": "ok",
            "user_id": user_id,
            "remaining": user['remaining'],
            "action": "continue" if user['remaining'] > 0 else "block"
        })
    except Exception as e:
        logger.error(f"Error reporting traffic: {e}")
        return jsonify({"error": str(e)}), 500

# ==================== 统计查询 API ====================

@app.route('/api/v1/stats/users', methods=['GET'])
def get_users_stats():
    """查询所有用户统计"""
    try:
        users = get_all_users()

        user_list = []
        for user in users:
            used = user['used_upload'] + user['used_download']
            usage_percent = (used / user['total_quota'] * 100) if user['total_quota'] > 0 else 0

            user_list.append({
                "user_id": user['user_id'],
                "total_quota": user['total_quota'],
                "used": used,
                "remaining": user['remaining'],
                "usage_percent": round(usage_percent, 2)
            })

        return jsonify({
            "total_users": len(user_list),
            "users": user_list
        })
    except Exception as e:
        logger.error(f"Error getting user stats: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/v1/stats/nodes', methods=['GET'])
def get_nodes_stats():
    """查询节点上报统计"""
    try:
        nodes = get_node_stats()

        node_list = []
        for node in nodes:
            node_list.append({
                "node_id": node['node_id'],
                "total_reports": node['total_reports'],
                "total_upload": node['total_upload'],
                "total_download": node['total_download']
            })

        return jsonify({
            "nodes": node_list
        })
    except Exception as e:
        logger.error(f"Error getting node stats: {e}")
        return jsonify({"error": str(e)}), 500

# ==================== 健康检查 ====================

@app.route('/health', methods=['GET'])
def health_check():
    """健康检查"""
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9000, debug=False)
