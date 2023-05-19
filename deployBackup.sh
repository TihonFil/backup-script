#!/bin/sh

# Задаем пути к бэкапам и к сайту
BACKUP_DIR=
SITE_CORE=
DB_NAME=

# Ищем последний полный бэкап базы данных и сайта
LATEST_DB_BACKUP=$(ls -1t $BACKUP_DIR/full_backupdb_* | head -n 1)
LATEST_SITE_BACKUP=$(ls -1t $BACKUP_DIR/full_site_* | head -n 1)

# Удаляем все файли из директории сайта
chmod -R 777 $SITE_CORE/* && rm -rf $SITE_CORE/*

# Разархивируем бэкап базы данных и восстанавливаем базу данных
pg_restore -c -Fc -d $DB_NAME $LATEST_DB_BACKUP

# Разархивируем бэкап сайта и копируем его в корневую директорию сайта
tar -xf $LATEST_SITE_BACKUP -C $SITE_CORE

# Получить список инкрементальных бекапов, отсортированный по времени создания (от старых к новым)
INCREMENTAL_BACKUPS=$(ls -1tr $BACKUP_DIR/incr_backupdb_*)

# Проход по каждому инкрементальному бекапу
for backup_file in $INCREMENTAL_BACKUPS
do
    echo "Restoring backup $backup_file"

    # Восстановить базу данных из инкрементального бекапа
    pg_restore -c -Fc -d $DB_NAME $backup_file

    # Получить имя файла с бекапом сайта
    site_backup=$(echo $backup_file | sed 's/backupdb/site/g; s/\.dump/\.tar/g')

    # Восстановить сайт из инкрементального бекапа
    tar -xf $site_backup -C $SITE_CORE

    echo "Restore completed for $backup_file"
done

# Обновляем конфиги, БД и чистим кеш на сайте
echo "### drush ###"
cd $SITE_CORE && vendor/bin/drush cim -y && vendor/bin/drush updb -y && vendor/bin/drush cr

