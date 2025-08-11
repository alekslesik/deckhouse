#!/usr/bin/env bash

set -e

echo "Старт скрипта с параметрами: $*"

if [ -n "$1" ]; then
    NODE_NUM="$1"
else
    echo -n "Введите номер региона: "
    read -r NODE_NUM
fi

# Проверяем, что NODE_NUM — число
if ! [[ "$NODE_NUM" =~ ^[0-9]+$ ]]; then
    echo "Ошибка: номер региона должен быть числом!" >&2
    exit 1
fi

# Сохраняем список образов в файл (без ":" в имени)
docker images | grep "${NODE_NUM}-node-1:5000/digit/" > "${NODE_NUM}-node-1_5000.txt"

echo "Список образов сохранён в ${NODE_NUM}-node-1_5000.txt"


docker login -u registry -p registry "https://${NODE_NUM}-node-1:5000"

# Адрес вашего Docker Registry (например, backup-and-harbor.local)
REGISTRY="${NODE_NUM}-node-1:5000"

# Читаем файл со списком образов
INPUT_FILE="${NODE_NUM}-node-1_5000.txt"

# Проверяем, существует ли файл
if [ ! -f "$INPUT_FILE" ]; then
    echo "Ошибка: файл $INPUT_FILE не найден!"
    exit 1
fi

# Перебираем строки с образами
while IFS= read -r line; do
    # Извлекаем имя образа и тег (формат: REPO:TAG)
    image=$(echo "$line" | awk '{print $1 ":" $2}')

    # Пушим образ в Registry
    echo "Pushing $image to $REGISTRY..."
    docker push "$image"

    if [ $? -eq 0 ]; then
        echo "✅ Успешно: $image загружен в $REGISTRY"
    else
        echo "❌ Ошибка: не удалось загрузить $image"
    fi
done < "$INPUT_FILE"

echo "Готово! Все образы отправлены в Registry."
