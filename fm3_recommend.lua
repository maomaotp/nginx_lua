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

local DB_TIMEOUT = 8000  --5 sec
local MAX_SIZE = 1024*1024
local USER_LOG = "/home/work/logs/fm"

--key
local SEARCH_KEY_REDIS = "rank:hotwords"

--res code
local OK_RES = 0
local ERR_PARSE_POSTARGS = 80001
local ERR_MYSQL_INIT = 80003
local ERR_OPNAME = 80005
local ERR_NULL_SQL = 80006
local ERR_READ_POST_BODY = 80007
local ERR_REDIS_INIT = 80008
local ERR_REDIS_QUERY = 80009
local ERR_INEXIST_TYPE = 80010
local ERR_NULL_SEARCH = 80011
local ERR_INEXIST_PTYPE = 80012
local ERR_NULL_PHONEIDENTIFY = 80013
local ERR_GET_RECOMMENT = 80014
local ERR_NULL_RADIOALBUM = 80015
local ERR_GET_RADIOALBUMINFO = 80016
local ERR_GET_TOP = 80017
local ERR_INEXIST_PTYPE = 80018
local ERR_INEXIST_USERID = 80019
local ERR_INEXIST_ACTION = 80020
local ERR_FAIL_STATISTICS = 80021
local ERR_FAIL_DURATION = 80022
local ERR_FAIL_STATICSNUM = 80023
local ERR_FAIL_ORDERLIST = 80024
local ERR_FAIL_HOTWORDS = 80025
local ERR_FAIL_FM = 80026
local ERR_FAIL_CITY = 80027
local ERR_FAIL_SHOW = 80028

--[[lua写日志
function fm_log(opName, code, err)
	local file = string.format("%s_%s.log", USER_LOG, os.date("%Y%m"))
	local f = assert(io.open(file, "a"))
	f:write(string.format("%s %s %s %s\n", os.date("%Y-%m-%d %H:%M:%S"), opName, code, err))
	f:close()
end
]]

--初始化mysql、redis
function init_db()
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
		ngx.log(ngx.ERR, err)
		http_resp(ERR_MYSQL_INIT)
	end

	--初始化redis
	red = assert(redis:new())
    red:set_timeout(REDIS_TIMEOUT) -- 1 sec

    local ok, err = red:connect(REDIS_SERVER_IP, REDIS_SERVER_PORT)
    if not ok then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_REDIS_INIT)
    end
end

function parse_postargs()
	ngx.req.read_body()
	args,err = ngx.req.get_post_args()
	if not args then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_READ_POST_BODY)
	end
	
	--解析翻页参数
	start = args["start"] or 0
	page = args["page"] or 20
end

function close_db()
	--mysql关闭连接
--	local ok, err = db:close()
--	if not ok then
--	    ngx.say("failed to close: ", err)
--	    return 10010
--	end

-- put it into the connection pool of size 100,
-- with 10 seconds max idle timeout
	local ok, err = db:set_keepalive(30000, 100)
	if not ok then
		ngx.log(ngx.ERR, err)
	end

	--redis close
-- put it into the connection pool of size 100,
-- with 10 seconds max idle time
    local ok, err = red:set_keepalive(30000, 100)
    if not ok then
		ngx.log(ngx.ERR, err)
    end

    -- or just close the connection right away:
--     local ok, err = red:close()
--     if not ok then
--         ngx.say("failed to close: ", err)
--         return 10000
--     end
end

function http_resp(code)	
	local err_array = {
		[0] = "OK",
		[80001] = "请求参数错误",
		[80002] = "数据库请求错误",
		[80003] = "数据库初始化错误",
		[80005] = "方法名错误",
		[80006] = "数据库请求错误",
		[80007] = "获取post body内容错误",
		[80008] = "redis初始化错误",
		[80009] = "redis查询错误",
		[80010] = "不存在的节目类型",
		[80011] = "关键词为null",
		[80012] = "错误的ptype类型",
		[80013] = "获取手机唯一标识码错误",
		[80014] = "获取个性电台失败",
		[80015] = "电台ID和专辑ID不可同时为空",
		[80016] = "获取专辑或电台信息失败",
		[80017] = "获取排行信息失败",
		[80018] = "不存在的ID类型",
		[80019] = "用户ID/节目ID/类型不可为空",
		[80020] = "不存在的行为类型",
		[80021] = "统计用户行为信息失败",
		[80022] = "获取节目播放时长失败",
		[80023] = "更新用户行为统计数据信息失败",
		[80024] = "获取节目列表失败",
		[80025] = "获取热词失败",
		[80026] = "获取电台信息错误",
		[80027] = "获取城市电台信息错误",
		[80028] = "获取传播单信息失败",
	}

	close_db()
	local res_str = string.format('{"describe":"%s","code":%d}', err_array[code],code)
	ngx.say(res_str)
	ngx.exit(ngx.HTTP_OK)
end

