#!/bin/bash

# 检查是否传入容器名称
if [ -z "$1" ]; then
    echo "用法: $0 <容器名称>"
    exit 1
fi

CONTAINER_NAME=$1

# 获取容器内的 Java 进程 PID
PID=$(docker exec -it "$CONTAINER_NAME" jps | awk '/[^ ]/ {print $1}' | head -n 1)

if [ -z "$PID" ]; then
    echo "未找到容器 $CONTAINER_NAME 内的 Java 进程 PID"
    exit 1
fi

echo "容器 $CONTAINER_NAME 内的 Java 进程 PID 为: $PID"
echo "开始统计堆内存和 CPU 使用率，请等待10分钟..."

# 初始化最大值和最小值
max_heap=0
min_heap=10000000000000
max_cpu=0
min_cpu=100000

# 开始统计，采样 600 次，每次间隔 1 秒，总时长 10 分钟
for i in {1..600}; do
    # 获取堆内存使用情况
    heap_output=$(docker exec -it "$CONTAINER_NAME" jstat -gc "$PID" 2>/dev/null | tail -n 1)
    if [ -z "$heap_output" ]; then
        echo "无法获取堆内存使用情况，请检查容器或进程状态"
        exit 1
    fi

    # 计算堆内存总使用量 (以 U 结尾的列)
    total_u=0
    for value in $(echo "$heap_output" | awk '{print $3, $4, $6, $8, $10, $12}'); do
        total_u=$(echo "$total_u + $value" | bc)
    done
    total_heap=$(echo "scale=2; $total_u / 1024 / 1024" | bc)

    # 更新堆内存最大值和最小值
    if (( $(echo "$total_heap > $max_heap" | bc -l) )); then
        max_heap=$total_heap
    fi
    if (( $(echo "$total_heap < $min_heap" | bc -l) )); then
        min_heap=$total_heap
    fi

    # 获取 CPU 使用率
    cpu_usage=$(docker exec -it "$CONTAINER_NAME" top -b -n 1 -p "$PID" | awk -v pid="$PID" '$1 == pid {print $9}')
    if [ -z "$cpu_usage" ]; then
        echo "无法获取 CPU 使用率，请检查容器或进程状态"
        exit 1
    fi

    # 更新 CPU 使用率最大值和最小值
    if (( $(echo "$cpu_usage > $max_cpu" | bc -l) )); then
        max_cpu=$cpu_usage
    fi
    if (( $(echo "$cpu_usage < $min_cpu" | bc -l) )); then
        min_cpu=$cpu_usage
    fi

    # 每秒采样一次
    sleep 1
done

# 输出统计结果
echo "统计完成!"
echo "堆内存使用情况:"
echo "最大堆内存: $max_heap GB"
echo "最小堆内存: $min_heap GB"
echo
echo "CPU 使用率:"
echo "最大 CPU 使用率: $max_cpu%"
echo "最小 CPU 使用率: $min_cpu%"
