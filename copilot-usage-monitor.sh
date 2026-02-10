#!/bin/bash

# Copilot Premium Request 使用监控
# 功能: 
#   1. 查近n天各个模型用量明细
#   2. 监控指定模型的消耗情况
#   3. 支持watch模式 (每30秒刷新)
# 用法:
#   ./copilot-usage-monitor.sh [-d days] [-m model] [-w/--watch]
#   ./copilot-usage-monitor.sh -d 7 -m "Claude Sonnet 4.5" -w

USERNAME=$(gh api /user --jq '.login' 2>/dev/null)
DAYS=0
MODEL=""
WATCH_MODE=false
INTERVAL=30
PLAN_QUOTA=1500  # Pro+ plan default; change to 300 (Pro) or 50 (Free) as needed
LOG_FILE="/Users/rico/research/logs/copilot-usage-monitor.log"
COLORS_CYAN="\033[1;36m"
COLORS_GREEN="\033[1;32m"
COLORS_YELLOW="\033[1;33m"
COLORS_RED="\033[1;31m"
COLORS_MAGENTA="\033[1;35m"
RESET="\033[0m"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 解析命令行参数
usage() {
  cat << EOF
用法: $0 [选项]

选项:
  -d, --days N       查询近N天的用量 (默认: 0, 仅显示本月汇总)
  -m, --model NAME   指定监控的模型 (默认: 查所有模型)
  -q, --quota N      计划配额 (默认: 1500, Pro+)
  -w, --watch        启用监控模式，每30秒刷新一次
  -h, --help         显示帮助信息

示例:
  # 查近7天所有模型用量
  $0 -d 7

  # 监控 Sonnet 4.5 最近3天的用量，每30秒刷新
  $0 -m "Claude Sonnet 4.5" -w

  # 查近14天的 GPT-5.2 用量
  $0 -d 14 -m "GPT-5.2"
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--days)
      DAYS="$2"
      shift 2
      ;;
    -m|--model)
      MODEL="$2"
      shift 2
      ;;
    -q|--quota)
      PLAN_QUOTA="$2"
      shift 2
      ;;
    -w|--watch)
      WATCH_MODE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "未知选项: $1"
      usage
      ;;
  esac
done

# 验证GitHub CLI
if ! command -v gh &> /dev/null; then
  echo "❌ 错误: 未找到 gh CLI，请先安装 GitHub CLI"
  exit 1
fi

if [ -z "$USERNAME" ]; then
  echo "❌ 错误: 无法获取GitHub用户名，请检查gh认证"
  exit 1
fi

log_message() {
  echo -e "$1" >> "$LOG_FILE"
}

display_header() {
  local days_info=""
  if [ "$DAYS" -gt 0 ]; then
    days_info=" | 查询天数: ${DAYS}天"
  fi
  local msg="========================================\n📊 Copilot Premium Request 用量监控\n用户: $USERNAME | 配额: ${PLAN_QUOTA}${days_info}"
  if [ -n "$MODEL" ]; then
    msg="$msg | 监控模型: $MODEL"
  fi
  msg="$msg\n========================================"
  
  echo -e "${COLORS_CYAN}${msg}${RESET}"
  log_message "${msg}"
  echo "" | tee -a "$LOG_FILE" > /dev/null
}

