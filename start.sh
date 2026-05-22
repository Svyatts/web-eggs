#!/bin/sh
# start.sh — должен лежать в /home/container/start.sh
# Применяет переменные окружения DOMAIN, PROXY_MODE, TRUSTED_PROXIES, FORCE_HTTPS
# к шаблонам nginx перед запуском сервера.

set -e

CONF_DIR="/home/container/nginx/conf.d"
CONF_FILE="${CONF_DIR}/default.conf"
SNIPPET_PROXY="${CONF_DIR}/proxy-realip.conf"

# ---- 1. server_name -----------------------------------------------------------
# Если DOMAIN не задан — слушаем любой Host. Если задан — ограничиваем.
if [ -n "${DOMAIN}" ]; then
    SERVER_NAME_LINE="server_name ${DOMAIN};"
else
    SERVER_NAME_LINE="server_name _;"
fi

# Заменяем строку server_name в основном конфиге.
# В шаблоне default.conf должна быть строка-плейсхолдер: server_name __PLACEHOLDER__;
sed -i "s|server_name .*;|${SERVER_NAME_LINE}|" "${CONF_FILE}"

# ---- 2. Режим работы за прокси -----------------------------------------------
if [ "${PROXY_MODE}" = "1" ] || [ "${PROXY_MODE}" = "true" ]; then
    echo "[start.sh] Режим: за реверс-прокси"

    # Генерим snippet с real_ip_from для каждого доверенного CIDR
    {
        echo "# Автоматически сгенерировано start.sh"
        if [ -n "${TRUSTED_PROXIES}" ]; then
            for cidr in ${TRUSTED_PROXIES}; do
                echo "set_real_ip_from ${cidr};"
            done
        else
            echo "set_real_ip_from 172.16.0.0/12;"
        fi
        echo "real_ip_header X-Forwarded-For;"
        echo "real_ip_recursive on;"
        echo ""
        echo "# Передаём в PHP-FPM реальную схему и IP клиента"
        echo "fastcgi_param HTTP_X_FORWARDED_FOR  \$proxy_add_x_forwarded_for;"

        if [ "${FORCE_HTTPS}" = "1" ] || [ "${FORCE_HTTPS}" = "true" ]; then
            echo "fastcgi_param HTTPS              on;"
            echo "fastcgi_param HTTP_X_FORWARDED_PROTO https;"
        else
            echo "fastcgi_param HTTP_X_FORWARDED_PROTO \$http_x_forwarded_proto;"
        fi
    } > "${SNIPPET_PROXY}"

else
    echo "[start.sh] Режим: прямой доступ по IP:порту"
    # На случай если snippet остался от предыдущего запуска — обнуляем
    : > "${SNIPPET_PROXY}"
fi

# ---- 3. Запуск ---------------------------------------------------------------
echo "[start.sh] Запуск PHP-FPM..."
php-fpm -D

echo "[start.sh] Запуск Nginx..."
exec nginx -g 'daemon off;'
