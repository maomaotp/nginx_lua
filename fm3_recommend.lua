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
local ERR_INEXIST_TYPE = 80010

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
	[80010] = "不存在的节目类型",
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

	local src_sql = "select programId,programName,programUri,compere,picture,programIntro,radioId,albumId,programType,secondLevel,duration from a_program"
	if not programType or (programType == "") then
		select_sql = string.format("%s limit %d,%d", src_sql, start, page)
	else
		select_sql = src_sql .. " where programType="
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

	local rank_key = "rank:program:play:" .. ptype

	local list,list_err = red:zrange(rank_key, 0, -1)
	if list_err then
		fm_log(opname, ERR_REDIS_QUERY, red_err)
		return ERR_REDIS_QUERY
	end
	
	local field = ""
	local list_len = table.getn(list)
	if (list_len == 0) then
		ngx.say("[]")
		return
	else
		for i=1, list_len do
			field = field .. "'" .. list[i] .. "'," 
		end
		--切掉字符串末尾的','
		field = string.sub(field, 0,-2)
	end

	local action = {
		[1] = string.format("select programId,programName,programUri,compere,radioId,albumId,picture,programType,secondLevel,tabSet from a_program where programId in (%s)",field),
		[2] = string.format("select radioId,nameCn,nameEn,url,introduction,radioLevel,provinceSpell,cityName,logo,classification from Radio_Info where radioId in (%s) order by field (radioId,%s) limit %s,%s", field, field, start, page),
		[3] = string.format("select albumId,albumName,albumIntro,tabSet,albumType,picture from a_album where albumId in (%s) order by field (albumId,%s) limit %s,%s", field, field, start, page),
	}

	if not action[ptype] then
		fm_log(opname, ERR_INEXIST_TYPE)
		return ERR_INEXIST_TYPE
	end

	if (ptype == 1) then
		local programType = args["programType"]
		local secondLevel = args["secondLevel"]

		if programType then
			if not secondLevel then
				action[ptype] = action[ptype] .. " and programType=" .. programType
			else
				action[ptype] = action[ptype] .. " and programType=" .. programType .. " and secondLevel=" .. secondLevel
			end
		end
		action[ptype] = string.format("%s order by field (programId,%s) limit %s,%s", action[ptype], field, start, page)
	end

	local res, err = db:query(action[ptype])
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
	-- 1:收听时长  2:分享 3:下载 4:喜爱 5:收藏 6:不喜欢 7:电台评论(该操作自己调用) 8:预定
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
	local set_key = "list:" .. userId .. ":" .. num
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

	local user_key = "rank:user" .. ":" .. user_action[num]
	local program_key = "rank:program" .. ":" .. user_action[num] .. ":" .. ptype

	local user_res,user_err = red:zincrby(user_key, score, userId)
	if num_err then
		fm_log(opname, ERR_REDIS_QUERY, red_err)
		return ERR_REDIS_QUERY
	end

	local program_res,program_err = red:zincrby(program_key, score, id)
	if num_err then
		fm_log(opname, ERR_REDIS_QUERY, red_err)
		return ERR_REDIS_QUERY
	end
end

function order_list()
	local userId = args["userId"]
	local mtype = tonumber(args["mtype"])

	local list_key = "list:" .. userId .. ":" .. mtype
	local list,list_err = red:srandmember(list_key,20)
	if list_err then
		fm_log(opname, ERR_REDIS_QUERY, red_err)
		return ERR_REDIS_QUERY
	end

	local field = ""
	local list_len = table.getn(list)
	if (list_len == 0) then
		ngx.say("[]")
	else
		for i=1, list_len do
			field = field .. "'" .. list[i] .. "'," 
		end
		--切掉字符串末尾的','
		field = string.sub(field, 0,-2)
	
		local list_sql = string.format("select programId,programName,programUri,programIntro,radioId,albumId,compere,picture,programType,secondLevel,tabSet from a_program where programId in (%s)",field)
		local res, err = db:query(list_sql)
		if not res then
			fm_log(opname, ERR_MYSQL_QUERY, err)
			return ERR_MYSQL_QUERY
		end
		ngx.say(cjson.encode(res))
	end
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

function search() 
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
		["myprogram"] = function() return order_list() end,  --获取收藏/预定节目列表
		["search"] = function() return search() end,
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
