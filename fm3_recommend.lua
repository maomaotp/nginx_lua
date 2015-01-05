local cjson = require "cjson"
local mysql = require "resty.mysql"
local redis = require "resty.redis"

--mysql db
local MYSQL_HOST = "123.57.41.242"
local MYSQL_POST = 3306
local MYSQL_DATABASE = "fm_appserver"
local MYSQL_USER = "lingbanfm"
local MYSQL_PASSWD = "lingban2014"

--redis
local REDIS_SERVER_IP = "127.0.0.1"
local REDIS_SERVER_PORT = 6379
local REDIS_TIMEOUT = 1000

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
local ERR_REDIS_INIT = 80008
local ERR_REDIS_QUERY = 80009

local err_array = {
	[0] = "success",
	[80001] = "请求参数错误",
	[80002] = "数据库请求错误",
	[80003] = "数据库初始化错误",
	[80005] = "方法名错误",
	[80006] = "数据库请求错误",
	[80007] = "获取post body内容错误",
	[80008] = "redis初始化错误",
	[80009] = "redis查询错误",
}

function fm_log(opname, code, err)
	local file = string.format("%s_%s.log", USER_LOG, os.date("%Y%m"))
	local f = assert(io.open(file, "a"))
	f:write(string.format("%s %s %s %s\n", os.date("%Y-%m-%d %H:%M:%S"), opname, code, err))
	f:close()
end

--init redis 
function init_redis()
	red = redis:new()
    red:set_timeout(REDIS_TIMEOUT) -- 1 sec

    local ok, err = red:connect(REDIS_SERVER_IP, REDIS_SERVER_PORT)
    if not ok then
		fm_log(opname, ERR_REDIS_INIT, err)
        return
    end
	return OK_RES
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
	select_sql = string.format("select programId,programName,programUri,compere,picture,programIntro,radioId,albumId,programType,secondLevel from a_program limit %d,%d", start, page)
	else
		select_sql = "select programId,programName,programUri,compere,picture,programIntro,radioId,albumId,programType from a_program where programType="
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
		sql = string.format("select radioId,nameCn,nameEn,logo,url,introduction,radioLevel,provinceSpell,cityName,classification from Radio_Info where radioID='%s'", radioId)
	elseif albumId and not radioId then
		sql = string.format("select albumId,albumName,picture,albumIntro,tabset,albumType from a_album where albumId='%s'", albumId)
	else
		sql = string.format("select A.radioId,A.nameCn,A.nameEn,A.logo,A.url,A.introduction,A.radioLevel,A.provinceSpell,A.cityName,A.classification,B.albumName,B.picture,B.albumId,B.albumIntro,B.tabset,B.albumType from Radio_Info A, a_album B where A.radioID='%s' and B.albumId='%s'", radioId, albumId)
	end

	local res, err = db:query(sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end

	ngx.say(cjson.encode(res))
end

function top_list()
	local ptype = tonumber(args["ptype"])
	local top_sql
	if not ptype then
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	if (ptype == 1) then
		local programType = args["programType"]
		local secondLevel = args["secondLevel"]
		local wh_str = ""
		if programType then
			if not secondLevel then
				wh_str = "and A.programType=" .. programType
			else
				wh_str = "and A.programType=" .. secondLevel .. " and A.secondLevel=" .. secondLevel
			end
		end
		top_sql = string.format("select A.programId,A.programName,A.programUri,A.compere,A.radioId,A.albumId,A.picture,A.programType,A.secondLevel,A.tabSet from a_program A,t_play B where A.programId = B.id and B.ptype=1 %s order by B.duration desc limit %s,%s",wh_str, start, page)
		ngx.say(top_sql)

	elseif (ptype == 2) then
		top_sql = string.format("select A.radioId,A.nameCn,A.nameEn,A.url,A.introduction,A.radioLevel,A.provinceSpell,A.cityName,A.logo,A.classification from Radio_Info A,t_play B where A.radioId = B.id and B.ptype=2 order by B.duration desc limit %s,%s", start, page)
	elseif (ptype == 3) then
		top_sql = string.format("select A.albumId,A.albumName,A.albumIntro,A.tabSet,A.albumType,A.picture from a_album A,t_play B where A.albumId = B.id and B.ptype=3 order by B.duration desc limit %s,%s", start, page)
	else
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end

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
	local user_sql = nil
	local id_sql = nil

	if not userId or not id or not ptype or not num then
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	-- 1:收听时长  2:分享 3:下载 4:喜爱 5:收藏 6:不喜欢 7:电台评论(该操作自己调用)
	local user_action = {
		[1] = "play",
		[2] = "shares",
		[3] = "download",
		[4] = "favorites",
		[5] = "collection",
		[6] = "dislike",
		[7] = "comment",
	}
	local field = user_action[num]
	if not field then
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end

--redis add
	--用户收藏/喜欢/下载..列表
	local set_key = userId .. ":" .. num .. ":" .. ptype
	local red_res,red_err = red:sadd(set_key, id)
	if red_err then
		fm_log(opname, ERR_REDIS_QUERY, red_err)
		return ERR_REDIS_QUERY
	end
	--用户收藏/喜欢/下载..数目统计
	local score=nil
	if (num == 1) then 
		if not duration then
			fm_log(opname, ERR_PARSE_POSTARGS)
			return ERR_PARSE_POSTARGS
		end
		score=duration 
	else score=1 
	end

	local hash_user_key = "user" .. ":" .. user_action[num] .. ":" .. ptype
	local hash_program_key = "program" .. ":" .. user_action[num] .. ":" .. ptype
	local user_res,user_err = red:hincrby(hash_user_key, userId, score)
	if num_err then
		fm_log(opname, ERR_REDIS_QUERY, red_err)
		return ERR_REDIS_QUERY
	end

	local program_res,program_err = red:hincrby(hash_program_key, id, score)
	if num_err then
		fm_log(opname, ERR_REDIS_QUERY, red_err)
		return ERR_REDIS_QUERY
	end

--	
--end
--

	if (num ~= 1) then
		user_sql = string.format("insert t_user (userId,%s) values('%s',1) on duplicate key update %s=%s+1", field, userId, field,field)
		id_sql = string.format("insert t_play (id,ptype,%s) values('%s',%s,1) on duplicate key update %s=%s+1", field, id, ptype, field,field)
	else
		user_sql = string.format("insert t_user (userId,play,duration) values('%s',1,%d) on duplicate key update play=play+1,duration=duration+%d", userId,duration,duration)
		id_sql = string.format("insert t_play (id,ptype,play,duration) values('%s',%s,1,%d) on duplicate key update play=play+1,duration=duration+%d", id,ptype,duration,duration)
	end

	if not user_sql or not id_sql then
		fm_log(opname, ERR_NULL_SQL)
		return ERR_PARSE_POSTARGS
	end

	local res, err = db:query(user_sql .. ";" .. id_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end
	return OK_RES
end

function program_list()
	local radioId = args["radioId"]
	local programId = args["programId"]
	local select_sql = nil

	if radioId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where radioId='%s' order by playTime limit %d,%d", radioId, start, page)
	elseif programId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where programType=(select programType from a_program where programId='%s') limit %d,%d", programId, start, page)
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
	if (init_redis() ~= 0) then
		http_resp(ERR_REDIS_INIT)
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
		["statistics"] = function() return statistics() end, 
	}
	if not op_action[opname] then
		fm_log(opname, ERR_OPNAME)
		http_resp(ERR_OPNAME)	
		return
	end

	local res_code = op_action[opname]()

	if res_code then
		http_resp(res_code)
	end
end

main()
