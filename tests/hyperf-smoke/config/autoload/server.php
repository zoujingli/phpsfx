<?php

declare(strict_types=1);

use Hyperf\Framework\Bootstrap\ServerStartCallback;
use Hyperf\Framework\Bootstrap\WorkerExitCallback;
use Hyperf\Framework\Bootstrap\WorkerStartCallback;
use Hyperf\HttpServer\Server as HttpServer;
use Hyperf\Server\Event;
use Hyperf\Server\Server;
use Hyperf\Server\ServerInterface;

return [
    'type' => Server::class,
    'mode' => SWOOLE_BASE,
    'servers' => [
        [
            'name' => 'http',
            'type' => ServerInterface::SERVER_HTTP,
            'host' => '127.0.0.1',
            'port' => (int) (getenv('PHPSFX_HYPERF_SMOKE_PORT') ?: 19501),
            'sock_type' => SWOOLE_SOCK_TCP,
            'callbacks' => [
                Event::ON_REQUEST => [HttpServer::class, 'onRequest'],
            ],
        ],
    ],
    'settings' => [
        'enable_coroutine' => true,
        'worker_num' => 1,
        'max_request' => 10,
        'max_coroutine' => 100,
        'pid_file' => BASE_PATH . '/runtime/hyperf.pid',
    ],
    'callbacks' => [
        Event::ON_BEFORE_START => [ServerStartCallback::class, 'beforeStart'],
        Event::ON_WORKER_START => [WorkerStartCallback::class, 'onWorkerStart'],
        Event::ON_WORKER_EXIT => [WorkerExitCallback::class, 'onWorkerExit'],
    ],
];
