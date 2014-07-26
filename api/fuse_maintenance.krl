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
             alerts, maintanceRecords

  }

 // reminder record
 // {<datetime> : { "timestamp" : <datetime>,
 // 	            "type" : mileage | date
 // 		    "id" : <datetime>,
 // 		    "what" : <string>,
 // 		    "mileage" : <string>,
 // 		    "due_date" : timestamp
 // 	          },
 //  ...
 // }
 // 
 // history record = reminder record + 
 //   "status" : complete | deferred 
 //   "updated" : <timestamp>
 //   "cost" : <string>
 //   "receipt" : <url>
 //   "vendor" : <string>


  global {

    // external decls

    reminders = function () { {} };

    activeReminders = function(current_time, mileage){
      utc_ct = common:convertToUTC(current_time);
      
      ent:reminders.query([], { 
       'requires' : '$or',
       'conditions' : [
          { 
     	   'search_key' : [ 'timestamp'],
       	   'operator' : '$lte',
       	   'value' : utc_ct 
	  },
     	  {
       	   'search_key' : [ 'mileage' ],
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

    alerts = function(id, limit, offset) {
       // x_id = id.klog(">>>> id >>>>>");
       // x_limit = limit.klog(">>>> limit >>>>>");
       // x_offset = offset.klog(">>>> offset >>>>>");

      id.isnull() => allAlerts(limit, offset)
                   | ent:alerts{id};
    };

    allAlerts = function(limit, offset) {
      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };

      max_returned = 25;

      hard_offset = offset.isnull()     => 0               // default
                  |                        offset;

      hard_limit = limit.isnull()       => 10              // default
                 | limit > max_returned => max_returned
		 |                         limit;

      global_opt = {
        "index" : hard_offset,
	"limit" : hard_limit
      }; 

      sorted_keys = this2that:transform(ent:alerts, sort_opt, global_opt).klog(">>> sorted keys for alerts >>>> ");
      sorted_keys.map(function(id){ ent:alerts{id} })
    };

    maintenanceRecords = function(id, limit, offset) {
       // x_id = id.klog(">>>> id >>>>>");
       // x_limit = limit.klog(">>>> limit >>>>>");
       // x_offset = offset.klog(">>>> offset >>>>>");

      id.isnull() => allMaintenanceRecords(limit, offset)
                   | ent:maintenance_records{id};
    };

    allMaintenanceRecords = function(limit, offset) {
      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };

      max_returned = 25;

      hard_offset = offset.isnull()     => 0               // default
                  |                        offset;

      hard_limit = limit.isnull()       => 10              // default
                 | limit > max_returned => max_returned
		 |                         limit;

      global_opt = {
        "index" : hard_offset,
	"limit" : hard_limit
      }; 

      sorted_keys = this2that:transform(ent:maintenance_records, sort_opt, global_opt).klog(">>> sorted keys for maintenance records >>>> ");
      sorted_keys.map(function(id){ ent:maintenance_records{id} })
    };

    // internal use only
    S3Bucket = "Fuse_assets";    

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

      vdata = vehicle:vehicleSummary();

      odometer = event:attr("odometer") || vdata{"mileage"};

      when_alerted = common:convertToUTC(event:attr("when") || time:now());

      rec = {
        "id": id,
	"troubleCodes": trouble_codes,
	"odometer": odometer,
	"reminderRef": event:attr("reminder_ref"),
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
    select when fuse maintenance_alert
    pre {
      id = event:attr("id");
      alert = alerts(id);
      status = event:attr("status");

      rec = {
        "alert_ref": id,
	"status": status,
	"agent": event:attr("agent"),
	"receipt": event:attr("receipt")
      };
    }
    if( not id.isnull()
     && not alert.isnull()
      ) then {
        send_directive("processing alert to create maintenance record") with 
	 rec = rec and
  	 alert = alert
      }
    fired {
      log ">>>> processing alert for maintenance  >>>> " + alert.encode();
      raise fuse event new_maintenance_record attributes rec
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
      odometer = event:attr("odometer") || vdata{"mileage"};

      completed_time = event:attr("when") || current_time;

      // receipt photo 
      img_source = event:attr("receipt");
      img_is_new = img_source.match(re/^data:image/); // might get an http:// URL for updates
      vehicle_id = CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.channelName").klog(">>>> vehicle ID >>>>> ");
      img_name   = "fuse_vehicle_files/#{meta:eci()}/#{vehicle_id}/#{id}.img";
      seed       = math:random(100000);
      img_url    = img_is_new => "https://s3.amazonaws.com/#{S3Bucket}/#{img_name}.img?q=#{seed}" 
                               | img_source;
     

      rec = {
        "id": id,
	"activity": activity,
	"agent": event:attr("agent"),
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
      current_time = common:convertToUTC(time:now());

      id = event:attr("id") || random:uuid();

      rec = {
        "id": id,
	"troubleCodes": event:attr("troubleCodes"),
	"odometer": event:attr("odometer"),
	"reminderRef": event:attr("reminderRef") || "organic",
	"activity": event:attr("activity"),
	"timestamp": current_time
      };
    }
    if( not rec{"odometer"}.isnull() 
     && not rec{"activity"}.isnull()
     && not id.isnull()
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


  
  


}
