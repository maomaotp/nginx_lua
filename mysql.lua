local cjson = require "cjson"
local mysql = require "resty.mysql"
local MYSQL_HOST = "123.57.41.242"
local MYSQL_POST = 3306
local MYSQL_DATABASE = "test"
local MYSQL_USER = "lingbanfm"
local MYSQL_PASSWD = "lingban2014"

local DB_TIMEOUT = 2000  --2 sec
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

--查询电台信息
function query_fm(city_name, radio_level, classification)
	if not city_name then
		queryfm_sql = string.format( "select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo,classification from Radio_Info where cityName='%s' and radioState=0 limit %s,%s", city_name, start, page)
	elseif not radio_level then
		queryfm_sql = string.format( "select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo,classification from Radio_Info where radioLevel='%s' and radioState=0 limit %s,%s", radio_level, start, page)
	elseif not classification then
		queryfm_sql = string.format( "select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo,classification from Radio_Info where classification='%s' and radioState=0 limit %s,%s", classification, start, page)
	else
		return 10003
	end
	
	local res, err, errno, sqlstate = db:query(queryfm_sql)
	if not res then
	    return 10004
	end

	ngx.say(cjson.encode(res))
	return 0
end
--查询市区信息
function query_city(provinceSpell)
	if not provinceSpell then
		return 10006
	end
	
	local queryCity_sql = string.format("select cityName from Radio_Info where provinceSpell='%s' group by cityName limit %s,%s", provinceSpell, start, page)
	local res, err, errno, sqlstate = db:query(queryCity_sql)
	if not res then
	    return 10007
	end
	--ngx.say(queryCity_sql)

	ngx.say(cjson.encode(res))
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

function error_res(err_code)	
	local describe = "describe"
	local res_json = {
		errorId = err_code, desc = describe
	}
	close_mysql()
	ngx.say(cjson.encode(res_json))
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

	--查询电台信息
	if (opname == "queryFm") then
		local city_name = args["cityName"]	
		local radio_level = args["radioLevel"]	
		local classification = args["classification"]
		local res_code = query_fm(city_name, radio_level, classification)
	
	--查询市区信息	
	elseif (opname == "queryCity") then
		local provinceSpell = args["provinceSpell"]	
		local res_code = query_city(provinceSpell)
		if ( res_code ~= 0 ) then
			error_res(res_code)
			return
		end
	
	--查询串播单	
	elseif (opname == "queryShow") then
		local radioId = args["radioId"]
		local res_code = query_show(radioId)
		if ( res_code ~= 0 ) then
			error_res(res_code)
			return
		end
	
	else
		error_res(10000)
		return
	end
	
	close_mysql()
end

main()
