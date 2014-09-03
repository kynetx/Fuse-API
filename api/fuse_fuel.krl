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

	
    provides fillups, fillupsByDate, currentCPM, standardMPG, standardCPG
  }

  global {

    // external decls
    fillupsByDate = function(start, end){

      utc_start = common:convertToUTC(start);
      utc_end = common:convertToUTC(end);

      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };
      
      this2that:transform(ent:fuel_purchases.query([], { 
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
	),
	sort_opt
      )
    }

    fillups = function(id, limit, offset) {
       // x_id = id.isnull().klog(">>>> id >>>>>");
       // x_limit = limit.klog(">>>> limit >>>>>");
       // x_offset = offset.klog(">>>> offset >>>>>"); 

      id.isnull() || id eq "" => allFillups(limit, offset)
                               | ent:fuel_purchases{id};
    };

    allFillups = function(limit, offset) {
      sort_opt = {
        "path" : ["timestamp"],
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

      sorted_keys = this2that:transform(ent:fuel_purchases, sort_opt, global_opt.klog(">>>> transform using global options >>>> ")) || [];
      sorted_keys.map(function(id){ ent:fuel_purchases{id} })
    };


    currentCPM = function() {
      fillup = fillups(null, 1, 0).head() || {"mpg": 1, "unit_price": 0};
      vehicle_mpg = not fillup{"mpg"}.isnull() => fillup{"mpg"} 
                                                | 0;
      vehicle_cpg = not fillup{"unit_price"}.isnull() => fillup{"unit_price"}
                                                       | 0;

      mpg = vehicle_mpg || standardMPG().klog(">>> MPG >>>>");
      cpg = vehicle_cpg || standardCPG().klog(">>> CPG >>>>");

      cpm = cpg / mpg;
      {"costPerMile": cpm,
       "mpg": mpg,
       "costPerGallon": cpg,
       "vehicleData": vehicle_mpg > 0 && vehicle_cpg > 0
      }.klog(">>>>> returning CPM >>>>>> ")
      
    };

    standardMPG = function() {
      not ent:mpg => callEdmunds()
                   | ent:mpg.klog(">>>> returning cached MPG >>>>") 
    }

    callEdmunds = function() {
      vin = pds:get_me("vin");
      edmunds_key = keys:edmunds_client("key").klog(">>> edmunds key >>>>");
      edmunds_url = "https://api.edmunds.com/api/vehicle/v2/vins/#{vin}";
      raw_resp = http:get(edmunds_url, {"fmt":"json",
                                        "api_key": edmunds_key});
      resp = raw_resp{"status_code"} eq "200" => raw_resp{"content"}.decode().klog(">>>> Edmunds response >>>> ")
                                               | {};
      highway = resp{["MPG","highway"]} || 15;
      city = resp{["MPG","city"]} || 15;
      mpg = (highway + city) / 2  // assume half city, half highway
      mpg.pset(ent:mpg); 
    }
      
    standardCPG = function() {
      num_days = 2;
      expired = (ent:cpg{"timestamp"} + (num_days * 3600 * 24) < time:strftime(time:now(), "%s")).klog(">>> cpg expired? >>>>");
      result = not ent:cpg || expired => callFuelEconomy()
                                       | ent:cpg.klog(">>>> returning cached CPG >>>>") ;
      result{"cpg"}
    }

    callFuelEconomy = function() {
      fe_url = "http://www.fueleconomy.gov/ws/rest/fuelprices"; 
      raw_resp = http:get(fe_url);
      resp = raw_resp{"status_code"} eq "200" => raw_resp{"content"}
                                               | {};
      json = this2that:xml2json(resp, {"content_key" : "val"}).decode().klog(">>>> response as JSON >>>> ");
      cpg = json{["fuelPrices", "midgrade", "val"]} || "3.50";
      cpg_obj = {"cpg" : cpg,
                 "timestamp": time:strftime(time:now(), "%s")
                };
      cpg_obj.pset(ent:cpg);   
    }
      
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

      vdata = vehicle:vehicleSummary();

      volume = event:attr("volume") || 1;
      unit_price = event:attr("unitPrice");
      odometer = event:attr("odometer") || vdata{"mileage"};
      location = event:attr("location");
      
      offset = new_record => 0 | 1; // new record isn't already on the list
      lastfillup = fillups(null, 1, offset).head().klog(">>>> returned from fillup >>>> ") || {};
      distance = lastfillup{"odometer"}.isnull() => 0 | (odometer - lastfillup{"odometer"});
      mpg = distance/volume;

      when_bought = common:convertToUTC(event:attr("when") || time:now());

      seconds = lastfillup{"timestamp"}.isnull() => 0 | (time:strftime(when_bought, "%s") - time:strftime(lastfillup{"timestamp"}, "%s"));

      cost = volume * unit_price;


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
      raise fuse event fuel_purchase_saved;
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
