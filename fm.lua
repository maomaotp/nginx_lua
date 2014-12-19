worker_processes  2;

error_log logs/error.log error;
pid logs/nginx.pid;
user root;

events {
	use epoll;
	worker_connections 2048;
}
http {
	default_type application/json;
	#限制一个IP最多的并发连接数
	limit_conn_zone $binary_remote_addr zone=slimits:5m;

	#开启ssl加密
	ssl on;
	ssl_certificate ../conf/ca.crt;
	ssl_certificate_key ../conf/server.key;

	log_format access_log '[$time_local] $remote_addr $request_uri '
					'[$http_user_agent] $bytes_sent $request_time '
					'"$request_body" $host $status';
	access_log logs/access.log access_log;
    error_log logs/error.log error;

	keepalive_timeout 1200;
	upstream fmserver{
		server 192.168.1.120:8080 weight=2;
		server 192.168.1.120:8090 weight=2;
	}
	server {
		listen 8080;
		limit_conn slimits 5;

		if ($request_method !~ ^(GET|POST)$ ) {
			return 444;
		}

        location /query_top{
			content_by_lua_file "nginx_lua/redis.lua";
		}
        location /lingbanfm{
			content_by_lua_file "nginx_lua/mysql.lua";
		}
		location /test{
			content_by_lua_file "nginx_lua/json.lua";
		}
    }
	server {
		listen 8090;
		limit_conn slimits 5;
		location /user{
			content_by_lua_file "nginx_lua/fm3_user.lua";
		}
		location /fm{
			content_by_lua_file "nginx_lua/fm3_recommend.lua";
		}
		location /search{
			content_by_lua_file "nginx_lua/fm3_search.lua";
		}
	}
}
