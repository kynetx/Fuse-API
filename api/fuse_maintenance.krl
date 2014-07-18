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
    use module b16x19 alias common
    use module b16x11 alias carvoyant
    use module b16x9 alias vehicle

	
    provides activeReminders, maintenaceHistory

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
    maintenanceHistory = function(start, end){
      1;
    };

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

    // for use with scheduled events  
    use_domain = "explicit";    
    use_type = "maintenance_due";
    evid = 0;
    event = 1;
    sctype = 2;
    evrid = 3; 


  }

  
  // ---------- create reminders ----------
  rule schedule_reminder {
    select when fuse new_reminder
    pre {
      rec = event:attrs()
              .delete(["id"]) // new records can't have id
	      ; 
    }      
    {
      send_directive("Recording maintenance reminder") with rec = rec;
    }
    fired {
      raise fuse event updated_reminder attributes rec; // Keeping it DRY
    }
  }

  rule update_reminder {
    select when fuse updated_reminder
    pre {
      new_record = event:attr("id").isnull();
      current_time = common:convertToUTC(time:now());

      id = event:attr("id") || random:uuid();
      rec = event:attrs()
              .put(["id"], id)
              .put(["timestamp"], current_time);

    }
    if( event:attr("type") eq "mileage") then 
    {
      send_directive("Processing mileage reminder") with attrs = rec
    }
    fired {
      raise explicit event "mileage_reminder" attributes rec;
      set ent:reminders{id} rec;
    } else {
      raise explicit event "date_reminder" attributes rec;
      set ent:reminders{id} rec;
    }
  }   

   rule process_date_reminder {
     select when explicit date_reminder
     pre {

      id = event:attr("id");

      // if no id, assume new record and create one
      scheduled_ev_id = ent:reminders{id}.pick("$..schedEv");

      scheduled = event:get_list();
      this_event = scheduled.filter(function(e){e[evid] eq scheduled_ev_id
                                               }).head().klog(">>>> this event >>>>");

      // event schedule system doesn't allow updates, so we delete than then recreate 
      isDeleted = this_event.isnull() => 0
                                       | event:delete(id);
      

 // reminder record
 // {<datetime> : { "timestamp" : <datetime>,
 // 	            "type" : mileage | date,
 // 		    "recurring": "once" | "repeat",
 // 		    "activity" : <string>,
 // 		    "due" : DateTime | Integer
 // 	          },
    
      recurring = event:attr("recurring");

      rec = {
	"type": event:attr("type"),  // should always be "date" here
	"recurring": recurring,
	"activity": event:attr("activity"),
	"due": event:attr("due"),
	"timestamp": current_time
      };
    }
    if( not rec{"activity"}.isnull()
     && (recurring eq "once" || recurring eq "repeat")
     && not rec{"due"}.isnull()
      ) then
    {
      send_directive("Updating maintenance reminder") with
        rec = rec
    }
    fired {
      log(">>>>>> Processing date-based maintenance reminder >>>>>> " + rec.encode());
      raise explicit event "schedule_#{recurring}" attributes rec;
    } else {
      log(">>>>>> Could not store maintenance reminder >>>>  " + rec.encode());
    }
  }

  rule create_recurring_reminder {
    select when explicit schedule_repeat
    pre {
      hour = math:random(3).klog(">>> hour (plus 3)>>> ") + 3; // between 3 and 7
      minute = math:random(59).klog(">>>> minute >>>> ");
      current_day = time:strftime("%d");
      
      due = (event:attr("due") % 12) + 1; // ensure it's 1-12
      current_month = time:strftime("%m");
      num_reminders = math:round(12/due);
      month_array = (0).range(num_reminders).map(function(x){((x + current_month) % 12) + 1}).klog(">> reminder array for months >>>> ");
      month = (num_reminders == 1) => "*"
                                    | month_array;
      id = event:attr("id");
      rec = event:attrs();
				   
    }
    {
      send_directive("schedule repeat reminder") with
        attrs = rec and
        cronspec = "#{minute} #{hour} #{day} #{month} *";
    }
    
    always {
      schedule explicit event "fuse_reminder" repeat "#{minute} #{hour} #{day} #{month} *" 
        attributes rec
        setting (sched_ev_id);
      set ent:reminders{[id, "schedEv"]} sched_ev_id;
    }
  }

  rule create_single_reminder {
    select when explicit schedule_once
    pre {
      id = event:attr("id");
      rec = event:attrs();
    }
    {
      send_directive("schedule single reminder") with
        attrs = rec;
    }
    always {
      schedule explicit event "fuse_reminder" at event:attr("due") 
        attributes rec
        setting (sched_ev_id);
      set ent:reminders{[id, "schedEv"]} sched_ev_id;
    }
  }

  rule move_to_history {
    select when fuse task_complete
  }


}