--获取个性电台
function radio_recommend()
	local select_sql = nil
	local phoneIdentify = args["phoneIdentify"]
	local programType = args["programType"]

	if not phoneIdentify then 
		ngx.log(ngx.ERR, ERR_NULL_PHONEIDENTIFY)
		http_resp(ERR_NULL_PHONEIDENTIFY)
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
		ngx.log(ngx.ERR, err)
		http_resp(ERR_GET_RECOMMENT)
	end
	ngx.say(cjson.encode(res))

	--更新用户标签
	local user_sql = string.format("insert into u_userInfo (userId,userTag) values('%s', '%s') on duplicate key update userTag='%s'", phoneIdentify, programType, programType)
	local res, err = db:query(user_sql)
	if not res then
		ngx.log(ngx.ERR, err)
	end
end

function program_info()	
	local radioId = args["radioId"]	
	local albumId = args["albumId"]
	local sql = nil

	if not radioId and not albumId then
		ngx.log(ngx.ERR, ERR_NULL_RADIOALBUM)
		http_resp(ERR_NULL_RADIOALBUM)
	elseif radioId and not albumId then
		sql = string.format("select radioId,nameCn,nameEn,logo,url,introduction,radioLevel,provinceSpell,cityName,classification,isOffline from Radio_Info where radioID='%s'", radioId)
	elseif albumId and not radioId then
		sql = string.format("select albumId,albumName,picture,albumIntro,tabset,albumType,updateTime from a_album where albumId='%s'", albumId)
	else
		sql = string.format("select A.radioId,A.nameCn,A.nameEn,A.logo,A.url,A.introduction,A.radioLevel,A.isOffline,A.provinceSpell,A.cityName,A.classification,B.albumName,B.picture,B.albumId,B.albumIntro,B.tabset,B.albumType,B.updateTime from Radio_Info A, a_album B where A.radioID='%s' and B.albumId='%s'", radioId, albumId)
	end

	local res, err = db:query(sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_GET_RADIOALBUMINFO)
	end
	ngx.say(cjson.encode(res))
end

function top_list()
	local ptype = tonumber(args["ptype"]) or 0
	local top_sql = nil
	local field = ""

	local rank_key = "rank:program:play:" .. ptype

	local list,list_err = red:zrange(rank_key, 0, -1)
	if list_err then
		ngx.log(ngx.ERR, list_err)
		http_resp(ERR_GET_TOP)
	end
	
	local list_len = table.getn(list)
	if (list_len == 0) then
		ngx.say("{}")
		ngx.exit(ngx.HTTP_OK)
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
		[2] = string.format("select radioId,nameCn,nameEn,url,introduction,radioLevel,provinceSpell,cityName,logo,classification,isOffline from Radio_Info where radioId in (%s) order by field (radioId,%s) limit %s,%s", field, field, start, page),
		[3] = string.format("select albumId,albumName,albumIntro,tabSet,albumType,picture,updateTime from a_album where albumId in (%s) order by field (albumId,%s) limit %s,%s", field, field, start, page),
	}

	if not action[ptype] then
		ngx.log(ngx.ERR, ERR_INEXIST_PTYPE)
		http_resp(ERR_INEXIST_PTYPE)
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
		ngx.log(ngx.ERR, err)
		http_resp(ERR_GET_TOP)
	end
	ngx.say(cjson.encode(res))
end

function statistics()
	local userId = args["userId"]
	local id = args["id"]
	local ptype = args["ptype"]
	local index = tonumber(args["operate"]) or 0
	local duration = args["duration"]

	local user_sql = nil
	local id_sql = nil

	if not userId or not id or not ptype then
		ngx.log(ngx.ERR, ERR_INEXIST_USERID)
		http_resp(ERR_INEXIST_USERID)
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
	local field = user_action[index]
	if not field then
		ngx.log(ngx.ERR, ERR_INEXIST_ACTION)
		http_resp(ERR_INEXIST_ACTION)
	end

--redis add
	--用户收藏/喜欢/下载..列表
	local set_key = "list:" .. userId .. ":" .. index
	local red_res,red_err = red:sadd(set_key, id)
	if not red_res then
		ngx.log(ngx.ERR, red_err)
		http_resp(ERR_FAIL_STATISTICS)
	end

	--用户收藏/喜欢/下载..数目统计
	local score=nil
	if (index == 1) then 
		if not duration then
			ngx.log(ngx.ERR, ERR_FAIL_DURATION)
			http_resp(ERR_FAIL_DURATION)
		end
		score=duration 
	else score=1 
	end

	local user_key = "rank:user" .. ":" .. user_action[index]
	local program_key = "rank:program" .. ":" .. user_action[index] .. ":" .. ptype

	local user_res,user_err = red:zincrby(user_key, score, userId)
	local program_res,program_err = red:zincrby(program_key, score, id)
	if not user_res or not program_res then
		user_err = user_err or program_err
		ngx.log(ngx.ERR, user_err)
		http_resp(ERR_FAIL_STATICSNUM)
	end
end

