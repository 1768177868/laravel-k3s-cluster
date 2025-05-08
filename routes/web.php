<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Http\Request;

Route::get('/', function (Request $request) {
    // 获取 Laravel 解析的真实 IP（已考虑代理）
    $clientIp = $request->ip();

    // 原始 $_SERVER 中的 REMOTE_ADDR（可能是代理 IP）
    $remoteAddr = $_SERVER['REMOTE_ADDR'] ?? '未知';

    // 解析 X-Forwarded-For 头（可能包含多个代理 IP）
    $xForwardedFor = $request->header('X-Forwarded-For') ?? '无';

    // 解析 Cloudflare 的 CF-Connecting-IP（如果使用 Cloudflare）
    $cfConnectingIp = $request->header('CF-Connecting-IP') ?? '无';

    // 输出信息到页面
    echo "<h2>客户端真实 IP 信息</h2>";
    echo "<p>真实 IP（Laravel 解析）: <strong>$clientIp</strong></p>";
    echo "<p>原始 REMOTE_ADDR（可能是代理 IP）: $remoteAddr</p>";
    echo "<p>X-Forwarded-For 头内容: $xForwardedFor</p>";
    echo "<p>Cloudflare CF-Connecting-IP: $cfConnectingIp</p>";


    echo "<pre>";
    print_r($_SERVER);

});