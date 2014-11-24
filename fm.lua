worker_processes  1;
error_log logs/error.log;
events {
	use epoll;
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
		location /test{
			content_by_lua '
				ngx.say("liuq test")
				ngx.req.read_body()
				local args, err = ngx.req.get_post_args()
				for key, val in pairs(args) do
					ngx.say(key .. ":" .. args[key])
				end
			';
		}
    }
}
