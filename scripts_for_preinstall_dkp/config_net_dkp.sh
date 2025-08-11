#!/usr/bin/env bash

# =============================================
# НАСТРОЙКА BOND LACP + VLAN
# Версия 2.0 - Идеальная
# =============================================

# Проверка прав
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[1;31mОШИБКА: Скрипт требует root-прав. Запустите через sudo!\033[0m" >&2
    exit 1
fi

# Цвета для удобства
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция проверки команд
check_command() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}ОШИБКА: Команда не выполнена!${NC}" >&2
        exit 1
    fi
}

# Заголовок
echo -e "${GREEN}"
echo "============================================="
echo "  НАСТРОЙКА BOND LACP + VLAN"
echo "  Автоматическая конфигурация сети"
echo "============================================="
echo -e "${NC}"

# Запрос региона с проверкой
while true; do
    read -p "Введите номер региона (3-й октет IP, например 162): " region
    if [[ "$region" =~ ^[0-9]+$ ]] && [ "$region" -ge 1 ] && [ "$region" -le 255 ]; then
        break
    fi
    echo -e "${YELLOW}Ошибка: введите число от 1 до 255${NC}"
done

# Подтверждение
echo -e "${YELLOW}"
echo "Будут настроены следующие параметры:"
echo "-----------------------------------"
echo "Режим bond: LACP (802.3ad)"
echo "Интерфейсы: ens7f0, ens7f1, ens7f2, ens7f3"
echo "VLAN 1002: 172.21.$region.22/28, шлюз 172.21.$region.17"
echo "VLAN 1003: 172.21.$region.38/28, шлюз 172.21.$region.33"
echo "VLAN 1004: 172.21.$region.54/28, шлюз 172.21.$region.49"
echo -e "${NC}"

read -p "Вы уверены, что хотите продолжить? [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${YELLOW}Отмена выполнения скрипта${NC}"
    exit 0
fi

# =============================================
# ШАГ 1: Очистка старых конфигураций
# =============================================
echo -e "\n${BLUE}Шаг 1: Очистка старых настроек...${NC}"

# Удаление VLAN подключений
for vlan in 1002 1003 1004; do
    if nmcli con show "bond0.$vlan" &>/dev/null; then
        echo "Удаляем VLAN bond0.$vlan..."
        nmcli con del "bond0.$vlan"
    fi
done

# Удаление bond0
if nmcli con show bond0 &>/dev/null; then
    echo "Удаляем bond0..."
    nmcli con del bond0
fi

# Удаление подключений физических интерфейсов
for iface in ens7f0 ens7f1 ens7f2 ens7f3; do
    conn_name=$(nmcli -t -f NAME,DEVICE con | grep ":$iface$" | cut -d: -f1)
    if [ -n "$conn_name" ]; then
        echo "Удаляем подключение $conn_name для $iface..."
        nmcli con del "$conn_name"
    fi
done

# =============================================
# ШАГ 2: Создание bond0
# =============================================
echo -e "\n${BLUE}Шаг 2: Создаем bond0 (LACP 802.3ad)...${NC}"
nmcli con add type bond con-name bond0 ifname bond0 \
    mode 802.3ad \
    ipv4.method link-local \
    ipv6.method disabled \
    bond.options "mode=802.3ad,miimon=100,lacp_rate=fast" \
    connection.autoconnect yes
check_command

# =============================================
# ШАГ 3: Добавление интерфейсов в bond
# =============================================
echo -e "\n${BLUE}Шаг 3: Добавляем интерфейсы в bond0...${NC}"
for iface in ens7f0 ens7f1 ens7f2 ens7f3; do
    echo "Добавляем $iface в bond0..."
    nmcli con add type ethernet con-name "$iface" ifname "$iface" \
        master bond0 slave-type bond \
        connection.autoconnect yes
    check_command
done

