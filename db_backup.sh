#!/bin/bash

# Конфигурационные параметры
BACKUP_DIR="/opt/backups/db"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="/opt/db/log/db_backup.log"
RSYNC_USER="backupuser"
BACKUP_SERVER="backup-server.local"
BACKUP_REMOTE_DIR="/opt/backups/db"
RETENTION_DAYS=7

# Логирование
exec >> $LOG_FILE 2>&1

echo "=============================================="
echo "Starting backup at $(date)"
echo "=============================================="

# Функция для очистки старых бекапов
clean_old_backups() {
    echo "Cleaning old backups (older than $RETENTION_DAYS days)..."
    find $BACKUP_DIR -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;
}

# Резервное копирование PostgreSQL из Kubernetes
backup_postgresql() {
    echo "Starting PostgreSQL backup..."
    
    # Получаем имя пода PostgreSQL
    PG_POD_NAME=$(kubectl get pods -l app=digit-postgres -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$PG_POD_NAME" ]; then
        echo "ERROR: Cannot find PostgreSQL pod"
        return 1
    fi
    
    # Получаем список всех баз данных
    DATABASES=$(kubectl exec $PG_POD_NAME -- psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres');")
    
    for DB in $DATABASES; do
        echo "Backing up database: $DB"
        BACKUP_FILE="$BACKUP_DIR/$DATE/postgres_${DB}_${DATE}.sql.gz"
        kubectl exec $PG_POD_NAME -- pg_dump -U postgres $DB | gzip > $BACKUP_FILE
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "ERROR: Failed to backup PostgreSQL database $DB"
        else
            echo "Successfully backed up PostgreSQL database $DB to $BACKUP_FILE"
        fi
    done
}

# Резервное копирование Cassandra из Kubernetes
backup_cassandra() {
    echo "Starting Cassandra backup..."
    
    # Получаем имя пода Cassandra
    CASSANDRA_POD_NAME=$(kubectl get pods -l app=digit-cassandra -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$CASSANDRA_POD_NAME" ]; then
        echo "ERROR: Cannot find Cassandra pod"
        return 1
    fi
    
    # Создаем snapshot
    echo "Creating Cassandra snapshot..."
    kubectl exec $CASSANDRA_POD_NAME -- nodetool -u cassandra -pw cassandra snapshot -t $DATE
    
    # Копируем файлы снапшотов
    echo "Copying Cassandra snapshots..."
    SNAPSHOT_DIR="$BACKUP_DIR/$DATE/cassandra_snapshot_$DATE"
    mkdir -p "$SNAPSHOT_DIR"
    
    # Получаем список keyspaces
    KEYSPACES=$(kubectl exec $CASSANDRA_POD_NAME -- ls /var/lib/cassandra/data)
    
    for KEYSPACE in $KEYSPACES; do
        # Пропускаем системные keyspaces
        if [[ "$KEYSPACE" == "system"* ]]; then
            continue
        fi
        
        echo "Processing keyspace: $KEYSPACE"
        KEYSPACE_DIR="$SNAPSHOT_DIR/$KEYSPACE"
        mkdir -p "$KEYSPACE_DIR"
        
        # Получаем список таблиц в keyspace
        TABLES=$(kubectl exec $CASSANDRA_POD_NAME -- ls "/var/lib/cassandra/data/$KEYSPACE")
        
        for TABLE in $TABLES; do
            # Убираем UUID из имени таблицы
            CLEAN_TABLE_NAME=$(echo "$TABLE" | cut -d'-' -f1)
            echo "Copying snapshot for table: $CLEAN_TABLE_NAME"
            
            # Копируем файлы снапшота
            kubectl exec $CASSANDRA_POD_NAME -- sh -c "cp -r /var/lib/cassandra/data/$KEYSPACE/$TABLE/snapshots/$DATE/ $KEYSPACE_DIR/$CLEAN_TABLE_NAME/"
        done
    done
    
    # Архивируем снапшоты
    echo "Archiving Cassandra snapshots..."
    tar -czf "$BACKUP_DIR/$DATE/cassandra_snapshot_$DATE.tar.gz" -C "$SNAPSHOT_DIR" .
    rm -rf "$SNAPSHOT_DIR"
    
    # Очищаем снапшоты
    echo "Cleaning up Cassandra snapshots..."
    kubectl exec $CASSANDRA_POD_NAME -- nodetool -u cassandra -pw cassandra clearsnapshot -t $DATE
}

# Синхронизация с резервным сервером
sync_to_backup_server() {
    echo "Starting sync to backup server..."
    rsync -avz --delete $BACKUP_DIR/ $RSYNC_USER@$BACKUP_SERVER:$BACKUP_REMOTE_DIR/
    if [ $? -eq 0 ]; then
        echo "Successfully synced backups to $BACKUP_SERVER"
    else
        echo "ERROR: Failed to sync backups to $BACKUP_SERVER"
        return 1
    fi
}

# Создаем директорию для бекапов
mkdir -p $BACKUP_DIR/$DATE

# Выполняем бекапы
backup_postgresql
backup_cassandra

# Синхронизируем с резервным сервером
sync_to_backup_server

# Очищаем старые бекапы
clean_old_backups

echo "=============================================="
echo "Backup completed at $(date)"
echo "=============================================="