fetch_cycle_summary() {
  echo -e "${COLORS_MAGENTA}━━━━━━━━━ 当前计费周期 (本月) ━━━━━━━━━${RESET}" | tee -a "$LOG_FILE"

  local cycle_response
  cycle_response=$(gh api "/users/$USERNAME/settings/billing/premium_request/usage" \
    -H "X-GitHub-Api-Version: 2022-11-28" 2>/dev/null)

  if [ -z "$cycle_response" ]; then
    echo "  ⚠️  无法获取本月用量数据" | tee -a "$LOG_FILE"
    echo -e "${COLORS_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE" > /dev/null
    return
  fi

  local period
  period=$(echo "$cycle_response" | jq -r '"周期: \(.timePeriod.year)-\(.timePeriod.month)"' 2>/dev/null)
  echo "  📆 $period" | tee -a "$LOG_FILE"

  local cycle_total
  cycle_total=$(echo "$cycle_response" | jq '[.usageItems[].grossQuantity // 0] | add // 0 | . * 100 | round / 100' 2>/dev/null)
  local cycle_amount
  cycle_amount=$(echo "$cycle_response" | jq '[.usageItems[].grossAmount // 0] | add // 0 | . * 100 | round / 100' 2>/dev/null)
  local net_amount
  net_amount=$(echo "$cycle_response" | jq '[.usageItems[].netAmount // 0] | add // 0 | . * 100 | round / 100' 2>/dev/null)

  local remaining
  remaining=$(echo "$PLAN_QUOTA - $cycle_total" | bc 2>/dev/null)
  local pct_used
  pct_used=$(echo "scale=1; $cycle_total * 100 / $PLAN_QUOTA" | bc 2>/dev/null)

  # 进度条 (20格)
  local bar_len=20
  local filled=$(echo "$cycle_total * $bar_len / $PLAN_QUOTA" | bc 2>/dev/null)
  [ "$filled" -gt "$bar_len" ] 2>/dev/null && filled=$bar_len
  local empty=$((bar_len - filled))
  local bar=$(printf '█%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null)
  bar="${bar}$(printf '░%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null)"

  # 颜色: <60% 绿, 60-85% 黄, >85% 红
  local bar_color="$COLORS_GREEN"
  local pct_int=${pct_used%.*}
  [ "$pct_int" -ge 60 ] 2>/dev/null && bar_color="$COLORS_YELLOW"
  [ "$pct_int" -ge 85 ] 2>/dev/null && bar_color="$COLORS_RED"

  echo -e "  ${bar_color}[${bar}] ${pct_used}%${RESET}" | tee -a "$LOG_FILE"
  echo -e "  已用: ${cycle_total}/${PLAN_QUOTA} | 剩余: ${remaining} | 💰 \$${cycle_amount}" | tee -a "$LOG_FILE"

  if [ "$(echo "$net_amount > 0" | bc 2>/dev/null)" = "1" ]; then
    echo -e "  ${COLORS_RED}⚠️  超额费用: \$${net_amount}${RESET}" | tee -a "$LOG_FILE"
  fi

  # 本月各模型明细
  local model_count
  model_count=$(echo "$cycle_response" | jq '.usageItems | length' 2>/dev/null)
  if [ "$model_count" -gt 0 ]; then
    echo "" | tee -a "$LOG_FILE" > /dev/null
    echo "  模型明细:" | tee -a "$LOG_FILE"
    echo "$cycle_response" | jq -r '.usageItems | sort_by(-.grossQuantity)[] | "  \(.model): \(.grossQuantity) reqs (\(.grossAmount | tostring | if test("\\.") then . else . + ".00" end)$)"' 2>/dev/null | \
    while read -r line; do
      echo -e "    🔹${line}" | tee -a "$LOG_FILE"
    done
  fi

  echo -e "${COLORS_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE" > /dev/null
}

fetch_usage() {
  local timestamp="⏱️  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "$timestamp - 正在查询..." | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE" > /dev/null

  # 先显示当前计费周期整体用量
  fetch_cycle_summary

  # DAYS=0 时只显示周期汇总，跳过每日明细
  if [ "$DAYS" -le 0 ]; then
    echo "📝 日志已保存: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE" > /dev/null
    return
  fi
  
  local total_requests=0
  local total_amount=0
  local temp_file=$(mktemp)
  
  # 第一遍：显示每日明细，同时收集数据
  for ((i=0; i<DAYS; i++)); do
    DATE=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "-$i days" +%Y-%m-%d)
    YEAR=$(echo $DATE | cut -d- -f1)
    MONTH=$(echo $DATE | cut -d- -f2 | sed 's/^0//')
    DAY=$(echo $DATE | cut -d- -f3 | sed 's/^0//')
    
    RESPONSE=$(gh api "/users/$USERNAME/settings/billing/premium_request/usage?year=$YEAR&month=$MONTH&day=$DAY" \
      -H "X-GitHub-Api-Version: 2022-11-28" 2>/dev/null)
    
    if [ -z "$RESPONSE" ]; then
      continue
    fi
    
    local items_count=$(echo "$RESPONSE" | jq '.usageItems | length' 2>/dev/null)
    
    if [ "$items_count" -gt 0 ]; then
      echo "📅 $DATE:" | tee -a "$LOG_FILE"
      
      echo "$RESPONSE" | jq -r '.usageItems[]' 2>/dev/null | \
      jq -r '@json' 2>/dev/null | while read -r item_json; do
        item_model=$(echo "$item_json" | jq -r '.model' 2>/dev/null)
        item_requests=$(echo "$item_json" | jq -r '.grossQuantity' 2>/dev/null)
        item_amount=$(echo "$item_json" | jq -r '.grossAmount' 2>/dev/null)
        
        if [ -n "$item_model" ] && [ "$item_model" != "null" ]; then
          # 显示与指定模型匹配的项
          if [ -z "$MODEL" ] || [ "$item_model" = "$MODEL" ]; then
            echo "  🔹 $item_model: $item_requests requests | 💰 \$$item_amount" | tee -a "$LOG_FILE"
          fi
          # 所有项都记录用于统计
          echo "$item_model|$item_requests|$item_amount" >> "$temp_file"
        fi
      done
    else
      echo "📅 $DATE: 无使用记录" | tee -a "$LOG_FILE"
    fi
  done
  
  # 显示聚合统计
  echo "" | tee -a "$LOG_FILE" > /dev/null
  echo -e "${COLORS_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOG_FILE"
  
  # 计算统计数据
  if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
    # 过滤指定模型（如果有）
    local filter_file="$temp_file"
    if [ -n "$MODEL" ]; then
      filter_file=$(mktemp)
      grep "^$MODEL|" "$temp_file" > "$filter_file" 2>/dev/null || true
    fi
    
    if [ -s "$filter_file" ]; then
      total_requests=0
      total_amount=0
      
      # 按行处理，累加数据
      while IFS='|' read -r m r a; do
        total_requests=$(echo "$total_requests + $r" | bc 2>/dev/null)
        total_amount=$(echo "$total_amount + $a" | bc 2>/dev/null)
      done < "$filter_file"
    fi
    
    if [ -n "$MODEL" ]; then
      rm -f "$filter_file"
    fi
  fi
  
  # 输出汇总
  if [ -n "$MODEL" ]; then
    echo -e "${COLORS_GREEN}📈 ${MODEL} 近${DAYS}天合计: $total_requests requests | 💰 \$$total_amount${RESET}" | tee -a "$LOG_FILE"
  else
    echo -e "${COLORS_GREEN}📈 近${DAYS}天汇总 (按模型):${RESET}" | tee -a "$LOG_FILE"
    
    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
      # 按模型分组统计 - 使用awk处理
      awk -F'|' '{
        model=$1; req=$2; amt=$3
        models[model] = (models[model] ? models[model] : 0) + req
        amounts[model] = (amounts[model] ? amounts[model] : 0) + amt
      }
      END {
        for (m in models) {
          print m "|" models[m] "|" amounts[m]
        }
      }' "$temp_file" | sort | while IFS='|' read -r model m_req m_amt; do
        if [ -n "$model" ]; then
          echo -e "${COLORS_YELLOW}  🔸 $model: $m_req requests | 💰 \$$m_amt${RESET}" | tee -a "$LOG_FILE"
        fi
      done
    fi
    
    echo "" | tee -a "$LOG_FILE" > /dev/null
    echo -e "${COLORS_GREEN}📊 全部模型合计: $total_requests requests | 💰 \$$total_amount${RESET}" | tee -a "$LOG_FILE"
  fi
  
  echo -e "${COLORS_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE" > /dev/null
  
  if [ "$WATCH_MODE" = true ]; then
    echo "💡 提示: Ctrl+C 停止监控 | 日志: $LOG_FILE" | tee -a "$LOG_FILE"
  else
    echo "📝 日志已保存: $LOG_FILE" | tee -a "$LOG_FILE"
  fi
  echo "" | tee -a "$LOG_FILE" > /dev/null
  
  rm -f "$temp_file"
}

# 显示初始header
echo -e "${COLORS_CYAN}=== 开始监控 $(date '+%Y-%m-%d %H:%M:%S') ===${RESET}" | tee -a "$LOG_FILE"
log_message ""

display_header

# 主逻辑
if [ "$WATCH_MODE" = true ]; then
  # 监控模式：持续运行，每30秒刷新
  while true; do
    fetch_usage
    
    # 倒计时显示
    for ((i=$INTERVAL; i>0; i--)); do
      echo -ne "\r⏳ ${i}秒后刷新... "
      sleep 1
    done
    echo "" | tee -a "$LOG_FILE" > /dev/null
  done
else
  # 单次查询模式
  fetch_usage
fi
