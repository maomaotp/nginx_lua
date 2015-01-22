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
local ERR_OPNAME = 90000
local ERR_NULL_FIELD = 90001
local ERR_GET_USERINFO = 90002
local ERR_EXIST_USER = 90003
local ERR_REGISTER_USER = 90004
local ERR_ERR_PASSWORD = 90005
local ERR_ERR_LOGINTYPE = 90006
local ERR_FAIL_UPDATEUSER = 90007
local ERR_FAIL_ADDMESSAGE = 90008
local ERR_FAIL_GETMESSAGE = 90009
local ERR_FAIL_COMMENT = 90010
local ERR_FAIL_ADDPLAUD = 90011
local ERR_FAIL_GETCOMMENT = 90012

local err_array = {
	[0] = "success",
	[90000] = "请求方法错误",
	[90001] = "请求参数不完整",
	[90002] = "获取用户信息失败",
	[90003] = "用户ID已存在",
	[90004] = "用户注册失败",
	[90005] = "密码错误",
	[90006] = "登陆类型错误",
	[90007] = "更新用户信息失败",
	[90008] = "增加用户消息失败",
	[90009] = "获取用户消息失败",
	[90010] = "用户评论失败",
	[90011] = "评论点赞失败",
	[90012] = "获取节目评论信息失败",
}

--读取配置文件
function get_json()
	local f = assert(io.open(CONFIG_FILE, "r"))
	local content = f:read("*all")
	ngx.say(content)
	f:close()
end


function http_resp(code)	
	local err_array = {
		[0] = "success",
		[90000] = "请求方法错误",
		[90001] = "请求参数不完整",
		[90002] = "获取用户信息失败",
		[90003] = "用户ID已存在",
		[90004] = "用户注册失败",
		[90005] = "密码错误",
		[90006] = "登陆类型错误",
		[90007] = "更新用户信息失败",
		[90008] = "增加用户消息失败",
		[90009] = "获取用户消息失败",
		[90010] = "用户评论失败",
		[90011] = "评论点赞失败",
		[90012] = "获取节目评论信息失败",
	}

	close_db()
	local res_str = string.format('{"describe":"%s","code":%d}', err_array[code],code)
	ngx.say(res_str)
	ngx.exit(ngx.HTTP_OK)
end


--初始化mysql连接
function init_db()
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
		ngx.log(ngx.ERR, err)
		http_resp(ERR_MYSQL_INIT)
	end
end

function parse_postargs()
	ngx.req.read_body()
	args = ngx.req.get_post_args()
	if not args then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_READ_POST_BODY)
	end
	
	--解析翻页参数
	start = args["start"] or 0
	page = args["page"] or 20
end

function close_db()
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
		ngx.log(ngx.ERR, err)
	end
end

function user_register()	
	local password = args["password"]	
	local nickname = args["nickname"]
	local userId = args["userId"]

	if not userId or not password or not nickname then
		ngx.log(ngx.ERR, ERR_NULL_FIELD)
		http_resp(ERR_NULL_FIELD)
	end

	local user_sql = string.format("select count(*) from u_userInfo where userId='%s'", userId)
	local register_sql = string.format("insert into u_userInfo (userId,password,nickname) values('%s','%s','%s')", userId, password, nickname)
	
	--判断用户ID是否存在
	local user_res,user_err = db:query(user_sql)
	if not user_res then
		ngx.log(ngx.ERR, user_err)
	end
	local count = tonumber(user_res[1]["count(*)"])
	if (count ~= 0) then
		ngx.log(ngx.ERR, ERR_EXIST_USER)
		http_resp(ERR_EXIST_USER)
	end

	local res, err = db:query(register_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_REGISTER_USER)
	end

	return OK_RES
end

