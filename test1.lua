local cjson = require "cjson"
local mysql = require "resty.mysql"

local MYSQL_HOST = "123.57.41.242"
local MYSQL_POST = 3306
local MYSQL_DATABASE = "fm_appserver"
local MYSQL_USER = "lingbanfm"
local MYSQL_PASSWD = "lingban2014"

local DB_TIMEOUT = 5000  --5 sec
local MAX_SIZE = 1024*1024
local USER_LOG = "/home/work/logs/fm"

--error message
local OK_RES = 0
local ERR_PARSE_POSTARGS = 80001
local ERR_MYSQL_QUERY = 80002
local ERR_MYSQL_INIT = 80003
local ERR_MYSQL_CLOSE = 80004
local ERR_OPNAME = 80005
local ERR_NULL_SQL = 80006
local ERR_GET_POST_BODY = 80007

local err_array = {
	[0] = "success",
	[80001] = "请求参数错误",
	[80002] = "数据库请求错误",
	[80003] = "数据库初始化错误",
	[80004] = "数据库请求错误",
	[80005] = "操作名错误",
	[80006] = "数据库请求错误",
	[80007] = "获取post body内容错误",
}

--liuq_lua = "lua: require"

mysql_func = {}
function mysql_func.init() 
	db = mysql:new()
	
	db:set_timeout(DB_TIMEOUT)
	local ok, err, errno, sqlstate = db:connect{
	    host = MYSQL_HOST,
	    port = MYSQL_POST,
	    database = MYSQL_DATABASE,
	    user = MYSQL_USER,
	    password = MYSQL_PASSWD,
	    max_packet_size = MAX_SIZE
	}
	
	if not ok then
		fm_log(opname, ERR_MYSQL_INIT, err)
	    return
	end
	return db
end
function mysql_func.close()
	local ok, err = db:set_keepalive(30000, 100)
	return 0
end

return mysql_func
