# 开发包使用统一名称，ODBC 能力按平台区分

为限制编译与交付数量，两条 PHP 线在三个平台各保留 MySQL、PostgreSQL、ODBC 线上包及开发包，合计 24 个运行时。用户确认 macOS 保留独立 ODBC 线上包，而统一命名为 `sqlite-mysql-pgsql` 的开发包仅在 Linux 增加 ODBC，macOS 开发包无需 unixODBC；因此包名表示用途，精确 PDO 集合与 ODBC 状态必须按平台核验，不能从开发包后缀推断。
