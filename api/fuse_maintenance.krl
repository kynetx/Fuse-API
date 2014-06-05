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
    }
  
  }

  

  rule schedule_reminder {
    select when fuse new_reminder
  }

  rule update_reminder {
    select when fuse updated_reminder
  }

  rule move_to_history {
    select when fuse task_complete
  }


}
