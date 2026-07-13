<?php

declare(strict_types=1);

use Hyperf\Coroutine\Coroutine;
use Hyperf\HttpServer\Router\Router;

Router::get('/health', static function (): string {
    try {
        $pdo = new PDO('sqlite::memory:', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        $pdo->exec('CREATE TABLE smoke (value TEXT NOT NULL)');
        $pdo->exec("INSERT INTO smoke (value) VALUES ('ok')");

        $result = [
            'status' => 'ok',
            'swoole_version' => SWOOLE_VERSION,
            'coroutine_id' => Coroutine::id(),
            'pdo_sqlite' => $pdo->query('SELECT value FROM smoke')->fetchColumn(),
        ];
    } catch (Throwable $throwable) {
        $result = [
            'status' => 'error',
            'swoole_version' => SWOOLE_VERSION,
            'coroutine_id' => Coroutine::id(),
            'pdo_sqlite' => null,
            'error' => $throwable->getMessage(),
        ];
    }

    return json_encode($result, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
});
