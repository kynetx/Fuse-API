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

    use module a169x625 alias CloudOS
    use module a169x676 alias pds
    use module b16x19 alias common
    use module b16x11 alias carvoyant
    use module b16x9 alias vehicle

	
    provides lastFillup
  }

  global {

    // external decls
    lastFillup = function(key){
      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };
      last_key = not key.isnull()                    => key 
               | not ent:last_fuel_purchase.isnull() => ent:last_fuel_purchase
		                                      | pds:get_keys(common:fuel_namespace(), sort_opt, 1).head().klog(">>>> pds key <<<<")
      pds:get_item(common:fuel_namespace(), last_key.klog(">>>>> using this key <<<<<<<<<"));
    };

  }


  rule record_fuel_purchase {
    select when fuse new_fuel_purchase
    pre {
      rec = event:attrs()
              .delete(["key"]) // new records can't have key
	      .klog(">>>>>> new record <<<<<<<<"); 
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
      key = event:attr("key") || time:now({"tz" : "UTC"});  // UTC; using time as key

      volume = event:attr("volume") || 1;
      unit_price = event:attr("unit_price");
      odometer = event:attr("odometer");
      location = event:attr("location");
      current_time = time:now({"tz": "UTC"});

      fillup = lastFillup().klog(">>>> last fill up <<<<<<<") || {"odometer": 0, "timestamp": current_time};
      distance = odometer - fillup{"odometer"};
      mpg = distance/volume;

      seconds = (time:strftime(current_time, "%s") - time:strftime(fillup{"timestamp"}, "%s"));


      rec = {
        "key": key,	    
        "volume": volume,
	"unit_price": unit_price,
	"location": location,
	"odometer": odometer.sprintf("%.1f"),
	"distance": distance.sprintf("%.1f"),
	"mpg": mpg.sprintf("%.2f"),
	"interval": seconds,
	"timestamp": current_time
      }.klog(">>>>>>> fuel record <<<<<<<<");
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
      raise pds event new_data_available
        attributes {
	    "namespace": common:fuel_namespace(),
	    "keyvalue": key,
	    "value": rec,
            "_api": "sky"
 		   
	  };
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
      raise pds event remove_old_data
        attributes {
	    "namespace": common:fuel_namespace(),
	    "keyvalue": key,
            "_api": "sky"
 		   
	  };
    }
  }

  rule reset_last_fuel_entry {
    select when pds data_updated namespace "fuse-fuel"
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
