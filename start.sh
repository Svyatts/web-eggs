#!/bin/sh
# start.sh — лежит в /home/container/start.sh
# Применяет переменные DOMAIN, PROXY_MODE, TRUSTED_PROXIES, FORCE_HTTPS
# к шаблонам nginx и запускает PHP-FPM + Nginx.

set -e

CONF_DIR="/home/container/nginx/conf.d"
CONF_FILE="${CONF_DIR}/default.conf"
SNIPPET_PROXY="${CONF_DIR}/proxy-realip.conf"

# ---- 1. server_name ----------------------------------------------------------
if [ -n "${DOMAIN}" ]; then
    SERVER_NAME_LINE="server_name ${DOMAIN};"
else
    SERVER_NAME_LINE="server_name _;"
fi

# В default.conf должна быть строка-плейсхолдер: server_name __PLACEHOLDER__;
# (или любая другая server_name — sed заменит первую попавшуюся)
if [ -f "${CONF_FILE}" ]; then
    sed -i "s|server_name .*;|${SERVER_NAME_LINE}|" "${CONF_FILE}"
fi

# ---- 2. Режим работы за прокси ----------------------------------------------
if [ "${PROXY_MODE}" = "1" ] || [ "${PROXY_MODE}" = "true" ]; then
    echo "[start.sh] Режим: за реверс-прокси"

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
    : > "${SNIPPET_PROXY}"
fi

# ---- 3. Поиск бинарника PHP-FPM ---------------------------------------------
# В образе бинарник называется php-fpm8 (общий симлинк, не зависит от подверсии)
PHPFPM_BIN=""
for candidate in /usr/sbin/php-fpm8 /usr/sbin/php-fpm84 /usr/sbin/php-fpm83 \
                 /usr/sbin/php-fpm82 /usr/sbin/php-fpm81 /usr/sbin/php-fpm80 \
                 /usr/local/sbin/php-fpm /usr/sbin/php-fpm; do
    if [ -x "${candidate}" ]; then
        PHPFPM_BIN="${candidate}"
        break
    fi
done

if [ -z "${PHPFPM_BIN}" ]; then
    echo "[start.sh] ОШИБКА: PHP-FPM не найден ни в /usr/sbin/php-fpm8x, ни в /usr/local/sbin/"
    echo "[start.sh] Содержимое /usr/sbin/:"
    ls -la /usr/sbin/ | grep -i php || true
    exit 1
fi

# ---- 4. Запуск PHP-FPM -------------------------------------------------------
echo "[start.sh] Запуск PHP-FPM (${PHPFPM_BIN})..."
if "${PHPFPM_BIN}" --fpm-config /home/container/php-fpm/php-fpm.conf --daemonize; then
    echo "[start.sh] PHP-FPM запущен."
else
    echo "[start.sh] ОШИБКА: не удалось запустить PHP-FPM."
    exit 1
fi

# ---- 5. Запуск Nginx ---------------------------------------------------------
echo "[start.sh] Запуск Nginx..."
echo "[УСПЕХ] Веб-сервер запущен. Все сервисы успешно стартовали."
exec /usr/sbin/nginx -c /home/container/nginx/nginx.conf -p /home/container/
