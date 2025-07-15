### Чек-лист проверки работоспособности сервисов DIGIT

#### Проверка через ArgoCD

| № | Мероприятие | Инструкция | Ожидаемый результат |
|---|------------|------------|---------------------|
| 1 | Проверить общее состояние проекта | В интерфейсе ArgoCD проверить статус приложений (cassandra, postgres, dgepu, svd-control, svd-simple) | **Healthy** |
| 2 | Проверить статус синхронизации с манифестами | В интерфейсе ArgoCD проверить статус синхронизации для каждого приложения | **Sync OK** |
| 3 | Проверить синхронизацию с манифестами | Нажать кнопку **SYNC** для каждого приложения | Успешная синхронизация |
| 4 | Проверить пересоздание подов | Удалить поды через интерфейс ArgoCD | Поды автоматически пересоздаются |
| 5 | Проверить события | Проверить вкладку **EVENTS** для каждого приложения | Нет ошибок |
| 6 | Проверить логи | Проверить вкладку **LOGS** для основных контейнеров | Нет критических ошибок |

#### Проверка через Kubernetes консоль

**1. Общие проверки**

| № | Мероприятие | Команда | Ожидаемый результат |
|---|------------|---------|---------------------|
| 1 | Проверить статус всех подов | `kubectl get pods -n digit` | Все поды в статусе **Running** |
| 2 | Проверить статус PersistentVolumeClaims | `kubectl get pvc -n digit` | Все PVC в статусе **Bound** |
| 3 | Проверить сервисы | `kubectl get svc -n digit` | Все сервисы доступны с правильными портами |

**2. Проверка Cassandra**

| № | Мероприятие | Команда | Ожидаемый результат |
|---|------------|---------|---------------------|
| 1 | Проверить логи | `kubectl logs -n digit digit-cassandra-statefulset-0` | Нет ошибок, сообщения о успешном старте |
| 2 | Проверить статус ноды | `kubectl exec -n digit digit-cassandra-statefulset-0 -- nodetool status` | Нода в статусе **UN** |
| 3 | Проверить соединение CQL | `kubectl exec -n digit digit-cassandra-statefulset-0 -- cqlsh -u cassandra -p cassandra -e "DESCRIBE KEYSPACES"` | Список keyspaces без ошибок |
| 4 | Проверить порты | `kubectl exec -n digit digit-cassandra-statefulset-0 -- netstat -tuln` | Прослушиваются порты 7000, 7001, 7199, 9042 |

**3. Проверка PostgreSQL**

| № | Мероприятие | Команда | Ожидаемый результат |
|---|------------|---------|---------------------|
| 1 | Проверить логи | `kubectl logs -n digit digit-postgres-deployment-<hash>` | Нет ошибок, сообщения о успешном старте |
| 2 | Проверить доступность | `kubectl exec -n digit digit-postgres-deployment-<hash> -- pg_isready -U postgres` | Ответ: `postgres:5432 - accepting connections` |
| 3 | Проверить базы данных | `kubectl exec -n digit digit-postgres-deployment-<hash> -- psql -U postgres -c "\l"` | Список баз данных (ascug, pros, meas_params и др.) |
| 4 | Проверить порт | `kubectl exec -n digit digit-postgres-deployment-<hash> -- netstat -tuln` | Прослушивается порт 5432 |

**4. Проверка DGEPU**

| № | Мероприятие | Команда | Ожидаемый результат |
|---|------------|---------|---------------------|
| 1 | Проверить логи | `kubectl logs -n digit digit-dgepu-deployment-<hash>` | Нет ошибок, сообщения о успешном старте приложения |
| 2 | Проверить доступность API | `kubectl exec -n digit -it digit-dgepu-deployment-<hash> -- curl -I http://localhost:8080/pros/` | HTTP 200 OK |
| 3 | Проверить порт | `kubectl exec -n digit digit-dgepu-deployment-<hash> -- netstat -tuln` | Прослушивается порт 8080 |

**5. Проверка SVD Control**

| № | Мероприятие | Команда | Ожидаемый результат |
|---|------------|---------|---------------------|
| 1 | Проверить логи | `kubectl logs -n digit digit-svd-control-deployment-<hash>` | Нет ошибок, сообщения о подключении к SVD simple |
| 2 | Проверить порт UDP | `kubectl exec -n digit digit-svd-control-deployment-<hash> -- netstat -uln` | Прослушивается порт 11000 |

**6. Проверка SVD Simple**

| № | Мероприятие | Команда | Ожидаемый результат |
|---|------------|---------|---------------------|
| 1 | Проверить логи | `kubectl logs -n digit digit-svd-simple-deployment-<hash>` | Нет ошибок, сообщения о подключении к SVD Control |
| 2 | Проверить порт | `kubectl exec -n digit digit-svd-simple-deployment-<hash> -- netstat -uln` | Прослушивается порт 10101 |

**7. Проверка взаимодействия сервисов**

| № | Мероприятие | Команда | Ожидаемый результат |
|---|------------|---------|---------------------|
| 1 | Проверить подключение DGEPU к PostgreSQL | `kubectl exec -n digit digit-dgepu-deployment-<hash> -- curl -I http://digit-postgres-headless:5432` | Доступность порта |
| 2 | Проверить подключение DGEPU к Cassandra | `kubectl exec -n digit digit-dgepu-deployment-<hash> -- curl -I http://digit-cassandra-service:9042` | Доступность порта |
| 3 | Проверить подключение SVD Simple к SVD Control | `kubectl exec -n digit digit-svd-simple-deployment-<hash> -- nc -zv digit-svd-control-service 11000` | Успешное подключение |
