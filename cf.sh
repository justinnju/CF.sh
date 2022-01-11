#!/bin/sh
# random cloudflare anycast ip

cd /tmp/home/root

#read -p "请设置期望到 CloudFlare 服务器的带宽大小(单位 Mbps):" bandwidth
bandwidth=20


speed=$(($bandwidth*128*1024))
starttime=`date +'%Y-%m-%d %H:%M:%S'`


time="3600"
endtimestamp=$(($(cut -d '.' -f1 /proc/uptime) + $time))   #跑一小时还没筛选到就自动停止

if [ -f /koolshare/scripts/CF_best_IP.txt ]
then
	historyIP=$(grep 'Mbps' /koolshare/scripts/CF_best_IP.txt | awk '{ print $2}')
	rm -f /koolshare/scripts/CF_best_IP.txt
fi 


 maxspeedtest () {
			echo "第${2}次测试 $1"
			curl --resolve $domain:443:$1 https://$domain/$file -o /dev/null --connect-timeout 5 --max-time 10 > log.txt 2>&1
			cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep -v 'k\|M' >> speed.txt
			for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep k | sed 's/k//g'`
			do
				k=$i
				k=$((k*1024))
				echo $k >> speed.txt
			done
			for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep M | sed 's/M//g'`
			do
				i=$(echo | awk '{print '$i'*10 }')
				M=$i
				M=$((M*1024*1024/10))
				echo $M >> speed.txt
			done
			max=0
			for i in `cat speed.txt`
			do
				max=$i
				if [ $i -ge $max ]; then
					max=$i
				fi
			done
			rm -rf log.txt speed.txt
			if [ $max -ge $speed ]; then
				anycast=$1
				break
			fi
			max=$(($max/1024))
			echo 峰值速度 $max kB/s
			}
	
	

