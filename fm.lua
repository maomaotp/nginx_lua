worker_processes  1;
error_log logs/error.log;
events {
	use epoll;
	worker_connections 1024;
}
http {
	keepalive_timeout 120;
	upstream fmserver{
		server 127.0.0.1:8080 weight=2;
		server 123.57.41.242:8080 weight=2;
	}

	#default_type application/octet-stream;
	default_type application/json;
	server {
		listen 8080;
		server_name localhost;
        location /query_top{
			proxy_pass http://fmserver;
			content_by_lua_file "nginx_lua/redis.lua";
		}
        location /lingbanfm{
			proxy_pass http://fmserver;
			content_by_lua_file "nginx_lua/mysql.lua";
		}
		location /test{
			proxy_pass http://fmserver;
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
