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

	
    provides fillup, fillupByDate
  }

  global {

    // external decls
    fillup = function(key){
      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };
      last_key = not key.isnull()                     => key.klog(">>>> using the parameter key <<<<<") 
               |  not ent:last_fuel_purchase.isnull()
               && ent:last_fuel_purchase              => ent:last_fuel_purchase.klog(">>>> using entity var key <<<<")
		                                       | pds:get_keys(common:fuel_namespace(), sort_opt, 1)
                                                           .head()
 						 	   .klog(">>>>> had to punt on key for last fuel entry <<<<<<");
      ent:fuel_purchases{last_key.klog(">>>>> retrieving fuel purchase record using this key <<<<<<<<<")}
      //pds:get_item(common:fuel_namespace(), last_key.klog(">>>>> using this key <<<<<<<<<"));
    };

    fillupByDate = function(start, end){

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
              .delete(["key"]) // new records can't have key
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

      // if no key, assume new record and create one
      new_record = event:attr("key").isnull();
      current_time = common:convertToUTC(time:now());

      key = event:attr("key") || current_time;  // UTC; using time as key

      volume = event:attr("volume") || 1;
      unit_price = event:attr("unitPrice");
      odometer = event:attr("odometer");
      location = event:attr("location");
      
      lastfillup = fillup().klog(">>>> returned from fillup >>>> ") || {"odometer": 0, "timestamp": current_time};
      distance = odometer - lastfillup{"odometer"};
      mpg = distance/volume;

      seconds = (time:strftime(current_time, "%s") - time:strftime(lastfillup{"timestamp"}, "%s"));

      when_bought = common:convertToUTC(event:attr("when") || time:now());

      rec = {
        "key": key,	    
        "volume": volume,
	"unit_price": unit_price,
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
     && not key.isnull()
      ) then
    {
      send_directive("Updating fill up") with
        rec = rec
    }
    fired {
       // raise pds event new_data_available
       //   attributes {
       // 	    "namespace": common:fuel_namespace(),
       // 	    "keyvalue": key,
       // 	    "value": rec,
       //       "_api": "sky"
 		   
       // 	  };
      log(">>>>>> Storing fuel purchase >>>>>> " + rec.encode());
      set ent:fuel_purchases{key} rec;
      set ent:last_fuel_purchase key if new_record
    } else {
      log(">>>>>> Could not store fuel record " + rec.encode());
    }
  }

  rule delete_fuel_purchase {
    select when fuse unneeded_fuel_purchase
    pre {
      key = event:attr("key");
    }
    if( not key.isnull() 
      ) then
    {
      send_directive("Deleting fill up") with
        rec = rec
    }
    fired {
       // raise pds event remove_old_data
       //   attributes {
       // 	    "namespace": common:fuel_namespace(),
       // 	    "keyvalue": key,
       //       "_api": "sky"
 		   
       // 	  };
      clear ent:fuel_purchases{key} 
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
      last_key = pds:get_keys(common:fuel_namespace(), sort_opt, 1).head().klog(">>>> resetting pds key <<<<");
    }
    always {
      set ent:last_fuel_purchase last_key;
    }
  }

}
