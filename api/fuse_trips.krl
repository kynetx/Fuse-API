ruleset fuse_trips {
  meta {
    name "Fuse Manage Trips"
    description <<
Manage trips. PDS is not well-suited to these operations
    >>
    author "PJW"
    sharing on

    errors to b16x13

    use module b16x10 alias fuse_keys

    use module a169x625 alias CloudOS
    use module a169x676 alias pds
    use module ba6x19 alias common
    use module b16x11 alias carvoyant
    use module b16x9 alias vehicle

	
    provides trips, lastTrip, tripName
  }

  global {

    // external decls
    trips = function(){
      ent:trip_summaries
    };

    lastTrip = function(with_data){
      with_data => ent:trips(ent:last_trip)
                 | ent:trip_summaries(ent:last_trip)
    };

    tripName = function(start, end) {
      ent:trip_names{[reducePrecision(end), reducePrecision(start)]}
    }

    waypointToArray = function(wp) {
      wp.typeof() eq "hash" => [wp{"latitude"}, wp{"longitude"}]
                             | wp.split(re/,/)
    };

    // find latlong within 365 feet
    reducePrecision = function(a) {
      a_array = waypointToArray(a);
      // 1 decimal place - 7 miles 
      // 2 decimal places - 0.7 miles 
      // 3 decimal places - 365 feet 
      // 4 decimal places - 37 feet 
      nearest = 1000; // 3 decimal places
      a_array.map(function(n){math:round(n * nearest)/nearest}).join(",");
    };


    // find if two points, a and b, are within radius distance in meters
    close = function(a, b, radius) {
      a_array = waypointToArray(a);
      b_array = waypointToArray(b);

      r90   = math:pi()/2;      
      rEm   = 6378100;         // radius of the Earth in meters
      rEf   = 20925524.9;      // radius of Earth in feet
  
      // convert co-ordinates to radians
      rlata = math:deg2rad(a_array[0]);
      rlnga = math:deg2rad(a_array[1]);
      rlatb = math:deg2rad(b_array[0]);
      rlngb = math:deg2rad(b_array[1]);
 
      // distance between two co-ordinates on earth in meters
      dE = math:great_circle_distance(rlnga, r90 - rlata, rlngb, r90 - rlatb, rEm);
      dE < radius
    };

    // internal decls
    endTime = function(trip) {
      trip{"endTime"} || 
      trip{["endWaypoint","timestamp"]} || 
      trip{["data"]}.head().pick("$..timestamp").head() || 
      "ERROR_NO_TIMESTAMP_AVAILABLE"
    };

    tripSummary = function(trip) {
       // summary =  {
       //   "startWaypoint" : trip{"startWaypoint"},
       //   "endWaypoint" : trip{"endWaypoint"},
       // 	"mileage": trip{"mileage"},
       // 	"id": trip{"id"},
       // 	"endTime": endTime(trip),
       // 	"startTime": trip{"startTime"}
       // };
      summary = trip.delete(["data"]);
      summary
    };

    mkTid = function(tid){"T"+tid};
    mkCarvoyantTid = function(tid){tid.extract(re/T(\d+)/).head()};
  
  }

  rule clear_trip {
    select when fuse clear_trip
    always {
      clear ent:trips_by_id;
      clear ent:trip_summaries;
      clear ent:trips_by_week;
    }
  }

  // workhorse rule, saves and indexes trips and trip summaries
  rule save_trip {
    select when fuse new_trip
    pre {
      vid = carvoyant:vehicle_id();

      // accept either the trip as a set of attributes or just an ID that requires us to ping Carvoyant API
      incoming = event:attrs() || {};
      trip_info = incoming{"mileage"}.isnull() => carvoyant:tripInfo(incoming{"tripId"})
                                                | incoming;
      tid = mkTid(trip_info{"id"});
      end_time = endTime(trip_info);
      trip_info = trip_info.put(["endTime"], end_time);
      trip_summary = tripSummary(trip_info);
      time_split = time:strftime(end_time, "%Y_:%m_:%d_:%H_:%M%S_").split(re/:/);
      week_number = time:strftime(end_time, "%U_")
    }
    if(end_time neq "ERROR_NO_TIMESTAMP_AVAILABLE") then
    {send_directive("Adding trip #{tid}") with 
      end_time = end_time and
      time_split = time_split and
      trip_summary = trip_summary
      ;
     event:send({"cid": vehicle:fleetChannel()}, "fuse", "updated_vehicle") with
         attrs = {"keyvalue": "last_trip_info",
	          "vehicleId": vid,
	          "value": trip_info.encode()
		 }
    }
    fired {
      set ent:last_trip tid;
      set ent:trips_by_id{tid} trip_info;
      set ent:trip_summaries{tid} trip_summary;
      // set ent:trips_by_week{week_number} = (ent:trips_by_week{week_number} || []).append(tid);
    } else {
      log ">>>>>>>>>>>>>>>>>>>>>>>>> save_trip failed <<<<<<<<<<<<<<<<<<<<<<<<<";
      log "End time: #{end_time}";
    }
  }
  // daily summaries (TZs, ugh)
  // trip summaries (easier)

  rule name_trip {
    select when fuse name_trip
    pre {
      carvoyant_tid = event:attr("tripId");
      tid = mkTid(carvoyant_tid);
      tname = event:attr("tripName");	
      trip = ent:trip_summaries{tid} || {};
      start =reducePrecision(trip{"startWaypoint"});
      end = reducePrecision(trip{"endWaypoint"});
    }
//    if(not trip{"startWaypoint"}.isnull() && not trip{"endWaypoint"}.isnull()) then {
  {    send_directive("Named trip") with
        tripId = tid and
	anotherId = mkCarvoyantTid(tid) and
        tripName = tname and
	start = start and
	end = end and
	trip = trip
	;
	
    }
    fired {
      set ent:trip_names{[end, start]} {"tripId" : carvoyant_tid, "tripName": tname}
    } else {
      log "===========================================================================";
      log "Bad trip: " + trip.encode();
    }
  }

}
