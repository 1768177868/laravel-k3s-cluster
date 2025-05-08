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

# 清理临时编译依赖（减小镜像体积）
# RUN apk del autoconf build-base

# 配置 Nginx
COPY manifests/nginx.conf /etc/nginx/nginx.conf

# 配置时区（根据需求修改）
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 复制项目代码
COPY . /var/www/html


# 创建必要的基础目录结构（保留父目录）
RUN mkdir -p /var/www/html/storage/{framework/{views,cache,sessions,testing},app/{private,public},logs} \
    && ln -sfn storage/app/public public/storage \
    && chmod +x /var/www/html/artisan \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html/storage \
    && chmod -R 755 /var/www/html/bootstrap/cache

# 安装 Composer 依赖
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN composer update --with-all-dependencies --no-interaction --no-dev --optimize-autoloader

# 单独安装 Faker
RUN composer require fakerphp/faker

# 更新 Composer 自动加载器
RUN composer dump-autoload --optimize

# 配置 Supervisor
COPY manifests/supervisord.conf /etc/supervisor/supervisord.conf

EXPOSE 80 9000

CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]