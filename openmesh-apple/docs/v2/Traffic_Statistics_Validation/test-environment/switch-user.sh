#!/bin/bash
# 切换客户端使用的用户
# 用法: ./switch-user.sh [alice|bob|charlie]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/client"

USER=${1:-alice}

case $USER in
    alice)
        PASSWORD="ytRNEVFnBipME+xfzfznWw==:7TLKGXbFjuAYJsPTwNF/8A=="
        ;;
    bob)
        PASSWORD="ytRNEVFnBipME+xfzfznWw==:INFHA0S+FeS7DctzqnlP8w=="
        ;;
    charlie)
        PASSWORD="ytRNEVFnBipME+xfzfznWw==:NasrqPMv9lR5YiSXvcpl0A=="
        ;;
    *)
        echo "❌ 未知用户: $USER"
        echo "用法: ./switch-user.sh [alice|bob|charlie]"
        exit 1
        ;;
esac

echo "🔄 切换客户端用户到: $USER"

# 备份原配置
cp config.json config.json.bak

# 更新密码
sed -i.tmp "s|\"password\": \"[^\"]*\"|\"password\": \"$PASSWORD\"|" config.json
rm config.json.tmp

echo "✅ 已切换到用户: $USER"
echo ""
echo "现在可以启动客户端:"
echo "  ./start-client.sh"
