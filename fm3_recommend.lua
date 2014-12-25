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
local ERR_MYSQL_CONNECT = 80003
local ERR_MYSQL_CLOSE = 80004
local ERR_OPNAME = 80005


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
		fm_log(opname, ERR_MYSQL_CONNECT, err)
	    return ERR_MYSQL_CONNECT
	end
	return OK_RES
end

function parse_postargs()
	ngx.req.read_body()
	args = ngx.req.get_post_args()
	if not args then
		fm_log(opname, ERR_MYSQL_CONNECT, err)
		return ERR_PARSE_POSTARGS 
	end
	
	--解析翻页参数
	start = args["start"]
	page = args["page"]
	if not start then start = "0" end
	if not page then page = "20" end
	
	opname = args["opName"]
	if not opname then
		fm_log(opname, ERR_PARSE_POSTARGS, err)
		return ERR_PARSE_POSTARGS
	end
	return 0
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
		return ERR_MYSQL_CLOSE
	end
	return 0
end


function error_res(err_code)	
	local describe = "describe"
	local res_json = {
		errorId = err_code, desc = describe
	}
	close_mysql()
	ngx.say(cjson.encode(res_json))
end

--搜索电台信息
function search_fm(fm_name)
	local searchFm_sql = string.format("select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo,classification from Radio_Info where radioState=0 and (nameCn like '%%%s%%' or nameEn like '%%%s%%') limit %s,%s", fm_name, fm_name, start, page)
	
	local res, err, errno, sqlstate = db:query(searchFm_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end

	ngx.say(cjson.encode(res))
	return 0
end

--查询排行
function query_top(top_name)
	local query_sql
	if (top_name == "broadcast") then
		query_sql = string.format("select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo from Radio_Info where radioState=0 order by duration desc limit %s,%s", start, page)
	elseif (top_name == "appoint") then
		query_sql = string.format("select A.programID,A.radioID,A.programName,A.introduction,B.playtime,C.nameCn from Program_Info A,Program_Time B,Radio_Info C where B.ProgramID=A.ProgramID and C.RadioID=A.RadioID group by A.programID order by orderNumber desc limit %s,%s", start, page)
	else
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end

	local res, err, errno, sqlstate = db:query(query_sql) 
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end

	ngx.say(cjson.encode(res))
	return 0
end
--更新排行
function update_top(top_name, id, number)
	local update_sql
	--local tmp = tonumber(number)

	if not id then 
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	if not number then number=1 end	
	if (type(number) == "string") then number = tonumber(number) end

	if (top_name == "broadcast") then
		update_sql = string.format("update Radio_Info set duration=duration+%d where radioId='%s'", number, id)
	elseif (top_name == "appoint") then
		update_sql = string.format("update Program_Info set orderNumber=orderNumber+%d where ProgramID='%s'", number, id)
	else
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end

	local res, err, errno, sqlstate = db:send_query(update_sql) 
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end

	return 0
end

--查找串播单
function query_show(radioId)
	if not radioId then
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end

	local queryShow_sql = string.format("select A.RadioID,A.ProgramID,A.ProgramName,A.Introduction,A.WebSite,B.createTime,B.updateTime,B.playTime,B.Day,B.PlayState from Program_Info A,Program_Time B where B.ProgramID=A.ProgramID and A.radioId='%s' and B.Day=CURDATE() and A.programState=0 group by A.ProgramName order by B.playTime limit %s,%s", radioId, start, page)
	local res, err, errno, sqlstate = db:query(queryShow_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end
	if (res == ngx.null) then
		return 10005
	end

	ngx.say(cjson.encode(res))
	return 0
end

function slacker_radio()
	local select_sql
	local phoneIdentify = args["phoneIdentify"]
	local programType = args["programType"]
	ngx.say(programType)

	if not phoneIdentify then 
		fm_log(opname, ERR_PARSE_POSTARGS)
		return ERR_PARSE_POSTARGS
	end
	if not programType or (programType == "") then
		select_sql = string.format("select programId,programName,programUri,picture,programIntro,radioId,albumId from a_program order by duration limit %d,%d", start, page)	
	else
		select_sql = "select programId,programName,programUri,picture,programIntro,radioId,albumId from a_program where programType="
		for number in string.gfind(programType, '%d+') do
			select_sql = string.format("%s%s or programType=", select_sql, number)
		end
		select_sql = string.sub(select_sql, 0, -16)
		select_sql = string.format("%s order by duration limit %d,%d", select_sql, start, page)
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

	return 0
end

function program_info()	
	local radioId = args["radioId"]	
	local albumId = args["albumId"]
	local sql

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
	return 0
end

function programList()
	local radioId = args["radioId"]
	local albumId = args["albumId"]
	local programId = args["programId"]
	local select_sql

	if albumId then
		select_sql = string.format("select albumId,albumName,picture,albumIntro,tag,albumType,sharesCount from a_album where albumId='%s'", albumId)
	elseif radioId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where radioId='%s' order by playTime limit %d,%d", radioId, start, page)
	elseif programId then
		result_sql = string.format("select compere,programType from a_program where programId='%s'", programId)
		local res, err = db:query(result_sql)
		if not res then
			fm_log(opname, ERR_MYSQL_QUERY, err)
			return ERR_MYSQL_QUERY
		end
		local compere = res[1]["compere"]
		local programType = res[1]["programType"]
		if not compere or not programType then
			fm_log(opname, ERR_PARSE_POSTARGS)
			return ERR_PARSE_POSTARGS
		end
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where compere='%s' and programType=%d limit %d,%d", compere, programType, start, page)
	end

	local res, err = db:query(select_sql)
	if not res then
		fm_log(opname, ERR_MYSQL_QUERY, err)
		return ERR_MYSQL_QUERY
	end
	ngx.say(cjson.encode(res))
	return 0
end

--函数入口
function main()
	local res_code = init_mysql()
	if ( res_code ~= 0 ) then
		error_res(res_code)
		return
	end
	--解析post参数
	res_code = parse_postargs()
	--个性电台节目列表
	if (opname == "slackerRadio") then
		res_code = slacker_radio()
	--获取节目所属电台专辑信息
	elseif (opname == "programInfo") then
		res_code = program_info()	
	--电台/专辑 节目列表
	elseif (opname == "programList") then
		res_code = programList()
	--查询串播单	
	elseif (opname == "queryShow") then

	--查询排行榜信息
	elseif (opname == "queryTop") then

	elseif (opname == "updateTop") then
	else
		fm_log(opname, ERR_OPNAME, err)
		res_code = 80005 
	end

	if( res_code ~= 0) then
		error_res(res_code)
		return
	end
	
	close_mysql()
end

main()
