#!/usr/bin/env bash

set -e

echo "Старт скрипта с параметрами: $*"

if [ -n "$1" ]; then
    NODE_NUM="$1"
else
    echo -n "Введите номер региона: "
    read -r NODE_NUM
fi
TARGET_DEVICE="${2:-/dev/sda}"
FLASH_DEVICE="${3:-/dev/sdc1}"

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
TARGET_DIRS=("/data" "/backup" "/flash" "/data/registry")
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

# Create registry directories
REGISTRY_DIRS=("/etc/registry/auth" "/etc/registry/cert")
for dir in "${REGISTRY_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -vp "$dir" || {
            echo "ОШИБКА: Не удалось создать каталог $dir"
            exit 1
        }
        chmod 750 "$dir"
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

# Mount flash device
mount /dev/sdc1 /flash && ls -ahl /flash

rsync -ah --progress /flash/offline-packages /opt/
rsync -ah --progress /flash/dnf-update /opt/

# Create backup user
useradd -m -s /bin/bash backup
echo "backup:backup" | chpasswd

cat > /etc/yum.repos.d/local-dnf.repo <<EOF
[local-dnf-update]
name=Local DNF Update
baseurl=file:///opt/dnf-update
enabled=1
gpgcheck=0
EOF

cat > /etc/yum.repos.d/offline.repo <<EOF
[offline-repo]
name=Offline Packages Repository
baseurl=file:///opt/offline-packages
enabled=1
gpgcheck=0
EOF

dnf clean all
dnf makecache
echo "Удаляем yum..."
dnf remove -y yum

echo "Обновление системы из локального репозитория..."
dnf update -y --disablerepo=* --enablerepo=local-dnf-update
dnf update -y --disablerepo=* --enablerepo=local-dnf-update dnf


echo "Установка пакетов из offline репозитория..."
dnf install -y --disablerepo=* --enablerepo=offline-repo \
    httpd-tools \
    nfs-utils \
    registry

dnf install -y /flash/rpm_packages/yum/yum-4.17.0-2.el7.noarch.rpm

# Check and start registry service
if ! systemctl cat registry.service &>/dev/null; then
    echo "ОШИБКА: Служба registry.service не найдена"
    exit 1
fi
echo "Запуск и включение registry service..."
systemctl enable --now registry.service || {
    echo "ОШИБКА: Не удалось настроить registry.service"
    exit 1
}

# Generate certificates
cd /etc/registry/cert || {
    echo "ОШИБКА: Не удалось перейти в /etc/registry/cert"
    exit 1
}
echo "Генерация CA ключа и сертификата..."
openssl genrsa -out ca.key 4096 || {
    echo "ОШИБКА: Не удалось сгенерировать CA ключ"
    exit 1
}
openssl req -x509 -new -nodes -sha512 -days 3650 \
    -subj "/C=RU/ST=SPB/L=SPB/O=IT/OU=Enterprise/CN=EPU CA Authority" \
    -key ca.key \
    -out ca.crt || {
    echo "ОШИБКА: Не удалось сгенерировать CA сертификат"
    exit 1
}
echo "Генерация ключа и CSR для узла ${NODE_NUM}-node-1..."
openssl genrsa -out "${NODE_NUM}-node-1.key" 4096 || {
    echo "ОШИБКА: Не удалось сгенерировать ключ узла"
    exit 1
}
openssl req -sha512 -new \
    -subj "/C=RU/ST=SPB/L=SPB/O=IT/OU=Enterprise/CN=${NODE_NUM}-node-1" \
    -key "${NODE_NUM}-node-1.key" \
    -out "${NODE_NUM}-node-1.csr" || {
    echo "ОШИБКА: Не удалось сгенерировать CSR"
    exit 1
}
cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1=${NODE_NUM}-node-1
IP.1=172.21.${NODE_NUM}.22
EOF
echo "Генерация сертификата для узла ${NODE_NUM}-node-1..."
openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in "${NODE_NUM}-node-1.csr" \
    -out "${NODE_NUM}-node-1.crt" || {
    echo "ОШИБКА: Не удалось сгенерировать сертификат узла"
    exit 1
}
cp ca.crt /etc/pki/ca-trust/source/anchors/ || {
    echo "ОШИБКА: Не удалось скопировать CA сертификат"
    exit 1
}

