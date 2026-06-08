#!/usr/bin/env python3
import os
import json
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime

PORT = 8080
DB_FILE = 'telemetry.db'

def init_db():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS heartbeats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            installation_id TEXT,
            user_name TEXT,
            duration_seconds INTEGER,
            app_version TEXT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

def format_duration(seconds):
    if not seconds:
        return "0s"
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    
    parts = []
    if days > 0:
        parts.append(f"{days}天")
    if hours > 0:
        parts.append(f"{hours}小时")
    if minutes > 0:
        parts.append(f"{minutes}分")
    if secs > 0 or not parts:
        parts.append(f"{secs}秒")
    return "".join(parts)

def format_time(utc_str):
    try:
        # SQLite's CURRENT_TIMESTAMP returns UTC time like 'YYYY-MM-DD HH:MM:SS'
        dt = datetime.strptime(utc_str, '%Y-%m-%d %H:%M:%S')
        # Simple local display (assuming local timezone or just returning nicely formatted)
        return dt.strftime('%Y-%m-%d %H:%M:%S')
    except Exception:
        return utc_str

class TelemetryRequestHandler(BaseHTTPRequestHandler):
    
    def log_message(self, format, *args):
        # Override to suppress standard HTTP request logging in console to keep output clean
        pass

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_POST(self):
        if self.path == '/api/telemetry':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                payload = json.loads(post_data.decode('utf-8'))
                inst_id = payload.get('installationId')
                user_name = payload.get('userName')
                duration = payload.get('durationSeconds', 0)
                app_version = payload.get('appVersion', '1.0.0')
                
                if inst_id and user_name:
                    conn = sqlite3.connect(DB_FILE)
                    c = conn.cursor()
                    c.execute('''
                        INSERT INTO heartbeats (installation_id, user_name, duration_seconds, app_version)
                        VALUES (?, ?, ?, ?)
                    ''', (inst_id, user_name, duration, app_version))
                    conn.commit()
                    conn.close()
                    
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(b'{"status":"success"}')
                    print(f"[Heartbeat] User: {user_name} ({inst_id[:8]}...) | Duration: {duration}s | Ver: {app_version}")
                    return
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(f'{{"error":"{str(e)}"}}'.encode('utf-8'))
                return
        
        self.send_response(404)
        self.end_headers()

    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            
            # 1. Total unique users
            c.execute("SELECT COUNT(DISTINCT installation_id) FROM heartbeats")
            total_users = c.fetchone()[0] or 0
            
            # 2. Total duration tracked
            c.execute("SELECT SUM(duration_seconds) FROM heartbeats")
            total_seconds = c.fetchone()[0] or 0
            
            # 3. Active users in the last 10 minutes (using SQLite datetime modifier)
            c.execute("SELECT COUNT(DISTINCT installation_id) FROM heartbeats WHERE timestamp >= datetime('now', '-10 minutes')")
            active_users = c.fetchone()[0] or 0
            
            # 4. User details table
            c.execute('''
                SELECT user_name, installation_id, SUM(duration_seconds) as total_duration, MAX(timestamp) as last_active, app_version
                FROM heartbeats
                GROUP BY installation_id
                ORDER BY total_duration DESC
            ''')
            users_list = c.fetchall()
            
            # 5. Recent heartbeat logs (last 15)
            c.execute('''
                SELECT timestamp, user_name, duration_seconds, app_version, installation_id
                FROM heartbeats
                ORDER BY timestamp DESC
                LIMIT 15
            ''')
            recent_logs = c.fetchall()
            
            conn.close()
            
            html = self.generate_dashboard_html(total_users, total_seconds, active_users, users_list, recent_logs)
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(html.encode('utf-8'))
            return
            
        self.send_response(404)
        self.end_headers()

    def generate_dashboard_html(self, total_users, total_seconds, active_users, users_list, recent_logs):
        formatted_total_time = format_duration(total_seconds)
        
        user_rows = ""
        for row in users_list:
            u_name, inst_id, dur, last_act, ver = row
            dur_str = format_duration(dur)
            last_act_str = format_time(last_act)
            user_rows += f"""
            <tr>
                <td class="font-medium text-slate-200">{u_name}</td>
                <td class="text-slate-400 font-mono text-xs" title="{inst_id}">{inst_id[:8]}...{inst_id[-8:]}</td>
                <td class="text-emerald-400 font-semibold">{dur_str}</td>
                <td class="text-slate-300 font-mono text-xs">{last_act_str}</td>
                <td class="text-slate-400"><span class="badge">{ver}</span></td>
            </tr>
            """
            
        if not users_list:
            user_rows = "<tr><td colspan='5' class='text-center text-slate-500 py-8'>暂无安装用户数据</td></tr>"

        log_rows = ""
        for row in recent_logs:
            timestamp, u_name, dur, ver, inst_id = row
            time_str = format_time(timestamp)
            log_rows += f"""
            <div class="flex items-center justify-between py-2 border-b border-slate-700/50 text-sm">
                <div class="flex items-center space-x-3">
                    <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
                    <span class="text-slate-300 font-medium">{u_name}</span>
                </div>
                <div class="flex items-center space-x-4">
                    <span class="text-slate-400 font-mono text-xs">{time_str}</span>
                    <span class="text-slate-500 text-xs">+{dur}秒</span>
                </div>
            </div>
            """
            
        if not recent_logs:
            log_rows = "<div class='text-center text-slate-500 py-6 text-sm'>暂无心跳活动</div>"

        return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AIQuotaWidget 使用时长监测面板</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }}
        body {{
            font-family: 'Outfit', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background-color: #0f172a;
            color: #f8fafc;
            min-height: 100vh;
            padding: 2rem;
            line-height: 1.5;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
        }}
        header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2.5rem;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
            padding-bottom: 1.5rem;
        }}
        h1 {{
            font-size: 2rem;
            font-weight: 700;
            background: linear-gradient(135deg, #a78bfa 0%, #818cf8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }}
        .refresh-indicator {{
            font-size: 0.85rem;
            color: #94a3b8;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }}
        .refresh-dot {{
            width: 8px;
            height: 8px;
            background-color: #10b981;
            border-radius: 50%;
            display: inline-block;
            animation: pulse 2s infinite;
        }}
        @keyframes pulse {{
            0% {{ transform: scale(0.95); opacity: 0.5; }}
            50% {{ transform: scale(1.1); opacity: 1; }}
            100% {{ transform: scale(0.95); opacity: 0.5; }}
        }}
        .grid-stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2.5rem;
        }}
        .card-stat {{
            background: rgba(30, 41, 59, 0.7);
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            padding: 1.5rem;
            backdrop-filter: blur(12px);
            box-shadow: 0 4px 30px rgba(0, 0, 0, 0.2);
            transition: transform 0.2s;
        }}
        .card-stat:hover {{
            transform: translateY(-2px);
            border-color: rgba(255, 255, 255, 0.1);
        }}
        .stat-label {{
            font-size: 0.9rem;
            color: #94a3b8;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 0.5rem;
        }}
        .stat-value {{
            font-size: 2.25rem;
            font-weight: 700;
            color: #fff;
        }}
        .text-gradient-purple {{
            background: linear-gradient(135deg, #c084fc 0%, #818cf8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }}
        .text-gradient-emerald {{
            background: linear-gradient(135deg, #34d399 0%, #059669 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }}
        .grid-content {{
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 2rem;
        }}
        @media (max-width: 900px) {{
            .grid-content {{
                grid-template-columns: 1fr;
            }}
        }}
        .card-table, .card-timeline {{
            background: rgba(30, 41, 59, 0.7);
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            padding: 1.5rem;
            box-shadow: 0 4px 30px rgba(0, 0, 0, 0.2);
        }}
        .card-title {{
            font-size: 1.25rem;
            font-weight: 600;
            margin-bottom: 1.25rem;
            color: #f1f5f9;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            text-align: left;
        }}
        th, td {{
            padding: 1rem 0.75rem;
            border-bottom: 1px solid rgba(255, 255, 255, 0.06);
        }}
        th {{
            font-weight: 600;
            color: #94a3b8;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }}
        td {{
            font-size: 0.95rem;
        }}
        .font-mono {{
            font-family: 'JetBrains Mono', monospace;
        }}
        .badge {{
            background: rgba(255, 255, 255, 0.08);
            padding: 0.2rem 0.6rem;
            border-radius: 9999px;
            font-size: 0.75rem;
            font-weight: 600;
        }}
        .timeline-list {{
            display: flex;
            flex-direction: column;
            gap: 0.75rem;
            max-height: 500px;
            overflow-y: auto;
        }}
    </style>
    <script>
        // 自动每 10 秒刷新页面以实现准实时看板效果
        setTimeout(function() {{
            window.location.reload();
        }}, 10000);
    </script>
</head>
<body>
    <div class="container">
        <header>
            <div>
                <h1>AIQuotaWidget 使用时长监测面板</h1>
            </div>
            <div class="refresh-indicator">
                <span class="refresh-dot"></span>
                <span>数据实时自动刷新 (10s)</span>
            </div>
        </header>
        
        <div class="grid-stats">
            <div class="card-stat">
                <div class="stat-label">已安装总设备数</div>
                <div class="stat-value text-gradient-purple">{total_users}</div>
            </div>
            <div class="card-stat">
                <div class="stat-label">总累计使用时长</div>
                <div class="stat-value">{formatted_total_time}</div>
            </div>
            <div class="card-stat">
                <div class="stat-label">当前活跃用户 (10分钟内)</div>
                <div class="stat-value text-gradient-emerald">{active_users}</div>
            </div>
        </div>
        
        <div class="grid-content">
            <div class="card-table">
                <div class="card-title">用户使用排行榜</div>
                <div style="overflow-x: auto;">
                    <table>
                        <thead>
                            <tr>
                                <th>用户名 / 邮箱</th>
                                <th>独立设备 ID</th>
                                <th>总使用时长</th>
                                <th>最后活跃时间</th>
                                <th>版本</th>
                            </tr>
                        </thead>
                        <tbody>
                            {user_rows}
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="card-timeline">
                <div class="card-title">最近心跳活动</div>
                <div class="timeline-list">
                    {log_rows}
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"""

def main():
    init_db()
    server_address = ('', PORT)
    httpd = HTTPServer(server_address, TelemetryRequestHandler)
    print(f"===========================================================")
    print(f" AIQuotaWidget Telemetry Server starting on port {PORT}...")
    print(f" Dashboard URL: http://localhost:{PORT}")
    print(f" SQLite DB: {os.path.abspath(DB_FILE)}")
    print(f"===========================================================")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down Telemetry Server.")
        httpd.server_close()

if __name__ == '__main__':
    main()
