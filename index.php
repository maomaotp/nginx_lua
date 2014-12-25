<?php

main();
function main()
{
	#解析post请求内容
	$keywords = $_POST["keywords"];
	$type = $_POST["type"];
	$start = $_POST["start"];
	$page = $_POST["page"];
	if(!$start){ 
		$start = 0;
	}
	if(!$page){
		$page = 20;
	}

	$connection = init_db();

	$unicode = str2Unicode($keywords);

	if ($type == "program"){
		$query_sql = "select programId,programName,programUri,programIntro from a_program where MATCH(searchindex) AGAINST('$unicode')order by duration limit $start,$page";
	}
	elseif ($type == "radio"){
		$query_sql = "select radioId,nameCn,nameEn,url,webSite,introduction,address,zip,scheduleURL,radioLevel,provinceSpell,cityName,createTime,updateTime,logo,classification from Radio_Info where radioState=0 and (nameCn like '%%$keywords%%' or nameEn like '%%$keywords%%') limit $start,$page";
	}
	elseif ($type == "album"){
		$query_sql = "select albumId,albumName,albumIntro,albumType,sharesCount,downloadNumber,picture from a_album where flag=1 and(albumName like '%%$keywords%%' or tag like '%%$keywords%%') limit $start,$page";
	}
	else{
	}
	echo "$query_sql\n";

	$records = array(); 
	$select_res = mysql_query($query_sql) or die("query failed\n");
	while($r = mysql_fetch_assoc($select_res)){
		$records[] = $r;	
	}
	$json = json_encode($records); 
	echo $json;

	mysql_close($connection);
}

#解析post请求
function init_db()
{
	$host = "123.57.41.242";
	$db = "fm_appserver";
	$user = "lingbanfm";
	$pass = "lingban2014";

	#连接mysql
	$connection = mysql_connect($host, $user, $pass);
	if (!$connection){
		die("database server connection failed.");
	}
	$dbconnect = mysql_select_db($db, $connection);
	if (!$dbconnect){
		die("unable to connect to the specified database!");
	}

	return $connection;
}

#编码转换
function str2Unicode($str, $encoding = 'UTF-8') 
{
	$str = iconv($encoding, 'UCS-2', $str);
	$arr = str_split($str, 2);
	$unicode = '';
	foreach ($arr as $tmp) {
	    $dec = hexdec(bin2hex($tmp));
		$unicode .= $dec . ' ';
	}
	return $unicode;
}


#增加全文索引字段
function add_index()
{
	for($i=0; $i<=2; $i++){
		$query = "select programId,programName,compere,tabSet from a_program";
		$start = $i*10;
		$limit = "limit $start,10";
		$select_sql = $query . " " . $limit;
	
		$select_res = mysql_query($select_sql) or die("query failed");
		while($r = mysql_fetch_array($select_res)){
			$programId = $r["programId"];
			$str = $r["programName"] . "" . $r["compere"] . "" . $r["tabSet"];
			$unicode = str2Unicode($str);
			
			$update = "update a_program set searchindex='$unicode' where programId='$programId'";
			echo "$update\n";
			mysql_query($update) or die("update failed");
		}
		mysql_free_result($select_res);
	}
}

function get_program($keywords,$start,$page)
{
	$unicode = str2Unicode($keywords);
	$query_sql = "select programId,programName,programUri,programIntro from a_program where MATCH(searchindex) AGAINST('$unicode')order by duration limit $start,$page";
	
	$records = array(); 
	$select_res = mysql_query($query_sql) or die("query failed\n");
	while($r = mysql_fetch_assoc($select_res)){
		$records[] = $r;	
	}
	$json = json_encode($records); 
	echo $json;
}

?>


