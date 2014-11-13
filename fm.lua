worker_processes  1;
error_log logs/error.log;
events {
	worker_connections 1024;
}
http {
	default_type application/octet-stream;
	server {
		listen 8080;
        location /zincrby{
			internal;
			redis2_query zincrby $arg_type $arg_score $arg_id;
			redis2_pass 127.0.0.1:6379;
		}
        location /rank{
           content_by_lua_file "nginx_lua/rank.lua"; 
        }
        location /getorder{
            content_by_lua '
				ngx.req.read_body()
				local args, err = ngx.req.get_post_args()
				if not args then
					ngx.say("failed to get post args: ", err)
					return
				end

				for key, val in pairs(args) do
					ngx.say(key .. ":" .. args["clientId"])
				end
			';
		}
    }
}
