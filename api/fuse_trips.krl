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
    use module b16x11 alias carvoyant

	
    provides trips
  }

  global {

    // external decls
    trips = function(){
      ent:trips
    }

    // internal decls
    endTime = function(trip) {
      trip{"endTime"} || 
      trip{["endWaypoint","timestamp"]} || 
      trip{["data"]}.head().pick("$..timestamp").head() || 
      "ERROR_NO_TIMESTAMP_AVAILABLE"
    }
  
  }

  rule save_trip {
    select when fuse new_trip
    pre {

      // accept either the trip as a set of attributes or just an ID that requires us to ping Carvoyant API
      incoming = event:attrs();
      trip_info = incoming{"mileage"}.isnull() => carvoyant:trip_info(incoming{"tripId"})
                                                | incoming;
      tid = trip_info{"id"};
      end_time = endTime(trip_info);
      time_split = time:strftime(end_time, "%Y:%m:%d:%H:%M%S").split(re/:/);
    }
    if(not end_time eq "ERROR_NO_TIMESTAMP_AVAILABLE") then
    {send_directive("Adding trip #{tid}") with 
      end_time = end_time and
      time_split = time_split
      ;
    }
    fired {
      set ent:trips{time_split} trip_info
    } else {
      log ">>>>>>>>>>>>>>>>>>>>>>>>> save_trip <<<<<<<<<<<<<<<<<<<<<<<<<";
      log "End time: #{end_time}";
    }
  }


}
