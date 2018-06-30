#!/bin/bash
# Guanheng Zhong 21822197

#extract Train Routes

day_takeoff=$(date '+%w')
###########################################################################
printf "Extracting Train Route Information, sorry for the waiting\n" 
	#train code is 0, 1 or 2
	awk -F',' '{if($6<3){ 
	Route[$1][1]=$1
	Route[$1][2]=$4
	print Route[$1][1]","Route[$1][2]}
	}' routes.txt >temp_TrainRoute.txt

	#Join train routes and trips, choose those to fremantle or perth stn
	awk -F',' 'NR==FNR{a[$1]=$0;}
	NR!=FNR && a[$1] && ($5 == "Fremantle Stn" || $5 == "Perth Underground Stn" || $5 == "Perth Stn"){print a[$1]","$2","$3","$4}' temp_TrainRoute.txt trips.txt > temp_TrainTrips.txt
	rm temp_TrainRoute.txt
	
	#Join TrainTrips and stop_time, choose the right direction, fremantle line 1, perth 0
	awk -F',' 'NR==FNR && ($2=="Fremantle Line" && $5==1) || ($2!="Fremantle Line" && $5==0){a[$4]=$0;}
	NR!=FNR && a[$1]{print a[$1]","$2","$4","$5}' temp_TrainTrips.txt stop_times.txt > 		temp_TrainStopTimes1.txt
	rm temp_TrainTrips.txt
	
#pickout those trips id are available on this day.
	cut -d, -f 1,$[ $day_takeoff + 1 ] calendar.txt > temp_TodayService.txt
	awk -F',' 'NR==FNR && $2==1{a[$1]=1;}
	NR!=FNR && a[$3]{print $0}' temp_TodayService.txt temp_TrainStopTimes1.txt > temp_TrainStopTimes2.txt
	rm temp_TrainStopTimes1.txt
	rm temp_TodayService.txt

	#self join pickout those trips id contains 99352 or 99601, 99007, except midland line
	awk -F',' 'NR==FNR && ($7==99007 || $7==99352 || $7==99601) && $2!="Midland Line"{a[$4]=1;}
	NR!=FNR && a[$4]{print $0}' temp_TrainStopTimes2.txt temp_TrainStopTimes2.txt > temp_TrainStopTimesFinal.txt
	rm temp_TrainStopTimes2.txt

	#Join TrainStopTimes and stop
	awk -F',' 'NR==FNR{a[$7]=1;}
	NR!=FNR && a[$3]{print $3","$5","$7","$8}' temp_TrainStopTimesFinal.txt stops.txt > temp_TrainStops.txt
	printf "Extracting is done.\n"
############################################################################
findNearestStation(){ #function that returns 1whether found one,2stop_id,3stop_name,4distance,5stop_lat,6stop_lng
min_distance=1000
count=0
lat=$1
lng=$2
stop_id=0
while read line
do
stop_lat=$(echo $line|awk -F',' '{print $3}')
stop_lng=$(echo $line|awk -F',' '{print $4}')
distance_toStop=$(./haversine.awk $lat $lng $stop_lat $stop_lng)

if [ $distance_toStop -le $min_distance ] #get the closest station
then
	count=$[ $count + 1 ]
	min_distance=$distance_toStop
	stop_id=$(echo $line|awk -F"," '{print $1}')
	stop_name=$(echo $line|awk -F"," '{print $2}')
	nearstop_lat=$stop_lat
	nearstop_lng=$stop_lng
fi
done < temp_TrainStops.txt
min_distance=$[ $min_distance / 1000 ]
echo "$count;$stop_id;$stop_name;$min_distance;$nearstop_lat;$nearstop_lng" #return 6 variables to array
}
##################################################################################
findNextStop(){ #find the return next stop id and time arrive based on the start_stop_id $1 and the current time $2
start_stop_id=$1
time_takeoff=$(date -d "$2" +%s)
time_limit=$(date -d "15:30:00" +%s)
count=0
trip_id=0
if [ $start_stop_id == 99007 -o $start_stop_id == 99601 ]
then
grep ",$start_stop_id," temp_TrainStopTimesFinal.txt | grep "Fremantle Line" |sort -k6n -t, > temp_NearestStopTimes.txt
else
grep ",$start_stop_id," temp_TrainStopTimesFinal.txt | sort -k6n -t, > temp_NearestStopTimes.txt
fi
while read line #find trip_id
do
	arrival_time=$(echo $line|awk -F',' '{print $6}')
	arrival_time=$(echo $arrival_time|awk -F':' '{if($1==24)$1="00";print $1":"$2":"$3}') #replace the wrong 24:00:06
	arrival_time=$(date -d "$arrival_time" +%s)
	stop_id=$(echo $line|awk -F',' '{print $7}')
	if [ $arrival_time -gt $time_takeoff -a $start_stop_id == $stop_id -a $arrival_time -le 		$time_limit ] #find the earliest trip id
	then
		trip_id=$(echo $line|awk -F',' '{print $4}')
		break
	fi
	done < temp_NearestStopTimes.txt
if [ $trip_id == 0 ]
then
	echo "0;0;0" #no result
else
	last_recode=$(grep ",$trip_id," temp_TrainStopTimesFinal.txt| sort -k8n -t,|tail -1)
	arrival_time=$(echo $last_recode|awk -F',' '{print $6}')
	arrival_time=$(date -d "$arrival_time" +%X)
	stop_id=$(echo $last_recode|awk -F',' '{print $7}')
	echo "$stop_id;$trip_id;$arrival_time"
fi
}
#######################################################################################

