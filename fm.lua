worker_processes  1;
error_log logs/error.log;
events {
	use epoll;
	worker_connections 1024;
}
http {
	upstream backend{
		server 127.0.0.1:8080;
		server 123.57.41.242:8080;
	}

	#default_type application/octet-stream;
	default_type application/json;
	server {
		listen 8080;
#server_name "http://192.168.1.120:8080";
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
