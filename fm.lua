worker_processes  2;

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

	#客户端请求包体最大值限制
	client_max_body_size 100k;

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
	upstream mysvr{
		server 192.168.1.120:8080 weight=2;
		server 192.168.1.120:8090 weight=2;
	}
	server {
		listen 8080;
		limit_conn slimits 5;

		if ($request_method !~ ^(POST)$ ) {
			return 444;
		}

        location  = /query_top{
			content_by_lua_file "nginx_lua/redis.lua";
		}
        location  = /lingbanfm{
			content_by_lua_file "nginx_lua/mysql.lua";
		}
		location  = /test{
			content_by_lua_file "nginx_lua/json.lua";
		}
    }
	server {
		listen 8090;
		limit_conn slimits 5;

		#只允许post方法，如果需要get方法将 POST 改为  POST|GET
		if ($request_method !~ ^(POST)$ ) {
			return 444;
		}

		location = /user{
			content_by_lua_file "nginx_lua/fm3_user.lua";
		}
		location = /fm{
			content_by_lua_file "nginx_lua/fm3_recommend.lua";
		}
		location = /search{
			echo_location /fm;
			echo_location /index.php;
		}
		location ~ \.php$ {
			fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
            fastcgi_param  SCRIPT_FILENAME  /home/work/php$fastcgi_script_name;
			include        fastcgi_params;
        }
	}
	#虚拟主机
	server {
		listen 8000;
		server_name 192.168.1.120;
		access_log logs/mysvr.access.log access_log;
		location /loadtest {
			proxy_pass http://mysvr;  #以这种格式来使用后端的web服务器
			proxy_redirect off;
			proxy_set_header Host $host; 
			proxy_set_header X-Real-IP $remote_addr;
			proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; 
			client_max_body_size 10m;
			client_body_buffer_size 128k; 
			proxy_connect_timeout 90;
			proxy_send_timeout 90;
			proxy_read_timeout 90;
			proxy_buffer_size 4k;
			proxy_buffers 4 32k;
			proxy_busy_buffers_size 64k; 
			proxy_temp_file_write_size 64k;
		}
	}
}
