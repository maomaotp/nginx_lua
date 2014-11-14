--query mysql

local cjson = require "cjson"
local mysql = require "resty.mysql"

local db, err = mysql:new()
if not db then
    ngx.say("failed to instantiate mysql: ", err)
    return
end

db:set_timeout(2000) -- 1 sec
local ok, err, errno, sqlstate = db:connect{
    host = "123.57.41.242",
    port = 3306,
    database = "test",
    user = "dba",
    password = "123456",
    max_packet_size = 1024 * 1024
}

if not ok then
    ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
    return
end

--ngx.say("connected to mysql.")

ngx.req.read_body()
local args, err = ngx.req.get_post_args()
if not args then
	ngx.say("failed to get post args: ", err)
	return 
end

--解析翻页参数
local start = args["start"]
local page = args["page"]
if not start then start = "0" end
if not page then page = "20" end

local opname = args["opName"]
if not opname then
	ngx.say("optype error")
	return 
end

--查询电台信息
if (opname == "queryfm") then
	local city_name = args["cityName"]	
	local radio_level = args["radioLevel"]	
	local queryfm_sql

	if(city_name ~= nil) then
		queryfm_sql = string.format( "select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo from Radio_Info where cityName='%s' and radioState=0 limit %s,%s", city_name, start, page)
	elseif(radio_level ~= nil) then
		queryfm_sql = string.format( "select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo from Radio_Info where radioLevel='%s' and radioState=0 limit %s,%s", radio_level, start, page)
	else
		ngx.say("queryFm: error args")
	end

	if not queryfm_sql then
		ngx.say("here")
		return 
	end
	ngx.say(queryfm_sql)

	res, err, errno, sqlstate = db:query(queryfm_sql, 20)
	if not res then
	    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
	    return
	end
--查询市区信息	
elseif (opname == "queryCity") then
	local provinceSpell = args["provinceSpell"]	
	if not provinceSpell then
		ngx.say("queryCity:error args")
	end

	local queryCity_sql = string.format("select cityName from Radio_Info where provinceSpell='%s' group by cityName limit %s,%s", provinceSpell, start, page)
	res, err, errno, sqlstate = db:query(queryCity_sql, 20)
	if not res then
	    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
	    return
	end

--搜索电台信息
elseif (opname == "searchFm") then
	local fm_name = args["fmName"]

	local searchFm_sql = string.format("select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo from Radio_Info where radioState=0 and (nameCn like '%%%s%%' or nameEn like '%%%s%%') limit %s,%s", fm_name, fm_name, start, page)

	res, err, errno, sqlstate = db:query(searchFm_sql, 20)
	if not res then
	    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
	    return
	end

elseif (opname == "queryShow") then
	local radioId = args["radioId"]

	res, err, errno, sqlstate =
	    db:query("select A.RadioID,A.ProgramName,A.Introduction,A.WebSite,B.createTime,B.updateTime,B.playTime,B.Day,B.PlayState from Program_Info A,Program_Time B where B.ProgramID=A.ProgramID and A.radioId='%s' and B.Day=CURDATE() and A.programState=0 group by A.ProgramName order by B.playTime limit 20", 20)
	if not res then
	    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
	    return
	end

else
	res = {errorId="10000", desc = "the error opname"}
end

ngx.say(cjson.encode(res))

--close the mysql connection:
local ok, err = db:close()
if not ok then
    ngx.say("failed to close: ", err)
    return
end

-- put it into the connection pool of size 100,
-- with 10 seconds max idle timeout
--local ok, err = db:set_keepalive(10000, 100)
--if not ok then
--    ngx.say("failed to set keepalive: ", err)
--    return
--end

