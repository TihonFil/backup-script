#!/bin/sh

# Задаем пути к бэкапам, файлам и к сайту
SITE_CORE=
SITE=
SERVER_BACKUP=
STAGE=
BACKUP_DIR=
BACKUP_DIR_SERVER=
BACKUP_DIR_STAGE=
DB_NAME=
HOST_NAME=
WEEKLY_DIR=$BACKUP_DIR_SERVER
MONTHLY_DIR=$BACKUP_DIR_SERVER
QUARTERLY_DIR=$BACKUP_DIR_SERVER
DB_FULL_FILE=full_backupdb_$(date +%Y-%m-%d_%H_%M_%S).dump
DB_INCR_FILE=incr_backupdb_$(date +%Y-%m-%d_%H_%M_%S).dump
SITE_FULL_FILE=full_site_$(date +%Y-%m-%d_%H_%M_%S).tar
SITE_INCR_FILE=incr_site_$(date +%Y-%m-%d_%H_%M_%S).tar

DAY_OF_WEEK=$(date +%a)

# Обновляем конфиги, БД и чистим кеш на сайте
echo "### drush ###"
cd $SITE_CORE && vendor/bin/drush cex -y && vendor/bin/drush updb -y && vendor/bin/drush cr

# Полный бэкап в субботу (Понедельник - Mon Вторник - Tue Среда - Wed Четверг - Thu Пятница - Fri Суббота - Sat Воскресенье - Sun)
if [ $DAY_OF_WEEK = "Sat" ]; then

  # Проверяем, существует ли уже полный бэкап
  if test -n "$(find $BACKUP_DIR -maxdepth 1 -type f -name 'full_backupdb_*' -o -name 'full_site_*' -print -quit)"; then
    echo "Full backup already exists. Removing old full backups..."
    rm "$BACKUP_DIR"/full_backupdb_* "$BACKUP_DIR"/full_site_*
    rm "$BACKUP_DIR"/db_snapshot "$BACKUP_DIR"/site_snapshot
  fi

  echo "### Full backup ###"
  pg_dump -Fc $DB_NAME > $BACKUP_DIR/$DB_FULL_FILE  
  cd $SITE_CORE && tar --listed-incremental=$BACKUP_DIR/site_snapshot -cf $BACKUP_DIR/$SITE_FULL_FILE *
  touch $BACKUP_DIR/db_snapshot

  # Удалить все инкрементные резервные копии, если создается полная резервная копия
  find $BACKUP_DIR -type f -name 'incr_backupdb_*' -delete
  find $BACKUP_DIR -type f -name 'incr_site_*' -delete
  
  # Перемещаем полную резервную копию
  echo "### scp full backup ###"
  scp $BACKUP_DIR/full_backupdb_* $SERVER_BACKUP:$WEEKLY_DIR/
  scp $BACKUP_DIR/full_site_* $SERVER_BACKUP:$WEEKLY_DIR/
  
  scp $BACKUP_DIR/full_backupdb_* $STAGE:$BACKUP_DIR_STAGE/
  scp $BACKUP_DIR/full_site_* $STAGE:$BACKUP_DIR_STAGE/
  
else
  # Инкрементальное резервное копирование в другие дни
  echo "### Incr backup ###"
  if [ -f $BACKUP_DIR/db_snapshot ]; then
    pg_dump -Fc $DB_NAME --file=$BACKUP_DIR/$DB_INCR_FILE --create --format=custom --compress=9 -F c
    cd $SITE_CORE && tar --listed-incremental=$BACKUP_DIR/site_snapshot -cf $BACKUP_DIR/$SITE_INCR_FILE *
  fi
fi

# Копировать резервные копии за месяц
if [ -f "$BACKUP_DIR/full_backupdb_"* ] && [ -f "$BACKUP_DIR/full_site_"* ]; then
  if [ "$(date +%V)" = "$(date -d "$(date -d '-1 day' +%Y-%m-01) + 7 day" +%V)" ]; then
    scp $BACKUP_DIR/full_backupdb_* $SERVER_BACKUP:$MONTHLY_DIR/
    scp $BACKUP_DIR/full_site_* $SERVER_BACKUP:$MONTHLY_DIR/
  fi
else
  echo "One or both backup files do not exist in $BACKUP_DIR"
fi


# Копировать ежеквартальные резервные копии
if [ -f "$BACKUP_DIR/full_backupdb_"* ] && [ -f "$BACKUP_DIR/full_site_"* ]; then
  current_month=$(date '+%m')
  current_year=$(date '+%Y')
  case $current_month in
    01|04|07|10)
      first_week=$(date -d "$(echo $current_month)/01/$current_year" '+%U')
      if [ "$(date '+%U')" -eq "$first_week" ]; then
        scp "$BACKUP_DIR/full_backupdb_"* "$SERVER_BACKUP:$QUARTERLY_DIR/"
        scp "$BACKUP_DIR/full_site_"* "$SERVER_BACKUP:$QUARTERLY_DIR/"
      fi
      ;;
    *)
      ;;
  esac
else
  echo "One or both backup files do not exist in $BACKUP_DIR"
fi

# Удалить резервные копии на стейдже, старше 7 дней
ssh $STAGE "find $BACKUP_DIR_STAGE -type f -name 'full_backupdb_*' -mtime +7 -delete"
ssh $STAGE "find $BACKUP_DIR_STAGE -type f -name 'full_site_*' -mtime +7 -delete"

# Удалить резервные копии на сервере с бэкапами, старше 30 дней
ssh $SERVER_BACKUP "find $WEEKLY_DIR -type f -name 'full_backupdb_*' -mtime +30 -delete"
ssh $SERVER_BACKUP "find $WEEKLY_DIR -type f -name 'full_site_*' -mtime +30 -delete"

# Удалить резервные копии на сервере с бэкапами, старше 90 дней
ssh $SERVER_BACKUP "find $MONTHLY_DIR -type f -name 'full_backupdb_*' -mtime +90 -delete"
ssh $SERVER_BACKUP "find $MONTHLY_DIR -type f -name 'full_site_*' -mtime +90 -delete"

# Удалить резервные копии на сервере с бэкапами, старше 365 дней
ssh $SERVER_BACKUP "find $QUARTERLY_DIR -type f -name 'full_backupdb_*' -mtime +365 -delete"
ssh $SERVER_BACKUP "find $QUARTERLY_DIR -type f -name 'full_site_*' -mtime +365 -delete"

