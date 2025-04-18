FROM php:8.2-fpm-alpine

# 安装基础依赖
RUN apk add --no-cache \
    autoconf \
    build-base \
    curl \
    libzip-dev \
    zlib-dev \
    nginx \
    supervisor \
    git

# 安装 PHP 扩展
RUN docker-php-ext-install pdo_mysql zip pcntl

# 配置 Nginx
COPY k8s/nginx.conf /etc/nginx/nginx.conf

# 复制项目代码
COPY . /var/www/html


# 创建必要的基础目录结构（保留父目录）
RUN mkdir -p /var/www/html/storage/{framework/{views,cache,sessions,testing},app/{private,public},logs} \
    && ln -sfn storage/app/public public/storage \
    && chmod +x /var/www/html/artisan \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 775 /var/www/html/storage \
    && chmod -R 775 /var/www/html/bootstrap/cache

# 安装 Composer 依赖
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN composer install --no-interaction --no-dev --optimize-autoloader

# 配置 Supervisor
COPY k8s/supervisord.conf /etc/supervisor/supervisord.conf

EXPOSE 80 9000

CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]