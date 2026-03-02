#!/bin/bash

# ==========================================
# 服务器配置信息检查脚本
# 作者: donghua
# 描述: 自动收集并显示硬件、系统及软件配置信息
# ==========================================

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 创建日志文件
LOG_FILE="server_info_$(hostname)_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${GREEN}检查时间: $(date)${NC}"
echo -e "==========================================\n"

# 函数：打印章节标题
print_header() {
    echo -e "${BLUE}"
    echo -e "=========================================="
    echo -e ">>> $1"
    echo -e "=========================================="
    echo -e "${NC}"
}

# 1. 系统基本信息
print_header "1. 系统基本信息"
echo -e "主机名: ${YELLOW}$(hostname)${NC}"
echo "------"
cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"'
echo "------"
uname -a

# 2. CPU 信息
print_header "2. CPU 信息"

# 检查CPU架构
CPU_ARCH=$(uname -m)
case "$CPU_ARCH" in
    x86_64)
        ARCH_TYPE="x86_64 (AMD/Intel)"
        ;;
    aarch64)
        ARCH_TYPE="ARM64 (ARM)"
        ;;
    armv7*)
        ARCH_TYPE="ARMv7 (ARM)"
        ;;
    *)
        ARCH_TYPE="$CPU_ARCH"
        ;;
esac
echo -e "${YELLOW}CPU架构:${NC} $ARCH_TYPE"

# 获取CPU核心信息
if command -v lscpu &> /dev/null; then
    echo -e "\n${YELLOW}CPU详细信息:${NC}"
    lscpu | grep -E "(^CPU\(s\):|架构|型号名称|CPU 最大 MHz|CPU 最小 MHz|每个核的线程数|每个座的核数|座：|NUMA 节点)"
    
    # 提取并显示核心数信息
    PHYSICAL_CORES=$(lscpu | grep "每个座的核数" | awk '{print $NF}' 2>/dev/null)
    SOCKETS=$(lscpu | grep "座：" | awk '{print $NF}' 2>/dev/null)
    THREADS_PER_CORE=$(lscpu | grep "每个核的线程数" | awk '{print $NF}' 2>/dev/null)
    LOGICAL_CORES=$(lscpu | grep "^CPU\(s\):" | awk '{print $NF}' 2>/dev/null)
    
    if [ -z "$PHYSICAL_CORES" ] || [ -z "$SOCKETS" ]; then
        # 英文系统尝试
        PHYSICAL_CORES=$(lscpu | grep "Core(s) per socket" | awk '{print $NF}' 2>/dev/null)
        SOCKETS=$(lscpu | grep "Socket(s)" | awk '{print $NF}' 2>/dev/null)
        THREADS_PER_CORE=$(lscpu | grep "Thread(s) per core" | awk '{print $NF}' 2>/dev/null)
    fi
    
    echo -e "\n${YELLOW}CPU核心总结:${NC}"
    [ ! -z "$PHYSICAL_CORES" ] && [ ! -z "$SOCKETS" ] && echo -e "物理核心数: $((PHYSICAL_CORES * SOCKETS))"
    [ ! -z "$LOGICAL_CORES" ] && echo -e "逻辑核心数: $LOGICAL_CORES"
    [ ! -z "$SOCKETS" ] && echo -e "CPU插槽数: $SOCKETS"
    [ ! -z "$THREADS_PER_CORE" ] && echo -e "每核心线程数: $THREADS_PER_CORE"
else
    # 如果lscpu不可用，尝试使用其他方法
    echo -e "\n${YELLOW}CPU信息 (通过/proc/cpuinfo):${NC}"
    if [ -f /proc/cpuinfo ]; then
        echo -e "处理器数量: $(grep -c "processor" /proc/cpuinfo)"
        grep "model name" /proc/cpuinfo | head -1
        grep "cpu cores" /proc/cpuinfo | head -1
        echo -e "总线程数: $(grep -c "processor" /proc/cpuinfo)"
    else
        echo "无法获取CPU详细信息，/proc/cpuinfo不可用"
    fi
fi

# 3. 内存信息
print_header "3. 内存信息"
free -h

