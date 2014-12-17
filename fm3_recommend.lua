local cjson = require "cjson"
local mysql = require "resty.mysql"
local MYSQL_HOST = "123.57.41.242"
local MYSQL_POST = 3306
local MYSQL_DATABASE = "fm_appserver"
local MYSQL_USER = "lingbanfm"
local MYSQL_PASSWD = "lingban2014"

local DB_TIMEOUT = 5000  --2 sec
local MAX_SIZE = 1024*1024

--初始化mysql连接
function init_mysql()
	db = mysql:new()
	if not db then
	    return 10001
	end
	
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
	    --ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
	    return 10001
	end
	--ngx.say("connected to mysql.")
	return 0
end

function parse_postargs()
	ngx.req.read_body()
	args = ngx.req.get_post_args()
	if not args then
		--ngx.say("failed to get post args: ", err)
		return 10002 
	end
	
	--解析翻页参数
	start = args["start"]
	page = args["page"]
	if not start then start = "0" end
	if not page then page = "20" end
	
	opname = args["opName"]
	if not opname then
		--ngx.say("optype error")
		return 10002
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
	    ngx.say("failed to set keepalive: ", err)
	    return
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
	    return 10008
	end
	if (res == ngx.null) then
		return 10005
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
		return 10011
	end

	--ngx.say(query_sql)
	local res, err, errno, sqlstate = db:query(query_sql) 
	if not res then
		ngx.say("bad result: ", err)
		return 10010
	end
	if res == ngx.null then
		return 10005
	end

	ngx.say(cjson.encode(res))
	return 0
end
--更新排行
function update_top(top_name, id, number)
	local update_sql
	--local tmp = tonumber(number)

	if not id then return 10012 end
	if not number then number=1 end	
	if (type(number) == "string") then number = tonumber(number) end

	if (top_name == "broadcast") then
		update_sql = string.format("update Radio_Info set duration=duration+%d where radioId='%s'", number, id)
	elseif (top_name == "appoint") then
		update_sql = string.format("update Program_Info set orderNumber=orderNumber+%d where ProgramID='%s'", number, id)
	else
		return 10013
	end

	--ngx.say(update_sql)

	local res, err, errno, sqlstate = db:send_query(update_sql) 
	if not res then
		return 10010
	end

	return 0
end

--查找串播单
function query_show(radioId)
	if not radioId then
		return 10008
	end

	local queryShow_sql = string.format("select A.RadioID,A.ProgramID,A.ProgramName,A.Introduction,A.WebSite,B.createTime,B.updateTime,B.playTime,B.Day,B.PlayState from Program_Info A,Program_Time B where B.ProgramID=A.ProgramID and A.radioId='%s' and B.Day=CURDATE() and A.programState=0 group by A.ProgramName order by B.playTime limit %s,%s", radioId, start, page)
	local res, err, errno, sqlstate = db:query(queryShow_sql)
	if not res then
	    return 10009
	end
	if (res == ngx.null) then
		return 10005
	end

	ngx.say(cjson.encode(res))
	return 0
end

function slacker_radio()
	local select_sql
	local programType = args["programType"]
	if not programType or (programType == "") then
		select_sql = string.format("select programId,programName,programUri,picture from a_program order by duration limit %d,%d", start, page)	
	else
		select_sql = "select programId,programName,programUri,programIntro,picture,sharesCount,favoritesCount from a_program where programType="
		for number in string.gfind(programType, '%d+') do
			select_sql = string.format("%s%s or programType=", select_sql, number)
		end
		select_sql = string.sub(select_sql, 0, -16)
		select_sql = string.format("%s order by duration limit %d,%d", select_sql, start, page)
	end

	ngx.say(select_sql)
	local res, err = db:query(select_sql)
	if not res then
		ngx.say("error ", err)
	    return 10009
	end

	ngx.say(cjson.encode(res))
end

function program_info()	
	local programId = args["programId"]	
	if not programId then 
		return -1
	end
	local select_sql = string.format("select A.albumId,A.albumName,A.picture,B.radioID,B.nameCn,B.logo from Radio_Info B,a_album A, a_program C where C.programId='%s' and B.radioID=C.radioID and A.albumId = C.albumId", programId)

	ngx.say(select_sql)
	local res, err = db:query(select_sql)
	if not res then
		ngx.say("error ", err)
	    return 10009
	end
	ngx.say(cjson.encode(res))
end

function programList()
	local radioId = args["radioId"]
	local albumId = args["albumId"]
	local programId = args["programId"]
	local select_sql

	if albumId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where albumId='%s' order by playTime limit %d,%d", albumId, start, page)
	elseif radioId then
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where radioId='%s' order by playTime limit %d,%d", radioId, start, page)
	elseif programId then
		result_sql = string.format("select compere,programType from a_program where programId='%s'", programId)
		local res, err = db:query(result_sql)
		if not res then
			ngx.say("error ", err)
		    return 10009
		end
		local compere = res[1]["compere"]
		local programType = res[1]["programType"]
		if not compere or not programType then
			return -1
		end
		select_sql = string.format("select programId,programName,programUri,playTime,bytes from a_program where compere='%s' and programType=%d limit %d,%d", compere, programType, start, page)
	end

	ngx.say(select_sql)
	local res, err = db:query(select_sql)
	if not res then
		ngx.say("error ", err)
	    return 10009
	end
	ngx.say(cjson.encode(res))
end

--函数入口
function main()
	local res_code
	local res_code = init_mysql()
	if ( res_code ~= 0 ) then
		error_res(res_code)
		return
	end
	--解析post参数
	res_code = parse_postargs()
	if( res_code ~= 0) then
		error_res(res_code)
		return
	end

	writeFile("liuq test")

	--个性电台节目列表
	if (opname == "slackerRadio") then
		slacker_radio()
	
	--获取节目所属电台专辑
	elseif (opname == "programInfo") then
		program_info()	

	--电台节目列表
	elseif (opname == "programList") then
		programList()
	
	--查询串播单	
	elseif (opname == "queryShow") then

	--查询排行榜信息
	elseif (opname == "queryTop") then

	elseif (opname == "updateTop") then
	else
		error_res(10000)
		return
	end
	
	close_mysql()
end

main()
