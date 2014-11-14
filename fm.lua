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
        location /zincrby{
			internal;
			redis2_query zincrby $arg_optype $arg_score $arg_id;
			redis2_pass backend;
		}
        location /redisquery{
			internal;
			redis2_raw_queries $args $echo_request_body;
			redis2_pass backend;
		}
        location /update_top{
           content_by_lua_file "nginx_lua/update_top.lua";
        }
        location /query_top{
			content_by_lua_file "nginx_lua/query_top.lua";
		}
    }
}
