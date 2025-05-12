### Чек-лист для проверки работоспособности приложения в Kubernetes

#### 1. **Проверка подов (Pods)**
```bash
# Проверить статус всех подов в namespace
kubectl get pods -n digit

# Проверить логи конкретного пода (например, digit-dgepu-deployment)
kubectl logs -n digit <pod_name> -c digit-dgepu

# Проверить логи init-контейнера (если есть)
kubectl logs -n digit <pod_name> -c copy-config

# Проверить события, связанные с подами
kubectl describe pod -n digit <pod_name>
```

#### 2. **Проверка развертывания (Deployment)**
```bash
# Проверить статус deployment
kubectl get deployment -n digit digit-dgepu-deployment

# Проверить историю изменений deployment
kubectl rollout history deployment -n digit digit-dgepu-deployment

# Проверить детали deployment
kubectl describe deployment -n digit digit-dgepu-deployment
```

#### 3. **Проверка StatefulSet**
```bash
# Проверить статус StatefulSet
kubectl get statefulset -n digit digit-cassandra-statefulset

# Проверить историю изменений StatefulSet
kubectl rollout history statefulset -n digit digit-cassandra-statefulset

# Проверить детали StatefulSet
kubectl describe statefulset -n digit digit-cassandra-statefulset
```
#### 4. **Проверка состояния Cassandra**
```bash
# Проверить статус ноды Cassandra (через nodetool)
kubectl exec -n digit digit-cassandra-statefulset-0 -c digit-cassandra -- nodetool -u cassandra -pw cassandra status

# Проверить информацию о кластере
kubectl exec -n digit digit-cassandra-statefulset-0 -c digit-cassandra -- nodetool -u cassandra -pw cassandra describecluster

# Проверить доступность CQL
kubectl exec -n digit digit-cassandra-statefulset-0 -c digit-cassandra -- cqlsh -u cassandra -p cassandra -e "DESCRIBE KEYSPACES"
```

#### 5. **Проверка сервиса (Service)**
```bash
# Проверить статус сервиса
kubectl get service -n digit digit-dgepu-service

# Проверить детали сервиса
kubectl describe service -n digit digit-dgepu-service
```

#### 6. **Проверка Ingress**
```bash
# Проверить статус Ingress
kubectl get ingress -n digit digit-dgepu-ingress

# Проверить детали Ingress
kubectl describe ingress -n digit digit-dgepu-ingress
```

#### 7. **Проверка PersistentVolumeClaim (PVC)**
```bash
# Проверить статус PVC
kubectl get pvc -n digit

# Проверить детали PVC
kubectl describe pvc -n digit digit-dgepu-data-localpath-pvc
kubectl describe pvc -n digit digit-dgepu-config-localpath-pvc
```

#### 8. **Проверка ConfigMap**
```bash
# Проверить ConfigMap
kubectl get configmap -n digit dgepu-config

# Проверить содержимое ConfigMap
kubectl describe configmap -n digit dgepu-config
```

#### 9. **Проверка мониторинга (Grafana Dashboard)**
```bash
# Проверить доступность метрик в Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090
# Затем открыть в браузере http://localhost:9090 и проверить метрики для digit-dgepu-service
```

#### 10. **Проверка сетевой доступности**
```bash
# Проверить доступность сервиса изнутри кластера
kubectl exec -n digit <pod_name> -- curl http://digit-dgepu-service:80/pros/

# Проверить доступность через Ingress (если настроен DNS или hosts)
curl http://dgepu.172-21-100-22.sslip.io/pros/
```

#### 11. **Проверка ресурсов**
```bash
# Проверить использование ресурсов подами
kubectl top pods -n digit

# Проверить использование ресурсов нодами
kubectl top nodes
```

#### 12. **Проверка событий кластера**
```bash
# Просмотреть события в namespace
kubectl get events -n digit --sort-by=.metadata.creationTimestamp
```

#### 13. **Проверка автоматического восстановления**
```bash
# Удалить под и проверить его пересоздание
kubectl delete pod -n digit <pod_name>
kubectl get pods -n digit -w  # Отслеживать статус
```