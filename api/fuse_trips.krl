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
    use module b16x19 alias common
    use module b16x11 alias carvoyant
    use module b16x9 alias vehicle
    use module b16x20 alias fuel

	
    provides trips, lastTrip, tripMeta, tripMetaById, mileage, tripsByDate, newTrips,
             monthlyTripSummary, missedTrips, testPset,
             all_trips,  pruneTripDataTest, // for debugging
	       icalForVehicle, icalSubscriptionUrl, exportTrips
  }

  global {

    testPset = function() {
      x = common:genAndStore();
      {"orig": x,
       "retrieved": common:retrieveVal()
      }
    }

    // external decls
    tripsByDate = function(start, end){

      utc_start = common:convertToUTC(start);
      utc_end = common:convertToUTC(end);
      
      sort_opt = {
        "path" : ["endTime"],
	"reverse": true,
	"compare" : "datetime"
      };

      this2that:transform(ent:trip_summaries.query([], { 
       'requires' : '$and',
       'conditions' : [
          { 
     	   'search_key' : [ 'endWaypoint', 'timestamp'],
       	   'operator' : '$gte',
       	   'value' : utc_start 
	  },
     	  {
       	   'search_key' : [ 'endWaypoint', 'timestamp' ],
       	   'operator' : '$lte',
       	   'value' : utc_end 
	  }
	]},
	"return_values"
	), 
       sort_opt)
    };


    trips = function(id, limit, offset) {
       // x_id = id.isnull().klog(">>>> id >>>>>");
       // x_limit = limit.klog(">>>> limit >>>>>");
       // x_offset = offset.klog(">>>> offset >>>>>"); 

      id.isnull() || id eq "" => allTrips(limit, offset)
                               | ent:trips_by_id{mkTid(id)};
    };

    allTrips = function(limit, offset) {
      sort_opt = {
        "path" : ["endTime"],
	"reverse": true,
	"compare" : "datetime"
      };

      max_returned = 25;

      hard_offset = offset.isnull() 
                 || offset eq ""        => 0               // default
                  |                        offset;

      hard_limit = limit.isnull() 
                || limit eq ""          => 10              // default
                 | limit > max_returned => max_returned
		 |                         limit; 

      global_opt = {
        "index" : hard_offset,
	"limit" : hard_limit
      }; 

      sorted_keys = this2that:transform(ent:trip_summaries, sort_opt, global_opt.klog(">>>> transform using global options >>>> "));
      sorted_keys.map(function(id){ ent:trip_summaries{id} })
    };

    all_trips = function() {
      ent:trip_summaries
    };

    // temp for mark
    mileage = function(tid){
      ent:trip_summaries{[tid, "mileage"]}.klog(">>>>> trip mileage from summary");
    };

    lastTrip = function(with_data){
      with_data => ent:trips{ent:last_trip}
                 | ent:trip_summaries{ent:last_trip}.klog(">>> working with summary <<<")
    };

    tripMeta = function(start, end) {
      ent:trip_names{[reducePrecision(end), reducePrecision(start)]}
    }

    tripMetaById = function(id) {
      trp = trips(id);
      start =trp{"startWaypoint"};
      end = trp{"endWaypoint"};
      tripMeta(start, end)
    };

    monthlyTripSummary = function(year, month) {
      ent:monthly_trip_summary{[year, month]}
    }

    waypointToArray = function(wp) {
      wp.typeof() eq "hash" => [wp{"latitude"}, wp{"longitude"}]
                             | wp.split(re/,/)
    };

    icalSubscriptionUrl = function() {
      ical_channel_name = "iCal_for_vehicle";
      channel_list = CloudOS:channelList();
      channels = channel_list{"channels"}.filter(function(x){x{"name"} eq ical_channel_name});
      channel = channels.length() > 0 => channels.head()
                		       | CloudOS:channelCreate(ical_channel_name);
      eci = channel{"cid"} || channel{"token"}; // CloudOS uses cid in one place and token in another 
      {"url": "webcal://" + meta:hostname() + "/sky/cloud/" + meta:rid() + "/icalForVehicle?_eci=" + eci }
    };

    icalForVehicleDoNothing = function(){""};

    // return cached copy unless new trip
    icalForVehicle = function(force){
      last_trip = lastTrip();
      last = time:strftime(last_trip{"endTime"}, "%s");
      ent:last_ical_time < last || force => generateIcalForVehicle()  
                                          | ent:last_ical    
    }


    generateIcalForVehicle = function(){
      sort_opt = {
        "path" : ["endTime"],
	"reverse": true,
	"compare" : "datetime"
      };
      global_opt = {
        "index" : 0,
	"limit" : 100 
      }; 
      
      t = this2that:transform(ent:trip_summaries, sort_opt, global_opt)
              .map(function(k) {
	        e = ent:trip_summaries{k};
	        start = e{["startWaypoint", "latitude"]} + "," + e{["startWaypoint", "longitude"]};
	        dest = e{["endWaypoint", "latitude"]} + "," + e{["endWaypoint", "longitude"]};
		miles = e{"mileage"} || "unknown";
	        url = "http://maps.google.com/maps?saddr="+ start + "&daddr=" + dest;
                cost_str = e{"cost"} => "Cost: $" + e{"cost"} | "";
		summary = e{"name"} neq "" => e{"name"} + " (" + miles + " miles)"
                                            | "Trip of " + miles + "miles"
	        {"dtstart" : e{"startTime"},
		 "dtend" : e{"endTime"},
		 "summary" : summary,
		 "url": url,
		 "description": "Trip ID: " + e{"id"} + "; " + cost_str,
		 "uid": "http://fuse.to/ical/v1/trip/" + $e{"id"}  // should be the same each time generated
		}
	      });
      vdata = vehicle:vehicleSummary();
      gen_time =  time:strftime(time:now(), "%s").pset(ent:last_ical_time); // save time generated
      ical:from_array(t, {"name": vdata{"label"}, 
                          "desc": "Calendar of trips for " + vdata{"label"}}
	             ).replace(re#\\;#g, ";").pset(ent:last_ical);
    };

    exportTrips = function(start, end, tz) {
      timezone = tz.defaultsTo("America/Denver"); 

      trips = tripsByDate(start,end)
                 .map(function(v){ start = v{["startWaypoint", "latitude"]} + "," + v{["startWaypoint", "longitude"]};
	         		   dest = v{["endWaypoint", "latitude"]} + "," + v{["endWaypoint", "longitude"]};
				   v.put(["startWaypoint"], start)
				    .put(["endWaypoint"], dest)
				    .put(["startDate"], time:strftime(v{"startTime"},"%F", {"tz":timezone}))
				    .put(["startTime"], time:strftime(v{"startTime"},"%r", {"tz":timezone}))
				    .put(["endDate"], time:strftime(v{"endTime"}, "%F", {"tz":timezone}))
				    .put(["endTime"], time:strftime(v{"endTime"}, "%r", {"tz":timezone}))
		                 });
      csv:from_array(trips);
    }

    // find latlong within 365 feet
    reducePrecision = function(a) {
      a_array = waypointToArray(a).klog(">>> original waypoint >>>>");
      // 1 decimal place - 7 miles 
      // 2 decimal places - 0.7 miles 
      // 3 decimal places - 365 feet 
      // 4 decimal places - 37 feet 
      nearest = 1000; // 3 decimal places
      a_array.map(function(n){math:round(n * nearest)/nearest}).join(",").klog(">>>> reduced to >>>>");
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

      mileage = trip{"mileage"} < 0.1 =>  0.0
                                       |  trip{"mileage"}.sprintf("%.2f");

      cost_data = fuel:currentCPM();

      cost = math:round(mileage * cost_data{"costPerMile"} * 1000) / 1000;

      interval = (time:strftime(trip{"endTime"}, "%s") - time:strftime(trip{"startTime"}, "%s"));
      
      avg_speed = mileage * 3600 / interval;
      
      summary = trip
                 .delete(["data"])
 		 .put(["cost"], cost.sprintf("%.2f"))
		 .put(["costDataSource"], cost_data{"vehicleData"} => "vehicle" | "estimate")
 		 .put(["interval"], interval.klog(">>>> trip length in seconds >>>>> "))
 		 .put(["avgSpeed"], avg_speed.sprintf("%.1f").klog(">>>> trip avg speed >>>>> "))
                ;
      summary
    };

    missedTrips = function(duration) {
      vid = carvoyant:vehicle_id();
      dur = ( duration.isnull() => 1 | duration.klog(">>> input duration >>>>") ).klog(">>> missed trips for this many days >>>>");
      today = common:convertToUTC(time:now()).klog(">>> until this time >>>");
      yesterday = common:convertToUTC(time:add(today, { "days": 0 - dur })).klog(">>>> from this time >>>> ");
      raw_cv_trips = carvoyant:trips(yesterday, today, vid);
      cv_trips = raw_cv_trips.typeof() eq "array" => raw_cv_trips // Carvoyant error returns map
                                                   | [];
      missed_trips = cv_trips.filter(function(t){ t{"mileage"} > 0 && ent:trips_by_id{mkTid(t{"id"})}.isnull() });
      missed_trips
    };

    mkTid = function(tid){"T"+tid};
    mkCarvoyantTid = function(tid){tid.extract(re/T(\d+)/).head()};

    mkTripMeta = function(tname, tcategory) {
      {"tripName": tname,
       "tripCategory": tcategory
      }
    };
  

    pruneTripDataTest = function(id) {
      pruneTripData(trips(id))
    }

    pruneTripData = function(data) {
      new_data = data.defaultsTo([]).map(function(d){
		    new_datum = d{"datum"}.map(function(r) {
		       // r.delete(["timestamp"])
		       //  .delete(["id"])
		       //  .delete(["translatedValue"])
		       {"key": r{"key"},
		        "value": r{"value"}
		       }
		    });

		    d.put(["datum"], new_datum)
		 });
      new_data
    }

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
      incoming = event:attrs().defaultsTo({});
      raw_trip_info = incoming{"mileage"}.isnull() => carvoyant:tripInfo(incoming{"tripId"}, vid)
                                                    | incoming;

      // too large trips can cause a time out that results in div by zero and sprintf errors in tripSummary()
      record_count = raw_trip_info{"data"}.length().klog(">>>>> number of records in trip >>>>>");
      pruned_trip_data = pruneTripData(raw_trip_info{"data"});
  
      tid = mkTid(raw_trip_info{"id"}).klog(">>>>> trip ID >>>>>");

       // time_split = time:strftime(end_time, "%Y_:%m_:%d_:%H_:%M%S_").split(re/:/);
       // week_number = time:strftime(end_time, "%U_")

//    end_time = endTime(raw_trip_info); 

      trip_info = raw_trip_info
                   .delete(["data"])
//                   .put(["endTime"], end_time)
		   ;

      raw_trip_summary = not trip_info{"mileage"}.isnull() => tripSummary(trip_info)
                       |                                      {}
                       ;

      trip_meta = tripMeta(raw_trip_summary{"startWaypoint"}, raw_trip_summary{"endWaypoint"}) || {};
      trip_name = trip_meta{"tripName"} || "";
      trip_category = trip_meta{"tripCategory"} || "";

      trip_summary = raw_trip_summary
                          .put(["name"], trip_name)
                          .put(["category"], trip_category)
			  ;

      final_trip_info = trip_info
                   .put(["cost"], trip_summary{"cost"})
  		   .put(["interval"], trip_summary{"interval"})
 		   .put(["avgSpeed"], trip_summary{"avgSpeed"})
 		   .put(["name"], trip_name)
 		   .put(["category"], trip_categoty)
                   //.klog(">>>> storing trip <<<<< ")
		   ;
      

    }
    if( end_time neq "ERROR_NO_TIMESTAMP_AVAILABLE" 
     && trip_info{"mileage"} > 0.01
      ) then
    {send_directive("Adding trip #{tid}") with 
      end_time = end_time and
      trip_summary = trip_summary
      ;
    }
    fired {
      set ent:last_trip tid;
      set ent:trips_by_id{tid} final_trip_info;
      set ent:trips_by_id{[tid, "data"]} pruned_trip_data; // this can fail separately
      set ent:trip_summaries{tid} trip_summary;
      raise fuse event trip_saved with 
        tripId = tid and
        tripSummary = trip_summary
    } else {
      log ">>>>>>>>>>>>>>>>>>>>>>>>> save_trip failed <<<<<<<<<<<<<<<<<<<<<<<<<";
      log "End time: #{end_time}; mileage: " + trip_info{"mileage"};
    }
  }


  rule update_trip {
    select when fuse trip_meta_data
    pre {
      carvoyant_tid = event:attr("tripId");
      tid = mkTid(carvoyant_tid);
      tname = event:attr("tripName") || "";
      tcategory = event:attr("tripCategory") || "";
      trip_summary = ent:trip_summaries{tid}.klog(">>>> trip summary for #{tid} >>>> ") || {};
      trip_info = ent:trips_by_id{tid};      
      start =reducePrecision(trip_summary{"startWaypoint"});
      end = reducePrecision(trip_summary{"endWaypoint"});

      meta_obj = mkTripMeta(tname, tcategory);
      

    }
    if(not trip_summary{"startWaypoint"}.isnull()) then // if this isn't a real trip, don't pollute trip_summaries...
    {
      send_directive("Updating trip meta data") with
        tid = tid and
	trip_name = tname and
	trip_category = tcategory and
	start = start and
	end = end
    }
    fired {
      set ent:trip_summaries{tid} trip_summary
             .put(["category"], tcategory)
	     .put(["name"], tname);
      set ent:trips_by_id{tid} trip_info      
             .put(["category"], tcategory)
	     .put(["name"], tname);
      set ent:trip_names{[end, start]} meta_obj
    } else {
      log ">>> can't find #{tid} in trips for this vehicle >>>>> "
    }

  }

  rule name_trip {
    select when fuse trip_name
    pre {
      carvoyant_tid = event:attr("tripId");
      tid = mkTid(carvoyant_tid);
      tname = event:attr("tripName") || "";
      tcategory = event:attr("tripCategory") || "";
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
      set ent:trip_names{[end, start]} mkTripMeta(tname, tcategory);
    } else {
      log "===========================================================================";
      log "Bad trip: " + trip.encode();
    }
  }

  rule update_vehicle_totals {
    select when fuse trip_saved
    pre {

      // do current month if no month given
      raw_month = event:attr("month") || time:now();
      month = time:strftime(raw_month, "%m");
      year = time:strftime(raw_month, "%Y");

      start = time:strftime(raw_month, "%Y%m01T000000%z");
      end = time:add(start, {"months": 1});
      month_totals = tripsByDate(start, end)
                      .reduce(function(a, b){ 
		                              // for some early trips for a few people. Kill later... [PJW]
                                              new_interval = (time:strftime(b{"endTime"}, "%s") - time:strftime(b{"startTime"}, "%s"));
	                                      {"cost": a{"cost"} + b{"cost"}, 
		                               "interval": a{"interval"} + new_interval.klog(">>> trip interval >>> "),
					       "mileage": a{"mileage"} + b{"mileage"},
					       "trip_count": a{"trip_count"} + 1
					      }
					    },
			      {"cost": 0, 
		               "interval": 0,
			       "mileage": 0,
			       "trip_count": 0
			      }
                             );

    }
    {send_directive("Updated trip summary for #{month}/#{year}") with
       values =  month_totals;
     event:send({"cid": common:fleetChannel()}, "fuse", "updated_vehicle") with
        attrs = {"keyvalue": "trip_summaries,Y#{year},M#{month}",
	         "value": month_totals.encode()
	        };
      }

    always {
      set ent:monthly_trip_summary{[year, month]} month_totals;
    }
  }

  // ---------- vehicle emails ----------
  rule send_vehicle_export {
    select when fuse trip_export
    pre {

      // configurables
      year = event:attr("year");
      month = event:attr("month");
      tz = event:attr("timezone").klog(">>> owner told me their timezone >>>> ").defaultsTo("America/Denver");


      profile = pds:get_all_me().defaultsTo({});
      vehicle_name = profile{"myProfileName"};

      subj = "Fuse Trip Report for #{vehicle_name} (#{month}/#{year})";

      tz_str = time:strftime(time:now({"tz": tz}), "%Y%m%dT%H%M%S%z")
                  .split(re/[+-]/)
                  .reverse()
                  .head()
                  .klog(">>>> tz string >>>>>>>")
                  ;
      start = time:new(year+month+"01T000000-"+tz_str);
      end = time:add(start, {"months": 1});


      // don't generate report unless there are vehicles
      csv = exportTrips(start, end, tz);

      msg = <<
Here is your trip export for #{vehicle_name} for #{month} #{year}
      >>; 


      email_map = { "subj" :  subj,
		    "msg" : msg,
		    "attachment": csv,
		    "filename" : "Trips_#{vehicle_name}_#{year}_#{month}.csv"
                  };


    }
    if(not csv.isnull() ) then
    {
      send_directive("sending email to fleet owner") with
        content = email_map;
    }
    fired {
      raise fuse event email_for_owner attributes email_map;
    }
    
  }

  // ---------- maintenance ----------
  rule repair_trips {
    select when fuse trip_check
    foreach missedTrips(event:attr("duration").isnull() => 2 | event:attr("duration")) setting(trip) // check for last two days by default
    pre {
      trip_attrs = { "tripId" : trip{"id"} }.klog(">>>> trip attrs ");
    }
    send_directive("Checking for missed trips") with
      found = trip_attrs
    always {
      log (">>>> new (unseen trip) " + trip{"id"});
      raise fuse event new_trip 
        attributes trip_attrs
    }

  }




}
// fuse_trips.krl