local cjson = require "cjson"
local mysql = require "resty.mysql"

local MYSQL_HOST = "123.57.41.242"
local MYSQL_POST = 3306
local MYSQL_DATABASE = "fm_appserver"
local MYSQL_USER = "lingbanfm"
local MYSQL_PASSWD = "lingban2014"

local DB_TIMEOUT = 5000  --2 sec
local MAX_SIZE = 1024*1024

local USER_LOG = "/home/work/logs/fm"
local CONFIG_FILE = "/home/work/conf/fm_category.json"

--res code
local OK_RES = 0
local ERR_PARSE_POSTARGS = 80001
local ERR_MYSQL_QUERY = 80002
local ERR_MYSQL_INIT = 80003
local ERR_OPNAME = 80005
local ERR_NULL_SQL = 80006
local ERR_GET_POST_BODY = 80007
local ERR_USER_PASSWD = 80008
local ERR_USER_EXIST = 80009

local err_array = {
	[0] = "success",
	[80001] = "请求参数错误",
	[80002] = "数据库请求错误",
	[80003] = "数据库初始化错误",
	[80005] = "方法名错误",
	[80006] = "数据库请求错误",
	[80007] = "获取post body内容错误",
	[80008] = "用户名或密码错误",
	[80009] = "用户已存在",
}

function fm_log(opname, code, err)
	local file = string.format("%s_%s.log", USER_LOG, os.date("%Y%m"))
	local f = assert(io.open(file, "a"))
	f:write(string.format("%s %s %s %s\n", os.date("%Y-%m-%d %H:%M:%S"), opname, code, err))
	f:close()
end

--读取配置文件
function get_json()
	local f = assert(io.open(CONFIG_FILE, "r"))
	local content = f:read("*all")
	ngx.say(content)
	f:close()
end


function http_resp(code)	
	close_mysql()
	local res_str = string.format('{"describe":"%s","code":%d}', err_array[code],code)
	ngx.say(res_str)
end

--初始化mysql连接
function init_mysql()
	db = assert(mysql:new())
	
	db:set_timeout(DB_TIMEOUT)
	local ok, err = db:connect{
	    host = MYSQL_HOST,
	    port = MYSQL_POST,
	    database = MYSQL_DATABASE,
	    user = MYSQL_USER,
	    password = MYSQL_PASSWD,
	    max_packet_size = MAX_SIZE
	}
	
	if not ok then
		fm_log(opname, ERR_MYSQL_INIT, err)
	    return ERR_MYSQL_INIT
	end
	return OK_RES
end

function parse_postargs()
	ngx.req.read_body()
	args = ngx.req.get_post_args()
	if not args then
		fm_log(opname, ERR_GET_POST_BODY, err)
		return
	end
	
	--解析翻页参数
	start = args["start"]
	page = args["page"]
	if not start then start = "0" end
	if not page then page = "20" end
	
	opname = args["opName"]
	if not opname then
		fm_log(opname, ERR_OPNAME, err)
		return ERR_OPNAME
	end
	return OK_RES
end

function close_mysql()
	--关闭连接
--	local ok, err = db:close()
--	if not ok then
--	    ngx.say("failed to close: ", err)
--	    return ERR_MYSQL_QUERY
--	end
	-- put it into the connection pool of size 100,
	-- with 10 seconds max idle timeout
	local ok, err = db:set_keepalive(30000, 100)
	if not ok then
		db:close()
		fm_log(opname, ERR_MYSQL_QUERY, err)
	    return ERR_MYSQL_QUERY
	end
	return OK_RES
end

