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

--res code
local OK_RES = 0
local ERR_PARSE_POSTARGS = 80001
local ERR_MYSQL_QUERY = 80002
local ERR_MYSQL_INIT = 80003
local ERR_OPNAME = 80005
local ERR_NULL_SQL = 80006
local ERR_GET_POST_BODY = 80007

local err_array = {
	[0] = "success",
	[80001] = "请求参数错误",
	[80002] = "数据库请求错误",
	[80003] = "数据库初始化错误",
	[80005] = "方法名错误",
	[80006] = "数据库请求错误",
	[80007] = "获取post body内容错误",
}

function fm_log(opname, code, err)
	local file = string.format("%s_%s.log", USER_LOG, os.date("%Y%m"))
	local f = assert(io.open(file, "a"))
	f:write(string.format("%s %s %s %s\n", os.date("%Y-%m-%d %H:%M:%S"), opname, code, err))
	f:close()
end

--初始化mysql连接
function init_mysql()
	db = assert(mysql:new())
	
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
		fm_log(opname, ERR_PARSE_POSTARGS, err)
		return
	end

	return OK_RES
end

function close_mysql()
	--关闭连接
--	local ok, err = db:close()
--	if not ok then
--	    ngx.say("failed to close: ", err)
--	    return 10010
--	end
	-- put it into the connection pool of size 100,
	-- with 10 seconds max idle timeout
	local ok, err = db:set_keepalive(30000, 100)
	if not ok then
		fm_log(opname, ERR_MYSQL_CONNECT, err)
		return ERR_MYSQL_QUERY
	end
	return 0
end

function http_resp(code)	
	close_mysql()
	local res_str = string.format('{"describe":"%s","code":%d}', err_array[code],code)
	ngx.say(res_str)
end

function radio_recommend()
	local select_sql = nil
	local phoneIdentify = args["phoneIdentify"]
	local programType = args["programType"]

	if not phoneIdentify then 
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	if not programType or (programType == "") then
	select_sql = string.format("select programId,programName,programUri,picture,programIntro,radioId,albumId from a_program limit %d,%d", start, page)
	else
		select_sql = "select programId,programName,programUri,picture,programIntro,radioId,albumId from a_program where programType="
		for number in string.gfind(programType, '%d+') do
			select_sql = string.format("%s%s or programType=", select_sql, number)
		end
		select_sql = string.sub(select_sql, 0, -16)
		select_sql = string.format("%s limit %d,%d", select_sql, start, page)
	end

	local res, err = db:query(select_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end

	ngx.say(cjson.encode(res))

	--更新用户标签
	local user_sql = string.format("insert into u_userInfo (userId,userTag) values('%s', '%s') on duplicate key update userTag='%s'", phoneIdentify, programType, programType)
	local res, err = db:query(user_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end
end

function program_info()	
	local radioId = args["radioId"]	
	local albumId = args["albumId"]
	local sql = nil

	if not radioId and not albumId then
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	elseif radioId and not albumId then
		sql = string.format("select nameCn,logo,url,introduction from Radio_Info where radioID='%s'", radioId)
	elseif albumId and not radioId then
		sql = string.format("select albumName,picture from a_album where albumId='%s'", albumId)
	else
		sql = string.format("select A.nameCn,A.logo,A.url,A.introduction,B.albumName,B.picture from Radio_Info A, a_album B where A.radioID='%s' and B.albumId='%s'", radioId, albumId)
	end

	local res, err = db:query(sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end

	ngx.say(cjson.encode(res))
end

function top_list()
	local ptype = args["ptype"]
	local top_sql
	if not ptype then
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	if (ptype == "program") then
		local programType = args["programType"]
		if not programType then
			top_sql = string.format("select A.programId,A.programName,A.programUri,A.compere,A.picture from a_program A,t_play B where A.programId = B.id and B.ptype=1 order by B.duration desc limit %s,%s", start, page)
		else
			top_sql = string.format("select A.programId,A.programName,A.programUri,A.compere,A.picture from a_program A,t_play B where A.programId = B.id and A.programType = %s and B.ptype=1 order by B.duration desc limit %s,%s", programType, start, page)
		end

	elseif (ptype == "radio") then
		top_sql = string.format("select A.radioId,A.name_cn,A.name_en,A.url,A.introduction,A.logo,A.classification from radio_info A,t_play B where A.radioId = B.id and B.ptype=2 order by B.duration desc limit %s,%s", start, page)
	elseif (ptype == "album") then
		top_sql = string.format("select A.albumId,A.albumName,A.albumIntro,A.tag,A.albumType,A.picture from a_album A,t_play B where A.albumId = B.id and B.ptype=3 order by B.duration desc limit %s,%s", start, page)
	else
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	ngx.say(top_sql)

	local res, err = db:query(top_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end

	ngx.say(cjson.encode(res))
end

function statistics()
	local userId = args["userId"]
	local id = args["id"]
	local ptype = args["ptype"]
	local num = tonumber(args["operate"])
	local duration = args["duration"]

	local operate_sql = nil

	if not userId or not id or not ptype or not num then
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	-- 1:收听时长  2:分享 3:下载 4:喜爱 5:收藏 6:不喜欢 7:电台评论(该操作自己调用)
	local action = {
		[1] = string.format("insert t_user (userId,playCount,duration) values('%s',1,%d) on duplicate key update playCount=playCount+1,duration=duration+%d", userId,duration,duration),
		[2] = "sharesCount",
		[3] = "downloadCount",
		[4] = "favoritesCount",
		[5] = "collectionCount",
		[6] = "dislikeCount",
		[7] = "commentCount",
	}
	if (num ~= 1) then
		local field = action[num]
		if not field then
			fm_log(opname, ERR_PARSE_POSTARGS)
			return ERR_PARSE_POSTARGS
		end
		operate_sql = string.format("insert t_user (userId,%s) values('%s',1) on duplicate key update %s=%s+1", field, userId, field,field)
	else
		if not duration then
			fm_log(opname, ERR_PARSE_POSTARGS)
			return ERR_PARSE_POSTARGS
		end
		operate_sql = action[num]
	end

	if not operate_sql then
		fm_log(opname, ERR_NULL_SQL)
		return ERR_PARSE_POSTARGS
	end

	local res, err = db:query(operate_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end
	return OK_RES
end

function program_list()
	local radioId = args["radioId"]
	local albumId = args["albumId"]
	local programId = args["programId"]
	local select_sql = nil

	if albumId then
		select_sql = string.format("select albumId,albumName,picture,albumIntro,tag,albumType from a_album where albumId='%s'", albumId)
	elseif radioId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where radioId='%s' order by playTime limit %d,%d", radioId, start, page)
	elseif programId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where programType=(select programType from a_program where programId='%s')", programId)
	else
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end

	local res, err = db:query(select_sql)
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

	local op_action = {
		["slackerRadio"] = function() return radio_recommend() end,
		["programInfo"] = function() return program_info() end,
		["programList"] = function() return program_list() end,
		["top"] = function() return top_list() end,
		["statistics"] = function() statistics() end, 
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
