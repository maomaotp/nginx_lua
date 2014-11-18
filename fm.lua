worker_processes  1;
error_log logs/error.log;
events {
	worker_connections 1024;
}
http {
	upstream backend {
		server 127.0.0.1:6379;
	}

	default_type application/octet-stream;
	server {
		listen 8080;
        location /query_top{
			content_by_lua_file "nginx_lua/redis.lua";
		}
        location /lingbanfm{
			content_by_lua_file "nginx_lua/mysql.lua";
		}
    }
}
