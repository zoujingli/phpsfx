<?php

declare(strict_types=1);

function redactOdbcError(string $message, array $secrets): string
{
    foreach ($secrets as $secret) {
        if (is_string($secret) && $secret !== '') {
            $message = str_replace($secret, '[REDACTED]', $message);
        }
    }

    return (string) preg_replace('/(?i)(pwd|password)\s*=\s*[^;\s]+/', '$1=[REDACTED]', $message);
}

$dsn = getenv('PHPSFX_DM_ODBC_DSN') ?: '';
$user = getenv('PHPSFX_DM_ODBC_USER') ?: '';
$password = getenv('PHPSFX_DM_ODBC_PASSWORD') ?: '';
$allowWrite = (getenv('PHPSFX_DM_ODBC_ALLOW_WRITE') ?: '0') === '1';
$result = [
    'status' => 'error',
    'pdo_driver' => null,
    'dameng_server' => false,
    'read_probe' => false,
    'write_tests' => $allowWrite ? 'failed' : 'skipped',
    'unicode' => false,
    'number' => false,
    'timestamp' => false,
    'rollback' => false,
    'commit' => false,
    'error_propagation' => false,
    'concurrent_connections' => false,
];
$failure = null;

try {
    if (!in_array('odbc', PDO::getAvailableDrivers(), true)) {
        throw new RuntimeException('PDO ODBC driver is not available');
    }
    if (!defined('SWOOLE_HOOK_PDO_ODBC')) {
        throw new RuntimeException('Swoole PDO ODBC coroutine hook is not available');
    }

    Swoole\Runtime::enableCoroutine(
        Swoole\Runtime::getHookFlags() | SWOOLE_HOOK_PDO_ODBC
    );
    Swoole\Coroutine\run(static function () use (
        &$failure,
        &$result,
        $allowWrite,
        $dsn,
        $password,
        $user
    ): void {
        $pdo = null;
        $tableCreated = false;
        $table = 'PHPSFX_ODBC_' . strtoupper(bin2hex(random_bytes(4)));
        $connect = static fn (): PDO => new PDO(
            $dsn,
            $user,
            $password,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );

        try {
            $pdo = $connect();
            $result['pdo_driver'] = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME);
            $result['read_probe'] = (string) $pdo->query('SELECT 1')->fetchColumn() === '1';
            if (!$result['read_probe']) {
                throw new RuntimeException('Dameng read probe returned an unexpected value');
            }

            $serverIdentity = $pdo->query('SELECT ID_CODE()')->fetchColumn();
            $result['dameng_server'] = is_string($serverIdentity) && $serverIdentity !== '';
            if (!$result['dameng_server']) {
                throw new RuntimeException('Dameng server identity probe returned an unexpected value');
            }

            if (!$allowWrite) {
                $result['status'] = 'ok';
                return;
            }

            $pdo->exec(sprintf(
                'CREATE TABLE %s (id INTEGER NOT NULL PRIMARY KEY, text_value VARCHAR(255), number_value DECIMAL(18,2), time_value TIMESTAMP)',
                $table
            ));
            $tableCreated = true;

            $insert = $pdo->prepare(sprintf(
                'INSERT INTO %s (id, text_value, number_value, time_value) VALUES (?, ?, ?, ?)',
                $table
            ));
            $insert->execute([1, '达梦-ODBC', '12345.67', '2026-08-15 12:34:56']);

            $select = $pdo->prepare(sprintf(
                'SELECT text_value, number_value, time_value FROM %s WHERE id = ?',
                $table
            ));
            $select->execute([1]);
            $row = $select->fetch(PDO::FETCH_NUM);
            $result['unicode'] = is_array($row) && ($row[0] ?? null) === '达梦-ODBC';
            $result['number'] = is_array($row) && bccomp((string) ($row[1] ?? ''), '12345.67', 2) === 0;
            $result['timestamp'] = is_array($row)
                && str_starts_with((string) ($row[2] ?? ''), '2026-08-15 12:34:56');

            $pdo->beginTransaction();
            $insert->execute([2, 'rollback', '2.00', '2026-08-15 12:35:00']);
            $pdo->rollBack();
            $result['rollback'] = (int) $pdo->query(sprintf('SELECT COUNT(*) FROM %s', $table))->fetchColumn() === 1;

            $pdo->beginTransaction();
            $insert->execute([3, 'commit', '3.00', '2026-08-15 12:36:00']);
            $pdo->commit();
            $result['commit'] = (int) $pdo->query(sprintf('SELECT COUNT(*) FROM %s', $table))->fetchColumn() === 2;

            try {
                $pdo->query(sprintf('SELECT * FROM %s_MISSING', $table));
            } catch (PDOException) {
                $result['error_propagation'] = true;
            }

            $channel = new Swoole\Coroutine\Channel(2);
            for ($index = 0; $index < 2; ++$index) {
                Swoole\Coroutine::create(static function () use ($channel, $connect, $table): void {
                    try {
                        $connection = $connect();
                        $count = (int) $connection->query(sprintf('SELECT COUNT(*) FROM %s', $table))->fetchColumn();
                        $channel->push($count === 2);
                    } catch (Throwable) {
                        $channel->push(false);
                    }
                });
            }
            $result['concurrent_connections'] = $channel->pop(15) === true && $channel->pop(15) === true;

            foreach (['unicode', 'number', 'timestamp', 'rollback', 'commit', 'error_propagation', 'concurrent_connections'] as $check) {
                if ($result[$check] !== true) {
                    throw new RuntimeException(sprintf('Dameng ODBC check failed: %s', $check));
                }
            }

            $result['write_tests'] = 'passed';
            $result['status'] = 'ok';
        } catch (Throwable $throwable) {
            $failure = $throwable;
        } finally {
            if ($tableCreated && $pdo instanceof PDO) {
                try {
                    $pdo->exec(sprintf('DROP TABLE %s', $table));
                } catch (Throwable $cleanupError) {
                    if ($failure === null) {
                        $failure = $cleanupError;
                    }
                }
            }
        }
    });

    if ($failure instanceof Throwable) {
        throw $failure;
    }
} catch (Throwable $throwable) {
    $result['status'] = 'error';
    if ($allowWrite) {
        $result['write_tests'] = 'failed';
    }
    fwrite(STDERR, redactOdbcError($throwable->getMessage(), [$dsn, $user, $password]) . PHP_EOL);
    echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
    exit(1);
}

echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
