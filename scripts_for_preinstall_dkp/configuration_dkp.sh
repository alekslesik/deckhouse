#!/usr/bin/env bash

set -e

# Функция для проверки готовности ресурса
check_resource_ready() {
  local resource=$1
  local name=$2
  local timeout=$3
  local interval=5
  local attempts=$((timeout / interval))

  echo "Ожидание готовности $resource/$name (максимум $timeout секунд)..."
  for ((i=1; i<=attempts; i++)); do
    if kubectl get "$resource" "$name" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
      echo "$resource/$name готов"
      return 0
    fi
    sleep "$interval"
  done
  echo "Таймаут ожидания $resource/$name"
  return 1
}

# Удаляем taints с master nodegroup
echo "Удаляем taints с master nodegroup..."
sudo -i d8 k patch nodegroup master --type json -p '[{"op": "remove", "path": "/spec/nodeTemplate/taints"}]'

# Создаем LocalPathProvisioner
echo "Создаем LocalPathProvisioner..."
sudo -i d8 k create -f - << EOF
apiVersion: deckhouse.io/v1alpha1
kind: LocalPathProvisioner
metadata:
  name: localpath
spec:
  path: "/data/dkp"
  reclaimPolicy: Delete
EOF

# Настраиваем defaultClusterStorageClass
echo "Настраиваем defaultClusterStorageClass..."
sudo -i d8 k patch mc global --type merge \
  -p "{\"spec\": {\"settings\":{\"defaultClusterStorageClass\":\"localpath\"}}}"


# Развертываем IngressNginxController
echo "Развертываем IngressNginxController..."
cat <<'EOF' | kubectl apply -f -
apiVersion: deckhouse.io/v1
kind: IngressNginxController
metadata:
  name: nginx
spec:
  ingressClass: nginx
  inlet: HostPort
  hostPort:
    httpPort: 80
    httpsPort: 443
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
    operator: Exists
EOF

# Создаем пользователя и правила доступа
echo "Создаем пользователя и правила доступа..."
cat <<'EOF' | kubectl apply -f -
apiVersion: deckhouse.io/v1
kind: ClusterAuthorizationRule
metadata:
  name: admin
spec:
  subjects:
  - kind: User
    name: admin@deckhouse.io
  accessLevel: SuperAdmin
  portForwarding: true
---
apiVersion: deckhouse.io/v1
kind: User
metadata:
  name: admin
spec:
  email: admin@deckhouse.io
  password: 'JDJhJDEwJG9TTzhaUml3N2RwR3FFUzRxaS5OcXVUUHJTa2dzUkU0V09CODhsRHdQdS9XWEhEdFN1eGx5'
EOF


# Включаем модуль console
echo "Включаем модуль console..."
cat <<'EOF' | kubectl apply -f -
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: console
spec:
  enabled: true
EOF

echo "Скрипт успешно завершен!"
echo "#################################################################"
echo "Данные для доступа:"
echo "Логин — admin@deckhouse.io"
echo "Пароль — doeqv4vu1w"
echo "#################################################################"
