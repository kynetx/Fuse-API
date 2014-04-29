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
    lastFillup = function(){
      pds:get_item(common:fuel_namespace(), ent:last_fuel_purchase);
    };

  }


  rule record_fuel_purchase {
    select when fuse new_fuel_purchase
    pre {
      key = time:now({"tz" : "UTC"});  // UTC; using time as key
      rec = event:attrs()
	      .put(["key"], key)  
	      .klog(">>>>>> new record <<<<<<<<"); 
    }
    {
      send_directive("Recording fill up") with rec = rec
    }
    fired {
      raise fuse event updated_fuel_purchase attributes rec; // Keeping it DRY
      set ent:last_fuel_purchase key
    }
  }

  rule update_fuel_purchase {
    select when fuse updated_fuel_purchase
    pre {
      volume = event:attr("volume");
      unit_price = event:attr("unit_price");
      odometer = event:attr("odometer");
      location = event:attr("location");
      key = event:attr("key");
      rec = {
        "key": key,	    // don't assume key is timestamp here...
        "volume": volume,
	"unit_price": unit_price,
	"location": location,
	"odometer": odometer,
	"timestamp": time:now({"tz": "UTC"})
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

}