function user_register()	
	local password = args["password"]	
	local nickname = args["nickname"]
	local userId = args["userId"]

	if not userId or not password or not nickname then
		fm_log(opname, ERR_PARSE_POSTARGS, err)		
		return ERR_PARSE_POSTARGS
	end

	local user_sql = string.format("select count(*) from u_userInfo where userId='%s'", userId)
	local register_sql = string.format("insert into u_userInfo (userId,password,nickname) values('%s','%s','%s')", userId, password, nickname)
	
	--判断用户ID是否存在
	local user_res,user_err = db:query(user_sql)
	if not user_res then
		fm_log(opname, ERR_MYSQL_QUERY, user_err)		
	    return ERR_MYSQL_QUERY
	end
	local count = tonumber(user_res[1]["count(*)"])
	if (count ~= 0) then
		fm_log(opname, ERR_USER_EXIST, user_err)		
	    return ERR_USER_EXIST
	end

	local res, err = db:query(register_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
	    return ERR_MYSQL_QUERY
	end

	return OK_RES
end

function user_login()
	local phoneIdentify = args["phoneIdentify"]
	local loginWay = tonumber(args["loginWay"])
	local userId = nil
	if (loginWay == 1) then	
		userId = args["userId"]
		local password = args["password"]
		if not userId or not password then
			fm_log(opname, ERR_PARSE_POSTARGS)		
			return ERR_PARSE_POSTARGS
		end
		local login_sql = string.format("select count(*) from u_userInfo where userId='%s' and password='%s'", userId, password)
		local res, err = db:query(login_sql)
		if not res then
			fm_log(opname, ERR_MYSQL_QUERY, err)		
			return ERR_MYSQL_QUERY
		end
		local count = tonumber(res[1]["count(*)"])
		if (count == 0) then
			fm_log(opname, ERR_USER_PASSWD)		
			return ERR_USER_PASSWD
		end
	elseif(loginWay == 2) then
		local qq = args["qq"]	
		if not qq then 
			fm_log(opname, ERR_MYSQL_QUERY)		
			return ERR_PARSE_POSTARGS
		end
		userId = "qq:" .. qq
		local i_sql = string.format("insert ignore u_userInfo (userId,qq) values('%s','%s')", userId, qq)

		local res, err = db:query(i_sql)
		if not res then
			fm_log(opname, ERR_MYSQL_QUERY, err)		
			return ERR_MYSQL_QUERY
		end
	elseif(loginWay == 3) then
		local sina = args["sina"]
		if not sina then 
			fm_log(opname, ERR_PARSE_POSTARGS)		 
			return ERR_PARSE_POSTARGS
		end
		userId = "sina:" .. sina
		local i_sql = string.format("insert ignore u_userInfo (userId, sina) values('%s','%s')", userId, sina)

		local res, err = db:query(i_sql)
		if not res then
			fm_log(opname, ERR_MYSQL_QUERY, err)		
		end
	else
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end

	local tag_sql = string.format("update u_userInfo set LogInNumber=LogInNumber+1,loginWay=%d,userTag=(select userTag from (select * from u_userInfo) as b where userId='%s') where userId='%s'", loginWay, phoneIdentify, userId)
	local res, err = db:query(tag_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end

	return OK_RES
end

function user_update()
	local userId = args["userId"]
	local nickname = args["nickname"]
	local sex = args["sex"]
	local telephone = args["telephone"]
	local email = args["email"]
	local picture = args["picture"]


	if not userId or not nickname then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end
  
	if not sex or (sex == "") then sex_string = "" else sex_string = string.format(",sex = '%s'", sex) end

	if not telephone or (telephone == "") then telephone_string = "" else telephone_string = string.format(",telephone='%s'", telephone) end
	if not email or (email == "") then email_string = "" else email_string = string.format(",email='%s'", email) end
	if not picture or (picture == "") then picture_string = "" else picture_string = string.format(",picture='%s'", picture) end
	local update_sql = string.format("update u_userInfo set nickname='%s'%s%s%s%s where userId='%s'", nickname, sex_string, telephone_string, email_string, picture_string , userId)

	local res, err = db:query(update_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end

	return OK_RES
end

function user_add(qq, phoneIdentify)
	if not qq then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end
	local add_sql = string.format("insert into u_userInfo (userId, loginWay) values(%s, 2)", qq)
	ngx.say(add_sql)

	local res, err = db:query(add_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end
	ngx.say('{"result":"OK"}')
	return OK_RES
end

function add_message()
	local userId = args["userId"]
	local messageType = args["messageType"]
	local programId = args["programId"]
	local content = args["content"]
	
	if not userId or (userId == "") or not messageType or (messageType == "") then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end

	if not programId then programId = "" end
	if not content then content = "" end

	local insert_sql = string.format("insert into u_message (userId,messageType,programId,content) values('%s','%s','%s','%s')", userId, messageType, programId, content)

	local res, err = db:query(insert_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end
	return OK_RES
end

function user_message()
	local userId = args["userId"]
	local status = args["status"]
	if not userId then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end
	if not status then
		status = ""
	else
		status = " and status=" .. status
	end
	local select_sql = string.format("select userId,messageType,messageTime,content,status from u_message where userId='%s' %s", userId, status)
	local update_sql = string.format("update u_message set status=1 where userId='%s'", userId)
	local res, err = db:query(select_sql .. ";" .. update_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end
	ngx.say(cjson.encode(res))
end

function send_message()
	local userId = args["userId"]
	local messageType = args["messageType"]
	local content = args["content"]
	local programId = args["programId"]
	
	if not userId or not messageType or not content then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end
	if not programId then
		programId = ""
	end

	local i_sql = string.format("insert into u_message (userId,messageType,content,programId) values('%s',%s,'%s','%s')", userId, messageType, content,programId)

	local res, err = db:query(i_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end
	return OK_RES
end

function add_comment()
	local userId = args["userId"]
	local programId = args["programId"]
	local content = args["content"]

	if not userId or not programId or not content then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end
	local i_sql = string.format("insert into p_comment (userId,programId,content) values('%s','%s','%s')", userId, programId, content)

	local res, err = db:query(i_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end
	return OK_RES
end

function addplaud() 
	local commentId = args["commentId"]
	local applaud = tonumber(args["applaud"])
	
	if not commentId or not applaud then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end
	
	if (applaud == 0) then applaud = -1 end

	local u_sql = string.format("update p_comment set applaud=applaud+%d where commentId=%s",applaud, commentId)
	ngx.say(u_sql)
	local res, err = db:query(u_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end

	return OK_RES
end

function get_comment()
	local programId = args["programId"]
	local curTime = args["curTime"]
	if not programId then
		fm_log(opname, ERR_PARSE_POSTARGS)		
		return ERR_PARSE_POSTARGS
	end
	if not curTime then
		curTime = ""
	else
		curTime = string.format(" and UNIX_TIMESTAMP(A.addTime) > UNIX_TIMESTAMP('%s')",curTime)
	end
	local real_sql = string.format("select A.userId,A.content,A.applaud,A.addTime,B.picture,A.commentId,B.nickname from p_comment A,u_userInfo B where A.programId='%s' and B.userId=A.userId %s limit %s,%s", programId,curTime,start,page)
	local res, err = db:query(real_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)		
		return ERR_MYSQL_QUERY
	end
	ngx.say(cjson.encode(res))
end

function hot_words()
	local hot_sql = string.format("select hotwords from t_hot order by seekNumber limit %s,%s", start, page)
	local res, err = db:query(hot_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end
	ngx.say(cjson.encode(res))
end

--函数入口
function main()
	if (init_mysql() ~= 0) then
		http_resp(ERR_MYSQL_INIT)
		return
	end

	if (parse_postargs() ~= 0) then
	    http_resp(ERR_GET_POST_BODY)	
		return 
	end

--	local content = ngx.var.request_body
--	ngx.say(content)
	
	local op_action = {
		["register"] = function() return user_register() end,
		["logIn"] = function() return user_login() end,
		["update"] = function() return user_update() end,
		["userMessage"] = function() return user_message() end,
		["sendMessage"] = function() return send_message() end,
		["addComment"] = function() return add_comment() end,
		["getComment"] = function() return get_comment() end,
		["getJson"] = function() return get_json() end,
		["hotwords"] = function() return hot_words() end,
		["applaud"] = function() return addplaud() end,
	}

	if not op_action[opname] then
		fm_log(opname, ERR_OPNAME, err)
		http_resp(ERR_OPNAME)	
		return
	end

	local res_code = op_action[opname]()

	if res_code then
		http_resp(res_code)
	end
end

main()
