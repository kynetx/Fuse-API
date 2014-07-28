ruleset fuse_fuel {
  meta {
    name "Fuse Fuel App"
    description <<
Operations for fuel
    >>
    author "PJW"
    sharing on

    errors to b16x13

    use module b16x10 alias fuse_keys

    use module a169x676 alias pds
    use module b16x19 alias common
    use module b16x11 alias carvoyant
    use module b16x9 alias vehicle

	
    provides fillups, fillupsByDate
  }

  global {

    // external decls
    fillups = function(id){
      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };
      global_opt = {
        "index" : 0,
	"limit" : 1
      }; 
      last_id = not id.isnull()                     => id.klog(">>>> using the parameter id <<<<<") 
               |  not ent:last_fuel_purchase.isnull()
               && ent:last_fuel_purchase              => ent:last_fuel_purchase.klog(">>>> using entity var id <<<<")
		                                       | this2that:transform(ent:fuel_purchases, sort_opt, global_opt)
                                                           .head()
 						 	   .klog(">>>>> had to punt on id for last fuel entry <<<<<<");
      ent:fuel_purchases{last_id.klog(">>>>> retrieving fuel purchase record using this id <<<<<<<<<")}
      //pds:get_item(common:fuel_namespace(), last_id.klog(">>>>> using this id <<<<<<<<<"));
    };

    fillupsByDate = function(start, end){

      utc_start = common:convertToUTC(start);
      utc_end = common:convertToUTC(end);
      
      ent:fuel_purchases.query([], { 
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
	  }
	]},
	"return_values"
	)
    };


  }


  rule record_fuel_purchase {
    select when fuse new_fuel_purchase
    pre {
      rec = event:attrs()
              .delete(["id"]) // new records can't have id
	      ; 
    }      
    {
      send_directive("Recording fill up") with rec = rec
    }
    fired {
      raise fuse event updated_fuel_purchase attributes rec; // Keeping it DRY
    }
  }

  rule update_fuel_purchase {
    select when fuse updated_fuel_purchase
    pre {

      // if no id, assume new record and create one
      new_record = event:attr("id").isnull();
      current_time = common:convertToUTC(time:now());

      id = event:attr("id") || random:uuid();  // UTC; using time as id

      volume = event:attr("volume") || 1;
      unit_price = event:attr("unitPrice");
      odometer = event:attr("odometer");
      location = event:attr("location");
      
      lastfillup = fillups().klog(">>>> returned from fillup >>>> ") || {"odometer": 0, "timestamp": current_time};
      distance = odometer - lastfillup{"odometer"};
      mpg = distance/volume;

      seconds = (time:strftime(current_time, "%s") - time:strftime(lastfillup{"timestamp"}, "%s"));

      cost = volume * unit_price;

      when_bought = common:convertToUTC(event:attr("when") || time:now());

      rec = {
        "id": id,	    
        "volume": volume,
	"unit_price": unit_price,
	"cost": cost.sprintf("%.2f"),
	"location": location,
	"odometer": odometer.sprintf("%.1f"),
	"distance": distance.sprintf("%.1f"),
	"mpg": (mpg < 100) => mpg.sprintf("%.2f") // throw out bad data
	                    | 0,
	"interval": seconds,
	"timestamp": when_bought
      };
    }
    if( not volume.isnull() 
     && not unit_price.isnull()
     && not odometer.isnull()
     && not id.isnull()
      ) then
    {
      send_directive("Updating fill up") with
        rec = rec
    }
    fired {
       // raise pds event new_data_available
       //   attributes {
       // 	    "namespace": common:fuel_namespace(),
       // 	    "keyvalue": id,
       // 	    "value": rec,
       //       "_api": "sky"
 		   
       // 	  };
      log(">>>>>> Storing fuel purchase >>>>>> " + rec.encode());
      set ent:fuel_purchases{id} rec;
      set ent:last_fuel_purchase id if new_record
    } else {
      log(">>>>>> Could not store fuel record " + rec.encode());
    }
  }

  rule delete_fuel_purchase {
    select when fuse unneeded_fuel_purchase
    pre {
      id = event:attr("id");
    }
    if( not id.isnull() 
      ) then
    {
      send_directive("Deleting fill up") with
        rec = rec
    }
    fired {
       // raise pds event remove_old_data
       //   attributes {
       // 	    "namespace": common:fuel_namespace(),
       // 	    "keyvalue": id,
       //       "_api": "sky"
 		   
       // 	  };
      clear ent:fuel_purchases{id};
      clear ent:last_fuel_purchase;
    }
  }

  rule reset_last_fuel_entry {
    select when pds data_deleted namespace "fuse-fuel"
    pre {
      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };
      last_id = pds:get_keys(common:fuel_namespace(), sort_opt, 1).head().klog(">>>> resetting pds id <<<<");
    }
    always {
      set ent:last_fuel_purchase last_id;
    }
  }


  rule update_vehicle_totals {
    select when fuse fuel_purchase_saved
    pre {

      // do current month if no month given
      raw_month = event:attr("month") || time:now();
      month = time:strftime(raw_month, "%m");
      year = time:strftime(raw_month, "%Y");

      start = time:strftime(raw_month, "%Y%m01T000000%z");
      end = time:add(start, {"months": 1});
      month_totals = fillupsByDate(start, end)
                      .klog(">>>> fillups for #{year}/#{month} >>>> ")
                      .reduce(function(a, b){ 
	                                      {"cost": a{"cost"} + b{"cost"}, 
		                               "distance": a{"distance"} + b{"distance"},
					       "volume": a{"volume"} + b{"volume"},
					       "fillups": a{"fillups"} + 1
					      }
					    },
			      {"cost": 0, 
			       "distance": 0,
			       "volume": 0,
			       "fillups": 0
			      }
                             );

    }
    {send_directive("Updated fuel summary for #{month}/#{year}") with
       values =  month_totals;
     event:send({"cid": vehicle:fleetChannel()}, "fuse", "updated_vehicle") with
        attrs = {"keyvalue": "fuel_summaries,Y#{year},M#{month}",
	         "value": month_totals.encode()
	        };
      }

    always {
      set ent:monthly_fuel_summary{[year, month]} month_totals;
    }
  }

}
// fuse_fuel.krl