update-ca-trust || {
    echo "ОШИБКА: Не удалось обновить хранилище сертификатов"
    exit 1
}
echo -e "\nПроверка созданных файлов:"
ls -l ca.* "${NODE_NUM}-node-1".*

# Generate htpasswd
htpasswd -Bbn registry registry > /etc/registry/auth/htpasswd

# Configure registry
REGISTRY_SECRET=$(openssl rand -base64 32)
cat > "/etc/registry/config.yml" <<-EOF
version: 0.1
log:
  accesslog:
    disabled: true
  level: info
  formatter: text
storage:
  delete:
    enabled: false
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /data/registry/lib/registry
http:
  addr: :5000
  host: ${NODE_NUM}-node-1
  secret: $REGISTRY_SECRET
  headers:
    X-Content-Type-Options: [nosniff]
  tls:
    certificate: /etc/registry/cert/${NODE_NUM}-node-1.crt
    key: /etc/registry/cert/${NODE_NUM}-node-1.key
auth:
  htpasswd:
    realm: basic-realm
    path: /etc/registry/auth/htpasswd
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

echo "Перезапуск registry service..."
systemctl restart registry.service || {
    echo "ОШИБКА: Не удалось перезапустить службу"
    exit 1
}
echo -e "\nСтатус registry service:"
systemctl status registry.service --no-pager

# Copy additional files
echo "Копируем /flash/1.69.16 в /data/install_dkp/..."
rsync -ah --progress /flash/1.69.16 /data/install_dkp/

cp -v /flash/push.sh /data/install_dkp/

cd /data/install_dkp

rsync -ah --progress /flash/d8 /usr/bin/

chmod +x /usr/bin/d8

# Update hosts file
echo "Добавляем запись в /etc/hosts..."
echo "172.21.${NODE_NUM}.22 ${NODE_NUM}-node-1" >> /etc/hosts

echo -e "\nТекущее содержимое /etc/hosts:"
cat /etc/hosts

curl -k -u registry:registry "https://${NODE_NUM}-node-1:5000/v2/_catalog"

# Update push.sh
echo "Заменяем '1-node-1:5000' на '${NODE_NUM}-node-1:5000' в файле push.sh..."
sed -i "s/1-node-1/${NODE_NUM}-node-1/g" /data/install_dkp/push.sh

# Запуск push.sh
echo -e "\nЗапуск скрипта push.sh..."
bash /data/install_dkp/push.sh

# Generate SSH keys
echo "Создаём новый SSH-ключ..."
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

cat "/root/.ssh/id_ed25519.pub" >> "/root/.ssh/authorized_keys"
chmod 600 "/root/.ssh/authorized_keys"

# Update config.yml
cp /flash/config.json /data/install_dkp

sed -i "s/1-node-1/${NODE_NUM}-node-1/g" /data/install_dkp/config.json


REGISTRY_DOCKER_CFG="$(cat /data/install_dkp/config.json | base64 -w 0)"
REGISTRY_CA="$(awk '/^-----BEGIN CERTIFICATE-----$/{print; next} {print "    " $0}' /etc/pki/ca-trust/source/anchors/ca.crt)"

