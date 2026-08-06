#!/bin/bash

echo "======================================"
echo "xxMac 菜单栏图标修复测试"
echo "======================================"
echo ""

# 检查 xxMac 是否在运行
if ! pgrep -x xxMac > /dev/null; then
    echo "❌ xxMac 未运行"
    exit 1
fi

echo "✅ xxMac 正在运行 (PID: $(pgrep -x xxMac))"
echo ""

# 获取状态项位置
echo "📍 检查菜单栏状态项位置..."
position=$(osascript -e 'tell application "System Events" to tell process "xxMac" to get position of menu bar item 1 of menu bar 2' 2>&1)

if [[ $position == *"error"* ]] || [[ $position == *"错误"* ]]; then
    echo "❌ 无法获取状态项位置（可能不可见）"
    echo "   错误信息: $position"
    exit 1
fi

# 解析位置
x_pos=$(echo "$position" | cut -d',' -f1 | tr -d ' ')
y_pos=$(echo "$position" | cut -d',' -f2 | tr -d ' ')

echo "   当前位置: ($x_pos, $y_pos)"
echo ""

# 判断位置状态
if [ "$x_pos" -lt 100 ]; then
    echo "⚠️  状态项位置异常！(x < 100)"
    echo "   这表示图标在屏幕最左侧，基本不可见"
    echo ""
    echo "🔧 建议操作："
    echo "   1. 点击设置 > 通用 > 配置 > 状态栏诊断"
    echo "   2. 点击刷新按钮，应用会自动修复"
    echo "   3. 或者重启 xxMac 应用"
    exit 2
elif [ "$x_pos" -gt 100 ] && [ "$x_pos" -lt 1000 ]; then
    echo "✅ 状态项位置正常（在合理范围内）"
elif [ "$x_pos" -ge 1000 ]; then
    echo "✅ 状态项位置正常（在右侧区域）"

    # 检查是否可能与时钟重叠
    if [ "$x_pos" -gt 4900 ]; then
        echo "⚠️  注意：位置非常靠右，可能与系统时钟重叠"
    fi
else
    echo "❓ 无法判断状态项位置状态"
fi

echo ""
echo "======================================"
echo "测试完成"
echo "======================================"
