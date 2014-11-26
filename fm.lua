worker_processes  1;
error_log logs/error.log;
events {
	use epoll;
	worker_connections 1024;
}
http {
	keepalive_timeout 120;
	upstream fmserver{
		server 192.168.1.120:8080 weight=2;
		server 192.168.1.120:8090 weight=2;
	}

	#default_type application/octet-stream;
	default_type application/json;
	server {
		listen 8080;
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
		location /post{
			content_by_lua_file "nginx_lua/json.lua";
		}
	}
}