# 4. 磁盘信息
print_header "4. 磁盘与分区信息"
echo -e "${YELLOW}磁盘使用情况 (df -h):${NC}"
df -h
echo -e "\n${YELLOW}磁盘列表 (lsblk):${NC}"
lsblk
echo -e "\n${YELLOW}物理磁盘详情 (fdisk -l):${NC}"
if command -v fdisk &> /dev/null; then
    sudo fdisk -l 2>/dev/null | head -n 20
else
    echo "fdisk 命令未找到，跳过。"
fi

# 5. 网络信息
print_header "5. 网络信息"
echo -e "${YELLOW}IP 地址信息:${NC}"
if command -v ip &> /dev/null; then
    ip addr show | grep -E "inet (10|172|192|[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*)" | grep -v "127.0.0.1" | awk '{print $2 " on " $NF}'
else
    ifconfig 2>/dev/null | grep -E "inet (10|172|192|[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*)" | grep -v "127.0.0.1" | awk '{print $2 " on " $1}' | sed 's/addr://'
fi

echo -e "\n${YELLOW}监听中的网络端口:${NC}"
if command -v ss &> /dev/null; then
    ss -tuln
elif command -v netstat &> /dev/null; then
    netstat -tuln
else
    echo "ss 和 netstat 命令均未找到，跳过端口检查。"
fi

# 检查外网连通性
echo -e "\n${YELLOW}外网连通性检测:${NC}"

# 定义要测试的目标
TARGETS=("www.baidu.com" "www.qq.com" "www.aliyun.com" "www.huaweicloud.com")
PING_COUNT=2
PING_TIMEOUT=3
CURL_TIMEOUT=5
WGET_TIMEOUT=5

# 检查是否有网络工具可用
if command -v ping &> /dev/null; then
    echo -e "\n${YELLOW}Ping 测试:${NC}"
    PING_SUCCESS=false
    for target in "${TARGETS[@]}"; do
        echo -n "Ping $target: "
        if ping -c $PING_COUNT -W $PING_TIMEOUT $target &> /dev/null; then
            echo -e "${GREEN}可访问${NC}"
            PING_SUCCESS=true
            break
        else
            echo -e "${RED}不可访问${NC}"
        fi
    done
    
    if [ "$PING_SUCCESS" = true ]; then
        echo -e "外网连通性: ${GREEN}正常${NC}"
    else
        echo -e "外网连通性: ${RED}异常${NC} (所有Ping测试均失败)"
    fi
fi

# 使用HTTP请求测试
HTTP_SUCCESS=false
if command -v curl &> /dev/null; then
    echo -e "\n${YELLOW}HTTP测试 (curl):${NC}"
    for target in "${TARGETS[@]}"; do
        echo -n "访问 http://$target: "
        if curl -s --connect-timeout $CURL_TIMEOUT -m $CURL_TIMEOUT -o /dev/null -w "%{http_code}" "http://$target" | grep -q -E "^[23]"; then
            echo -e "${GREEN}可访问${NC}"
            HTTP_SUCCESS=true
            break
        else
            echo -e "${RED}不可访问${NC}"
        fi
    done
elif command -v wget &> /dev/null; then
    echo -e "\n${YELLOW}HTTP测试 (wget):${NC}"
    for target in "${TARGETS[@]}"; do
        echo -n "访问 http://$target: "
        if wget -q --timeout=$WGET_TIMEOUT -O /dev/null "http://$target"; then
            echo -e "${GREEN}可访问${NC}"
            HTTP_SUCCESS=true
            break
        else
            echo -e "${RED}不可访问${NC}"
        fi
    done
fi

# DNS解析测试
if command -v nslookup &> /dev/null || command -v dig &> /dev/null || command -v host &> /dev/null; then
    echo -e "\n${YELLOW}DNS解析测试:${NC}"
    DNS_SUCCESS=false
    
    for target in "${TARGETS[@]}"; do
        echo -n "解析 $target: "
        if command -v nslookup &> /dev/null; then
            if nslookup $target &> /dev/null; then
                echo -e "${GREEN}成功${NC}"
                DNS_SUCCESS=true
                break
            else
                echo -e "${RED}失败${NC}"
            fi
        elif command -v dig &> /dev/null; then
            if dig +short $target &> /dev/null; then
                echo -e "${GREEN}成功${NC}"
                DNS_SUCCESS=true
                break
            else
                echo -e "${RED}失败${NC}"
            fi
        elif command -v host &> /dev/null; then
            if host $target &> /dev/null; then
                echo -e "${GREEN}成功${NC}"
                DNS_SUCCESS=true
                break
            else
                echo -e "${RED}失败${NC}"
            fi
        fi
    done
