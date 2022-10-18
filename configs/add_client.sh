#!/bin/bash
# ===========================================================================
# Скрипт позволяет добавить клиента к серверу
# ===========================================================================

# ===========================================================================
# Проверка запуска от имени суперпользователя
# ===========================================================================
if [[ $(id -u) -ne 0 ]] ; then echo "Необходимо запустить от имени суперпользователя" ; exit 1 ; fi
# ===========================================================================

# ===========================================================================
# Переменные для работы скрипта
# ===========================================================================
IP_NETWORK="10.101.0."
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
KEYS_DIR=$(cd $SCRIPT_PATH/../clients ; pwd -P)
ROOT_DIR=$(cd $SCRIPT_PATH/.. ; pwd -P)
DEFAULT_SERVER_FILE=$ROOT_DIR/wg0.conf.default
SERVER_DIR="/etc/wireguard"
SERVER_IP="IP_REMOTE_SERVER"
# ===========================================================================

# ===========================================================================
# Функция вывода на печать списка клиентов
# ===========================================================================
print_list_clients() {
    cat $SCRIPT_PATH/client_list.csv | awk -F, 'BEGIN {
        print "-------------------------------------------"
        printf "%-25s | %-16s\n", "UserName", "IP Address" 
        printf "%-25s | %-16s\n", "-------------------------", "---------------" 
    } NR!=1  {
        printf "%-25s | %-16s\n", $1, $2
    }'
}
# ===========================================================================

# ===========================================================================
# Создание нового клиента
# ===========================================================================
echo "Список зарегистрированных клиентов:"
print_list_clients
read -p "Введите имя нового клиента (без пробелов):" USERNAME
read -p "Введите последний разряд IP адреса (1-255):" LAST_IP_ADDR
LAST_IP_ADDR=$IP_NETWORK$LAST_IP_ADDR
SAVE=1
read -p "Будет создан клиент $USERNAME ($LAST_IP_ADDR)? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || SAVE=0
if [[ $SAVE -eq 1 ]]; then
    echo "$USERNAME,$LAST_IP_ADDR" >> $SCRIPT_PATH/client_list.csv
    echo "Новый список:"
    print_list_clients
fi
# ===========================================================================

# ===========================================================================
# Создание файла конфигурации сервера
# ===========================================================================
cat $SCRIPT_PATH/client_list.csv | awk -F,  -v keys_dir=$KEYS_DIR \
                                            -v config_server_file="$DEFAULT_SERVER_FILE" \
                                            'BEGIN {
    print "# Общая конфигурация сервера"
    while(( getline line < config_server_file) > 0 ) {
        print line
    }
    print ""
    print "# Настройки клиентов"
} NR!=1  {
    # Задание имен для новых ключей
    private_key_file = keys_dir "/" $1 "_privatekey"
    public_key_file = keys_dir "/" $1 "_publickey"
    # Генерация ключей
    if ((getline key < public_key_file) < 0 ) {
        system("wg genkey | tee " private_key_file " | wg pubkey | tee " public_key_file " > /dev/null")
    }
    # Cоздание конфигурации для клиента
    getline key < public_key_file
    print "# Настройка для " $1
    print "[Peer]"
    print "PublicKey = " key
    print "AllowedIPs = " $2 "/32"
    print ""
}' | tee $ROOT_DIR/wg0.conf
echo "Конфигурация успешно сохранена"
# ===========================================================================

# ===========================================================================
# Создание конфигурационных файлов для клиентов
# ===========================================================================
rm $SCRIPT_PATH/*.conf > /dev/null
echo ""
echo "======================================================================"
echo "Создание новых конфигураций для клиентов"
echo "======================================================================"
cat $SCRIPT_PATH/client_list.csv | awk -F,  -v keys_dir=$KEYS_DIR \
                                            -v config_dir=$SCRIPT_PATH \
                                            -v server_dir=$SERVER_DIR \
                                            -v server_ip=$SERVER_IP \
                                            'NR != 1 {
    client_private_file = keys_dir "/" $1 "_privatekey"
    getline client_private_key < client_private_file
    server_public_file = server_dir "/publickey"
    getline server_public_key < server_public_file
    print "# Настройка для " $1 > $1 ".conf"
    print "[Interface]" >> $1 ".conf"
    print "PrivateKey = " client_private_key >> $1 ".conf"
    print "Address = " $2 "/32" >> $1 ".conf"
    print "DNS = 8.8.8.8" >> $1 ".conf"
    print "" >> $1 ".conf"
    print "[Peer]" >> $1 ".conf"
    print "PublicKey = " server_public_key >> $1 ".conf"
    print "Endpoint = " server_ip ":51830" >> $1 ".conf"
    print "AllowedIPs = 0.0.0.0/0" >> $1 ".conf"
    print "PersistentKeepalive = 20" >> $1 ".conf"
    client_config_file = config_dir "/" $1 ".conf"
    print "Конфигурация для " $1 " сохранена в файле " client_config_file
}'
# ===========================================================================

# ===========================================================================
# Перезапуск служб и завершение настройки
# ===========================================================================
echo "Перезапуск службы Wirguard"
systemctl restart wg-quick@wg0.service
systemctl status wg-quick@wg0.service
# ===========================================================================
