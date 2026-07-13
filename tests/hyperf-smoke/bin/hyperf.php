#!/usr/bin/env php
<?php

declare(strict_types=1);

use Hyperf\Contract\ApplicationInterface;
use Hyperf\Di\ClassLoader;

defined('BASE_PATH') || define('BASE_PATH', dirname(__DIR__));
defined('SWOOLE_HOOK_FLAGS') || define('SWOOLE_HOOK_FLAGS', SWOOLE_HOOK_ALL);

require BASE_PATH . '/vendor/autoload.php';

ClassLoader::init();
$container = require BASE_PATH . '/config/container.php';
$container->get(ApplicationInterface::class)->run();