fi

# 总结网络连通性
echo -e "\n${YELLOW}网络连通性总结:${NC}"
if [ "$PING_SUCCESS" = true ] || [ "$HTTP_SUCCESS" = true ] || [ "$DNS_SUCCESS" = true ]; then
    echo -e "外网连通性: ${GREEN}正常${NC} (至少一项测试成功)"
else
    echo -e "外网连通性: ${RED}异常${NC} (所有测试均失败)"
    
    # 检查可能的网络问题
    echo -e "\n${YELLOW}网络故障排查:${NC}"
    
    # 检查默认网关
    echo -n "默认网关: "
    if command -v ip &> /dev/null; then
        DEFAULT_GATEWAY=$(ip route | grep default | awk '{print $3}')
        if [ -n "$DEFAULT_GATEWAY" ]; then
            echo "$DEFAULT_GATEWAY"
            echo -n "Ping 默认网关: "
            if ping -c 1 -W 2 $DEFAULT_GATEWAY &> /dev/null; then
                echo -e "${GREEN}可访问${NC}"
            else
                echo -e "${RED}不可访问${NC} (可能是网关问题)"
            fi
        else
            echo -e "${RED}未配置${NC}"
        fi
    else
        echo "无法检测 (ip 命令不可用)"
    fi
    
    # 检查DNS配置
    echo -n "DNS配置: "
    if [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf | grep nameserver
    else
        echo -e "${RED}无法读取 /etc/resolv.conf${NC}"
    fi
fi

# 6. 系统运行状态
print_header "6. 系统运行状态"
echo -e "${YELLOW}系统负载 (uptime):${NC}"
uptime
echo -e "\n${YELLOW}内存使用前10的进程 (ps):${NC}"
ps aux --sort=-%mem | head -n 11

# 7. 软件与环境检查
print_header "7. 已安装的软件与环境"

# 判断系统类型并使用对应的包管理器
if [ -f /etc/redhat-release ] || [ -f /etc/almalinux-release ] || [ -f /etc/rocky-release ]; then
    echo -e "${YELLOW}系统基于 RPM (yum/dnf)${NC}"
    PKG_MGR="yum"
    # 检查常见软件
    SOFTWARE_LIST="nginx httpd mysql docker java python3 nodejs"
# 国产操作系统 - 基于RPM的系统
elif [ -f /etc/kylin-release ] || [ -f /etc/uos-release ] || [ -f /etc/openeuler-release ] || [ -f /etc/neokylin-release ]; then
    echo -e "${YELLOW}国产系统基于 RPM (yum/dnf)${NC}"
    PKG_MGR="yum"
    # 检查常见软件
    SOFTWARE_LIST="nginx httpd mysql docker java python3 nodejs"
# 国产操作系统 - 基于Debian的系统
elif [ -f /etc/deepin-version ] || [ -f /etc/uniontech-release ]; then
    echo -e "${YELLOW}国产系统基于 Debian (apt)${NC}"
    PKG_MGR="apt"
    # 检查常见软件
    SOFTWARE_LIST="nginx apache2 mysql-server docker.io openjdk python3 nodejs"
elif [ -f /etc/debian_version ]; then
    echo -e "${YELLOW}系统基于 Debian (apt)${NC}"
    PKG_MGR="apt"
    # 检查常见软件
    SOFTWARE_LIST="nginx apache2 mysql-server docker.io openjdk python3 nodejs"
else
    echo -e "${RED}无法确定包管理器类型。${NC}"
    SOFTWARE_LIST=""
fi

# 循环检查列表中的软件是否安装
for software in $SOFTWARE_LIST; do
    # 使用不同的方法检查软件是否安装，根据可用的命令
    if command -v $software &> /dev/null; then
        # 命令存在于PATH中
        IS_INSTALLED=true
    elif command -v dpkg &> /dev/null && dpkg -l | grep -q "ii  $software"; then
        # 使用dpkg检查（Debian系统）
        IS_INSTALLED=true
    elif command -v rpm &> /dev/null && rpm -qa | grep -q "$software"; then
        # 使用rpm检查（RPM系统）
        IS_INSTALLED=true
    else
        IS_INSTALLED=false
    fi
    
    if $IS_INSTALLED; then
        echo -e "${GREEN}[已安装]${NC} $software"
        # 尝试获取版本号
        case $software in
            nginx|httpd|apache2)
                $software -v 2>/dev/null | head -n 1
                ;;
            mysql*)
                mysql --version 2>/dev/null
                ;;
            docker)
                docker --version 2>/dev/null
                ;;
            java)
                java -version 2>&1 | head -n 1
                ;;
            python3)
                python3 --version 2>/dev/null
                ;;
            nodejs)
                node --version 2>/dev/null
                ;;
            *)
                echo "   版本: (请手动确认)"
                ;;
        esac
    else
        echo -e "${RED}[未安装]${NC} $software"
    fi