cat > "/root/config.yml" <<-EOF
apiVersion: deckhouse.io/v1
kind: ClusterConfiguration
clusterType: Static
# Адресное пространство подов кластера.
podSubnetCIDR: 10.111.0.0/16
# Адресное пространство сети сервисов кластера.
serviceSubnetCIDR: 10.222.0.0/16
kubernetesVersion: "Automatic"
# Домен кластера.
clusterDomain: "cluster.local"
---
# Настройки первичной инициализации кластера Deckhouse.
# https://deckhouse.ru/products/kubernetes-platform/documentation/v1/installing/configuration.html#initconfiguration
apiVersion: deckhouse.io/v1
kind: InitConfiguration
deckhouse:
  # Адрес Docker registry с образами Deckhouse.
  imagesRepo: ${NODE_NUM}-node-1:5000/deckhouse/se
  # Строка с ключом для доступа к Docker registry.
  registryDockerCfg: ${REGISTRY_DOCKER_CFG}
  # Протокол доступа к registry (HTTP или HTTPS).
  registryScheme: HTTPS
  # Корневой сертификат, которым можно проверить сертификат registry (если registry использует самоподписанные сертификаты).
  registryCA: |
    ${REGISTRY_CA}
---
# Настройки модуля deckhouse.
# https://deckhouse.ru/products/kubernetes-platform/documentation/v1/modules/deckhouse/configuration.html
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: deckhouse
spec:
  version: 1
  enabled: true
  settings:
    bundle: Default
    releaseChannel: Stable
    logLevel: Info
---
# Глобальные настройки Deckhouse.
# https://deckhouse.ru/products/kubernetes-platform/documentation/v1/deckhouse-configure-global.html#%D0%BF%D0%B0%D1%80%D0%B0%D0%BC%D0%B5%D1%82%D1%80%D1%8B
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: global
spec:
  version: 2
  settings:
    modules:
      publicDomainTemplate: "%s.${NODE_NUM}-deckhouse.cluster"
      # Способ реализации протокола HTTPS, используемый модулями Deckhouse.
      https:
        certManager:
          # Использовать самоподписанные сертификаты для модулей Deckhouse.
          clusterIssuerName: selfsigned
---
# Настройки модуля user-authn.
# https://deckhouse.ru/products/kubernetes-platform/documentation/v1/modules/user-authn/configuration.html
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: user-authn
spec:
  version: 2
  enabled: true
  settings:
    controlPlaneConfigurator:
      dexCAMode: FromIngressSecret
    # Включение доступа к API-серверу Kubernetes через Ingress.
    # https://deckhouse.ru/products/kubernetes-platform/documentation/v1/modules/user-authn/configuration.html#parameters-publishapi
    publishAPI:
      enabled: true
      https:
        mode: Global
        global:
          kubeconfigGeneratorMasterCA: ""
---
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: cert-manager
spec:
  version: 1
  enabled: true
  settings:
    disableLetsencrypt: true
---
# Настройки модуля cni-cilium.
# https://deckhouse.ru/products/kubernetes-platform/documentation/v1/modules/cni-cilium/configuration.html
apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  name: cni-cilium
spec:
  version: 1
  # Включить модуль cni-cilium
  enabled: true
  settings:
    # Настройки модуля cni-cilium
    # https://deckhouse.ru/products/kubernetes-platform/documentation/v1/modules/cni-cilium/configuration.html
    tunnelMode: VXLAN
---
# Параметры статического кластера.
# https://deckhouse.ru/products/kubernetes-platform/documentation/v1/installing/configuration.html#staticclusterconfiguration
apiVersion: deckhouse.io/v1
kind: StaticClusterConfiguration
# Список внутренних сетей узлов кластера (например, '10.0.4.0/24'), который
# используется для связи компонентов Kubernetes (kube-apiserver, kubelet...) между собой.
# Укажите, если используете модуль virtualization или узлы кластера имеют более одного сетевого интерфейса.
# Если на узлах кластера используется только один интерфейс, ресурс StaticClusterConfiguration можно не создавать.
internalNetworkCIDRs:
- 172.21.${NODE_NUM}.16/28
EOF

cp /root/.ssh/* /data/install_dkp/

mkdir /data/dkp
mkdir /data/manifests

ping -c 4 "${NODE_NUM}-node-1"