--获取收藏/预定节目列表
function order_list()
	local userId = args["userId"]
	local mtype = tonumber(args["mtype"]) or 0

	local list_key = "list:" .. userId .. ":" .. mtype
	local list,list_err = red:srandmember(list_key,20)
	if not list then
		ngx.log(ngx.ERR, list_err)
		http_resp(ERR_FAIL_ORDERLIST)
	end

	local field = ""
	local list_len = table.getn(list)
	if (list_len == 0) then
		ngx.say("{}")
		ngx.exit(ngx.HTTP_OK)
	else
		for i=1, list_len do
			field = field .. "'" .. list[i] .. "'," 
		end
		--切掉字符串末尾的','
		field = string.sub(field, 0,-2)
	
		local list_sql = string.format("select programId,programName,programUri,programIntro,radioId,albumId,compere,picture,programType,secondLevel,tabSet from a_program where programId in (%s)",field)
		local res, err = db:query(list_sql)
		if not res then
			ngx.log(ngx.ERR, err)
			http_resp(ERR_FAIL_ORDERLIST)
		end
		ngx.say(cjson.encode(res))
	end
end

function program_list()
	local radioId = args["radioId"]
	local programId = args["programId"]
	local albumId = args["albumId"]
	local select_sql = nil

	if radioId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where radioId='%s' limit %d,%d", radioId, start, page)
	elseif programId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where programType=(select programType from a_program where programId='%s') limit %d,%d", programId, start, page)
	elseif albumId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where albumId='%s' limit %d,%d", albumId, start, page)
	else
		ngx.log(ngx.ERR, ERR_NULL_RADIOALBUM)
		http_resp(ERR_NULL_RADIOALBUM)
	end

	local res, err = db:query(select_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_ORDERLIST)
	end
	ngx.say(cjson.encode(res))
end

function search() 
	local keywords = args["keywords"]
	if not keywords then
		ngx.log(ngx.ERR, "null keywords")
	end
	local red_res,red_err = red:zincrby(SEARCH_KEY_REDIS, 1, keywords)
	if red_err then
		ngx.log(ngx.ERR, red_err)
	end
end

function hot_words()
	local red_res,red_err = red:zrange(SEARCH_KEY_REDIS, start, page-1)
	if not red_res then
		ngx.log(ngx.ERR, red_err)
		http_resp(ERR_FAIL_HOTWORDS)
	end
	ngx.say(cjson.encode(red_res))
end


function query_fm()
	local city_name = args["cityName"]	
	local radio_level = args["radioLevel"]	
	local classification = args["classification"]

	if not city_name then
		field = string.format("cityName='%s'", city_name)
	elseif not radio_level then
		field = string.format("radioLevel='%s'", radio_level)
	elseif not classification then
		field = string.format("classification='%s'", classification)
	else
		http_resp(ERR_PARSE_POSTARGS)
	end
	queryfm_sql = string.format("select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo,classification,isOffline from Radio_Info where radioState=0 and %s limit %s ,%s", field, start, page)

	local res, err, errno, sqlstate = db:query(queryfm_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_FM)
	end

	ngx.say(cjson.encode(res))
end

function query_show()
	local radioId = args["radioId"]
	if not radioId then
		http_resp(ERR_PARSE_POSTARGS)
	end

	local queryShow_sql = string.format("select A.radioId,A.ProgramID,A.ProgramName,A.Introduction,A.WebSite,B.createTime,B.updateTime,B.playTime,B.Day,B.PlayState from Program_Info A,Program_Time B where B.ProgramID=A.ProgramID and A.radioId='%s' and B.Day=CURDATE() and A.programState=0 group by A.ProgramName order by B.playTime limit %s,%s", radioId, start, page)
	local res, err = db:query(queryShow_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_SHOW)
	end

	ngx.say(cjson.encode(res))
end

function query_city() 
	local provinceSpell = args["provinceSpell"]	
	if not provinceSpell then
		http_resp(ERR_PARSE_POSTARGS)
	end
	
	local queryCity_sql = string.format("select cityName from Radio_Info where provinceSpell='%s' group by cityName limit %s,%s", provinceSpell, start, page)
	local res, err = db:query(queryCity_sql)
	if not res then
		ngx.log(ngx.ERR, err)
		http_resp(ERR_FAIL_CITY)
	end

	ngx.say(cjson.encode(res))
end

function main()
	init_db()
	parse_postargs()

	local op_action = {
		--点播
		["slackerRadio"] = function() return radio_recommend() end,
		["programInfo"] = function() return program_info() end,
		["programList"] = function() return program_list() end,
		["top"] = function() return top_list() end,
		["statistics"] = function() return statistics() end, 
		["myprogram"] = function() return order_list() end,  --获取收藏/预定节目列表
		["hotwords"] = function() return hot_words() end,
		["search"] = function() return search() end,
		--直播二期接口
		["queryCity"] = function() return query_city() end,
		["queryShow"] = function() return query_show() end,
		["queryFm"] = function() return query_fm() end,
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