function user_login()
	local phoneIdentify = args["phoneIdentify"]
	local loginWay = tonumber(args["loginWay"]) or 0
	local userId = nil
	if (loginWay == 1) then	
		userId = args["userId"]
		local password = args["password"]
		if not userId or not password then
			ngx.log(ngx.ERR, ERR_NULL_FIELD)
			http_resp(ERR_NULL_FIELD)
		end
		local login_sql = string.format("select count(*) from u_userInfo where userId='%s' and password='%s'", userId, password)
		local res, err = db:query(login_sql)
		if not res then
			ngx.log(ngx.ERR, err)
			http_resp(ERR_GET_USERINFO)
		end
		local count = tonumber(res[1]["count(*)"])
		if (count == 0) then
			http_resp(ERR_GET_USERINFO)
		end
	elseif(loginWay == 2) then
		local qq = args["qq"]	
		if not qq then 
			ngx.log(ngx.ERR, ERR_NULL_FIELD)
			http_resp(ERR_NULL_FIELD)
		end
		userId = "qq:" .. qq
		local i_sql = string.format("insert ignore u_userInfo (userId,qq) values('%s','%s')", userId, qq)

		local res, err = db:query(i_sql)
		if not res then
			ngx.log(ngx.ERR, err)
		end
	elseif(loginWay == 3) then
		local sina = args["sina"]
		if not sina then 
			ngx.log(ngx.ERR, ERR_NULL_FIELD)
			http_resp(ERR_NULL_FIELD)
		end
		userId = "sina:" .. sina
		local i_sql = string.format("insert ignore u_userInfo (userId, sina) values('%s','%s')", userId, sina)

		local res, err = db:query(i_sql)
		if not res then
			ngx.log(ngx.ERR, ERR_NULL_FIELD)
		end
	else
		ngx.log(ngx.ERR, ERR_ERR_LOGINTYPE)
		http_resp(ERR_ERR_LOGINTYPE)
	end

	local tag_sql = string.format("update u_userInfo set LogInNumber=LogInNumber+1,loginWay=%d,userTag=(select userTag from (select * from u_userInfo) as b where userId='%s') where userId='%s'", loginWay, phoneIdentify, userId)
	local res, err = db:query(tag_sql)
	if not res then
		ngx.log(ngx.ERR, ERR_FAIL_UPDATE)
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
		ngx.log(ngx.ERR, ERR_NULL_FIELD)
		http_resp(ERR_NULL_FIELD)
	end
  
	if not sex or (sex == "") then sex_string = "" else sex_string = string.format(",sex = '%s'", sex) end

	if not telephone or (telephone == "") then telephone_string = "" else telephone_string = string.format(",telephone='%s'", telephone) end
	if not email or (email == "") then email_string = "" else email_string = string.format(",email='%s'", email) end
	if not picture or (picture == "") then picture_string = "" else picture_string = string.format(",picture='%s'", picture) end
	local update_sql = string.format("update u_userInfo set nickname='%s'%s%s%s%s where userId='%s'", nickname, sex_string, telephone_string, email_string, picture_string , userId)

	local res, err = db:query(update_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_UPDATEUSER)
	end

	return OK_RES
end

function user_message()
	local userId = args["userId"]
	local status = args["status"]
	if not userId then
		ngx.log(ngx.ERR, ERR_NULL_FIELD)
		http_resp(ERR_NULL_FIELD)
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
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_GETMESSAGE)
	end
	ngx.say(cjson.encode(res))
end

function add_message()
	local userId = args["userId"]
	local messageType = args["messageType"]
	local content = args["content"]
	local programId = args["programId"]
	
	if not userId or not messageType or not content then
		ngx.log(ngx.ERR, ERR_NULL_FIELD)
		http_resp(ERR_NULL_FIELD)
	end
	if not programId then
		programId = ""
	end

	local i_sql = string.format("insert into u_message (userId,messageType,content,programId) values('%s',%s,'%s','%s')", userId, messageType, content,programId)

	local res, err = db:query(i_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_ADDMESSAGE)
	end
	return OK_RES
end

function add_comment()
	local userId = args["userId"]
	local programId = args["programId"]
	local content = args["content"]
	local programTime = args["programTime"]

	if not userId or not programId or not content or not programTime then
		ngx.log(ngx.ERR, ERR_NULL_FIELD)
		http_resp(ERR_NULL_FIELD)
	end
	local i_sql = string.format("insert into p_comment (userId,programId,content,programTime) values('%s','%s','%s',%s)", userId, programId, content, programTime)

	local res, err = db:query(i_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_COMMENT)
	end
	return OK_RES
end

function addplaud() 
	local commentId = args["commentId"]
	local applaud = tonumber(args["applaud"])
	
	if not commentId or not applaud then
		ngx.log(ngx.ERR, ERR_NULL_FIELD)
		http_resp(ERR_NULL_FIELD)
	end
	
	if (applaud == 0) then applaud = -1 end

	local u_sql = string.format("update p_comment set applaud=applaud+%d where commentId=%s",applaud, commentId)
	ngx.say(u_sql)
	local res, err = db:query(u_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_ADDPLAUD)
	end

	return OK_RES
end

function get_comment()
	local programId = args["programId"]
	local programTime = args["programTime"]
	if not programId then
		ngx.log(ngx.ERR, ERR_NULL_FIELD)
		http_resp(ERR_NULL_FIELD)
	end
	if not programTime then
		programTime = ""
	else
		programTime = string.format(" and programTime=%s",programTime)
	end

	local real_sql = string.format("select A.userId,A.content,A.applaud,B.picture,A.commentId,B.nickname from p_comment A,u_userInfo B where A.programId='%s' and B.userId=A.userId %s limit %s,%s", programId,programTime,start,page)
	local res, err = db:query(real_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_GETCOMMENT)
	end
	ngx.say(cjson.encode(res))
end

--函数入口
function main()
	init_db()
	parse_postargs()

--	local content = ngx.var.request_body
--	ngx.say(content)
	
	local op_action = {
		["register"] = function() return user_register() end,
		["logIn"] = function() return user_login() end,
		["update"] = function() return user_update() end,
		["userMessage"] = function() return user_message() end,
		["sendMessage"] = function() return add_message() end,
		["addComment"] = function() return add_comment() end,
		["getComment"] = function() return get_comment() end,
		["getJson"] = function() return get_json() end,
		["addplaud"] = function() return addplaud() end,
	}

	opName = args["opName"]
	if not op_action[opName] then
		ngx.log(ngx.ERR, "get opName error")
		http_resp(ERR_OPNAME)
	end

	local res_code = op_action[opName]()

	if res_code then
		http_resp(res_code)
	end
end

main()