# =============================================
# ШАГ 4: Настройка VLAN
# =============================================
create_vlan() {
    local vlan_id=$1
    local ip=$2
    local gw=$3
    local ifname="bond0.$vlan_id"

    echo -e "\n${BLUE}Шаг 4.$vlan_id: Настраиваем VLAN $vlan_id (IP: $ip)...${NC}"

    # Создаем VLAN
    nmcli con add type vlan con-name "$ifname" ifname "$ifname" \
        dev bond0 id "$vlan_id" \
        ipv4.addresses "$ip" \
        ipv4.gateway "$gw" \
        ipv4.dns "127.0.0.1" \
        ipv4.method manual \
        ipv4.may-fail no \
        ipv6.method disabled \
        connection.autoconnect yes
    check_command
}

# Создаем VLAN
create_vlan 1002 "172.21.$region.22/28" "172.21.$region.17"
create_vlan 1003 "172.21.$region.38/28" "172.21.$region.33"
create_vlan 1004 "172.21.$region.54/28" "172.21.$region.49"

# =============================================
# ШАГ 5: Активация соединений
# =============================================
echo -e "\n${BLUE}Шаг 5: Активируем соединения...${NC}"

# Активируем bond0
echo "Активируем bond0..."
nmcli con up bond0
check_command

# Активируем физические интерфейсы
for iface in ens7f0 ens7f1 ens7f2 ens7f3; do
    echo "Активируем $iface..."
    nmcli con up "$iface"
    check_command
done

# Активируем VLAN
for vlan in 1002 1003 1004; do
    echo "Активируем bond0.$vlan..."
    nmcli con up "bond0.$vlan"
    check_command
done

# =============================================
# ШАГ 6: Проверка
# =============================================
echo -e "\n${GREEN}=== ПРОВЕРКА КОНФИГУРАЦИИ ===${NC}"

# Проверка состояния bond
echo -e "\n${YELLOW}1. Состояние bond:${NC}"
bond_status=$(cat /proc/net/bonding/bond0)
echo "$bond_status" | grep -E 'Bonding Mode|Active Slave|Slave Interface'

# Проверка IP-адресов
echo -e "\n${YELLOW}2. IP-адреса VLAN:${NC}"
ip -br -c a show bond0.1002 bond0.1003 bond0.1004

# Проверка маршрутов
echo -e "\n${YELLOW}3. Маршруты по умолчанию:${NC}"
ip -c route show | grep default

# Проверка настроек VLAN
echo -e "\n${YELLOW}4. Настройки VLAN:${NC}"
for vlan in 1002 1003 1004; do
    echo "bond0.$vlan:"
    nmcli con show "bond0.$vlan" | grep -E 'ipv4\.(addresses|gateway|may-fail)'
done

# Проверка подключения к шлюзам
echo -e "\n${YELLOW}5. Проверка связи с шлюзами:${NC}"
ping -c 1 -W 1 "172.21.$region.17" >/dev/null && echo "VLAN 1002: шлюз доступен" || echo "VLAN 1002: шлюз недоступен"
ping -c 1 -W 1 "172.21.$region.33" >/dev/null && echo "VLAN 1003: шлюз доступен" || echo "VLAN 1003: шлюз недоступен"
ping -c 1 -W 1 "172.21.$region.49" >/dev/null && echo "VLAN 1004: шлюз доступен" || echo "VLAN 1004: шлюз недоступен"

# =============================================
# ФИНАЛЬНЫЙ ОТЧЕТ
# =============================================
echo -e "\n${GREEN}=== НАСТРОЙКА ЗАВЕРШЕНА ===${NC}"
echo "Текущая конфигурация:"
echo "---------------------------------------"
echo "Bond0:"
echo "  Режим: LACP (802.3ad)"
echo "  Интерфейсы: ens7f0, ens7f1, ens7f2, ens7f3"
echo "  IPv4: локальная связь"
echo "  IPv6: отключен"

echo -e "\nVLAN:"
for vlan in 1002 1003 1004; do
    ip_addr=$(nmcli con show "bond0.$vlan" | grep 'ipv4.addresses' | awk '{print $2}')
    gateway=$(nmcli con show "bond0.$vlan" | grep 'ipv4.gateway' | awk '{print $2}')
    echo "bond0.$vlan:"
    echo "  IP: $ip_addr"
    echo "  Шлюз: $gateway"
    echo "  Требовать IPv4: да"
done

echo -e "\n${GREEN}Можете проверить работу сети. Удачи!${NC}"
