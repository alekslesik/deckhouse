#!/usr/bin/env bash

lsblk

set -e

echo "Старт скрипта с параметрами: $*"

if [ -n "$1" ]; then
    NODE_NUM="$1"
else
    echo -n "Введите номер региона: "
    read -r NODE_NUM
fi
TARGET_DEVICE="${2:-/dev/sda}"

# Проверка обязательного параметра NODE_NUM
if [ -z "$NODE_NUM" ]; then
    echo "ОШИБКА: Не указан номер узла (NODE_NUM)"
    echo "Использование: $0 <NODE_NUM> [TARGET_DEVICE] [FLASH_DEVICE]"
    exit 1
fi

# Validate NODE_NUM is a number
if ! [[ "$NODE_NUM" =~ ^[0-9]+$ ]]; then
    echo "ОШИБКА: Номер узла должен быть числом"
    exit 1
fi

# List available block devices
echo "Доступные блочные устройства:"
lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk
echo

# Validate that the device exists and is a block device
if [ ! -b "$TARGET_DEVICE" ]; then
    echo "ОШИБКА: Устройство $TARGET_DEVICE не найдено или не является блочным устройством"
    exit 1
fi

# Check if the device is already mounted
DEVICE_MOUNT_POINT="/data"
if findmnt -n -o TARGET "$TARGET_DEVICE" >/dev/null || mountpoint -q "$DEVICE_MOUNT_POINT"; then
    echo "ОШИБКА: Устройство $TARGET_DEVICE уже смонтировано в $(findmnt -n -o TARGET "$TARGET_DEVICE" || echo "$DEVICE_MOUNT_POINT")"
    exit 1
fi

# Warning and confirmation for formatting
echo "ВНИМАНИЕ: Вы собираетесь отформатировать $TARGET_DEVICE"
echo "Все данные на устройстве будут уничтожены!"
echo -n "Продолжить? (y/N): "
read -r confirm
if [[ "$confirm" == [yY] ]]; then
    echo "Подтверждено. Продолжаем операцию..."
else
    echo "Отмена операции."
    exit 0
fi

# Format the device
echo "Форматирование $TARGET_DEVICE в ext4..."
mkfs.ext4 -m 1 -O ^has_journal "$TARGET_DEVICE" || {
    echo "ОШИБКА форматирования"
    exit 1
}
echo "Форматирование успешно завершено"

# Create base directories
TARGET_DIRS=("/data")
for dir in "${TARGET_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -vp "$dir" || {
            echo "ОШИБКА: Не удалось создать $dir"
            exit 1
        }
        chmod 755 "$dir"
        chown root:root "$dir"
        echo "Создан каталог $dir"
    else
        echo "Каталог $dir уже существует"
    fi
done

# Mount target device and add to fstab
if [ ! -b "$TARGET_DEVICE" ]; then
    echo "ОШИБКА: Устройство $TARGET_DEVICE не найдено"
    exit 1
fi
UUID=$(blkid -s UUID -o value "$TARGET_DEVICE" || {
    echo "ОШИБКА: Не удалось получить UUID для $TARGET_DEVICE"
    exit 1
})
FSTAB_ENTRY="UUID=$UUID /data ext4 defaults,discard,nofail 0 0"
if grep -q "^UUID=$UUID" /etc/fstab; then
    echo "Запись для UUID=$UUID уже существует в /etc/fstab"
else
    echo "Добавление записи в /etc/fstab..."
    echo "$FSTAB_ENTRY" | tee -a /etc/fstab >/dev/null || {
        echo "ОШИБКА: Не удалось записать в /etc/fstab"
        exit 1
    }
fi
mount -av | grep "/data" || {
    echo "ОШИБКА: Не удалось смонтировать /data"
    exit 1
}
echo -e "\nТекущее содержимое /etc/fstab:"
grep -v '^#' /etc/fstab | grep -v '^$'
echo -e "\nПроверка монтирования:"
df -hT | grep "/data"

# Generate SSH keys
echo "Создаём новый SSH-ключ..."
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

mkdir /data/backup

cat /root/.ssh/id_ed25519.pub > /root/.ssh/authorized_keys


useradd -m -s /bin/bash backup && echo "backup:backup" | chpasswd
