<?php

declare(strict_types=1);

use Hyperf\Coroutine\Coroutine;
use Hyperf\HttpServer\Router\Router;

Router::get('/health', static function (): string {
    try {
        $pdo = new PDO('sqlite::memory:', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        $pdo->exec('CREATE TABLE smoke (value TEXT NOT NULL)');
        $pdo->exec("INSERT INTO smoke (value) VALUES ('ok')");

        $odbcResult = null;
        $odbcDsn = getenv('PHPSFX_ODBC_SMOKE_DSN') ?: '';
        if ($odbcDsn !== '') {
            Swoole\Runtime::enableCoroutine(
                Swoole\Runtime::getHookFlags() | SWOOLE_HOOK_PDO_ODBC
            );
            $odbcUser = getenv('PHPSFX_ODBC_SMOKE_USER') ?: '';
            $odbcPassword = getenv('PHPSFX_ODBC_SMOKE_PASSWORD') ?: '';
            $connect = static fn (): PDO => new PDO(
                $odbcDsn,
                $odbcUser,
                $odbcPassword,
                [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
            );

            $odbc = $connect();
            $odbcTable = 'phpsfx_odbc_' . bin2hex(random_bytes(4));
            $odbcTableCreated = false;
            try {
                $odbc->exec(sprintf(
                    'CREATE TABLE %s (id INTEGER PRIMARY KEY, value VARCHAR(255) NOT NULL)',
                    $odbcTable
                ));
                $odbcTableCreated = true;
                $insert = $odbc->prepare(sprintf('INSERT INTO %s (id, value) VALUES (?, ?)', $odbcTable));
                $insert->execute([1, '标准-ODBC']);

                $odbc->beginTransaction();
                $insert->execute([2, 'rollback']);
                $odbc->rollBack();
                $rollbackCount = (int) $odbc->query(sprintf('SELECT COUNT(*) FROM %s', $odbcTable))->fetchColumn();

                $odbc->beginTransaction();
                $insert->execute([3, 'commit']);
                $odbc->commit();
                $commitCount = (int) $odbc->query(sprintf('SELECT COUNT(*) FROM %s', $odbcTable))->fetchColumn();

                $channel = new Swoole\Coroutine\Channel(2);
                for ($index = 0; $index < 2; ++$index) {
                    Swoole\Coroutine::create(static function () use ($channel, $connect, $odbcTable): void {
                        try {
                            $connection = $connect();
                            $statement = $connection->prepare(sprintf('SELECT value FROM %s WHERE id = ?', $odbcTable));
                            $statement->execute([1]);
                            $channel->push(['value' => $statement->fetchColumn()]);
                        } catch (Throwable $throwable) {
                            $channel->push(['error' => $throwable->getMessage()]);
                        }
                    });
                }

                $concurrentValues = [];
                for ($index = 0; $index < 2; ++$index) {
                    $concurrentResult = $channel->pop(10);
                    if (!is_array($concurrentResult) || isset($concurrentResult['error'])) {
                        throw new RuntimeException('Concurrent ODBC query failed');
                    }
                    $concurrentValues[] = $concurrentResult['value'] ?? null;
                }

                $odbcResult = [
                    'driver' => $odbc->getAttribute(PDO::ATTR_DRIVER_NAME),
                    'value' => $odbc->query(sprintf('SELECT value FROM %s WHERE id = 1', $odbcTable))->fetchColumn(),
                    'rollback_count' => $rollbackCount,
                    'commit_count' => $commitCount,
                    'concurrent_values' => $concurrentValues,
                ];
            } finally {
                if ($odbcTableCreated) {
                    $odbc->exec(sprintf('DROP TABLE %s', $odbcTable));
                }
            }
        }

        $result = [
            'status' => 'ok',
            'swoole_version' => SWOOLE_VERSION,
            'coroutine_id' => Coroutine::id(),
            'pdo_sqlite' => $pdo->query('SELECT value FROM smoke')->fetchColumn(),
            'pdo_odbc' => $odbcResult,
        ];
    } catch (Throwable $throwable) {
        $error = $throwable->getMessage();
        foreach ([
            getenv('PHPSFX_ODBC_SMOKE_DSN'),
            getenv('PHPSFX_ODBC_SMOKE_USER'),
            getenv('PHPSFX_ODBC_SMOKE_PASSWORD'),
        ] as $secret) {
            if (is_string($secret) && $secret !== '') {
                $error = str_replace($secret, '[REDACTED]', $error);
            }
        }
        $result = [
            'status' => 'error',
            'swoole_version' => SWOOLE_VERSION,
            'coroutine_id' => Coroutine::id(),
            'pdo_sqlite' => null,
            'pdo_odbc' => null,
            'error' => preg_replace('/(?i)(pwd|password)\s*=\s*[^;\s]+/', '$1=[REDACTED]', $error),
        ];
    }

    return json_encode($result, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
});
