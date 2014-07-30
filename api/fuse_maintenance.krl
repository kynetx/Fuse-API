ruleset fuse_maintenance {
  meta {
    name "Fuse Maintenance App"
    description <<
Operations for maintenance
    >>
    author "PJW"
    sharing on

    errors to b16x13

    use module b16x10 alias fuse_keys

    use module a169x625 alias CloudOS
    use module a169x676 alias pds
    use module a41x174 alias S3
       with AWSKeys = keys:aws()
    use module b16x19 alias common
    use module b16x11 alias carvoyant
    use module b16x9 alias vehicle

	
    provides activeReminders, reminders,
             alerts, alertsByDate, maintenanceRecords, maintenanceRecordsByDate

  }

  global {

    // external decls

    reminders = function (id, type, limit, offset) { 
      x_id = id.klog(">>>> id >>>>>");
      id.isnull() => allReminders(type, limit, offset)
                   | ent:reminders{id};
    };

    allReminders = function(type, limit, offset) {

      max_returned = 25;

      type_val = type || ".*";


      hard_offset = offset.isnull()     => 0               // default
                  |                        offset;

      hard_limit = limit.isnull()       => 10              // default
                 | limit > max_returned => max_returned
		 |                         limit;

      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };

      global_opt = {
        "index" : hard_offset,
	"limit" : hard_limit
      };  

      sorted_keys = this2that:transform(ent:reminders.query([], { 
       'requires' : '$and',
       'conditions' : [
          { 
     	   'search_key' : ['type'],
       	   'operator' : '$regex',
       	   'value' : "^#{type_val}$" 
	  }
	]},
	"return_values"
	).klog(">>> unsorted vals >>>>   "), sort_opt, global_opt).klog(">>> sorted keys for reminders >>>> ");
      sorted_keys
    };

    activeReminders = function(current_time, mileage){
      utc_ct = common:convertToUTC(current_time);

      ent:reminders.query([], { 
       'requires' : '$or',
       'conditions' : [
          { 
     	   'search_key' : [ 'duedate'],
       	   'operator' : '$lte',
       	   'value' : utc_ct 
	  },
     	  {
       	   'search_key' : [ 'duemileage' ],
       	   'operator' : '$lte',
       	   'value' : mileage 
	  }
	]},
	"return_values"
	)
    };

    daysBetween = function(time_a, time_b) {
      sec_a = strftime(time_a, "%s");
      sec_b = strftime(time_b, "%s");
      math:abs(math:int((sec_a-sec_b)/86400));
    };

    alerts = function(id, status, limit, offset) {
       // x_id = id.klog(">>>> id >>>>>");
       // x_limit = limit.klog(">>>> limit >>>>>");
       // x_offset = offset.klog(">>>> offset >>>>>");

      id.isnull() => allAlerts(status, limit, offset)
                   | ent:alerts{id};
    };

    allAlerts = function(status, limit, offset) {

      status_val = status || "active";
    
      max_returned = 25;


      hard_offset = offset.isnull()     => 0               // default
                  |                        offset;

      hard_limit = limit.isnull()       => 10              // default
                 | limit > max_returned => max_returned
		 |                         limit;

      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };

      global_opt = {
        "index" : hard_offset,
	"limit" : hard_limit
      }; 

      sorted_keys = this2that:transform(ent:alerts.query([], { 
       'requires' : '$and',
       'conditions' : [
     	  {
       	   'search_key' : [ 'status' ],
       	   'operator' : '$regex',
       	   'value' : "^#{status_val}$"
	  }
	]},
	"return_values"
	), sort_opt, global_opt).klog(">>> sorted keys for alerts >>>> ");
      sorted_keys
    };

    alertsByDate = function(status, start, end){

      status_val = status || "active";
    
      utc_start = common:convertToUTC(start);
      utc_end = common:convertToUTC(end);
      
      sort_opt = {
        "path" : ["endTime"],
	"reverse": true,
	"compare" : "datetime"
      };

      this2that:transform(ent:alerts.query([], { 
       'requires' : '$and',
       'conditions' : [
          { 
     	   'search_key' : [ 'timestamp'],
       	   'operator' : '$gte',
       	   'value' : utc_start 
	  },
     	  {
       	   'search_key' : [ 'timestamp' ],
       	   'operator' : '$lte',
       	   'value' : utc_end 
	  },
     	  {
       	   'search_key' : [ 'status' ],
       	   'operator' : '$regex',
       	   'value' : "^#{status_val}$"
	  }
	]},
	"return_values"
	), 
       sort_opt)
    };


    maintenanceRecords = function(id, status, limit, offset) {
       // x_id = id.klog(">>>> id >>>>>");
       // x_limit = limit.klog(">>>> limit >>>>>");
       // x_offset = offset.klog(">>>> offset >>>>>");

      id.isnull() => allMaintenanceRecords(status, limit, offset)
                   | ent:maintenance_records{id};
    };

    allMaintenanceRecords = function(status, limit, offset) {

      status_val = status || ".*"; // find them all if missing

      max_returned = 25;

      hard_offset = offset.isnull()     => 0               // default
                  |                        offset;

      hard_limit = limit.isnull()       => 10              // default
                 | limit > max_returned => max_returned
		 |                         limit;

      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };

      global_opt = {
        "index" : hard_offset,
	"limit" : hard_limit
      }; 

      sorted_keys = this2that:transform(ent:maintenance_records.query([], { 
       'requires' : '$and',
       'conditions' : [
     	  {
       	   'search_key' : [ 'status' ],
       	   'operator' : '$regex',
       	   'value' : "^#{status_val}$"
	  }
	]},
	"return_values"
	), sort_opt, global_opt).klog(">>> sorted keys for maintenance records >>>> ");
      sorted_keys  
    };

    maintenanceRecordsByDate = function(status, start, end){

      status_val = status || ".*"; // find them all if missing

      utc_start = common:convertToUTC(start);
      utc_end = common:convertToUTC(end);
      
      sort_opt = {
        "path" : ["endTime"],
	"reverse": true,
	"compare" : "datetime"
      };

      this2that:transform(ent:maintenance_records.query([], { 
       'requires' : '$and',
       'conditions' : [
          { 
     	   'search_key' : [ 'timestamp'],
       	   'operator' : '$gte',
       	   'value' : utc_start 
	  },
     	  {
       	   'search_key' : [ 'timestamp' ],
       	   'operator' : '$lte',
       	   'value' : utc_end 
	  },
     	  {
       	   'search_key' : [ 'status' ],
       	   'operator' : '$regex',
       	   'value' : "^#{status_val}$"
	  }	]},
	"return_values"
	), 
       sort_opt)
    };


    // internal use only
    S3Bucket = "Fuse_assets";   

  }

  // ---------- reminders ----------
  rule record_reminder {
    select when fuse new_reminder
    pre {
      rec = event:attrs()
              .delete(["id"]) // new records can't have id
	      ; 
    }      
    {
      send_directive("Recording reminder") with rec = rec
    }
    fired {
      raise fuse event updated_reminder attributes rec; // Keeping it DRY
    }
  }

  rule update_reminder {
    select when fuse updated_reminder
    pre {

      // if no id, assume new record and create one
      new_record = event:attr("id").isnull();

      id = event:attr("id") || random:uuid();

      // can't default since the "due" type has to match
      type =  event:attr("kind") eq "date" 
           || event:attr("kind") eq "mileage"  => event:attr("kind")
            |                                     "unknown";

      recurring = event:attr("recurring").isnull()      => "once"
                | event:attr("recurring") eq "once" 
               || event:attr("recurring") eq "repeat"   => event:attr("recurring")
                |                                          "unknown";

      interval = event:attr("interval");

      vdata = vehicle:vehicleSummary();

      when_reminded = common:convertToUTC(event:attr("when") || time:now());

      duedate = type eq "date" && recurring eq "repeat"    => time:add(when_reminded, {"months": interval})
              | type eq "date" && recurring eq "once"      => event:attr("due")
              |                                               time:add(time:now(), {"years": 25}); // never

      duemileage = type eq "mileage" && recurring eq "repeat" => vdata{"mileage"} + interval
                 | type eq "mileage" && recurring eq "once"   => event:attr("due")
                 |                                               "999999"; // everything's before this


 // reminder record
 // {<datetime> : { "timestamp" : <datetime>,
 // 	            "type" : mileage | date,
 // 		    "recurring": "once" | "repeat",
 // 		    "activity" : <string>,
 // 		    "due" : DateTime | Integer
 // 	          },
      rec = {
        "id": id,
	"type": type,
	"recurring": recurring,
	"interval": interval,
	"activity": event:attr("activity"),
	"duedate": common:convertToUTC(duedate),
	"duemileage": duemileage,
	"mileagestamp" : vdata{"mileage"},
	"timestamp": when_reminded
      };
    }
    if( not rec{"activity"}.isnull()
     && rec{"type"} neq "unknown"
     && rec{"recurring"} neq "unknown"
      ) then
    {
      send_directive("Updating reminder") with
        rec = rec
    }
    fired {
      log(">>>>>> Storing reminder >>>>>> " + rec.encode());
      set ent:reminders{id} rec;
    } else {
      log(">>>>>> Could not store reminder " + rec.encode());
    }
  }

  rule delete_reminder {
    select when fuse unneeded_reminder
    pre {
      id = event:attr("id");
    }
    if( not id.isnull() 
      ) then
    {
      send_directive("Deleting reminder") with
        rec = rec
    }
    fired {
      clear ent:reminders{id} 
    }
  }

  rule process_reminder {
    select when fuse handled_reminder
    pre {
      id = event:attr("id");

      rec = {
        "reminder_ref": id,
	"status": event:attr("status"),
	"agent": event:attr("agent"),
	"receipt": event:attr("receipt")
      };
    }
    if( not id.isnull()
      ) then {
        send_directive("processing reminder to create maintenance record") with 
	 rec = rec
      }
    fired {
      log ">>>> processing reminder for maintenance  >>>> " + reminder.encode();
      raise fuse event new_alert attributes rec;
      raise fuse event new_reminder_status with
        id = id and
	status = "inactive";
    } else {
    }
  }



  // ---------- alerts ----------
  rule record_alert {
    select when fuse new_alert
    pre {
      rec = event:attrs()
              .delete(["id"]) // new records can't have id
	      ; 
    }      
    {
      send_directive("Recording alert") with rec = rec
    }
    fired {
      raise fuse event updated_alert attributes rec; // Keeping it DRY
    }
  }

  rule update_alert {
    select when fuse updated_alert
    pre {

      // if no id, assume new record and create one
      new_record = event:attr("id").isnull();

      id = event:attr("id") || random:uuid();

      reminder = reminders(event:attr("reminder_ref")) || {};

      trouble_codes = event:attr("trouble_codes");

      activity = event:attr("activity") || reminder{"activity"};
      reason = event:attr("reason") || reminder{"reason"};

      status = event:attr("status").isnull()      => "active"
             | event:attr("status") eq "active" 
            || event:attr("status") eq "inactive" => event:attr("status")
             |                                       "unknown";

      vdata = vehicle:vehicleSummary();

      odometer = event:attr("odometer") || vdata{"mileage"};

      when_alerted = common:convertToUTC(event:attr("when") || time:now());

      rec = {
        "id": id,
	"trouble_codes": trouble_codes,
	"odometer": odometer,
	"reminder_ref": event:attr("reminder_ref"),
	"activity": activity,
	"reason": reason,
	"timestamp": when_alerted
      };
    }
    if( not rec{"odometer"}.isnull() 
     && not rec{"activity"}.isnull()
     && not id.isnull()
      ) then 
    {
      send_directive("Updating alert") with
        rec = rec
    }
    fired {
      log(">>>>>> Storing alert >>>>>> " + rec.encode());
      set ent:alerts{id} rec;
    } else {
      log(">>>>>> Could not store alert " + rec.encode());
    }
  }

  rule update_alert_status {
    select when fuse new_alert_status
    pre {
      id = event:attr("id");
      new_status = event:attr("status");
    }
    if( not id.isnull()
     && not new_status.isnull()
      ) then 
    {
      send_directive("Updating alert status") with
        id = id and
        status = new_status
    }
    always {
      set ent:alerts{[id, "status"]} new_status;
    }
  }

  rule delete_alert {
    select when fuse unneeded_alert
    pre {
      id = event:attr("id");
    }
    if( not id.isnull() 
      ) then
    {
      send_directive("Deleting alert") with
        rec = rec
    }
    fired {
      clear ent:alerts{id} 
    }
  }

  rule process_alert {
    select when fuse handled_alert
    pre {
      id = event:attr("id");

      rec = {
        "alert_ref": id,
	"status": event:attr("status"),
	"agent": event:attr("agent"),
	"cost": event:attr("cost"),
	"receipt": event:attr("receipt")
      };
    }
    if( not id.isnull()
      ) then {
        send_directive("processing alert to create maintenance record") with 
	 rec = rec
      }
    fired {
      log ">>>> processing alert for maintenance  >>>> " + alert.encode();
      raise fuse event new_maintenance_record attributes rec;
      raise fuse event new_alert_status with
        id = id and
	status = "inactive";
    } else {
    }
  }

  // ---------- maintenance_records ----------
  rule record_maintenance_record {
    select when fuse new_maintenance_record
    pre {
      rec = event:attrs()
              .delete(["id"]) // new records can't have id
	      ; 
    }      
    {
      send_directive("Recording maintenance_record") with rec = rec
    }
    fired {
      raise fuse event updated_maintenance_record attributes rec; // Keeping it DRY
    }
  }


  rule update_maintenance_record {
    select when fuse updated_maintenance_record
    pre {

      // if no id, assume new record and create one
      new_record = event:attr("id").isnull();
      current_time = common:convertToUTC(time:now());

      id = event:attr("id") || random:uuid();

      alert = alerts(event:attr("alert_ref")) || {};

      vdata = vehicle:vehicleSummary();

      status = event:attr("status") eq "completed" 
            || event:attr("status") eq "deferred" => event:attr("status")
             |                                       "unknown";

      activity = event:attr("activity") || alert{"activity"};
      reason = event:attr("reason") || alert{"reason"};
      odometer = event:attr("odometer") || vdata{"mileage"};

      completed_time = event:attr("when") || current_time;

      // receipt photo 
      img_source = event:attr("receipt");
      img_is_new = img_source.match(re/^data:image/).klog(">>>> image is new >>>>"); // might get an http:// URL for updates
      vehicle_id = CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.channelName").klog(">>>> vehicle ID >>>>> ");
      img_name   = "fuse_vehicle_files/#{meta:eci()}/#{vehicle_id}/#{id}.img";
      img_url    = img_is_new => S3:makeAwsUrl(S3Bucket,img_name)
                               | img_source;
     

      rec = {
        "id": id,
	"activity": activity,
	"activity": reason,
	"alert_ref": event:attr("alert_ref") || "none",
	"reminder_ref": alert{"reminder_ref"},
	"trouble_codes": alert{"trouble_codes"},
	"agent": event:attr("agent"),
	"cost": event:attr("cost"),
	"status": status,
	"receipt": img_url,
	"odometer": odometer,
	"timestamp": completed_time
      };
    }
    if( not rec{"odometer"}.isnull() 
     && not rec{"activity"}.isnull()
     && not id.isnull()
      ) then
    {
      send_directive("Updating maintenance_record") with
        rec = rec
	
    }
    fired {
      log(">>>>>> Storing maintenance_record >>>>>> " + rec.encode());
      set ent:maintenance_records{id} rec;
      raise fuse event new_receipt with
        image_name = image_name and
	image_source = image_source      if img_is_new;
    } else {
      log(">>>>>> Could not store maintenance_record " + rec.encode());
    }
  }

  // to make this work with a AWS IAM user (fuse_admin) I had to create a bucket policy
  rule store_maintenance_receipt {
    select when fuse new_receipt
    pre {
      img_name = event:attr("img_name");
      img_source = event:attr("img_source");
      img_value  = this2that:base642string(S3:getValue(img_source));
      img_type   = S3:getType(img_source);
    }
    if(img_source.match(re/^data:image/)) then
    {
      send_directive("storing receipt at Amazon") with
        name = img_name and
        type = img_type
	;
      S3:upload(S3Bucket, img_name, img_value)
        with object_type = img_type;
    }

  }

  // to make this work with a AWS IAM user (fuse_admin) I had to create a bucket policy
  rule delete_maintenance_receipt {
    select when fuse unneeded_receipt
    pre {
      img_name = event:attr("img_name");
    }
    {
      send_directive("deleting receipt at Amazon") with
        name = img_name 
	;
      S3:del(S3Bucket, img_name);
    }

  }

  rule delete_maintenance_record {
    select when fuse unneeded_maintenance_record
    pre {
      id = event:attr("id");
    }
    if( not id.isnull() 
      ) then
    {
      send_directive("Deleting maintenance_record") with
        rec = rec
    }
    fired {
      clear ent:maintenance_records{id} 
    }
  }


}
// fuse_maintenance.krl
