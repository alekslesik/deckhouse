# Переменные
REPO="85.141.97.224:443"
EXCLUDED_SERVICES="simple mqtt opcua adm akta asduk asumontazh axikam bpekck csd_spg740 csd_stel csd_tekon control client"

# Получаем список всех сервисов с тегами 'k'
SERVICES_WITH_K=$(grep -B1 -E '"4\.[0-9]+\.[0-9]+\.[0-9]+k"' get-images-result.txt | grep -v "{" | sed 's/Образ: //' | sort -u)

# Фильтруем исключённые сервисы
FILTERED_SERVICES=$(echo "$SERVICES_WITH_K" | grep -vE "$(echo "$EXCLUDED_SERVICES" | tr ' ' '|')")

# Генерируем YAML-файлы
for service in $FILTERED_SERVICES; do
    # Извлекаем последний тег с 'k' (например, 4.8.2.0k)
    TAG=$(grep -A1 "Образ: $service" get-images-result.txt | grep -oE '"4\.[0-9]+\.[0-9]+\.[0-9]+k"' | tr -d '"' | head -1)

    # Получаем socket из вашего конфига (если нужно)
    SOCKET=$(grep -A1 "\"code\": \"$service\"," <<<"$config" | grep -oP '\"socket\": \"\K[0-9]+')

    # Создаём YAML-файл
    cat <<EOF >digit-svd-${service}-deploy.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: digit-svd-${service}-data-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: localpath
  resources:
    requests:
      storage: 5Gi

---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: digit-svd-${service}-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: digit-svd
      component: ${service}
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: digit-svd
        component: ${service}
    spec:
      serviceAccountName: digit-svd-sa
      imagePullSecrets:
        - name: digit-dgepu-secret
      containers:
      - name: ${service}
        namespace: digit
        image: ${REPO}/svd_${service}:${TAG}
        ports:
        - containerPort: ${SOCKET:-10100}  # Если socket не найден, ставим 10100
        env:
        - name: SVDCode
          value: "${service}"
        - name: SVDControl
          value: "digit-svd-control-service:11000"
        - name: TZ
          value: "Europe/Moscow"
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
          - name: digit-svd-${service}-data-rsc
            mountPath: /svd/host
      volumes:
      - name: digit-svd-${service}-data-rsc
        persistentVolumeClaim:
          claimName: digit-svd-${service}-data-pvc
EOF
done