echo "please enter latitude."
read lat
echo "please enter longitude."
read lng
time_takeoff=$(date '+%X')
time_limit=$(date -d "15:30:00" +%s)
time_takeoff_s=$(date -d "$time_takeoff" +%s)
gmap_setting='width="400" height="300" frameborder="0" style="border:0" src="https://www.google.com/maps/embed/v1/place?key=AIzaSyDwBKoF5qP07JifpHuYTUfo8zBmCm3oc-U&q='
echo "" > routeplan.html
if [ $time_takeoff_s -gt $time_limit ] #check if time passed 15:30:00
then
echo "<p>oh, it has passed 15:30:00 already. Planning for tomorrow from 08:00:00.</p>" >> routeplan.html 
time_takeoff=08:00:00
fi
IFS=';' read -r -a array <<< $(findNearestStation $lat $lng)
#IFS=';' read -r -a array <<< $(findNearestStation -31.9770933333333010 115.78699611111099)
if [ ${array[0]} == 0 ] #station nearby found ,end 1
then
	echo "<p>sorry, there are no nearby stations within 1km.</p>" >> routeplan.html 

elif [ ${array[1]} == 99352 ] #in fremantle station ,end 2
then
	echo "<p>hey, you are right near fremantle station, just go and catch a ferry.</p>" >> routeplan.html 
	echo "<iframe "$gmap_setting ${array[4]}","${array[5]}"\"></iframe>" >> routeplan.html
else # in other station end 3
	echo "<p>walk ${array[3]} km to station ${array[2]}(${array[1]}).</p>" >> routeplan.html 
	echo "<iframe "$gmap_setting ${array[4]}","${array[5]}"\"></iframe>" >> routeplan.html
	# find the end stop of this trip
	start_stop_id=${array[1]}
	IFS=';' read -r -a array <<< $(findNextStop $start_stop_id $time_takeoff)
	next_stop_id=${array[0]}
	next_stop_name=$(grep "$next_stop_id," temp_TrainStops.txt|awk -F',' '{print $2}')
	next_stop_lat=$(grep "$next_stop_id," temp_TrainStops.txt|awk -F',' '{print $3}')
	next_stop_lng=$(grep "$next_stop_id," temp_TrainStops.txt|awk -F',' '{print $4}')
	time_arrival=${array[2]}
	time_arrival_s=$(date -d "$time_arrival" +%s)
	
	if [ $time_arrival_s -gt $time_limit ] #end 3.1
	then
		echo "<p>Sorry, it passes 15:30:00 when you arrived $next_stop_name($next_stop_id).</p>" >> routeplan.html 
	
	elif [ $next_stop_id == 99352 ] #end 3.2
	then
		echo "<p>keep on the train and you will arrive \"Fremantle Stn\"(99532) at ${array[2]}.</p>" >> routeplan.html 
		echo "<iframe "$gmap_setting $next_stop_lat","$next_stop_lng"\"></iframe>" >> routeplan.html
		echo "" >> routeplan.html
	elif [ $next_stop_id == 99601 -o $next_stop_id == 99007 ] #end 3.3
	then
		echo "<p>keep on the bus and you will arrive $next_stop_name($next_stop_id) at ${array[2]},</p>" >> routeplan.html 
		echo "<iframe "$gmap_setting $next_stop_lat","$next_stop_lng"\"></iframe>" >> routeplan.html
		echo "" >> routeplan.html
		if [ $next_stop_id == 99601 ] #end 3.3.1
		then
			next_stop_id=99007 #from perth stn
			instruction="$instruction go to \"Perth Stn Platform 7\"(99007), "
		fi
		IFS=';' read -r -a array <<< $(findNextStop $next_stop_id $time_arrival)
		next_stop_id=${array[0]}
		time_arrival=${array[2]}
		next_stop_lat=$(grep "$next_stop_id," temp_TrainStops.txt|awk -F',' '{print $3}')
		next_stop_lng=$(grep "$next_stop_id," temp_TrainStops.txt|awk -F',' '{print $4}')
		echo "<p>keep on the train and you will arrive \"Fremantle Stn\"(99532) at ${array[2]}.</p>" >> routeplan.html 
		echo "<iframe "$gmap_setting $next_stop_lat","$next_stop_lng"\"></iframe>" >> routeplan.html
		echo "" >> routeplan.html
	else #end 3.4
		echo "<p>Sorry, no train can get you there before 15:30:00, pleas go tomorrow.</p>" >> routeplan.html 
	fi	
fi
echo "Thank you, the output route plan is in 'routplan.html'"