done

# 8. 检查容器环境
print_header "8. 容器环境检查"

# 检查各种容器运行时
CONTAINER_FOUND=false

# 检查Docker
if command -v docker &> /dev/null; then
    CONTAINER_FOUND=true
    echo -e "${GREEN}Docker 已安装。${NC}"
    echo -e "${YELLOW}Docker版本:${NC}"
    docker version | grep -E "Version:|API version:" | head -2
    echo -e "\n${YELLOW}Docker运行中的容器:${NC}"
    docker ps 2>/dev/null || echo "无法获取运行中的容器信息"
    echo -e "\n${YELLOW}所有Docker容器 (包括已停止的):${NC}"
    docker ps -a 2>/dev/null || echo "无法获取所有容器信息"
fi

# 检查Podman
if command -v podman &> /dev/null; then
    CONTAINER_FOUND=true
    echo -e "\n${GREEN}Podman 已安装。${NC}"
    echo -e "${YELLOW}Podman版本:${NC}"
    podman version | grep -E "Version:|API version:" | head -2
    echo -e "\n${YELLOW}Podman运行中的容器:${NC}"
    podman ps 2>/dev/null || echo "无法获取运行中的容器信息"
    echo -e "\n${YELLOW}所有Podman容器 (包括已停止的):${NC}"
    podman ps -a 2>/dev/null || echo "无法获取所有容器信息"
fi

# 检查containerd
if command -v ctr &> /dev/null; then
    CONTAINER_FOUND=true
    echo -e "\n${GREEN}containerd 已安装。${NC}"
    echo -e "${YELLOW}containerd版本:${NC}"
    ctr version 2>/dev/null || echo "无法获取containerd版本信息"
    echo -e "\n${YELLOW}containerd容器:${NC}"
    ctr container ls 2>/dev/null || echo "无法获取containerd容器信息"
fi

# 检查crictl (Kubernetes容器运行时接口)
if command -v crictl &> /dev/null; then
    CONTAINER_FOUND=true
    echo -e "\n${GREEN}CRI工具 (crictl) 已安装。${NC}"
    echo -e "${YELLOW}crictl版本:${NC}"
    crictl version 2>/dev/null || echo "无法获取crictl版本信息"
    echo -e "\n${YELLOW}CRI容器:${NC}"
    crictl ps 2>/dev/null || echo "无法获取CRI容器信息"
fi

# 检查isula (华为iSula容器)
if command -v isula &> /dev/null; then
    CONTAINER_FOUND=true
    echo -e "\n${GREEN}iSula容器 已安装。${NC}"
    echo -e "${YELLOW}iSula版本:${NC}"
    isula version 2>/dev/null || echo "无法获取iSula版本信息"
    echo -e "\n${YELLOW}iSula运行中的容器:${NC}"
    isula ps 2>/dev/null || echo "无法获取运行中的iSula容器信息"
    echo -e "\n${YELLOW}所有iSula容器 (包括已停止的):${NC}"
    isula ps -a 2>/dev/null || echo "无法获取所有iSula容器信息"
fi

# 如果没有找到任何容器运行时
if [ "$CONTAINER_FOUND" = false ]; then
    echo -e "${YELLOW}未发现任何容器运行时 (Docker/Podman/containerd/CRI/iSula)。${NC}"
fi

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}信息收集完成！${NC}"
echo -e "${GREEN}详细日志已保存至: ${YELLOW}$LOG_FILE${NC}"
echo -e "${GREEN}==========================================${NC}"