while [ $(cut -d '.' -f1 /proc/uptime) -lt $endtimestamp ]
 do
	while [ $(cut -d '.' -f1 /proc/uptime) -lt $endtimestamp ] 
	do
		rm -rf icmp temp log.txt anycast.txt temp.txt
		mkdir icmp
		datafile="/koolshare/scripts/data.txt"
		if [ ! -f "$datafile" ]
		then
			echo 获取CF节点IP
			curl --retry 3 https://update.freecdn.workers.dev -o /koolshare/scripts/data.txt -#
		fi
		domain=$(cat /koolshare/scripts/data.txt | grep domain= | cut -f 2- -d'=')
		file=$(cat /koolshare/scripts/data.txt | grep file= | cut -f 2- -d'=')
		databaseold=$(cat /koolshare/scripts/data.txt | grep database= | cut -f 2- -d'=')
		n=0
	    RANDNUM=$(awk 'BEGIN { srand(); {print int(rand() *32767)}}')
        count=$(echo | awk -v random=$RANDNUM '{print random%5}')
		for i in `cat /koolshare/scripts/data.txt | sed '1,7d'`
		do
			if [ $n -eq $count ]
			then
			    randomip=$(echo | awk -v random=$RANDNUM '{print random%256}')
				echo 生成随机IP $i$randomip
				echo $i$randomip>>anycast.txt
				count=$((count+4))
			else
				n=$((n+1))
			fi
		done
		n=0
		m=$(cat anycast.txt | wc -l)
		count=$(($m/30 + 1))
		for i in `cat anycast.txt`
		do
			ping -c $count  -q $i > icmp/$n.log&
			n=$((n+1))
			per=$(($n*100/$m))
			while true
			do
				p=$(ps | grep ping | grep -v "grep" | wc -l)
				if [ $p -ge 200 ]
				then
					echo 正在测试 ICMP 丢包率:进程数 $p,已完成 $per %
					sleep 1
				else
					echo 正在测试 ICMP 丢包率:进程数 $p,已完成 $per %
					break
				fi
			done
		done
		rm -f anycast.txt
		while true
		do
			p=$(ps | grep ping | grep -v "grep" | wc -l)
			if [ $p -ne 0 ]
			then
				echo 等待 ICMP 进程结束:剩余进程数 $p
				sleep 1
			else
				echo ICMP 丢包率测试完成
				break
			fi
		done
		cat icmp/*.log | grep 'statistics\|loss' | sed -n '{N;s/\n/\t/p}' | cut -f 1 -d'%' | awk '{print $NF,$2}' | sort -n | awk '{print $2}' | sed '31,$d' > ip.txt
		rm -rf icmp
		echo 选取30个丢包率最少的IP地址下载测速
		mkdir temp
		for i in `cat ip.txt`
		do
			echo $i 启动测速
			curl --resolve $domain:443:$i https://$domain/$file -o temp/$i -s --connect-timeout 2 --max-time 10&
		done
		echo 等待测速进程结束,筛选出三个优选的IP
		sleep 15
		echo 测速完成
		ls -S temp > ip.txt
		rm -rf temp
		n=$(wc -l ip.txt | awk '{print $1}')
		if [ $n -ge 3 ]; then
			first=$(sed -n '1p' ip.txt)
			second=$(sed -n '2p' ip.txt)
			third=$(sed -n '3p' ip.txt)
			rm -f ip.txt
			echo 优选的IP地址为 $first - $second - $third
			maxspeedtest "$first" 1
			maxspeedtest "$first" 2
			maxspeedtest "$second" 1
			maxspeedtest "$second" 2
			maxspeedtest "$third" 1
			maxspeedtest "$third" 2
		fi
	done
		break
done


	max=$(($max/1024))
	endtime=`date +'%Y-%m-%d %H:%M:%S'`
	start_seconds=$(date --date="$starttime" +%s)
	end_seconds=$(date --date="$endtime" +%s)
	clear
	curl --ipv4 --resolve update.freecdn.workers.dev:443:$anycast --retry 3 -s -X POST -d '"CF-IP":"'$anycast'","Speed":"'$max'"' 'https://update.freecdn.workers.dev' -o temp.txt
	publicip=$(cat temp.txt | grep publicip= | cut -f 2- -d'=')
	colo=$(cat temp.txt | grep colo= | cut -f 2- -d'=')
	url=$(cat temp.txt | grep url= | cut -f 2- -d'=')
	url=$(cat temp.txt | grep url= | cut -f 2- -d'=')
	app=$(cat temp.txt | grep app= | cut -f 2- -d'=')
	databasenew=$(cat temp.txt | grep database= | cut -f 2- -d'=')
	if [ "$app" != "20201208" ]
	then
		echo 发现新版本程序: $app
		echo 更新地址: $url
		echo 更新后才可以使用
		exit
	fi
	if [ "$databasenew" != "$databaseold" ]
	then
		echo 发现新版本数据库: $databasenew
		mv temp.txt /koolshare/scripts/data.txt
		echo 数据库 $databasenew 已经自动更新完毕
	fi
	rm -f temp.txt 
	echo "优选IP $anycast 满足 $bandwidth Mbps带宽需求" > /koolshare/scripts/CF_best_IP.txt
	echo "峰值速度 $max kB/s " >>/koolshare/scripts/CF_best_IP.txt
	echo "公网IP $publicip" >> /koolshare/scripts/CF_best_IP.txt
	echo "数据中心 $colo" >> /koolshare/scripts/CF_best_IP.txt
	echo "总计用时 $((end_seconds-start_seconds)) 秒" >> /koolshare/scripts/CF_best_IP.txt

	cat /koolshare/scripts/CF_best_IP.txt
	
	if [ -f /koolshare/scripts/CF_best_IP.txt ] && [ "$anycast" != "$historyIP" ]
	then
	 	/usr/bin/dbus set ss_basic_server=$anycast
		/bin/sh /koolshare/ss/ssconfig.sh restart
	fi
