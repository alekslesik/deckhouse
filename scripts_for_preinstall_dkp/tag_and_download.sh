#!/usr/bin/env bash

set -e

echo "Старт скрипта с параметрами: $*"

if [ -n "$1" ]; then
    NODE_NUM="$1"
else
    echo -n "Введите номер региона: "
    read -r NODE_NUM
fi

for file in *.tar; do
    # Загружаем образ (выводим информацию для парсинга)
    loaded_info=$(docker load -i "$file" | grep "Loaded image:")

    # Извлекаем оригинальное имя образа
    original_image=$(echo "$loaded_info" | awk '{print $3}')

    # Формируем новый тег (заменяем возможные старые registry на backup-and-harbor.local/digit/)
    new_tag="${NODE_NUM}-node-1:5000/digit/$(basename "$original_image")"

    # Перетегируем образ
    docker tag "$original_image" "$new_tag"

    # Опционально: удаляем старый тег (если не нужен)
    docker rmi "$original_image" 2>/dev/null

    echo "Loaded and retagged: $file → $new_tag"
done
