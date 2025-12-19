# Screenshots Documentation

本目录应包含以下运行时截图，作为项目功能的证据。

## 必需的截图

### 1. `server_start.png`
**说明**：显示服务器启动时的状态，包括：
- Master 进程和多个 Worker 进程的 PID
- 服务器日志输出（显示 workers 启动信息）
- 可以使用 `ps aux | grep server` 或 `htop` 显示进程树

**生成方法**：
```bash
# 启动服务器
./bin/server --port 9000 --workers 4

# 在另一个终端查看进程
ps aux | grep server

# 或使用 htop/pstree
pstree -p $(pgrep -f "bin/server" | head -1)
```

### 2. `client_stress.png`
**说明**：显示客户端压力测试运行，包括：
- 至少 100 个并发连接
- 测试统计输出（connections, threads, duration, total, ok, err, rps, p50/p95/p99）
- 可以使用 `netstat -an | grep :9000` 或 `ss -tn | grep :9000` 显示连接数

**生成方法**：
```bash
# 在一个终端运行服务器
./bin/server --port 9000 --workers 4

# 在另一个终端运行客户端
./bin/client --host 127.0.0.1 --port 9000 --connections 100 --threads 16 --duration 30 --mix mixed

# 同时查看连接数
watch -n 1 'ss -tn | grep :9000 | wc -l'
```

### 3. `metrics.png`
**说明**：显示性能指标，包括：
- p50/p95/p99 延迟数据
- 吞吐量 (req/s)
- 可以从 CSV 输出或客户端控制台输出中截取
- 也可以使用 gnuplot 生成的图表

**生成方法**：
```bash
# 运行测试并生成 CSV
./bin/client --host 127.0.0.1 --port 9000 --connections 100 --threads 16 --duration 60 --mix mixed --out results/test.csv

# 查看 CSV 内容
cat results/test.csv

# 或生成图表
gnuplot -c scripts/plot_latency.gp results/test.csv results/latency.png
gnuplot -c scripts/plot_throughput.gp results/test.csv results/throughput.png
```

### 4. `graceful_shutdown.png`
**说明**：显示优雅关闭过程，包括：
- 发送 SIGINT 信号
- 服务器日志显示 "Shutting down..."
- Workers 正常退出
- Shared memory 被清理（`ls /dev/shm/ns_trading_chat` 应该不存在）

**生成方法**：
```bash
# 启动服务器
./bin/server --port 9000 --workers 4

# 在另一个终端发送 SIGINT
kill -INT $(pgrep -f "bin/server" | head -1)

# 观察服务器日志输出
# 检查 shared memory 是否被清理
ls /dev/shm/ns_trading_chat  # 应该不存在
```

## 截图要求

- **格式**：PNG 或 JPEG
- **分辨率**：建议至少 1280x720，确保文字清晰可读
- **内容**：应包含足够的上下文信息（终端窗口、命令、输出等）
- **命名**：使用上述文件名

## 替代方案

如果无法生成实际截图，可以：
1. 提供终端输出的文本日志（保存为 `.txt` 文件）
2. 提供 CSV 数据文件作为证据
3. 在文档中说明截图生成步骤，供 TA/Instructor 验证

## 验证清单

- [ ] `server_start.png` - 显示多个 worker 进程
- [ ] `client_stress.png` - 显示 ≥100 并发连接
- [ ] `metrics.png` - 显示 p50/p95/p99 和 req/s
- [ ] `graceful_shutdown.png` - 显示优雅关闭和资源清理

---

**注意**：这些截图是 A++ 检查清单的要求项（第 13 项）。请确保在提交前完成所有截图。

